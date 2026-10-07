#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <queue>
#include <string>

#include "background_worker.h"
#include "cli_process.h"
#include "physical_net.h"
#include "runner/platform_api.g.h"
#include "ui_thread_dispatcher.h"

namespace vpn_plugin {

class VpnEventStreamHandler
    : public flutter::StreamHandler<flutter::EncodableValue> {
public:
    VpnEventStreamHandler() = default;
    virtual ~VpnEventStreamHandler() = default;

    /**
     * Send an event to the Flutter side via the event channel.
     * If no listener is active, the event is queued and delivered on the next listen.
     * @param event The event value to send.
     */
    void SendEvent(const flutter::EncodableValue& event);

protected:
    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
    OnListenInternal(
            const flutter::EncodableValue* arguments,
            std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events)
            override;

    std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
    OnCancelInternal(const flutter::EncodableValue* arguments) override;

private:
    std::mutex m_mutex;
    std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> m_sink;
    std::queue<flutter::EncodableValue> m_event_queue;
};

/**
 * Windows VPN: runs the public TrustTunnel CLI client (trusttunnel_client.exe
 * next to the app, version from ENGINE_VERSION) with the config the Dart
 * side encodes - the same TOML the CLI reads. See CliProcess.
 *
 * The CLI needs administrator rights (wintun), so CatTunnel.exe asks for
 * them in its manifest.
 */
class VpnPlugin : public flutter::Plugin, public IVpnManager {
public:
    static void RegisterWithRegistrar(
            flutter::PluginRegistrarWindows* registrar);

    VpnPlugin(flutter::PluginRegistrarWindows* registrar);
    ~VpnPlugin() override;

    VpnPlugin(const VpnPlugin&) = delete;
    VpnPlugin& operator=(const VpnPlugin&) = delete;

    /** Writes [config] to a private file and (re)starts the CLI with it. */
    std::optional<FlutterError> Start(const std::string& config) override;

    /** Stops the CLI (Ctrl+C, then terminate). */
    std::optional<FlutterError> Stop() override;

    /** No-op on Windows: configuration is passed via Start(). */
    std::optional<FlutterError> UpdateConfiguration(
            const std::string* config) override;

    ErrorOr<VpnManagerState> GetCurrentState() override;

    /** Copies the CLI log files into a new temp directory, returns their paths. */
    ErrorOr<flutter::EncodableList> ExportLogs() override;

    std::optional<FlutterError> ClearLogs() override;

private:
    /** Any thread: forwards a CLI state to Dart on the UI thread. */
    void NotifyStateChanged(VpnManagerState state);

    flutter::PluginRegistrarWindows* m_registrar;
    UIThreadDispatcher m_dispatcher;
    BackgroundWorker m_worker;

    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
            m_state_channel;
    // The CLI has no per-connection query log; the channel exists because
    // the Dart side subscribes to it on every platform.
    std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
            m_query_log_channel;

    VpnEventStreamHandler* m_state_handler = nullptr;

    std::filesystem::path m_data_dir;
    std::unique_ptr<CliProcess> m_cli;

    // cattunnel/physical_net: diagnostics and latency tests over the physical
    // adapter while the tunnel is up (see PhysicalNet).
    PhysicalNet m_physical_net;
    std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> m_physical_net_channel;
    void HandlePhysicalNet(const flutter::MethodCall<flutter::EncodableValue>& call,
                           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

    VpnManagerState m_current_state = VpnManagerState::kDisconnected;
};

}  // namespace vpn_plugin
