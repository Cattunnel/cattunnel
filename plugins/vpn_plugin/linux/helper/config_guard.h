#pragma once

#include <optional>
#include <string>
#include <string_view>

namespace cattunnel_helper {

/** Limits on what the app may hand to root (see HELPER.md). */
inline constexpr size_t kMaxConfigBytes = 1024 * 1024;
inline constexpr size_t kMaxListItems = 50000;

/**
 * Whether the CLI config [toml] may be run as root: valid TOML, only the keys
 * the app's encoder writes (lib/domain/configuration_codec.dart), no file
 * paths, sane sizes, a SOCKS listener on loopback only.
 * @return The reason it's refused, or nullopt if it's fine.
 */
std::optional<std::string> CheckConfig(std::string_view toml);

}  // namespace cattunnel_helper
