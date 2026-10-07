// cattunnel-helper - the root part of CatTunnel for Linux. Protocol and rules:
// ../HELPER.md. Two ways to run (still to be chosen):
//   --system                  systemd service, /run/cattunnel/helper.sock,
//                             members of group "cattunnel" may connect
//   --socket PATH --uid UID   started by pkexec for one session: only UID may
//                             connect; exits when that app disconnects
// Other options (tests): --cli PATH --state-dir DIR --log FILE --no-system-dns
//                           --physical-iface NAME

#include <grp.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "cli_runner.h"
#include "config_guard.h"
#include "physical_link.h"
#include "system_dns.h"
#include "third_party/json.hpp"

using json = nlohmann::json;
using namespace cattunnel_helper;

namespace {

constexpr size_t kMaxLine = 1200 * 1024;  // a config (<= 1 MiB) JSON-escaped
constexpr int kProtocolVersion = 1;
constexpr const char* kEngineVersion = CATTUNNEL_ENGINE_VERSION;

struct Options {
    bool system = false;
    std::string socket_path;
    uid_t uid = static_cast<uid_t>(-1);
    bool system_dns = true;  // --no-system-dns: tests, never touch /etc/resolv.conf
    std::string physical_iface;  // --physical-iface NAME: tests (lo); default: detected
    Paths paths;
};

volatile sig_atomic_t g_stop = 0;

// Relay/probe threads at once; more are refused (a group member could
// otherwise open threads and descriptors without limit).
constexpr int kMaxDiagnosticThreads = 32;
std::atomic<int> g_diagnostic_threads{0};

// A client that doesn't finish its line within this is dropped, so it can't
// hold up the single poll loop.
constexpr int kReadTimeoutSeconds = 5;

/** request[key] if it is a string, else [fallback]: a wrong type must not throw (type_error aborted the helper). */
std::string Str(const json& request, const char* key, const std::string& fallback = "") {
    auto it = request.find(key);
    return it != request.end() && it->is_string() ? it->get<std::string>() : fallback;
}

/** request[key] if it is an integer, clamped to [low, high], else [fallback]. */
int Int(const json& request, const char* key, int fallback, int low, int high) {
    auto it = request.find(key);
    if (it == request.end() || !it->is_number_integer()) return fallback;
    long long value = it->get<long long>();
    return static_cast<int>(std::clamp<long long>(value, low, high));
}

const char* StateName(CliState state) {
    switch (state) {
        case CliState::kDisconnected: return "disconnected";
        case CliState::kConnecting: return "connecting";
        case CliState::kConnected: return "connected";
        case CliState::kWaitingRecovery: return "waiting_recovery";
        case CliState::kRecovering: return "recovering";
        case CliState::kWaitingForNetwork: return "waiting_for_network";
    }
    return "disconnected";
}

bool SendLine(int fd, const json& message) {
    std::string line = message.dump() + "\n";
    for (size_t sent = 0; sent < line.size();) {
        ssize_t n = send(fd, line.data() + sent, line.size() - sent, MSG_NOSIGNAL);
        if (n <= 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

/** The uid of the peer on [fd], or -1. */
uid_t PeerUid(int fd) {
    ucred cred{};
    socklen_t length = sizeof(cred);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &length) != 0) return static_cast<uid_t>(-1);
    return cred.uid;
}

/** Whether the peer on [fd] may talk to us (SO_PEERCRED, see HELPER.md). */
bool PeerAllowed(int fd, const Options& options) {
    ucred cred{};
    socklen_t length = sizeof(cred);
    if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &length) != 0) return false;
    if (!options.system) return cred.uid == options.uid;
    if (cred.uid == 0) return true;

    group* cattunnel = getgrnam("cattunnel");
    passwd* user = getpwuid(cred.uid);
    if (cattunnel == nullptr || user == nullptr) return false;
    int count = 64;
    std::vector<gid_t> groups(static_cast<size_t>(count));
    if (getgrouplist(user->pw_name, user->pw_gid, groups.data(), &count) < 0) return false;
    for (int i = 0; i < count; ++i) {
        if (groups[static_cast<size_t>(i)] == cattunnel->gr_gid) return true;
    }
    return false;
}

/** Reads one line (blocking, bounded). */
bool ReadLine(int fd, std::string* line) {
    line->clear();
    char c;
    while (line->size() < kMaxLine) {
        ssize_t n = recv(fd, &c, 1, 0);
        if (n <= 0) return false;
        if (c == '\n') return true;
        *line += c;
    }
    return false;
}

/**
 * A relay connection (HELPER.md): pinned connect, then raw bytes both ways.
 * Nothing is sent back on success - the app starts TLS on this socket right
 * away, so any reply would be read as the server's first bytes. A failed
 * connect just closes it; "probe" is the way to learn why.
 */
void ServeRelay(int client, json request, std::string iface) {
    std::string outcome;
    int remote = ConnectPinned(Str(request, "ip"), Int(request, "port", 0, 0, 65535), 5000, iface, &outcome);
    if (remote < 0) {
        close(client);
    } else {
        Pipe(client, remote);
    }
    --g_diagnostic_threads;
}

/** A one-shot probe connection: pinned TCP connect, {"outcome": ...}, close. */
void ServeProbe(int client, json request, std::string iface) {
    std::string outcome;
    int remote = ConnectPinned(Str(request, "ip"), Int(request, "port", 0, 0, 65535),
                               Int(request, "timeout_ms", 5000, 100, 10000), iface, &outcome);
    if (remote >= 0) close(remote);
    SendLine(client, {{"outcome", outcome}});
    close(client);
    --g_diagnostic_threads;
}

class Server {
 public:
    explicit Server(Options options) : options_(std::move(options)), cli_(options_.paths) {}

    int Run() {
        // A helper that died mid-session left the tunnel's resolv.conf (and
        // the CLI's ip rules) behind.
        if (options_.system_dns) {
            CleanUpCliRouting();
            cli_.Note(dns_.Restore());
        }
        listener_ = Listen();
        if (listener_ < 0) return 1;
        while (!g_stop) {
            std::vector<pollfd> fds = {{listener_, POLLIN, 0}};
            if (control_ >= 0) fds.push_back({control_, POLLIN, 0});
            if (cli_.fd() >= 0) fds.push_back({cli_.fd(), POLLIN, 0});
            int ready = poll(fds.data(), fds.size(), 1000);
            if (ready < 0 && errno != EINTR) break;

            for (const auto& p : fds) {
                if (!(p.revents & (POLLIN | POLLHUP | POLLERR))) continue;
                if (p.fd == listener_) Accept();
                else if (p.fd == control_) OnControl();
                else if (p.fd == cli_.fd()) {
                    auto changes = cli_.ReadOutput();
                    // Before the state it explains (waiting_recovery / disconnected).
                    for (const auto& failure : cli_.TakeFailures()) {
                        if (control_ >= 0) SendLine(control_, {{"event", "failure"}, {"failure", failure}});
                    }
                    Notify(changes);
                }
            }
            if (cli_.ReapIfExited()) {
                RestoreDns();
                Notify({CliState::kDisconnected});
            }
            if (session_over_) break;
        }
        cli_.Stop();
        RestoreDns();
        close(listener_);
        unlink(options_.socket_path.c_str());
        return 0;
    }

 private:
    int Listen() {
        sockaddr_un address{};
        address.sun_family = AF_UNIX;
        if (options_.socket_path.size() >= sizeof(address.sun_path)) return -1;
        strncpy(address.sun_path, options_.socket_path.c_str(), sizeof(address.sun_path) - 1);

        int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
        if (fd < 0) return -1;
        unlink(options_.socket_path.c_str());
        mode_t old = umask(0177);  // created 0600, widened below for --system
        int rc = bind(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address));
        umask(old);
        if (rc != 0 || listen(fd, 8) != 0) {
            perror("cattunnel-helper: socket");
            close(fd);
            return -1;
        }
        if (options_.system) {
            group* cattunnel = getgrnam("cattunnel");
            if (cattunnel != nullptr && chown(options_.socket_path.c_str(), 0, cattunnel->gr_gid) == 0) {
                chmod(options_.socket_path.c_str(), 0660);
            }
        } else if (chown(options_.socket_path.c_str(), options_.uid, static_cast<gid_t>(-1)) != 0) {
            perror("cattunnel-helper: chown socket");
        }
        return fd;
    }

    void Accept() {
        int client = accept4(listener_, nullptr, nullptr, SOCK_CLOEXEC);
        if (client < 0) return;
        if (!PeerAllowed(client, options_)) {
            close(client);
            return;
        }
        timeval timeout{kReadTimeoutSeconds, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        std::string line;
        json request;
        if (!ReadLine(client, &line) || !(request = json::parse(line, nullptr, false)).is_object()) {
            close(client);
            return;
        }
        // Diagnostics connections get their own thread: a connect may take
        // seconds and must not hold up the CLI's output or the app's commands.
        const std::string cmd = Str(request, "cmd");
        const uid_t uid = PeerUid(client);
        if (cmd == "relay" || cmd == "probe") {
            // While a tunnel is up, a connection around it is for its owner
            // only: another group member must not route around it.
            if (cli_.running() && !IsOwner(uid)) {
                close(client);
                return;
            }
            if (++g_diagnostic_threads > kMaxDiagnosticThreads) {
                --g_diagnostic_threads;
                close(client);
                return;
            }
            // Relayed TLS may idle for long: no read timeout on these.
            timeval none{0, 0};
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &none, sizeof(none));
            std::thread(cmd == "relay" ? ServeRelay : ServeProbe, client, std::move(request), Interface()).detach();
            return;
        }
        if (control_ >= 0) {  // one app at a time
            SendLine(client, {{"ok", false}, {"error", "busy"}});
            close(client);
            return;
        }
        control_ = client;
        control_uid_ = uid;
        Handle(request);
    }

    void OnControl() {
        std::string line;
        if (!ReadLine(control_, &line)) {
            close(control_);
            control_ = -1;
            // pkexec mode: the app is gone, so is the reason to be root.
            if (!options_.system) session_over_ = true;
            return;
        }
        json request = json::parse(line, nullptr, false);
        if (!request.is_object()) {
            SendLine(control_, {{"ok", false}, {"error", "bad request"}});
            return;
        }
        Handle(request);
    }

    void Handle(const json& request) {
        try {
            HandleUnchecked(request);
        } catch (const json::exception& e) {
            SendLine(control_, {{"ok", false}, {"error", "bad request"}});
        }
    }

    /** The session's owner (who started the tunnel) or root. No owner yet: anyone allowed in. */
    bool IsOwner(uid_t uid) const {
        return uid == 0 || owner_uid_ == static_cast<uid_t>(-1) || uid == owner_uid_;
    }

    void HandleUnchecked(const json& request) {
        const std::string cmd = Str(request, "cmd");
        // Another user's tunnel: they can see that it is up (state, hello),
        // but not stop it, replace it or read its log.
        if ((cmd == "stop" || cmd == "logs" || (cmd == "start" && cli_.running())) && !IsOwner(control_uid_)) {
            SendLine(control_, {{"ok", false}, {"error", "another user's session"}});
            return;
        }
        if (cmd == "hello") {
            SendLine(control_, {{"ok", true}, {"version", kProtocolVersion}, {"engine", kEngineVersion}});
        } else if (cmd == "start") {
            std::string config = Str(request, "config");
            if (auto error = CheckConfig(config)) {
                SendLine(control_, {{"ok", false}, {"error", *error}});
                return;
            }
            if (control_uid_ != owner_uid_) cli_.ClearRecords();
            auto error = cli_.Start(config, Str(request, "log_level", "info"));
            if (!error) owner_uid_ = control_uid_;
            if (!error && options_.system_dns) {
                // Fail closed: with the old resolv.conf, DNS would go around the tunnel.
                std::string dns = dns_.Apply(kTunnelDnsServers);
                cli_.Note(dns);
                if (dns.rfind("DNS NOT SET", 0) == 0) {
                    cli_.Stop();
                    RestoreDns();
                    error = dns;
                }
            }
            SendLine(control_, error ? json{{"ok", false}, {"error", *error}} : json{{"ok", true}});
        } else if (cmd == "stop") {
            cli_.Stop();
            RestoreDns();
            SendLine(control_, {{"ok", true}});
            Notify({CliState::kDisconnected});
        } else if (cmd == "state") {
            SendLine(control_, {{"state", StateName(cli_.state())}});
        } else if (cmd == "logs") {
            SendLine(control_, {{"records", cli_.Records(static_cast<size_t>(Int(request, "max", 500, 0, 5000)))}});
        } else if (cmd == "probe_tcp") {
            std::string outcome;
            int s = ConnectPinned(Str(request, "ip"), Int(request, "port", 0, 0, 65535),
                                  Int(request, "timeout_ms", 5000, 100, 10000), Interface(), &outcome);
            if (s >= 0) close(s);
            SendLine(control_, {{"outcome", outcome}});
        } else {
            SendLine(control_, {{"ok", false}, {"error", "unknown command"}});
        }
    }

    /** After the CLI is gone: DNS back, and its routing if it couldn't clean up itself. */
    void RestoreDns() {
        if (!options_.system_dns) return;
        CleanUpCliRouting();
        cli_.Note(dns_.Restore());
    }

    /** The physical interface, or --physical-iface (tests). */
    std::string Interface() const {
        return options_.physical_iface.empty() ? PhysicalInterface() : options_.physical_iface;
    }

    void Notify(const std::vector<CliState>& changes) {
        if (control_ < 0) return;
        for (CliState state : changes) SendLine(control_, {{"event", "state"}, {"state", StateName(state)}});
    }

    Options options_;
    CliRunner cli_;
    SystemDns dns_;
    int listener_ = -1;
    int control_ = -1;
    uid_t control_uid_ = static_cast<uid_t>(-1);
    // Who started the current (or last) tunnel; keeps its log theirs too.
    uid_t owner_uid_ = static_cast<uid_t>(-1);
    bool session_over_ = false;
};

bool ParseArgs(int argc, char** argv, Options* options) {
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        auto next = [&]() -> std::string { return i + 1 < argc ? argv[++i] : ""; };
        if (arg == "--system") options->system = true;
        else if (arg == "--socket") options->socket_path = next();
        else if (arg == "--uid") options->uid = static_cast<uid_t>(strtoul(next().c_str(), nullptr, 10));
        else if (arg == "--cli") options->paths.cli = next();
        else if (arg == "--state-dir") options->paths.state_dir = next();
        else if (arg == "--log") options->paths.log_file = next();
        else if (arg == "--no-system-dns") options->system_dns = false;
        else if (arg == "--physical-iface") options->physical_iface = next();
        else return false;
    }
    if (options->system) {
        if (options->socket_path.empty()) options->socket_path = "/run/cattunnel/helper.sock";
        return true;
    }
    return !options->socket_path.empty() && options->uid != static_cast<uid_t>(-1);
}

}  // namespace

int main(int argc, char** argv) {
    Options options;
    if (!ParseArgs(argc, argv, &options)) {
        fprintf(stderr, "usage: cattunnel-helper --system | --socket PATH --uid UID\n");
        return 2;
    }
    signal(SIGPIPE, SIG_IGN);
    struct sigaction stop {};
    stop.sa_handler = [](int) { g_stop = 1; };
    sigaction(SIGTERM, &stop, nullptr);
    sigaction(SIGINT, &stop, nullptr);
    umask(0077);
    return Server(std::move(options)).Run();
}
