#include "config_guard.h"

#include <algorithm>
#include <map>

#define TOML_EXCEPTIONS 1
#include "third_party/toml.hpp"

namespace cattunnel_helper {

namespace {

// Exactly what the encoder writes, with the node type of each key; anything
// else - a log file, a certificate path, an option added upstream later, an
// array of tables where a table belongs ([[listener.socks]]) - is refused
// until it's reviewed here.
enum class Kind { kString, kBool, kInt, kStrings, kTable };
using Schema = std::map<std::string_view, Kind>;

const Schema kTopKeys = {
        {"loglevel", Kind::kString}, {"vpn_mode", Kind::kString}, {"killswitch_enabled", Kind::kBool},
        {"post_quantum_group_enabled", Kind::kBool}, {"exclusions", Kind::kStrings},
        {"endpoint", Kind::kTable}, {"listener", Kind::kTable},
};
const Schema kEndpointKeys = {
        {"hostname", Kind::kString}, {"addresses", Kind::kStrings}, {"has_ipv6", Kind::kBool},
        {"username", Kind::kString}, {"password", Kind::kString}, {"client_random", Kind::kString},
        {"custom_sni", Kind::kString}, {"skip_verification", Kind::kBool}, {"certificate", Kind::kString},
        {"upstream_protocol", Kind::kString}, {"upstream_fallback_protocol", Kind::kString},
        {"anti_dpi", Kind::kBool}, {"anti_dpi_mode", Kind::kInt}, {"tls_profile", Kind::kString}, {"client_random_auth_key", Kind::kString}, {"anti_dpi_desync", Kind::kString}, {"h2_padding_frames", Kind::kInt}, {"block_quic", Kind::kBool}, {"dns_upstreams", Kind::kStrings},
        {"name", Kind::kString},
        // The expert settings ("For experts" in the app): the traffic shaper,
        // the keepalive and the XHTTP transport.
        {"h2_padding_frames_min", Kind::kInt}, {"h2_padding_per_stream", Kind::kBool},
        {"h2_padding_min_bytes", Kind::kInt}, {"h2_padding_max_bytes", Kind::kInt},
        {"h2_padding_stream_bytes", Kind::kInt}, {"h2_padding_session_bytes", Kind::kInt},
        {"keepalive_interval_secs", Kind::kInt}, {"keepalive_signal", Kind::kString},
        {"session_lifetime_secs", Kind::kInt}, {"xhttp_enable", Kind::kBool}, {"xhttp_path", Kind::kString},
};

// The engine clamps the numbers to the same limits (see the app's
// ConfigurationCodecKeys); a value outside them is a hand-written config, not
// something the app produced.
constexpr int64_t kPaddingFramesMax = 64;
constexpr int64_t kPaddingBytesMax = 256;
constexpr int64_t kPaddingBudgetMax = 1048576;
constexpr int64_t kKeepaliveIntervalMax = 3600;
constexpr int64_t kSessionLifetimeMax = 86400;

// The keepalive signal the engine knows.
constexpr const char* kKeepaliveSignalCheck = "check";
constexpr const char* kKeepaliveSignalPing = "ping";
const Schema kListenerKeys = {{"tun", Kind::kTable}, {"socks", Kind::kTable}};
const Schema kTunKeys = {
        {"included_routes", Kind::kStrings}, {"excluded_routes", Kind::kStrings}, {"mtu_size", Kind::kInt},
        {"excluded_apps", Kind::kStrings}, {"included_apps", Kind::kStrings},
};
const Schema kSocksKeys = {{"address", Kind::kString}, {"username", Kind::kString}, {"password", Kind::kString}};

bool HasKind(const toml::node& node, Kind kind) {
    switch (kind) {
        case Kind::kString: return node.is_string();
        case Kind::kBool: return node.is_boolean();
        case Kind::kInt: return node.is_integer();
        case Kind::kTable: return node.is_table();
        case Kind::kStrings: {
            const auto* array = node.as_array();
            return array != nullptr && array->size() <= kMaxListItems &&
                   std::all_of(array->begin(), array->end(), [](const toml::node& item) { return item.is_string(); });
        }
    }
    return false;
}

std::optional<std::string> CheckKeys(const toml::table& table, const Schema& allowed, std::string_view where) {
    for (const auto& [key, value] : table) {
        auto it = allowed.find(key.str());
        if (it == allowed.end()) {
            return std::string("key not allowed: ") + std::string(where) + std::string(key.str());
        }
        if (!HasKind(value, it->second)) {
            return std::string("wrong type or list too long: ") + std::string(where) + std::string(key.str());
        }
    }
    return std::nullopt;
}

/** A SOCKS listener as root must not be reachable from the network. */
bool IsLoopbackListen(std::string_view address) {
    return address.rfind("127.0.0.1:", 0) == 0 || address.rfind("[::1]:", 0) == 0 ||
           address.rfind("localhost:", 0) == 0;
}

/** Whether the number [key] of [table] is within [min]..[max]. */
std::optional<std::string> CheckRange(const toml::table& table, std::string_view key, int64_t min, int64_t max) {
    const auto it = table.find(std::string(key));
    if (it == table.end()) return std::nullopt;
    const auto value = it->second.value<int64_t>();
    if (!value) return std::string("not a number: ") + std::string(key);
    if (*value < min || *value > max) {
        return std::string("value out of range: ") + std::string(key);
    }
    return std::nullopt;
}

/** The keepalive signal is one the engine knows. */
std::optional<std::string> CheckKeepaliveSignal(const toml::table& table) {
    const auto it = table.find("keepalive_signal");
    if (it == table.end()) return std::nullopt;
    const auto signal = it->second.value<std::string>();
    if (!signal) return "keepalive_signal: not a string";
    if (*signal != kKeepaliveSignalCheck && *signal != kKeepaliveSignalPing) {
        return "keepalive_signal: unknown signal";
    }
    return std::nullopt;
}

/**
 * The XHTTP path prefix goes into an HTTP request line as it is: it has to
 * look like a path, with no spaces and nothing that would split the line.
 */
std::optional<std::string> CheckXhttpPath(const toml::table& table) {
    const auto it = table.find("xhttp_path");
    if (it == table.end()) return std::nullopt;
    const auto path = it->second.value<std::string>();
    if (!path) return "xhttp_path: not a string";
    if (path->empty() || path->front() != '/' || path->size() > kMaxXhttpPathLength) {
        return "xhttp_path: not a path prefix";
    }
    for (const char c : *path) {
        if (c <= ' ' || c == 0x7f) return "xhttp_path: not a path prefix";
    }
    return std::nullopt;
}

}  // namespace

std::optional<std::string> CheckConfig(std::string_view text) {
    if (text.size() > kMaxConfigBytes) return "config too large";

    toml::table config;
    try {
        config = toml::parse(text);
    } catch (const toml::parse_error& e) {
        return std::string("not valid TOML: ") + std::string(e.description());
    }

    if (auto error = CheckKeys(config, kTopKeys, "")) return error;

    const auto* endpoint = config["endpoint"].as_table();
    if (endpoint == nullptr) return "no [endpoint]";
    if (auto error = CheckKeys(*endpoint, kEndpointKeys, "endpoint.")) return error;

    // The numbers of the expert settings, and the two strings with a fixed
    // set of values.
    if (auto error = CheckRange(*endpoint, "h2_padding_frames", 0, kPaddingFramesMax)) return error;
    if (auto error = CheckRange(*endpoint, "h2_padding_frames_min", 0, kPaddingFramesMax)) return error;
    if (auto error = CheckRange(*endpoint, "h2_padding_min_bytes", 0, kPaddingBytesMax)) return error;
    if (auto error = CheckRange(*endpoint, "h2_padding_max_bytes", 0, kPaddingBytesMax)) return error;
    if (auto error = CheckRange(*endpoint, "h2_padding_stream_bytes", 0, kPaddingBudgetMax)) return error;
    if (auto error = CheckRange(*endpoint, "h2_padding_session_bytes", 0, kPaddingBudgetMax)) return error;
    if (auto error = CheckRange(*endpoint, "keepalive_interval_secs", 0, kKeepaliveIntervalMax)) return error;
    if (auto error = CheckRange(*endpoint, "session_lifetime_secs", 0, kSessionLifetimeMax)) return error;
    if (auto error = CheckKeepaliveSignal(*endpoint)) return error;
    if (auto error = CheckXhttpPath(*endpoint)) return error;

    if (const auto* listener = config["listener"].as_table()) {
        if (auto error = CheckKeys(*listener, kListenerKeys, "listener.")) return error;
        if (const auto* tun = (*listener)["tun"].as_table()) {
            if (auto error = CheckKeys(*tun, kTunKeys, "listener.tun.")) return error;
        }
        if (const auto* socks = (*listener)["socks"].as_table()) {
            if (auto error = CheckKeys(*socks, kSocksKeys, "listener.socks.")) return error;
            auto address = (*socks)["address"].value<std::string_view>();
            if (!address || !IsLoopbackListen(*address)) return "listener.socks.address must be loopback";
        }
    }
    return std::nullopt;
}

}  // namespace cattunnel_helper
