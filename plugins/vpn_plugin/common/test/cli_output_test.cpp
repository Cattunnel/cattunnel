#include "cli_output.h"

#include <gtest/gtest.h>

namespace vpn_plugin::cli_output {
namespace {

constexpr const char* kNow = "2026-09-25T00:00:00.000";

// Lines as trusttunnel_client 1.1.7 prints them.
TEST(ParseState, ReadsEveryCliState) {
    EXPECT_EQ(ParseState("25.09.2026 22:45:23.887787 INFO  [22430] VPNCORE raise_state: [0] VPN_SS_CONNECTING"),
            CliState::kConnecting);
    EXPECT_EQ(ParseState("x raise_state: [0] VPN_SS_CONNECTED"), CliState::kConnected);
    EXPECT_EQ(ParseState("x raise_state: [0] VPN_SS_DISCONNECTED"), CliState::kDisconnected);
    EXPECT_EQ(ParseState("x raise_state: [0] VPN_SS_WAITING_RECOVERY"), CliState::kWaitingRecovery);
    EXPECT_EQ(ParseState("x raise_state: [0] VPN_SS_RECOVERING"), CliState::kRecovering);
    EXPECT_EQ(ParseState("x raise_state: [0] VPN_SS_WAITING_FOR_NETWORK\r"), CliState::kWaitingForNetwork);
}

TEST(ParseState, IgnoresOtherLines) {
    EXPECT_FALSE(ParseState("25.09.2026 22:45:23.887 INFO  [1] VPNCORE vpn_connect: [0] Done"));
    EXPECT_FALSE(ParseState("VPN_SS_CONNECTED without the marker"));
    EXPECT_FALSE(ParseState("x raise_state: [0] VPN_SS_SOMETHING_NEW"));
    EXPECT_FALSE(ParseState(""));
}

TEST(ParseFailure, ReadsTheEngineTag) {
    EXPECT_EQ(ParseFailure("03.10.2026 00:58:53.598868 WARN  [5405] VPNCORE pinger_handler: [0] Failed to ping location "
                           "[failure=hello_no_answer]"),
            "hello_no_answer");
    EXPECT_EQ(ParseFailure("x [failure=connect] y"), "connect");
    EXPECT_EQ(ParseFailure("x [failure=none]"), std::nullopt);
    EXPECT_EQ(ParseFailure("x [failure=hello_reset"), std::nullopt);
    EXPECT_EQ(ParseFailure("raise_state: [0] VPN_SS_CONNECTING"), std::nullopt);
}

TEST(ToRecord, ConvertsCliLine) {
    EXPECT_EQ(ToRecord("25.09.2026 22:45:23.887787 INFO  [22430] VPNCORE raise_state: [0] VPN_SS_CONNECTING", kNow),
            "2026-09-25T22:45:23.887787 [info] [22430] VPNCORE raise_state: [0] VPN_SS_CONNECTING");
    EXPECT_EQ(ToRecord("25.09.2026 22:45:23.887787 ERROR [1] OS_TUNNEL tun_open: failed", kNow),
            "2026-09-25T22:45:23.887787 [error] [1] OS_TUNNEL tun_open: failed");
}

TEST(ToRecord, OtherLinesGetTheCurrentTime) {
    EXPECT_EQ(ToRecord("=== CatTunnel: starting ===", kNow), "2026-09-25T00:00:00.000 [info] === CatTunnel: starting ===");
    EXPECT_EQ(ToRecord("", kNow), "2026-09-25T00:00:00.000 [info] -");
}

TEST(ToRecord, NeverEmitsInvalidUtf8OrSeparators) {
    // "Привет" in cp1251 - not UTF-8.
    EXPECT_EQ(ToRecord("\xcf\xf0\xe8\xe2\xe5\xf2", kNow), "2026-09-25T00:00:00.000 [info] ??????");
    // Real UTF-8 is kept.
    EXPECT_EQ(ToRecord("\xd0\x9f\xd1\x80\xd0\xb8", kNow), "2026-09-25T00:00:00.000 [info] \xd0\x9f\xd1\x80\xd0\xb8");
    EXPECT_EQ(ToRecord("a\x1e" "b", kNow), "2026-09-25T00:00:00.000 [info] a b");
    // A cut-off multibyte sequence at the end.
    EXPECT_EQ(ToRecord("ok \xd0", kNow), "2026-09-25T00:00:00.000 [info] ok ?");
}

TEST(CliLogLevel, RaisesToInfoKeepsDebugAndTrace) {
    EXPECT_EQ(CliLogLevel("loglevel = \"error\"\nvpn_mode = \"general\"\n"), "info");
    EXPECT_EQ(CliLogLevel("loglevel = \"warn\"\n"), "info");
    EXPECT_EQ(CliLogLevel("loglevel = \"debug\"\n"), "debug");
    EXPECT_EQ(CliLogLevel("  loglevel = \"trace\"\n"), "trace");
    EXPECT_EQ(CliLogLevel(""), "info");
    // Only the top-level key counts.
    EXPECT_EQ(CliLogLevel("loglevel = \"error\"\n[endpoint]\nname = \"debug\"\n"), "info");
    EXPECT_EQ(CliLogLevel("[endpoint]\nloglevel = \"debug\"\n"), "info");
}

}  // namespace
}  // namespace vpn_plugin::cli_output
