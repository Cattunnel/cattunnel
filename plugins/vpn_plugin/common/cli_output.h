#pragma once

// Parsing of the TrustTunnel CLI output, shared by the Windows and Linux
// plugins (both run the public trusttunnel_client CLI) and kept free of
// platform APIs so it can be tested anywhere. See windows/CliProcess.

#include <algorithm>
#include <array>
#include <cctype>
#include <charconv>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace vpn_plugin::cli_output {

/** CLI state names, in the order of VpnManagerState. */
enum class CliState { kDisconnected, kConnecting, kConnected, kWaitingRecovery, kRecovering, kWaitingForNetwork };

// "25.09.2026 22:45:23.887 INFO  [22430] VPNCORE raise_state: [0] VPN_SS_CONNECTING"
inline constexpr std::string_view kStateMarker = "raise_state:";
inline constexpr std::string_view kStatePrefix = "VPN_SS_";

inline constexpr std::array<std::pair<std::string_view, CliState>, 6> kStates = {{
        {"DISCONNECTED", CliState::kDisconnected},
        {"CONNECTING", CliState::kConnecting},
        {"CONNECTED", CliState::kConnected},
        {"WAITING_RECOVERY", CliState::kWaitingRecovery},
        {"RECOVERING", CliState::kRecovering},
        {"WAITING_FOR_NETWORK", CliState::kWaitingForNetwork},
}};

inline std::optional<CliState> ParseState(std::string_view line) {
    size_t marker = line.find(kStateMarker);
    if (marker == std::string_view::npos) return std::nullopt;
    size_t prefix = line.find(kStatePrefix, marker);
    if (prefix == std::string_view::npos) return std::nullopt;

    std::string_view name = line.substr(prefix + kStatePrefix.size());
    size_t end = name.find_first_of(" \t\r");
    if (end != std::string_view::npos) name = name.substr(0, end);

    for (const auto& [text, state] : kStates) {
        if (name == text) return state;
    }
    return std::nullopt;
}

// "VPNCORE pinger_handler: [0] Failed to ping location [failure=hello_no_answer]" - our engine build
// (tools/engine_native, see PingFailure in net/utils.h) tags why the server could not be reached.
inline constexpr std::string_view kFailureMarker = "[failure=";
inline constexpr std::array<std::string_view, 3> kFailures = {"connect", "hello_reset", "hello_no_answer"};

inline std::optional<std::string> ParseFailure(std::string_view line) {
    size_t marker = line.find(kFailureMarker);
    if (marker == std::string_view::npos) return std::nullopt;
    std::string_view name = line.substr(marker + kFailureMarker.size());
    size_t end = name.find(']');
    if (end == std::string_view::npos) return std::nullopt;
    name = name.substr(0, end);
    for (std::string_view known : kFailures) {
        if (name == known) return std::string(name);
    }
    return std::nullopt;
}

/**
 * "19.10.2026 21:06:15.073812 INFO  [10099] NETDIAG symptom=cut_after_bytes proto=h2 up=8200 down=8100
 * dur_ms=1000 idle_ms=500 repeat=2 cut=16342" - our engine build (see net_diagnostics.h in the engine)
 * says what the session to the endpoint died of. The tail after the marker is the payload the app gets.
 */
inline constexpr std::string_view kNetDiagMarker = "NETDIAG ";

/** What the engine said about the last session to the endpoint. */
struct NetDiag {
    std::string symptom;
    std::string protocol;
    uint64_t bytes_up = 0;
    uint64_t bytes_down = 0;
    uint32_t duration_ms = 0;
    uint32_t idle_ms = 0;
    uint32_t repeat = 0;
    uint64_t cut_bytes = 0;

    /** The engine's line as it is, without the marker: "symptom=... up=... down=...". */
    std::string raw;
};

inline std::optional<uint64_t> ParseUint(std::string_view text) {
    uint64_t value = 0;
    auto [end, ec] = std::from_chars(text.data(), text.data() + text.size(), value);
    if (ec != std::errc{} || end != text.data() + text.size()) return std::nullopt;
    return value;
}

inline std::optional<NetDiag> ParseNetDiag(std::string_view line) {
    const size_t marker = line.find(kNetDiagMarker);
    if (marker == std::string_view::npos) return std::nullopt;
    const std::string_view rest = line.substr(marker + kNetDiagMarker.size());

    NetDiag diag;
    diag.raw = std::string(rest);
    for (size_t i = 0; i < rest.size();) {
        const size_t space = rest.find(' ', i);
        const std::string_view token = rest.substr(i, space == std::string_view::npos ? rest.size() : space - i);
        i = (space == std::string_view::npos) ? rest.size() : space + 1;

        const size_t eq = token.find('=');
        if (eq == std::string_view::npos) continue;
        const std::string_view key = token.substr(0, eq);
        const std::string_view value = token.substr(eq + 1);
        if (key == "symptom") {
            diag.symptom = value;
        } else if (key == "proto") {
            diag.protocol = value;
        } else if (key == "up") {
            diag.bytes_up = ParseUint(value).value_or(0);
        } else if (key == "down") {
            diag.bytes_down = ParseUint(value).value_or(0);
        } else if (key == "dur_ms") {
            diag.duration_ms = static_cast<uint32_t>(ParseUint(value).value_or(0));
        } else if (key == "idle_ms") {
            diag.idle_ms = static_cast<uint32_t>(ParseUint(value).value_or(0));
        } else if (key == "repeat") {
            diag.repeat = static_cast<uint32_t>(ParseUint(value).value_or(0));
        } else if (key == "cut") {
            diag.cut_bytes = ParseUint(value).value_or(0);
        }
    }

    if (diag.symptom.empty()) return std::nullopt;
    return diag;
}

/** Invalid UTF-8 (a system message in the ANSI code page) becomes '?', so the
 * app's log reader (utf8.decode) never throws; the record separator too. */
inline std::string SanitizeUtf8(std::string_view in) {
    std::string out;
    out.reserve(in.size());
    for (size_t i = 0; i < in.size();) {
        auto c = static_cast<unsigned char>(in[i]);
        size_t len = c < 0x80 ? 1 : (c >> 5) == 0x6 ? 2 : (c >> 4) == 0xE ? 3 : (c >> 3) == 0x1E ? 4 : 0;
        bool valid = len != 0 && i + len <= in.size();
        for (size_t k = 1; valid && k < len; ++k) {
            valid = (static_cast<unsigned char>(in[i + k]) & 0xC0) == 0x80;
        }
        if (!valid) {
            out += '?';
            ++i;
        } else if (c == 0x1E) {
            out += ' ';
            ++i;
        } else {
            out.append(in.substr(i, len));
            i += len;
        }
    }
    return out;
}

/**
 * One record in the format of the app's log reader (vpn_plugin LogDecoder):
 * "2026-09-25T22:45:23.887787 [info] message". The CLI writes
 * "25.09.2026 22:45:23.887787 INFO  [22430] VPNCORE message".
 */
inline std::string ToRecord(std::string_view line, const std::string& now) {
    std::string time;
    std::string level = "info";
    std::string_view message = line;

    // dd.mm.yyyy hh:mm:ss.ffffff LEVEL message
    if (line.size() > 27 && line[2] == '.' && line[5] == '.' && line[10] == ' ' && line[13] == ':') {
        size_t time_end = line.find(' ', 11);
        size_t level_end = time_end == std::string_view::npos ? time_end : line.find(' ', time_end + 1);
        if (level_end != std::string_view::npos) {
            time = std::string(line.substr(6, 4)) + "-" + std::string(line.substr(3, 2)) + "-" +
                    std::string(line.substr(0, 2)) + "T" + std::string(line.substr(11, time_end - 11));
            level.clear();
            for (char c : line.substr(time_end + 1, level_end - time_end - 1)) {
                level += static_cast<char>(tolower(static_cast<unsigned char>(c)));
            }
            message = line.substr(level_end);
            message.remove_prefix((std::min)(message.find_first_not_of(' '), message.size()));
        }
    }
    if (time.empty()) time = now;
    if (message.empty()) message = "-";
    return time + " [" + level + "] " + SanitizeUtf8(message);
}

/**
 * The -l argument for the CLI. The state lines this plugin relies on are
 * logged at info, but the app puts its own log level into the config
 * (usually "error"), so anything below info is raised to info; debug and
 * trace are kept.
 */
inline std::string CliLogLevel(std::string_view config) {
    size_t line_start = 0;
    while (line_start < config.size()) {
        size_t line_end = config.find('\n', line_start);
        if (line_end == std::string_view::npos) line_end = config.size();
        std::string_view line = config.substr(line_start, line_end - line_start);
        line_start = line_end + 1;

        size_t key = line.find_first_not_of(" \t");
        if (key == std::string_view::npos || line[key] == '[') {
            if (key != std::string_view::npos) break;  // top-level keys end at the first section
            continue;
        }
        if (line.substr(key, 8) != "loglevel") continue;
        if (line.find("\"debug\"") != std::string_view::npos) return "debug";
        if (line.find("\"trace\"") != std::string_view::npos) return "trace";
        break;
    }
    return "info";
}

}  // namespace vpn_plugin::cli_output
