// Copyright 2024 TrustTunnel contributors. All rights reserved.
// Use of this source code is governed by a BSD-style license.

#include "vpn_plugin.h"

#include <ShlObj.h>

#include <cstdarg>
#include <cstdio>
#include <fstream>

namespace vpn_plugin {

/**
 * Minimal Windows-native logging: OutputDebugStringA (DebugView, debugger).
 * @param fmt Printf-style format string.
 */
static void LogError(const char* fmt, ...) {
    char buf[512];
    va_list args;
    va_start(args, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);
    if (n > 0) {
        OutputDebugStringA(buf);
        OutputDebugStringA("\n");
    }
}

/**
 * Return the directory containing the running executable.
 * Uses dynamic allocation to avoid MAX_PATH truncation.
 * @return Parent directory of the executable, or empty path on failure.
 */
static std::filesystem::path GetExeDir() {
    std::wstring exe_path;
    DWORD buf_size = MAX_PATH;
    do {
        exe_path.resize(buf_size);
        DWORD len = GetModuleFileNameW(nullptr, exe_path.data(), buf_size);
        if (len == 0) {
            LogError("GetModuleFileNameW failed (error: %lu)", GetLastError());
            return {};
        }
        if (len < buf_size) {
            exe_path.resize(len);
            break;
        }
        buf_size *= 2;
    } while (true);
    return std::filesystem::path(exe_path).parent_path();
}

/**
 * %LOCALAPPDATA%\CatTunnel - per user, so the config with the password is
 * readable only by this user (and administrators), unlike the app folder,
 * which may be shared or read-only. Falls back to the exe folder.
 */
static std::filesystem::path GetDataDir() {
    PWSTR local = nullptr;
    std::filesystem::path dir;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) {
        dir = std::filesystem::path(local) / L"CatTunnel";
    } else {
        dir = GetExeDir();
    }
    CoTaskMemFree(local);
    std::error_code ec;
    std::filesystem::create_directories(dir, ec);
    return dir;
}

// ---------------------------------------------------------------------------
// VpnEventStreamHandler
// ---------------------------------------------------------------------------

void VpnEventStreamHandler::SendEvent(
        const flutter::EncodableValue& event) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_sink) {
        m_sink->Success(event);
    } else {
        m_event_queue.push(event);
    }
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
VpnEventStreamHandler::OnListenInternal(
        const flutter::EncodableValue* /*arguments*/,
        std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&& events) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_sink = std::move(events);
    while (!m_event_queue.empty()) {
        m_sink->Success(m_event_queue.front());
        m_event_queue.pop();
    }
    return nullptr;
}

std::unique_ptr<flutter::StreamHandlerError<flutter::EncodableValue>>
VpnEventStreamHandler::OnCancelInternal(
        const flutter::EncodableValue* /*arguments*/) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_sink.reset();
    return nullptr;
}

// ---------------------------------------------------------------------------
// VpnPlugin
// ---------------------------------------------------------------------------

void VpnPlugin::RegisterWithRegistrar(
        flutter::PluginRegistrarWindows* registrar) {
    auto plugin = std::make_unique<VpnPlugin>(registrar);

    // Register IVpnManager with Pigeon generated handler
    IVpnManager::SetUp(registrar->messenger(), plugin.get());

    registrar->AddPlugin(std::move(plugin));
}

VpnPlugin::VpnPlugin(flutter::PluginRegistrarWindows* registrar)
    : m_registrar(registrar), m_data_dir(GetDataDir()) {
    auto state_handler = std::make_unique<VpnEventStreamHandler>();
    m_state_handler = state_handler.get();
    m_state_channel =
            std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
                    registrar->messenger(), "vpn_plugin_event_channel",
                    &flutter::StandardMethodCodec::GetInstance());
    m_state_channel->SetStreamHandler(std::move(state_handler));

    m_query_log_channel =
            std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
                    registrar->messenger(),
                    "vpn_plugin_event_channel_query_log",
                    &flutter::StandardMethodCodec::GetInstance());
    m_query_log_channel->SetStreamHandler(std::make_unique<VpnEventStreamHandler>());

    m_physical_net_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "cattunnel/physical_net",
            &flutter::StandardMethodCodec::GetInstance());
    m_physical_net_channel->SetMethodCallHandler(
            [this](const auto& call, auto result) { HandlePhysicalNet(call, std::move(result)); });

    m_cli = std::make_unique<CliProcess>(
            m_data_dir / L"logs" / L"client.log",
            [this](CliProcess::State state) {
                // Same order as VpnManagerState (cli_output.h).
                NotifyStateChanged(static_cast<VpnManagerState>(state));
            });
}

/**
 * "relay" -> {port, token}; "probeTcp" {ip, port, timeoutMs} -> "ok" /
 * "timeout" / "refused" / "failed" (off the UI thread - it blocks).
 */
void VpnPlugin::HandlePhysicalNet(const flutter::MethodCall<flutter::EncodableValue>& call,
                                  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    using flutter::EncodableMap;
    using flutter::EncodableValue;

    if (call.method_name() == "relay") {
        int port = m_physical_net.RelayPort();
        if (port == 0) {
            result->Success();
            return;
        }
        result->Success(EncodableValue(EncodableMap{
                {EncodableValue("port"), EncodableValue(port)},
                {EncodableValue("token"), EncodableValue(m_physical_net.Token())},
        }));
        return;
    }

    if (call.method_name() == "probeTcp") {
        const auto* args = std::get_if<EncodableMap>(call.arguments());
        auto get = [args](const char* key) -> const EncodableValue* {
            if (args == nullptr) return nullptr;
            auto it = args->find(EncodableValue(key));
            return it == args->end() ? nullptr : &it->second;
        };
        const auto* ip = get("ip") ? std::get_if<std::string>(get("ip")) : nullptr;
        const auto* port = get("port") ? std::get_if<int32_t>(get("port")) : nullptr;
        const auto* timeout = get("timeoutMs") ? std::get_if<int32_t>(get("timeoutMs")) : nullptr;
        if (ip == nullptr || port == nullptr || timeout == nullptr) {
            result->Error("bad_args", "ip, port and timeoutMs are required");
            return;
        }
        std::shared_ptr<flutter::MethodResult<EncodableValue>> shared(std::move(result));
        std::thread([this, shared, ip = *ip, port = *port, timeout = *timeout]() {
            std::string outcome = PhysicalNet::ProbeTcp(ip, port, timeout);
            m_dispatcher.RunOnUIThread([shared, outcome]() { shared->Success(EncodableValue(outcome)); });
        }).detach();
        return;
    }

    result->NotImplemented();
}

VpnPlugin::~VpnPlugin() {
    // Disconnect cleanly when the window closes; the job object would kill
    // the CLI anyway, but without restoring routes first.
    m_worker.Sync([this]() { m_cli.reset(); });
}

std::optional<FlutterError> VpnPlugin::Start(const std::string& config) {
    m_worker.Post([this, config = config]() {
        // Unique per start: the previous CLI deletes its own file when it
        // exits, which may be after this one is written.
        static uint64_t start_counter = 0;
        std::filesystem::path config_path = m_data_dir /
                (L"client-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(++start_counter) +
                        L".toml");
        {
            std::ofstream file(config_path, std::ios::binary | std::ios::trunc);
            file << config;
            if (!file) {
                LogError("Failed to write the VPN config");
                NotifyStateChanged(VpnManagerState::kDisconnected);
                return;
            }
        }

        NotifyStateChanged(VpnManagerState::kConnecting);
        if (auto error = m_cli->Start(GetExeDir() / L"trusttunnel_client.exe", config_path,
                    cli_output::CliLogLevel(config))) {
            LogError("Failed to start trusttunnel_client: %s", error->c_str());
            std::error_code ignored;
            std::filesystem::remove(config_path, ignored);
            NotifyStateChanged(VpnManagerState::kDisconnected);
        }
    });

    return std::nullopt;
}

std::optional<FlutterError> VpnPlugin::Stop() {
    m_worker.Post([this]() { m_cli->Stop(); });

    return std::nullopt;
}

std::optional<FlutterError> VpnPlugin::UpdateConfiguration(
        const std::string* /*config*/) {
    return std::nullopt;
}

ErrorOr<VpnManagerState> VpnPlugin::GetCurrentState() {
    return ErrorOr<VpnManagerState>(m_current_state);
}

void VpnPlugin::NotifyStateChanged(VpnManagerState state) {
    m_dispatcher.RunOnUIThread([this, state]() {
        m_current_state = state;
        if (m_state_handler) {
            m_state_handler->SendEvent(
                    flutter::EncodableValue(static_cast<int64_t>(state)));
        }
    });
}

ErrorOr<flutter::EncodableList> VpnPlugin::ExportLogs() {
    // Unique temp export dir per call; the caller owns cleanup.
    std::filesystem::path export_dir =
            std::filesystem::temp_directory_path() /
            (L"cattunnel_windows_logs_" + std::to_wstring(GetTickCount64()));
    std::error_code ec;
    std::filesystem::create_directories(export_dir, ec);

    flutter::EncodableList result;
    for (const auto& log : m_cli->LogFiles()) {
        std::filesystem::path target = export_dir / log.filename();
        if (!std::filesystem::copy_file(log, target, std::filesystem::copy_options::overwrite_existing, ec)) {
            continue;
        }
        // Dart strings are UTF-8; transcode the native wide path.
        std::u8string u8 = target.u8string();
        result.push_back(flutter::EncodableValue(std::string(u8.begin(), u8.end())));
    }
    return ErrorOr<flutter::EncodableList>(result);
}

std::optional<FlutterError> VpnPlugin::ClearLogs() {
    m_cli->ClearLogs();
    return std::nullopt;
}

}  // namespace vpn_plugin
