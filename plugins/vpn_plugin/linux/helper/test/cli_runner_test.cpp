#include "cli_runner.h"

#include <gtest/gtest.h>
#include <poll.h>
#include <sys/stat.h>
#include <unistd.h>

#include <cstdlib>
#include <fstream>
#include <string>

namespace cattunnel_helper {
namespace {

// A stand-in for trusttunnel_client: prints state lines like 1.1.7 does,
// exits cleanly on SIGINT (the helper's Ctrl+C).
std::string FakeCli(const std::string& dir) {
    std::string path = dir + "/fake_cli.sh";
    std::ofstream(path) << "#!/bin/sh\n"
                           "trap 'echo \"28.09.2026 01:00:02.000000 INFO  [1] VPNCORE raise_state: [0] "
                           "VPN_SS_DISCONNECTED\"; exit 0' INT\n"
                           "echo \"28.09.2026 01:00:00.000000 INFO  [1] VPNCORE raise_state: [0] VPN_SS_CONNECTING\"\n"
                           "echo \"28.09.2026 01:00:01.000000 INFO  [1] VPNCORE raise_state: [0] VPN_SS_CONNECTED\"\n"
                           "while :; do sleep 0.1; done\n";
    chmod(path.c_str(), 0755);
    return path;
}

TEST(CliRunner, ReportsStatesAndStopsCleanly) {
    char tmpl[] = "/tmp/cthelperXXXXXX";
    std::string dir = mkdtemp(tmpl);
    CliRunner cli({FakeCli(dir), dir + "/state", dir + "/client.log"});

    ASSERT_EQ(cli.Start("loglevel = \"error\"\n", "error"), std::nullopt);
    struct stat st{};
    ASSERT_EQ(stat((dir + "/state/client.toml").c_str(), &st), 0);
    EXPECT_EQ(st.st_mode & 0777, 0600u);

    std::vector<CliState> seen;
    for (int i = 0; i < 50 && seen.size() < 2; ++i) {
        pollfd p{cli.fd(), POLLIN, 0};
        poll(&p, 1, 100);
        for (auto s : cli.ReadOutput()) seen.push_back(s);
    }
    ASSERT_EQ(seen.size(), 2u);
    EXPECT_EQ(seen[0], CliState::kConnecting);
    EXPECT_EQ(seen[1], CliState::kConnected);

    cli.Stop();
    EXPECT_FALSE(cli.running());
    EXPECT_EQ(cli.state(), CliState::kDisconnected);
    EXPECT_NE(stat((dir + "/state/client.toml").c_str(), &st), 0);  // the password doesn't linger
    auto records = cli.Records(10);
    ASSERT_FALSE(records.empty());
    EXPECT_NE(records.front().find("starting trusttunnel_client"), std::string::npos);
    EXPECT_EQ(std::system(("rm -rf " + dir).c_str()), 0);
}

TEST(CliRunner, OnlyStateChangesAreReported) {
    CliRunner cli({"/nonexistent", "/tmp", ""});
    EXPECT_EQ(cli.OnLine("x raise_state: [0] VPN_SS_CONNECTING"), CliState::kConnecting);
    EXPECT_EQ(cli.OnLine("x raise_state: [0] VPN_SS_CONNECTING"), std::nullopt);
    EXPECT_EQ(cli.OnLine("x something else"), std::nullopt);
}

TEST(CliRunner, FailureTagsAreCollected) {
    CliRunner cli({"/nonexistent", "/tmp", ""});
    cli.OnLine("x pinger_handler: [0] Failed to ping location [failure=hello_no_answer]");
    cli.OnLine("x raise_state: [0] VPN_SS_WAITING_RECOVERY");
    EXPECT_EQ(cli.TakeFailures(), std::vector<std::string>{"hello_no_answer"});
    EXPECT_TRUE(cli.TakeFailures().empty());
}

}  // namespace
}  // namespace cattunnel_helper
