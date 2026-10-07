// HelperClient against a fake helper on a temporary unix socket.

#include <gtest/gtest.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#include <atomic>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "helper_client.h"

namespace vpn_plugin {
namespace {

using namespace std::chrono_literals;
using Json = HelperClient::Json;

std::string ReadLine(int fd) {
    std::string line;
    char c;
    while (recv(fd, &c, 1, 0) == 1 && c != '\n') line += c;
    return line;
}

void Send(int fd, const std::string& line) {
    std::string data = line + "\n";
    ASSERT_EQ(send(fd, data.data(), data.size(), MSG_NOSIGNAL), static_cast<ssize_t>(data.size()));
}

/** Accepts one client and runs [script] with its fd. */
class FakeHelper {
 public:
    explicit FakeHelper(std::function<void(int)> script) {
        char dir[] = "/tmp/cattunnel_test_XXXXXX";
        path_ = std::string(mkdtemp(dir)) + "/helper.sock";
        sockaddr_un address{};
        address.sun_family = AF_UNIX;
        strncpy(address.sun_path, path_.c_str(), sizeof(address.sun_path) - 1);
        listener_ = socket(AF_UNIX, SOCK_STREAM, 0);
        bind(listener_, reinterpret_cast<sockaddr*>(&address), sizeof(address));
        listen(listener_, 1);
        thread_ = std::thread([this, script]() {
            int client = accept(listener_, nullptr, nullptr);
            script(client);
            close(client);
        });
    }
    ~FakeHelper() {
        thread_.join();
        close(listener_);
        unlink(path_.c_str());
    }
    const std::string& path() const { return path_; }

 private:
    std::string path_;
    int listener_ = -1;
    std::thread thread_;
};

void Hello(int fd) {
    EXPECT_EQ(Json::parse(ReadLine(fd))["cmd"], "hello");
    Send(fd, R"({"ok":true,"version":1,"engine":"1.1.7"})");
}

TEST(HelperClient, NoHelperIsAClearError) {
    HelperClient client("/nonexistent/helper.sock", [](const Json&) {}, []() {});
    auto error = client.Connect();
    ASSERT_TRUE(error.has_value());
    EXPECT_NE(error->find("not running"), std::string::npos);
}

TEST(HelperClient, EventsBeforeTheReplyGoToTheCallback) {
    FakeHelper helper([](int fd) {
        Hello(fd);
        EXPECT_EQ(Json::parse(ReadLine(fd))["cmd"], "start");
        Send(fd, R"({"event":"state","state":"connecting"})");
        Send(fd, R"({"ok":true})");
        Send(fd, R"({"event":"state","state":"connected"})");
        ReadLine(fd);  // until the client hangs up
    });

    std::mutex mutex;
    std::vector<std::string> states;
    std::atomic<bool> closed{false};
    HelperClient client(
            helper.path(),
            [&](const Json& event) {
                std::lock_guard<std::mutex> lock(mutex);
                states.push_back(event["state"]);
            },
            [&]() { closed = true; });
    ASSERT_FALSE(client.Connect().has_value());

    std::string error;
    auto reply = client.Request({{"cmd", "start"}, {"config", "x"}}, 2s, &error);
    ASSERT_TRUE(reply.has_value()) << error;
    EXPECT_TRUE(reply->value("ok", false));

    for (int i = 0; i < 100; ++i) {
        {
            std::lock_guard<std::mutex> lock(mutex);
            if (states.size() == 2) break;
        }
        std::this_thread::sleep_for(10ms);  // not under the lock: the reader needs it
    }
    {
        std::lock_guard<std::mutex> lock(mutex);
        EXPECT_EQ(states, (std::vector<std::string>{"connecting", "connected"}));
    }
    client.Disconnect();
    EXPECT_TRUE(closed);
}

TEST(HelperClient, BusyHelperIsRefused) {
    FakeHelper helper([](int fd) {
        ReadLine(fd);
        Send(fd, R"({"ok":false,"error":"busy"})");
    });
    HelperClient client(helper.path(), [](const Json&) {}, []() {});
    auto error = client.Connect();
    ASSERT_TRUE(error.has_value());
    EXPECT_NE(error->find("another CatTunnel window"), std::string::npos);
}

TEST(HelperClient, HangUpFailsTheRequestAndReportsClosed) {
    FakeHelper helper([](int fd) {
        Hello(fd);
        ReadLine(fd);  // the request, never answered
    });
    std::atomic<bool> closed{false};
    HelperClient client(helper.path(), [](const Json&) {}, [&]() { closed = true; });
    ASSERT_FALSE(client.Connect().has_value());
    std::string error;
    auto reply = client.Request({{"cmd", "state"}}, 2s, &error);
    EXPECT_FALSE(reply.has_value());
    EXPECT_EQ(error, "helper hung up");
    for (int i = 0; i < 100 && !closed; ++i) std::this_thread::sleep_for(10ms);
    EXPECT_TRUE(closed);
    EXPECT_FALSE(client.Request({{"cmd", "state"}}, 100ms, &error).has_value());
}

TEST(HelperClient, SilentHelperTimesOut) {
    FakeHelper helper([](int fd) {
        Hello(fd);
        ReadLine(fd);
        ReadLine(fd);  // keep the connection open until the client leaves
    });
    HelperClient client(helper.path(), [](const Json&) {}, []() {});
    ASSERT_FALSE(client.Connect().has_value());
    std::string error;
    EXPECT_FALSE(client.Request({{"cmd", "state"}}, 200ms, &error).has_value());
    EXPECT_EQ(error, "helper did not answer in time");
    client.Disconnect();
}

#ifdef CATTUNNEL_HELPER_BIN
// The smallest config the helper's CheckConfig accepts.
constexpr const char* kConfig = R"(loglevel = "error"
vpn_mode = "general"

[endpoint]
hostname = "www.example.org"
addresses = ["192.0.2.1:443"]
username = "u"
password = "p"

[listener.tun]
mtu_size = 1280
)";

// The real helper in its per-session mode (no root needed) with a fake CLI:
// start -> connecting/connected events, stop -> disconnected, logs.
TEST(HelperClient, TalksToTheRealHelper) {
    char tmpl[] = "/tmp/cattunnel_it_XXXXXX";
    std::string dir = mkdtemp(tmpl);
    std::string cli = dir + "/fake_cli.sh";
    FILE* f = fopen(cli.c_str(), "w");
    fputs("#!/bin/sh\n"
          "trap 'echo \"28.09.2026 01:00:02.000000 INFO  [1] VPNCORE raise_state: [0] VPN_SS_DISCONNECTED\"; exit 0' INT\n"
          "echo \"28.09.2026 01:00:00.000000 INFO  [1] VPNCORE raise_state: [0] VPN_SS_CONNECTING\"\n"
          "echo \"28.09.2026 01:00:01.000000 INFO  [1] VPNCORE raise_state: [0] VPN_SS_CONNECTED\"\n"
          "while :; do sleep 0.1; done\n", f);
    fclose(f);
    chmod(cli.c_str(), 0755);
    std::string socket_path = dir + "/helper.sock";

    pid_t pid = fork();
    if (pid == 0) {
        std::string uid = std::to_string(getuid());
        std::string state = dir + "/state", log = dir + "/client.log";
        execl(CATTUNNEL_HELPER_BIN, "cattunnel-helper", "--socket", socket_path.c_str(), "--uid", uid.c_str(),
              "--cli", cli.c_str(), "--state-dir", state.c_str(), "--log", log.c_str(), "--no-system-dns", nullptr);
        _exit(127);
    }
    for (int i = 0; i < 100 && access(socket_path.c_str(), F_OK) != 0; ++i) std::this_thread::sleep_for(10ms);

    std::mutex mutex;
    std::vector<std::string> states;
    HelperClient client(
            socket_path,
            [&](const Json& event) {
                std::lock_guard<std::mutex> lock(mutex);
                states.push_back(event["state"]);
            },
            []() {});
    auto connect_error = client.Connect();
    ASSERT_FALSE(connect_error.has_value()) << *connect_error;

    std::string error;
    auto reply = client.Request({{"cmd", "start"}, {"config", kConfig}, {"log_level", "error"}}, 5s,
                                &error);
    ASSERT_TRUE(reply.has_value()) << error;
    EXPECT_TRUE(reply->value("ok", false)) << reply->dump();

    auto wait_for = [&](const std::string& state) {
        for (int i = 0; i < 200; ++i) {
            {
                std::lock_guard<std::mutex> lock(mutex);
                if (!states.empty() && states.back() == state) return true;
            }
            std::this_thread::sleep_for(10ms);
        }
        return false;
    };
    EXPECT_TRUE(wait_for("connected"));
    reply = client.Request({{"cmd", "state"}}, 2s, &error);
    ASSERT_TRUE(reply.has_value()) << error;
    EXPECT_EQ(reply->value("state", ""), "connected");

    reply = client.Request({{"cmd", "stop"}}, 10s, &error);
    ASSERT_TRUE(reply.has_value()) << error;
    EXPECT_TRUE(wait_for("disconnected"));

    reply = client.Request({{"cmd", "logs"}, {"max", 50}}, 2s, &error);
    ASSERT_TRUE(reply.has_value()) << error;
    EXPECT_GE((*reply)["records"].size(), 2u);

    client.Disconnect();  // per-session mode: the helper exits when the app leaves
    int status = 0;
    for (int i = 0; i < 300 && waitpid(pid, &status, WNOHANG) == 0; ++i) std::this_thread::sleep_for(10ms);
    EXPECT_TRUE(WIFEXITED(status));
}

namespace {

/** A TCP echo server on 127.0.0.1; [port] is where it listens. */
struct EchoServer {
    int listener = -1;
    int port = 0;
    std::thread thread;
    EchoServer() {
        listener = socket(AF_INET, SOCK_STREAM, 0);
        sockaddr_in a{};
        a.sin_family = AF_INET;
        a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        bind(listener, reinterpret_cast<sockaddr*>(&a), sizeof(a));
        listen(listener, 4);
        socklen_t len = sizeof(a);
        getsockname(listener, reinterpret_cast<sockaddr*>(&a), &len);
        port = ntohs(a.sin_port);
        thread = std::thread([this]() {
            for (int i = 0; i < 2; ++i) {  // the probe, then the relay
                int c = accept(listener, nullptr, nullptr);
                if (c < 0) return;
                char buf[256];
                ssize_t n;
                while ((n = recv(c, buf, sizeof(buf), 0)) > 0) send(c, buf, n, MSG_NOSIGNAL);
                close(c);
            }
        });
    }
    ~EchoServer() {
        shutdown(listener, SHUT_RDWR);
        close(listener);
        thread.join();
    }
};

int ConnectUnix(const std::string& path) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    sockaddr_un address{};
    address.sun_family = AF_UNIX;
    strncpy(address.sun_path, path.c_str(), sizeof(address.sun_path) - 1);
    if (connect(fd, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        close(fd);
        return -1;
    }
    return fd;
}

/** A closed port on 127.0.0.1. */
int ClosedPort() {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    sockaddr_in a{};
    a.sin_family = AF_INET;
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    bind(s, reinterpret_cast<sockaddr*>(&a), sizeof(a));
    socklen_t len = sizeof(a);
    getsockname(s, reinterpret_cast<sockaddr*>(&a), &len);
    close(s);
    return ntohs(a.sin_port);
}

}  // namespace

// Diagnostics connections (HELPER.md): probe answers and closes; a relay is
// silent on success (the app starts TLS at once) and just closes on failure.
TEST(HelperClient, ProbeAndRelayOnTheRealHelper) {
    char tmpl[] = "/tmp/cattunnel_pr_XXXXXX";
    std::string dir = mkdtemp(tmpl);
    std::string socket_path = dir + "/helper.sock";
    pid_t pid = fork();
    if (pid == 0) {
        std::string uid = std::to_string(getuid());
        execl(CATTUNNEL_HELPER_BIN, "cattunnel-helper", "--socket", socket_path.c_str(), "--uid", uid.c_str(),
              "--cli", "/bin/false", "--state-dir", (dir + "/state").c_str(), "--log", (dir + "/log").c_str(),
              "--no-system-dns", "--physical-iface", "lo", nullptr);
        _exit(127);
    }
    for (int i = 0; i < 100 && access(socket_path.c_str(), F_OK) != 0; ++i) std::this_thread::sleep_for(10ms);

    EchoServer echo;
    auto probe = [&](int port) {
        int fd = ConnectUnix(socket_path);
        Send(fd, Json{{"cmd", "probe"}, {"ip", "127.0.0.1"}, {"port", port}, {"timeout_ms", 2000}}.dump());
        std::string reply = ReadLine(fd);
        close(fd);
        return Json::parse(reply, nullptr, false).value("outcome", std::string("?"));
    };
    EXPECT_EQ(probe(echo.port), "ok");
    EXPECT_EQ(probe(ClosedPort()), "refused");

    int relay = ConnectUnix(socket_path);
    ASSERT_GE(relay, 0);
    // The request and the first payload bytes in one write, as a TLS client would.
    std::string request = Json{{"cmd", "relay"}, {"ip", "127.0.0.1"}, {"port", echo.port}}.dump() + "\nhello";
    ASSERT_EQ(send(relay, request.data(), request.size(), 0), static_cast<ssize_t>(request.size()));
    char buf[16] = {};
    ssize_t got = 0;
    while (got < 5) {
        ssize_t n = recv(relay, buf + got, sizeof(buf) - 1 - got, 0);
        if (n <= 0) break;
        got += n;
    }
    EXPECT_EQ(std::string(buf, static_cast<size_t>(got)), "hello");  // nothing before the echo
    close(relay);

    int failed = ConnectUnix(socket_path);
    Send(failed, Json{{"cmd", "relay"}, {"ip", "127.0.0.1"}, {"port", ClosedPort()}}.dump());
    EXPECT_EQ(recv(failed, buf, sizeof(buf), 0), 0);  // closed, no bytes
    close(failed);

    kill(pid, SIGTERM);
    waitpid(pid, nullptr, 0);
}
#endif

}  // namespace
}  // namespace vpn_plugin
