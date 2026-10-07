#include "helper_client.h"

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cerrno>
#include <cstdlib>
#include <cstring>

namespace vpn_plugin {

namespace {

constexpr size_t kMaxLine = 4 * 1024 * 1024;  // a "logs" reply of 5000 records
constexpr int kProtocolVersion = 1;

}  // namespace

std::string HelperClient::DefaultSocketPath() {
    const char* custom = getenv("CATTUNNEL_HELPER_SOCKET");
    return custom != nullptr && *custom != '\0' ? custom : "/run/cattunnel/helper.sock";
}

HelperClient::HelperClient(std::string socket_path, std::function<void(const Json&)> on_event,
                           std::function<void()> on_closed)
    : socket_path_(std::move(socket_path)), on_event_(std::move(on_event)), on_closed_(std::move(on_closed)) {}

HelperClient::~HelperClient() {
    Disconnect();
}

std::optional<std::string> HelperClient::Connect() {
    std::lock_guard<std::mutex> request_lock(request_mutex_);
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (fd_ >= 0) return std::nullopt;
    }

    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    if (socket_path_.size() >= sizeof(address.sun_path)) return "helper socket path too long";
    strncpy(address.sun_path, socket_path_.c_str(), sizeof(address.sun_path) - 1);

    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return std::string("socket: ") + strerror(errno);
    if (connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        std::string error = errno == ENOENT ? "cattunnel-helper is not running (" + socket_path_ + ")"
                          : errno == EACCES ? "no access to " + socket_path_ + " (is the user in group cattunnel?)"
                                            : "connect " + socket_path_ + ": " + strerror(errno);
        close(fd);
        return error;
    }
    if (!SendLine(fd, {{"cmd", "hello"}, {"version", kProtocolVersion}})) {
        close(fd);
        return "helper hung up";
    }

    // The hello reply comes before any event; read it here, then hand the
    // socket to the reader thread.
    std::string line;
    char c;
    while (true) {
        ssize_t n = recv(fd, &c, 1, 0);
        if (n <= 0) {
            close(fd);
            return "helper hung up (another CatTunnel window connected?)";
        }
        if (c == '\n') break;
        line += c;
    }
    Json hello = Json::parse(line, nullptr, false);
    if (!hello.is_object() || !hello.value("ok", false)) {
        close(fd);
        std::string reason = hello.is_object() ? hello.value("error", "") : "";
        return reason == "busy" ? "the helper is serving another CatTunnel window" : "helper refused: " + line;
    }
    if (hello.value("version", 0) != kProtocolVersion) {
        close(fd);
        return "helper protocol version mismatch";
    }

    // A reader of an earlier connection has finished (fd_ was -1) but may
    // still be in on_closed_; join it without holding mutex_, which it takes.
    std::unique_lock<std::mutex> lock(mutex_);
    std::thread old_reader = std::move(reader_);
    lock.unlock();
    if (old_reader.joinable()) old_reader.join();
    lock.lock();
    fd_ = fd;
    ++generation_;
    replies_.clear();
    reader_ = std::thread(&HelperClient::ReadLoop, this, fd);
    return std::nullopt;
}

void HelperClient::Disconnect() {
    std::unique_lock<std::mutex> lock(mutex_);
    if (fd_ >= 0) shutdown(fd_, SHUT_RDWR);  // wakes the reader, which closes it
    std::thread reader = std::move(reader_);
    lock.unlock();
    if (reader.joinable()) reader.join();
}

std::optional<HelperClient::Json> HelperClient::Request(const Json& request, std::chrono::milliseconds timeout,
                                                         std::string* error) {
    std::lock_guard<std::mutex> request_lock(request_mutex_);
    std::unique_lock<std::mutex> lock(mutex_);
    if (fd_ < 0) {
        *error = "not connected to the helper";
        return std::nullopt;
    }
    replies_.clear();  // a late reply to a request that timed out
    uint64_t generation = generation_;
    if (!SendLine(fd_, request)) {
        *error = "helper hung up";
        return std::nullopt;
    }
    bool answered = replies_changed_.wait_for(lock, timeout, [&]() {
        return !replies_.empty() || fd_ < 0 || generation_ != generation;
    });
    if (!replies_.empty() && generation_ == generation) {
        Json reply = std::move(replies_.front());
        replies_.pop_front();
        return reply;
    }
    *error = answered ? "helper hung up" : "helper did not answer in time";
    return std::nullopt;
}

bool HelperClient::SendLine(int fd, const Json& message) {
    std::string line = message.dump() + "\n";
    for (size_t sent = 0; sent < line.size();) {
        ssize_t n = send(fd, line.data() + sent, line.size() - sent, MSG_NOSIGNAL);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        sent += static_cast<size_t>(n);
    }
    return true;
}

void HelperClient::ReadLoop(int fd) {
    std::string buffer;
    char chunk[16 * 1024];
    while (true) {
        ssize_t n = recv(fd, chunk, sizeof(chunk), 0);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) break;
        buffer.append(chunk, static_cast<size_t>(n));
        if (buffer.size() > kMaxLine && buffer.find('\n') == std::string::npos) break;  // not our protocol

        size_t start = 0;
        for (size_t end; (end = buffer.find('\n', start)) != std::string::npos; start = end + 1) {
            Json message = Json::parse(buffer.begin() + static_cast<std::ptrdiff_t>(start),
                                       buffer.begin() + static_cast<std::ptrdiff_t>(end), nullptr, false);
            if (!message.is_object()) continue;
            if (message.contains("event")) {
                on_event_(message);  // replies never carry "event" (HELPER.md)
            } else {
                std::lock_guard<std::mutex> lock(mutex_);
                replies_.push_back(std::move(message));
                replies_changed_.notify_all();
            }
        }
        buffer.erase(0, start);
    }

    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (fd_ == fd) fd_ = -1;
        replies_changed_.notify_all();
    }
    close(fd);
    on_closed_();
}

}  // namespace vpn_plugin
