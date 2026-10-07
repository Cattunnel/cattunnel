#include "system_dns.h"

#include <fcntl.h>
#include <signal.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstring>
#include <fstream>
#include <sstream>
#include <thread>

namespace cattunnel_helper {

namespace {

constexpr auto kCommandTimeout = std::chrono::seconds(10);

// Backup format: first line "symlink" or "file", then the link target or the content.
constexpr const char* kSymlinkTag = "symlink\n";
constexpr const char* kFileTag = "file\n";

std::string Dir(const std::string& path) {
    size_t slash = path.rfind('/');
    return slash == std::string::npos ? "." : path.substr(0, slash == 0 ? 1 : slash);
}

bool ReadFile(const std::string& path, std::string* content) {
    std::ifstream in(path, std::ios::binary);
    if (!in) return false;
    std::ostringstream buffer;
    buffer << in.rdbuf();
    *content = buffer.str();
    return true;
}

/** Writes via a temp file + rename, so a reader never sees half a file. */
bool WriteAtomically(const std::string& path, const std::string& content, mode_t mode, std::string* error) {
    std::string temp = Dir(path) + "/.cattunnel-" + std::to_string(getpid()) + ".tmp";
    int fd = open(temp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, mode);
    if (fd < 0) {
        *error = "can't write " + temp + ": " + strerror(errno);
        return false;
    }
    fchmod(fd, mode);
    bool written = write(fd, content.data(), content.size()) == static_cast<ssize_t>(content.size());
    written = fsync(fd) == 0 && written;
    close(fd);
    if (!written || rename(temp.c_str(), path.c_str()) != 0) {
        *error = "can't replace " + path + ": " + strerror(errno);
        unlink(temp.c_str());
        return false;
    }
    return true;
}

}  // namespace

int RunCommand(const std::vector<std::string>& argv) {
    if (argv.empty() || argv[0].empty() || argv[0][0] != '/') return -1;
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        int null = open("/dev/null", O_RDWR);
        if (null >= 0) {
            dup2(null, 0);
            dup2(null, 1);
            dup2(null, 2);
        }
        std::vector<char*> args;
        for (const auto& arg : argv) args.push_back(const_cast<char*>(arg.c_str()));
        args.push_back(nullptr);
        char path[] = "PATH=/usr/bin:/bin";
        char lang[] = "LANG=C";
        char* env[] = {path, lang, nullptr};
        execve(args[0], args.data(), env);
        _exit(127);
    }
    auto deadline = std::chrono::steady_clock::now() + kCommandTimeout;
    int status = 0;
    while (true) {
        pid_t r = waitpid(pid, &status, WNOHANG);
        if (r == pid) break;
        if (r < 0 && errno != EINTR) return -1;
        if (std::chrono::steady_clock::now() >= deadline) {
            kill(pid, SIGKILL);
            waitpid(pid, &status, 0);
            return -1;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

void CleanUpCliRouting(const CommandRunner& run, const std::string& ip) {
    for (const char* family : {"-4", "-6"}) {
        run({ip, family, "route", "flush", "table", "880"});
        run({ip, family, "rule", "del", "prio", "30801", "lookup", "880"});
        run({ip, family, "rule", "del", "prio", "30800", "sport", "1-1024", "lookup", "main"});
        run({ip, family, "rule", "del", "prio", "30800", "sport", "5900-5920", "lookup", "main"});
    }
}

SystemDns::SystemDns(DnsPaths paths, CommandRunner run) : paths_(std::move(paths)), run_(std::move(run)) {}

std::string SystemDns::Apply(const std::vector<std::string>& servers) {
    if (ResolvedOwnsResolvConf()) {
        return "DNS: systemd-resolved - the client sets it (resolvectl)";
    }

    std::string error;
    if (!SaveBackup(&error)) return "DNS NOT SET, queries may bypass the tunnel: " + error;

    std::string how = "DNS: /etc/resolv.conf replaced for the session";
    if (IsActive("NetworkManager")) {
        mkdir(Dir(paths_.nm_drop_in).c_str(), 0755);
        std::string drop_in = "# CatTunnel: the VPN owns /etc/resolv.conf until it disconnects.\n[main]\ndns=none\n";
        if (!WriteAtomically(paths_.nm_drop_in, drop_in, 0644, &error)) {
            how += "; WARNING: NetworkManager may overwrite it (" + error + ")";
        } else if (run_({paths_.nmcli, "general", "reload", "conf"}) != 0) {
            how += "; WARNING: nmcli general reload conf failed, NetworkManager may overwrite it";
        } else {
            how = "DNS: NetworkManager paused (dns=none), /etc/resolv.conf replaced for the session";
        }
    }

    if (!WriteResolvConf(servers, &error)) return "DNS NOT SET, queries may bypass the tunnel: " + error;
    return how;
}

std::string SystemDns::Restore() {
    std::string done;
    std::string backup;
    if (ReadFile(paths_.backup, &backup)) {
        std::string error;
        bool restored = false;
        if (backup.rfind(kSymlinkTag, 0) == 0) {
            std::string target = backup.substr(strlen(kSymlinkTag));
            std::string temp = Dir(paths_.resolv_conf) + "/.cattunnel-link.tmp";
            unlink(temp.c_str());
            restored = symlink(target.c_str(), temp.c_str()) == 0 && rename(temp.c_str(), paths_.resolv_conf.c_str()) == 0;
            if (!restored) error = strerror(errno);
        } else if (backup.rfind(kFileTag, 0) == 0) {
            restored = WriteAtomically(paths_.resolv_conf, backup.substr(strlen(kFileTag)), 0644, &error);
        } else {
            error = "unreadable backup";
        }
        if (restored) {
            unlink(paths_.backup.c_str());
            done = "DNS: /etc/resolv.conf restored";
        } else {
            done = "DNS: can't restore /etc/resolv.conf from " + paths_.backup + ": " + error;
        }
    }

    struct stat st{};
    if (lstat(paths_.nm_drop_in.c_str(), &st) == 0) {
        unlink(paths_.nm_drop_in.c_str());
        // dns-rc: NetworkManager writes its resolv.conf again right away.
        bool reloaded = run_({paths_.nmcli, "general", "reload", "conf,dns-rc"}) == 0;
        done += std::string(done.empty() ? "DNS: " : "; ") +
                (reloaded ? "NetworkManager manages DNS again" : "WARNING: nmcli reload failed, restart NetworkManager");
    }
    return done;
}

bool SystemDns::ResolvedOwnsResolvConf() const {
    char target[512];
    ssize_t n = readlink(paths_.resolv_conf.c_str(), target, sizeof(target) - 1);
    if (n <= 0) return false;
    target[n] = '\0';
    // The stub or the full list: either way glibc asks resolved, and resolved
    // takes the tunnel's servers from the CLI's resolvectl calls.
    bool points_to_resolved = strstr(target, "/systemd/resolve/") != nullptr;
    return points_to_resolved && IsActive("systemd-resolved");
}

bool SystemDns::IsActive(const std::string& unit) const {
    return run_({paths_.systemctl, "is-active", "--quiet", unit}) == 0;
}

bool SystemDns::SaveBackup(std::string* error) const {
    struct stat st{};
    // A backup that's still there is the original from a session that never
    // got restored; overwriting it would save our own resolv.conf instead.
    if (lstat(paths_.backup.c_str(), &st) == 0) return true;

    std::string backup;
    char target[512];
    ssize_t n = readlink(paths_.resolv_conf.c_str(), target, sizeof(target) - 1);
    if (n > 0) {
        backup = kSymlinkTag + std::string(target, static_cast<size_t>(n));
    } else {
        std::string content;
        if (!ReadFile(paths_.resolv_conf, &content)) content.clear();  // none: restore to an empty file
        backup = kFileTag + content;
    }
    mkdir(Dir(paths_.backup).c_str(), 0700);
    return WriteAtomically(paths_.backup, backup, 0600, error);
}

bool SystemDns::WriteResolvConf(const std::vector<std::string>& servers, std::string* error) const {
    std::string content = "# Generated by CatTunnel for the VPN session; the original comes back on disconnect.\n";
    for (const auto& server : servers) content += "nameserver " + server + "\n";
    return WriteAtomically(paths_.resolv_conf, content, 0644, error);
}

}  // namespace cattunnel_helper
