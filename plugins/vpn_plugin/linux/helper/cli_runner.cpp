#include "cli_runner.h"

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstring>
#include <ctime>
#include <fstream>
#include <thread>

namespace cattunnel_helper {

namespace {

constexpr size_t kMaxRecordBytes = 2 * 1024 * 1024;
constexpr size_t kMaxLineBytes = 64 * 1024;
constexpr off_t kMaxLogFileBytes = 8 * 1024 * 1024;

std::string Now() {
    timespec ts{};
    clock_gettime(CLOCK_REALTIME, &ts);
    tm local{};
    localtime_r(&ts.tv_sec, &local);
    char buf[40];
    size_t n = strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%S", &local);
    snprintf(buf + n, sizeof(buf) - n, ".%03ld", ts.tv_nsec / 1000000);
    return buf;
}

/** Waits up to [timeout] for [pid] to exit. */
bool WaitExit(pid_t pid, std::chrono::milliseconds timeout) {
    auto deadline = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < deadline) {
        pid_t r = waitpid(pid, nullptr, WNOHANG);
        if (r == pid || (r < 0 && errno == ECHILD)) return true;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    return false;
}

}  // namespace

CliRunner::CliRunner(Paths paths) : paths_(std::move(paths)) {}

CliRunner::~CliRunner() { Stop(); }

std::optional<std::string> CliRunner::Start(const std::string& config, const std::string& log_level) {
    Stop();

    // Root-only config: it carries the VPN password.
    mkdir(paths_.state_dir.c_str(), 0700);
    std::string config_path = paths_.state_dir + "/client.toml";
    int cfd = open(config_path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (cfd < 0) return std::string("can't write the config: ") + strerror(errno);
    fchmod(cfd, 0600);
    bool written = write(cfd, config.data(), config.size()) == static_cast<ssize_t>(config.size());
    close(cfd);
    if (!written) return "can't write the config";

    int pipe_fds[2];
    if (pipe2(pipe_fds, O_CLOEXEC) != 0) return std::string("pipe: ") + strerror(errno);

    std::string level = log_level == "debug" || log_level == "trace" ? log_level : "info";
    pid_t pid = fork();
    if (pid < 0) {
        close(pipe_fds[0]);
        close(pipe_fds[1]);
        return std::string("fork: ") + strerror(errno);
    }
    if (pid == 0) {
        // Child: own process group (so SIGINT reaches only the CLI), output to
        // the pipe, nothing inherited from the helper's environment.
        setpgid(0, 0);
        dup2(pipe_fds[1], STDOUT_FILENO);
        dup2(pipe_fds[1], STDERR_FILENO);
        int devnull = open("/dev/null", O_RDONLY);
        if (devnull >= 0) dup2(devnull, STDIN_FILENO);
        const char* argv[] = {paths_.cli.c_str(), "-c", config_path.c_str(), "-l", level.c_str(), nullptr};
        // The CLI runs `ip` and `resolvectl` itself.
        const char* envp[] = {"PATH=/usr/sbin:/usr/bin:/sbin:/bin", "LANG=C.UTF-8", nullptr};
        execve(paths_.cli.c_str(), const_cast<char* const*>(argv), const_cast<char* const*>(envp));
        _exit(127);
    }
    close(pipe_fds[1]);
    pipe_fd_ = pipe_fds[0];
    fcntl(pipe_fd_, F_SETFL, fcntl(pipe_fd_, F_GETFL) | O_NONBLOCK);
    pid_ = pid;
    AddRecord(Now() + " [info] === CatTunnel: starting trusttunnel_client (pid " + std::to_string(pid) + ") ===");
    return std::nullopt;
}

void CliRunner::Stop() {
    if (pid_ <= 0) return;
    kill(pid_, SIGINT);
    if (!WaitExit(pid_, std::chrono::seconds(5))) {
        AddRecord(Now() + " [info] === CatTunnel: the client didn't stop in time, terminating ===");
        kill(pid_, SIGTERM);
        if (!WaitExit(pid_, std::chrono::seconds(2))) {
            kill(pid_, SIGKILL);
            WaitExit(pid_, std::chrono::seconds(2));
        }
    }
    ReadOutput();
    pid_ = -1;
    CloseOutput();
    state_ = CliState::kDisconnected;
    unlink((paths_.state_dir + "/client.toml").c_str());
}

bool CliRunner::ReapIfExited() {
    if (pid_ <= 0) return false;
    int status = 0;
    if (waitpid(pid_, &status, WNOHANG) != pid_) return false;
    ReadOutput();
    AddRecord(Now() + " [info] === CatTunnel: the client exited with code " +
              std::to_string(WIFEXITED(status) ? WEXITSTATUS(status) : -1) + " ===");
    pid_ = -1;
    CloseOutput();
    state_ = CliState::kDisconnected;
    unlink((paths_.state_dir + "/client.toml").c_str());
    return true;
}

std::vector<CliState> CliRunner::ReadOutput() {
    std::vector<CliState> changes;
    if (pipe_fd_ < 0) return changes;
    char buf[8192];
    for (;;) {
        ssize_t n = read(pipe_fd_, buf, sizeof(buf));
        if (n <= 0) break;
        partial_.append(buf, static_cast<size_t>(n));
        size_t start = 0;
        for (size_t nl; (nl = partial_.find('\n', start)) != std::string::npos; start = nl + 1) {
            if (auto state = OnLine(partial_.substr(start, nl - start))) changes.push_back(*state);
        }
        partial_.erase(0, start);
        if (partial_.size() > kMaxLineBytes) {
            OnLine(partial_);
            partial_.clear();
        }
    }
    return changes;
}

std::optional<CliState> CliRunner::OnLine(const std::string& raw) {
    std::string line = raw;
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (line.empty()) return std::nullopt;
    AddRecord(vpn_plugin::cli_output::ToRecord(line, Now()));
    if (auto failure = vpn_plugin::cli_output::ParseFailure(line)) failures_.push_back(std::move(*failure));
    auto state = vpn_plugin::cli_output::ParseState(line);
    if (!state || *state == state_) return std::nullopt;
    state_ = *state;
    return state;
}

void CliRunner::Note(const std::string& message) {
    if (!message.empty()) AddRecord(Now() + " [info] === CatTunnel: " + message + " ===");
}

void CliRunner::AddRecord(std::string record) {
    if (!paths_.log_file.empty()) {
        // One rotated file: the log on disk stays under 2 x kMaxLogFileBytes.
        struct stat st {};
        if (stat(paths_.log_file.c_str(), &st) == 0 && st.st_size > kMaxLogFileBytes) {
            rename(paths_.log_file.c_str(), (paths_.log_file + ".1").c_str());
        }
        std::ofstream log(paths_.log_file, std::ios::app);
        if (log) log << record << '\n';
    }
    records_bytes_ += record.size();
    records_.push_back(std::move(record));
    while (records_bytes_ > kMaxRecordBytes && !records_.empty()) {
        records_bytes_ -= records_.front().size();
        records_.pop_front();
    }
}

std::vector<std::string> CliRunner::Records(size_t max) const {
    size_t from = records_.size() > max ? records_.size() - max : 0;
    return {records_.begin() + static_cast<long>(from), records_.end()};
}

void CliRunner::CloseOutput() {
    if (pipe_fd_ >= 0) close(pipe_fd_);
    pipe_fd_ = -1;
    partial_.clear();
}

}  // namespace cattunnel_helper
