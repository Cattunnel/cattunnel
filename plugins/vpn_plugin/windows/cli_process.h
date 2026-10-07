#pragma once

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#include "cli_output.h"

#include <filesystem>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>
#include <fstream>

namespace vpn_plugin {

/**
 * The public TrustTunnel CLI client (trusttunnel_client.exe, next to the app)
 * run as a child process.
 *
 * Why a process and not a library: the CLI is the same 1.1.x engine as the
 * Android build and is published openly with every release, while the
 * Windows library is a closed alpha behind a GitHub Packages token.
 *
 * The CLI prints its state changes as log lines
 * ("VPNCORE raise_state: [0] VPN_SS_CONNECTED"); they are the only state
 * source. The process exits on its own after VPN_SS_DISCONNECTED.
 *
 * The child is put into a job object that kills it when CatTunnel dies, so
 * a crashed app never leaves a tunnel (and its kill switch) behind. Its
 * DNS lives on the wintun adapter, which disappears with the process.
 */
class CliProcess {
public:
    using State = cli_output::CliState;

    using StateCallback = std::function<void(State)>;

    /**
     * @param log_path  Where the CLI output goes (rotated at kMaxLogBytes).
     * @param on_state  Called from the reader thread on every state line and
     *                  with kDisconnected once the process has exited.
     */
    CliProcess(std::filesystem::path log_path, StateCallback on_state);
    ~CliProcess();

    CliProcess(const CliProcess&) = delete;
    CliProcess& operator=(const CliProcess&) = delete;

    /**
     * Stops a running CLI, then starts `exe -c config_path -l log_level`. [config_path]
     * holds the credentials and is deleted as soon as the CLI has read it
     * (its first state line) or has exited.
     * @return Empty on success, otherwise a message for the log.
     */
    std::optional<std::string> Start(
            const std::filesystem::path& exe, const std::filesystem::path& config_path, const std::string& log_level);

    /** Ctrl+C to the CLI (clean shutdown), TerminateProcess after [timeout_ms]. */
    void Stop(DWORD timeout_ms = 5000);

    bool IsRunning();

    /** The current and the previous log file, if they exist. */
    std::vector<std::filesystem::path> LogFiles() const;

    void ClearLogs();

private:
    static constexpr uintmax_t kMaxLogBytes = 4 * 1024 * 1024;

    void ReadOutput(HANDLE pipe, HANDLE process, std::filesystem::path config_path);
    void HandleLine(const std::string& line, bool& config_deleted, const std::filesystem::path& config_path);
    void AppendLog(const std::string& line);
    void JoinReader();

    std::filesystem::path m_log_path;
    StateCallback m_on_state;

    std::mutex m_mutex;  // guards the handles below
    HANDLE m_job = nullptr;
    HANDLE m_process = nullptr;
    DWORD m_pid = 0;
    std::thread m_reader;

    std::mutex m_log_mutex;  // guards m_log
    std::ofstream m_log;
};

}  // namespace vpn_plugin
