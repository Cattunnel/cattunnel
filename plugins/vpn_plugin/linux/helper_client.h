#pragma once

// The app's side of the cattunnel-helper protocol (helper/../HELPER.md):
// newline-delimited JSON over a unix socket. One control connection; the
// helper's unprompted events go to [on_event], replies to the caller of
// Request(). Plain C++17 + POSIX so it can be tested without Flutter.

#include <chrono>
#include <condition_variable>
#include <deque>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "third_party/json.hpp"

namespace vpn_plugin {

class HelperClient {
 public:
    using Json = nlohmann::json;

    /** Where the systemd service listens; CATTUNNEL_HELPER_SOCKET overrides (tests, pkexec mode). */
    static std::string DefaultSocketPath();

    /**
     * @param on_event called on the reader thread for every event line.
     * @param on_closed called on the reader thread when the helper hangs up.
     */
    HelperClient(std::string socket_path, std::function<void(const Json&)> on_event,
                 std::function<void()> on_closed);
    ~HelperClient();

    HelperClient(const HelperClient&) = delete;
    HelperClient& operator=(const HelperClient&) = delete;

    /** Connects and says hello unless already connected. @return an error, or nullopt. */
    std::optional<std::string> Connect();

    /** Closes the connection (the helper keeps running). */
    void Disconnect();

    /**
     * Sends [request] and waits for its reply. Requests are serialized.
     * @return the reply, or nullopt with [error] set (not connected, timeout, hang-up).
     */
    std::optional<Json> Request(const Json& request, std::chrono::milliseconds timeout, std::string* error);

 private:
    void ReadLoop(int fd);
    bool SendLine(int fd, const Json& message);

    const std::string socket_path_;
    const std::function<void(const Json&)> on_event_;
    const std::function<void()> on_closed_;

    std::mutex request_mutex_;  // one request in flight

    std::mutex mutex_;  // guards everything below
    std::condition_variable replies_changed_;
    std::deque<Json> replies_;
    int fd_ = -1;
    uint64_t generation_ = 0;  // bumped on every connect, so a stale reader can't close a new socket
    std::thread reader_;
};

}  // namespace vpn_plugin
