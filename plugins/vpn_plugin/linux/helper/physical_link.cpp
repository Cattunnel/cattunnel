#include "physical_link.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cerrno>
#include <climits>
#include <cstring>
#include <fstream>
#include <sstream>

namespace cattunnel_helper {

namespace {

constexpr int kArphrdNone = 65534;  // TUN devices

bool IsTun(const std::string& iface) {
    std::ifstream type("/sys/class/net/" + iface + "/type");
    int value = 0;
    return (type >> value) && value == kArphrdNone;
}

}  // namespace

std::string PhysicalInterface() {
    std::ifstream routes("/proc/net/route");
    std::string line;
    std::getline(routes, line);  // header
    std::string best;
    long best_metric = LONG_MAX;
    while (std::getline(routes, line)) {
        std::istringstream fields(line);
        std::string iface, destination, gateway, flags, refcnt, use, metric, mask;
        if (!(fields >> iface >> destination >> gateway >> flags >> refcnt >> use >> metric >> mask)) continue;
        if (destination != "00000000" || mask != "00000000" || IsTun(iface)) continue;
        long m = strtol(metric.c_str(), nullptr, 10);
        if (m < best_metric) {
            best_metric = m;
            best = iface;
        }
    }
    return best;
}

int ConnectPinned(const std::string& ip, int port, int timeout_ms, const std::string& iface, std::string* outcome) {
    *outcome = "failed";
    addrinfo hints{};
    hints.ai_flags = AI_NUMERICHOST | AI_NUMERICSERV;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* info = nullptr;
    if (port <= 0 || port > 65535 ||
        getaddrinfo(ip.c_str(), std::to_string(port).c_str(), &hints, &info) != 0 || info == nullptr) {
        return -1;
    }
    int s = socket(info->ai_family, SOCK_STREAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    if (s < 0) {
        freeaddrinfo(info);
        return -1;
    }
    if (!iface.empty()) {
        setsockopt(s, SOL_SOCKET, SO_BINDTODEVICE, iface.c_str(), static_cast<socklen_t>(iface.size() + 1));
    }
    int rc = connect(s, info->ai_addr, info->ai_addrlen);
    freeaddrinfo(info);
    if (rc != 0 && errno != EINPROGRESS) {
        *outcome = errno == ECONNREFUSED ? "refused" : "failed";
        close(s);
        return -1;
    }
    if (rc != 0) {
        pollfd p{s, POLLOUT, 0};
        int ready = poll(&p, 1, timeout_ms);
        if (ready == 0) {
            *outcome = "timeout";
            close(s);
            return -1;
        }
        int error = 0;
        socklen_t length = sizeof(error);
        getsockopt(s, SOL_SOCKET, SO_ERROR, &error, &length);
        if (ready < 0 || error != 0) {
            *outcome = error == ECONNREFUSED ? "refused" : error == ETIMEDOUT ? "timeout" : "failed";
            close(s);
            return -1;
        }
    }
    fcntl(s, F_SETFL, fcntl(s, F_GETFL) & ~O_NONBLOCK);
    *outcome = "ok";
    return s;
}

void Pipe(int a, int b) {
    char buffer[16 * 1024];
    for (;;) {
        pollfd fds[2] = {{a, POLLIN, 0}, {b, POLLIN, 0}};
        if (poll(fds, 2, 120 * 1000) <= 0) break;
        bool done = false;
        for (int i = 0; i < 2 && !done; ++i) {
            if (!(fds[i].revents & (POLLIN | POLLHUP | POLLERR))) continue;
            int from = i == 0 ? a : b;
            int to = i == 0 ? b : a;
            ssize_t n = read(from, buffer, sizeof(buffer));
            if (n <= 0) {
                done = true;
                break;
            }
            for (ssize_t sent = 0; sent < n;) {
                ssize_t m = send(to, buffer + sent, static_cast<size_t>(n - sent), MSG_NOSIGNAL);
                if (m <= 0) {
                    done = true;
                    break;
                }
                sent += m;
            }
        }
        if (done) break;
    }
    close(a);
    close(b);
}

}  // namespace cattunnel_helper
