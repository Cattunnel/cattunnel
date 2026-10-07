#include "config_guard.h"

#include <gtest/gtest.h>

namespace cattunnel_helper {
namespace {

// Shape of what lib/domain/configuration_codec.dart writes.
constexpr const char* kGood = R"(loglevel = "error"
vpn_mode = "general"
killswitch_enabled = false
post_quantum_group_enabled = true
exclusions = ["ya.ru", "*.ru", "10.0.0.0/8"]

[endpoint]
hostname = "www.example.org"
addresses = ["1.2.3.4:8443"]
has_ipv6 = false
username = "u"
password = "p"
client_random = "abcd"
custom_sni = ""
skip_verification = false
certificate = """
-----BEGIN CERTIFICATE-----
MIIB
-----END CERTIFICATE-----
"""
upstream_protocol = "http2"
upstream_fallback_protocol = ""
anti_dpi = true
anti_dpi_mode = 3
dns_upstreams = []
name = "Germany"

[listener]

[listener.tun]
included_routes = ["0.0.0.0/0"]
excluded_routes = ["10.0.0.0/8"]
mtu_size = 1280
)";

TEST(CheckConfig, AcceptsWhatTheAppWrites) { EXPECT_EQ(CheckConfig(kGood), std::nullopt); }

TEST(CheckConfig, RefusesUnknownKeysAnywhere) {
    EXPECT_NE(CheckConfig(std::string(kGood) + "logfile = \"/etc/shadow\"\n"), std::nullopt);  // in [listener.tun]
    EXPECT_NE(CheckConfig(std::string("certificate_path = \"/root/x\"\n") + kGood), std::nullopt);
    std::string endpoint_path = kGood;
    endpoint_path.insert(endpoint_path.find("name = "), "ca_file = \"/etc/shadow\"\n");
    EXPECT_NE(CheckConfig(endpoint_path), std::nullopt);
}

TEST(CheckConfig, SocksOnlyOnLoopback) {
    EXPECT_EQ(CheckConfig(std::string(kGood) + "\n[listener.socks]\naddress = \"127.0.0.1:1080\"\n"), std::nullopt);
    EXPECT_NE(CheckConfig(std::string(kGood) + "\n[listener.socks]\naddress = \"0.0.0.0:1080\"\n"), std::nullopt);
}

TEST(CheckConfig, RefusesOtherShapesAndTypes) {
    // Arrays of tables, arrays where a string belongs, a table where a list belongs: all refused.
    EXPECT_NE(CheckConfig(std::string(kGood) + "\n[[listener.socks]]\naddress = \"0.0.0.0:1080\"\n"), std::nullopt);
    EXPECT_NE(CheckConfig(std::string(kGood) + "\n[listener.socks]\naddress = [\"0.0.0.0:1080\"]\n"), std::nullopt);
    EXPECT_NE(CheckConfig(std::string(kGood) + "\n[listener.socks]\nusername = \"u\"\n"), std::nullopt);  // no address
    std::string wrong = kGood;
    wrong.replace(wrong.find("anti_dpi = true"), 15, "anti_dpi = \"yes\"");
    EXPECT_NE(CheckConfig(wrong), std::nullopt);
    std::string nested = kGood;
    nested.replace(nested.find("dns_upstreams = []"), 18, "dns_upstreams = [[\"a\"]]");
    EXPECT_NE(CheckConfig(nested), std::nullopt);
    // Escaped strings (what the app writes for a password with quotes) are fine.
    std::string escaped = kGood;
    escaped.replace(escaped.find("password = \"p\""), 14, "password = \"p\\\"w\\nx\"");
    EXPECT_EQ(CheckConfig(escaped), std::nullopt);
}

TEST(CheckConfig, RefusesGarbageAndHugeInput) {
    EXPECT_NE(CheckConfig("not = [toml"), std::nullopt);
    EXPECT_NE(CheckConfig("loglevel = \"error\"\n"), std::nullopt);  // no [endpoint]
    EXPECT_NE(CheckConfig(std::string(kMaxConfigBytes + 1, ' ')), std::nullopt);
}

}  // namespace
}  // namespace cattunnel_helper
