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
        {"anti_dpi", Kind::kBool}, {"anti_dpi_mode", Kind::kInt}, {"tls_profile", Kind::kString}, {"anti_dpi_desync", Kind::kString}, {"h2_padding_frames", Kind::kInt}, {"block_quic", Kind::kBool}, {"dns_upstreams", Kind::kStrings},
        {"name", Kind::kString},
};
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
