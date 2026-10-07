#pragma once

#include <sys/types.h>

#include <deque>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include "cli_output.h"

namespace cattunnel_helper {

using vpn_plugin::cli_output::CliState;

/** Where things live; the defaults are the installed layout. */
struct Paths {
    std::string cli = "/usr/lib/cattunnel/trusttunnel_client";
    std::string state_dir = "/run/cattunnel";  // client.toml, root 0600
    std::string log_file = "/var/log/cattunnel/client.log";
};

/**
 * One trusttunnel_client process at a time. The config is checked by the
 * caller (CheckConfig); here it's written root-only and the CLI started with
 * absolute paths and a clean environment. Output goes through a pipe the
 * caller polls ([fd]) and reads with [ReadOutput].
 */
class CliRunner {
 public:
    explicit CliRunner(Paths paths);
    ~CliRunner();

    CliRunner(const CliRunner&) = delete;
    CliRunner& operator=(const CliRunner&) = delete;

    /** Stops a running CLI first. @return an error, or nullopt. */
    std::optional<std::string> Start(const std::string& config, const std::string& log_level);

    /** Forgets the in-memory log (a new user's session must not see the last one's). */
    void ClearRecords() {
        records_.clear();
        records_bytes_ = 0;
    }

    /** SIGINT (the CLI's clean shutdown: routes, DNS), SIGTERM after 5 s, SIGKILL after 2 more. */
    void Stop();

    bool running() const { return pid_ > 0; }
    int fd() const { return pipe_fd_; }
    CliState state() const { return state_; }

    /** Reads what's available; returns the state changes seen, in order. */
    std::vector<CliState> ReadOutput();

    /** Reaps an exited CLI. @return true if it just ended (state -> disconnected). */
    bool ReapIfExited();

    /** The last [max] records, oldest first. */
    std::vector<std::string> Records(size_t max) const;

    /** Adds "=== CatTunnel: [message] ===" to the records (what the helper itself did). */
    void Note(const std::string& message);

    /** Why the server couldn't be reached, as tagged by the engine, since the last call. */
    std::vector<std::string> TakeFailures() { return std::exchange(failures_, {}); }

    /** Feeds one line of CLI output (public for tests). */
    std::optional<CliState> OnLine(const std::string& line);

 private:
    void CloseOutput();
    void AddRecord(std::string record);

    Paths paths_;
    pid_t pid_ = -1;
    int pipe_fd_ = -1;
    std::string partial_;
    CliState state_ = CliState::kDisconnected;
    std::deque<std::string> records_;
    std::vector<std::string> failures_;
    size_t records_bytes_ = 0;
};

}  // namespace cattunnel_helper
