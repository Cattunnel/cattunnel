// Linux VPN: the app runs as the user; the public trusttunnel_client CLI
// needs root (TUN, routes, DNS), so cattunnel-helper (helper/, a systemd
// service) runs it for us. This plugin only speaks the helper's protocol
// (HELPER.md) - the same config TOML the Dart side encodes for Windows goes
// to the helper, which checks it and starts the CLI.

#include "include/vpn_plugin/vpn_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <glib/gstdio.h>

#include <condition_variable>
#include <deque>
#include <fstream>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "cli_output.h"
#include "helper_client.h"
#include "platform_api.g.h"

namespace {

using Json = vpn_plugin::HelperClient::Json;
using namespace std::chrono_literals;

constexpr auto kRequestTimeout = 5s;  // "start" writes the config and forks the CLI
constexpr auto kLogsTimeout = 3s;
constexpr size_t kMaxLogRecords = 5000;

VpnPluginVpnManagerState StateFromName(const std::string& name) {
    if (name == "connecting") return VPN_PLUGIN_VPN_MANAGER_STATE_CONNECTING;
    if (name == "connected") return VPN_PLUGIN_VPN_MANAGER_STATE_CONNECTED;
    if (name == "waiting_recovery") return VPN_PLUGIN_VPN_MANAGER_STATE_WAITING_FOR_RECOVERY;
    if (name == "recovering") return VPN_PLUGIN_VPN_MANAGER_STATE_RECOVERING;
    if (name == "waiting_for_network") return VPN_PLUGIN_VPN_MANAGER_STATE_WAITING_FOR_NETWORK;
    return VPN_PLUGIN_VPN_MANAGER_STATE_DISCONNECTED;
}

/** "2026-09-28T21:30:00.123456 [error] message", the app's log record format. */
std::string LocalRecord(const char* level, const std::string& message) {
    g_autoptr(GDateTime) now = g_date_time_new_now_local();
    g_autofree gchar* stamp = g_date_time_format(now, "%Y-%m-%dT%H:%M:%S.%f");
    return std::string(stamp) + " [" + level + "] " + vpn_plugin::cli_output::SanitizeUtf8(message);
}

/** One serial background thread: start/stop keep their order and never block the UI. */
class Worker {
 public:
    Worker() : thread_([this]() { Loop(); }) {}

    ~Worker() {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            done_ = true;
        }
        changed_.notify_all();
        thread_.join();  // runs what's queued first (a stop on exit)
    }

    void Post(std::function<void()> task) {
        {
            std::lock_guard<std::mutex> lock(mutex_);
            tasks_.push_back(std::move(task));
        }
        changed_.notify_all();
    }

 private:
    void Loop() {
        while (true) {
            std::function<void()> task;
            {
                std::unique_lock<std::mutex> lock(mutex_);
                changed_.wait(lock, [this]() { return done_ || !tasks_.empty(); });
                if (tasks_.empty()) return;
                task = std::move(tasks_.front());
                tasks_.pop_front();
            }
            task();
        }
    }

    std::mutex mutex_;
    std::condition_variable changed_;
    std::deque<std::function<void()>> tasks_;
    bool done_ = false;
    std::thread thread_;  // last: starts after the fields it uses
};

/**
 * The plugin proper. Shared: the GObject holds one reference, every state
 * update queued to the main loop another, so a late update never finds it
 * gone.
 */
class Plugin : public std::enable_shared_from_this<Plugin> {
 public:
    explicit Plugin(FlBinaryMessenger* messenger) {
        g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
        state_channel_ = fl_event_channel_new(messenger, "vpn_plugin_event_channel", FL_METHOD_CODEC(codec));
        fl_event_channel_set_stream_handlers(state_channel_, OnListen, OnCancel, this, nullptr);
        // The CLI has no per-connection query log; the channel exists because
        // the Dart side subscribes to it on every platform.
        query_log_channel_ =
                fl_event_channel_new(messenger, "vpn_plugin_event_channel_query_log", FL_METHOD_CODEC(codec));
        // Why the server couldn't be reached (helper event "failure"); live only, nothing is queued.
        failure_channel_ = fl_event_channel_new(messenger, "vpn_plugin_event_channel_failures", FL_METHOD_CODEC(codec));
        fl_event_channel_set_stream_handlers(failure_channel_, OnFailureListen, OnFailureCancel, this, nullptr);
    }

    ~Plugin() {
        g_clear_object(&state_channel_);
        g_clear_object(&query_log_channel_);
        g_clear_object(&failure_channel_);
    }

    /** After construction (needs weak_from_this): the helper connection and the first state. */
    void Init() {
        std::weak_ptr<Plugin> weak = weak_from_this();
        client_ = std::make_unique<vpn_plugin::HelperClient>(
                vpn_plugin::HelperClient::DefaultSocketPath(),
                [weak](const Json& event) {
                    auto self = weak.lock();
                    if (self && event.value("event", "") == "state") {
                        self->Notify(StateFromName(event.value("state", "")));
                    } else if (self && event.value("event", "") == "failure") {
                        self->NotifyFailure(event.value("failure", ""));
                    }
                },
                [weak]() {
                    if (auto self = weak.lock()) self->Notify(VPN_PLUGIN_VPN_MANAGER_STATE_DISCONNECTED);
                });
        worker_ = std::make_unique<Worker>();
        // The helper outlives the app: pick up a tunnel that is already up.
        worker_->Post([this]() {
            if (client_->Connect()) return;  // not installed or not running - Start() will say so
            std::string error;
            if (auto reply = client_->Request({{"cmd", "state"}}, kRequestTimeout, &error)) {
                Notify(StateFromName(reply->value("state", "")));
            }
        });
    }

    /** Main thread, from GObject dispose: disconnect, as Windows does when the window closes. */
    void Shutdown() {
        if (!worker_) return;
        worker_->Post([this]() {
            std::string error;
            if (!client_->Connect()) client_->Request({{"cmd", "stop"}}, kRequestTimeout, &error);
        });
        worker_.reset();  // waits for the stop
        client_.reset();
    }

    void Start(std::string config) {
        worker_->Post([this, config = std::move(config)]() {
            if (auto error = client_->Connect()) {
                Fail("Can't start the VPN: " + *error);
                return;
            }
            Notify(VPN_PLUGIN_VPN_MANAGER_STATE_CONNECTING);
            Json request = {{"cmd", "start"},
                            {"config", config},
                            {"log_level", vpn_plugin::cli_output::CliLogLevel(config)}};
            std::string error;
            auto reply = client_->Request(request, kRequestTimeout, &error);
            if (!reply) {
                Fail("Can't start the VPN: " + error);
            } else if (!reply->value("ok", false)) {
                Fail("The helper refused to start the VPN: " + reply->value("error", std::string("unknown error")));
            }
        });
    }

    void Stop() {
        worker_->Post([this]() {
            std::string error;
            if (client_->Connect() || !client_->Request({{"cmd", "stop"}}, kRequestTimeout, &error)) {
                Notify(VPN_PLUGIN_VPN_MANAGER_STATE_DISCONNECTED);
            }
        });
    }

    VpnPluginVpnManagerState state() const { return state_; }

    /**
     * Our own errors and the helper's CLI records in a new temp file,
     * records separated by 0x1E. Blocks the UI for at most kLogsTimeout.
     * @return a new reference to a list of paths.
     */
    FlValue* ExportLogs() {
        std::vector<std::string> records;
        {
            std::lock_guard<std::mutex> lock(local_mutex_);
            records.assign(local_records_.begin(), local_records_.end());
        }
        std::string error;
        std::optional<Json> reply;
        if (auto connect_error = client_->Connect()) {
            error = *connect_error;
        } else {
            reply = client_->Request({{"cmd", "logs"}, {"max", kMaxLogRecords}}, kLogsTimeout, &error);
        }
        if (reply && reply->contains("records") && (*reply)["records"].is_array()) {
            for (const auto& record : (*reply)["records"]) {
                if (record.is_string()) records.push_back(record.get<std::string>());
            }
        } else {
            records.push_back(LocalRecord("error", "No engine log from cattunnel-helper: " + error));
        }

        FlValue* paths = fl_value_new_list();
        // A fresh 0700 directory with an unpredictable name: /tmp is shared,
        // and a planted directory or symlink with a guessable name must not
        // receive the log.
        g_autoptr(GError) dir_error = nullptr;
        g_autofree gchar* dir = g_dir_make_tmp("cattunnel_linux_logs_XXXXXX", &dir_error);
        if (dir == nullptr) return paths;
        g_autofree gchar* file = g_build_filename(dir, "client.log", nullptr);
        std::ofstream out(file, std::ios::binary | std::ios::trunc);
        for (const auto& record : records) out << record << '\x1E';
        out.close();
        if (out) fl_value_append_take(paths, fl_value_new_string(file));
        return paths;
    }

    /** Our own records only: the engine log is root's, the helper bounds it. */
    void ClearLogs() {
        std::lock_guard<std::mutex> lock(local_mutex_);
        local_records_.clear();
    }

 private:
    void Fail(const std::string& message) {
        g_warning("vpn_plugin: %s", message.c_str());
        {
            std::lock_guard<std::mutex> lock(local_mutex_);
            local_records_.push_back(LocalRecord("error", message));
            if (local_records_.size() > 100) local_records_.pop_front();
        }
        Notify(VPN_PLUGIN_VPN_MANAGER_STATE_DISCONNECTED);
    }

    /** Any thread: the state goes to Dart on the main loop. */
    void Notify(VpnPluginVpnManagerState state) {
        struct Update {
            std::shared_ptr<Plugin> plugin;
            VpnPluginVpnManagerState state;
        };
        g_main_context_invoke_full(
                nullptr, G_PRIORITY_DEFAULT,
                [](gpointer data) -> gboolean {
                    auto* update = static_cast<Update*>(data);
                    update->plugin->Deliver(update->state);
                    return G_SOURCE_REMOVE;
                },
                new Update{shared_from_this(), state}, [](gpointer data) { delete static_cast<Update*>(data); });
    }

    /** Any thread: an engine failure tag goes to Dart on the main loop, if anyone listens. */
    void NotifyFailure(std::string failure) {
        struct Update {
            std::shared_ptr<Plugin> plugin;
            std::string failure;
        };
        g_main_context_invoke_full(
                nullptr, G_PRIORITY_DEFAULT,
                [](gpointer data) -> gboolean {
                    auto* update = static_cast<Update*>(data);
                    if (update->plugin->failure_listening_) {
                        g_autoptr(FlValue) value = fl_value_new_string(update->failure.c_str());
                        fl_event_channel_send(update->plugin->failure_channel_, value, nullptr, nullptr);
                    }
                    return G_SOURCE_REMOVE;
                },
                new Update{shared_from_this(), std::move(failure)},
                [](gpointer data) { delete static_cast<Update*>(data); });
    }

    static FlMethodErrorResponse* OnFailureListen(FlEventChannel*, FlValue*, gpointer user_data) {
        static_cast<Plugin*>(user_data)->failure_listening_ = true;
        return nullptr;
    }

    static FlMethodErrorResponse* OnFailureCancel(FlEventChannel*, FlValue*, gpointer user_data) {
        static_cast<Plugin*>(user_data)->failure_listening_ = false;
        return nullptr;
    }

    /** Main thread. Events wait for a listener, like the Windows stream handler. */
    void Deliver(VpnPluginVpnManagerState state) {
        state_ = state;
        if (!listening_) {
            pending_.push_back(state);
            return;
        }
        Send(state);
    }

    void Send(VpnPluginVpnManagerState state) {
        g_autoptr(FlValue) value = fl_value_new_int(state);
        g_autoptr(GError) error = nullptr;
        if (!fl_event_channel_send(state_channel_, value, nullptr, &error)) {
            g_warning("vpn_plugin: can't send the VPN state: %s", error->message);
        }
    }

    static FlMethodErrorResponse* OnListen(FlEventChannel*, FlValue*, gpointer user_data) {
        auto* self = static_cast<Plugin*>(user_data);
        self->listening_ = true;
        for (auto state : self->pending_) self->Send(state);
        self->pending_.clear();
        return nullptr;
    }

    static FlMethodErrorResponse* OnCancel(FlEventChannel*, FlValue*, gpointer user_data) {
        static_cast<Plugin*>(user_data)->listening_ = false;
        return nullptr;
    }

    FlEventChannel* state_channel_ = nullptr;
    FlEventChannel* query_log_channel_ = nullptr;
    FlEventChannel* failure_channel_ = nullptr;
    bool listening_ = false;
    bool failure_listening_ = false;
    std::deque<VpnPluginVpnManagerState> pending_;
    VpnPluginVpnManagerState state_ = VPN_PLUGIN_VPN_MANAGER_STATE_DISCONNECTED;

    std::mutex local_mutex_;
    std::deque<std::string> local_records_;

    std::unique_ptr<vpn_plugin::HelperClient> client_;
    std::unique_ptr<Worker> worker_;  // after client_: destroyed first, tasks never outlive the client
};

}  // namespace

struct _VpnPlugin {
    GObject parent_instance;
    std::shared_ptr<Plugin>* impl;
};

G_DEFINE_TYPE(VpnPlugin, vpn_plugin, g_object_get_type())

#define VPN_PLUGIN(obj) (G_TYPE_CHECK_INSTANCE_CAST((obj), vpn_plugin_get_type(), VpnPlugin))

static void vpn_plugin_dispose(GObject* object) {
    VpnPlugin* self = VPN_PLUGIN(object);
    if (self->impl != nullptr) {
        (*self->impl)->Shutdown();
        delete self->impl;
        self->impl = nullptr;
    }
    G_OBJECT_CLASS(vpn_plugin_parent_class)->dispose(object);
}

static void vpn_plugin_class_init(VpnPluginClass* klass) {
    G_OBJECT_CLASS(klass)->dispose = vpn_plugin_dispose;
}

static void vpn_plugin_init(VpnPlugin* self) {
    self->impl = nullptr;
}

static Plugin* impl_of(gpointer user_data) {
    return VPN_PLUGIN(user_data)->impl->get();
}

static VpnPluginIVpnManagerStartResponse* handle_start(const gchar* config, gpointer user_data) {
    impl_of(user_data)->Start(config != nullptr ? config : "");
    return vpn_plugin_i_vpn_manager_start_response_new();
}

static VpnPluginIVpnManagerStopResponse* handle_stop(gpointer user_data) {
    impl_of(user_data)->Stop();
    return vpn_plugin_i_vpn_manager_stop_response_new();
}

/** iOS only (the system VPN profile); here the config comes with start(). */
static VpnPluginIVpnManagerUpdateConfigurationResponse* handle_update_configuration(const gchar*, gpointer) {
    return vpn_plugin_i_vpn_manager_update_configuration_response_new();
}

static VpnPluginIVpnManagerGetCurrentStateResponse* handle_get_current_state(gpointer user_data) {
    return vpn_plugin_i_vpn_manager_get_current_state_response_new(impl_of(user_data)->state());
}

static VpnPluginIVpnManagerExportLogsResponse* handle_export_logs(gpointer user_data) {
    g_autoptr(FlValue) paths = impl_of(user_data)->ExportLogs();
    return vpn_plugin_i_vpn_manager_export_logs_response_new(paths);
}

static VpnPluginIVpnManagerClearLogsResponse* handle_clear_logs(gpointer user_data) {
    impl_of(user_data)->ClearLogs();
    return vpn_plugin_i_vpn_manager_clear_logs_response_new();
}

static const VpnPluginIVpnManagerVTable kVpnManagerVTable = {
        handle_start,
        handle_stop,
        handle_update_configuration,
        handle_get_current_state,
        handle_export_logs,
        handle_clear_logs,
};

void vpn_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
    VpnPlugin* plugin = VPN_PLUGIN(g_object_new(vpn_plugin_get_type(), nullptr));
    FlBinaryMessenger* messenger = fl_plugin_registrar_get_messenger(registrar);

    plugin->impl = new std::shared_ptr<Plugin>(std::make_shared<Plugin>(messenger));
    (*plugin->impl)->Init();

    vpn_plugin_i_vpn_manager_set_method_handlers(messenger, nullptr, &kVpnManagerVTable, g_object_ref(plugin),
                                                 g_object_unref);
    g_object_unref(plugin);
}
