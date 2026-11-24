Русский: [shared.md](shared.md) (the Russian text is the main one; if the two differ, the Russian text is right)

# Shared code (all platforms): security (fixes)

Fixes of the shared app code found by an internal audit. Items 6 and 7 come from the list in [KNOWN-ISSUES.en.md](KNOWN-ISSUES.en.md), the rest were added later. All of them are present in the 1.5.9.5 code. Linux only fixes: [linux.en.md](linux.en.md).

```text
 outside data                         what the app checks
 ---------------------------------------------------------------------
 lists of Russian networks, domains -> coverage limits, zones .ru/.su/.рф (item 6)
 server name, password, certificate -> escaping in TOML (items 7, 11)
 tt:// link and config file         -> DER length, ru_exit, names (items 9, 10, 12)
 subscription, manifest, APK        -> size limit (item 13)
 certificate store                  -> no Russian roots (items 8, 14)
```

Figure 1. What comes from outside and where the check stands.

## Fixed in the first group (items 6 and 7)

| # | Problem | Fix | Check |
|---|---------|-----|-------|
| 6 | Russian lists: a poisoned IPv6 list could collapse into `2000::/3` (all IPv6 outside the VPN); any foreign domains could become "Russian" | `lib/data/ru_lists/ru_lists_service.dart`: a limit of 1 % of `2000::/3` per source (3 % for IPv4), a total limit after merging (5 % IPv4 and 2 % IPv6, otherwise the IP sections are empty and the built-in ones work); domains from downloaded lists only in `.ru`, `.su`, `.рф` and a short verified list (`vk.com`, `yandex.net` and others) | `test/ru_lists_test.dart` (400 /16 networks are rejected; `torproject.org` and `protonmail.com` do not pass) |
| 7 | The config encoder did not escape strings: a quote or a newline in a server name or password added extra keys to the core TOML | `IniString.encode` in `plugins/vpn_plugin/lib/models/ini_document.dart`: a basic string with escaping (`\"`, `\\`, `\n`, control characters as `\uXXXX`); the multiline `"""` form only for PEM without dangerous characters; the decoder and list parsing understand the escaping | `plugins/vpn_plugin/test/ini_escape_test.dart` |

## Certificates on Windows and Linux

| # | Problem | Fix | Check |
|---|---------|-----|-------|
| 8 | On Windows and Linux the core verified the server certificate against the whole system store. The Gosuslugi installer puts the NUC root ("Russian Trusted Root CA") into the trusted roots of Windows. Whoever holds it could forge the server certificate and read the tunnel along with the password | `lib/feature/security/domain/desktop_ca_bundle.dart`: roots from the Windows ROOT store or from the Linux distribution bundle minus "Russian Trusted Root/Sub CA" (a search in the DER), plus ISRG Root X1 and X2. `SecurityPlatform.systemCaBundle()` gives the bundle to the core (`EndpointCaResolver`) and to the diagnostics (`ServerTls`). The switch "trust user certificates" returns the default behavior. On Android the same is closed through `SecurityChannel.kt` | `test/feature/security/desktop_ca_bundle_test.dart` (the Russian root is dropped, ISRG is always present) |

Still open: the config size on Linux is limited to 1 MiB (`plugins/vpn_plugin/linux/helper/config_guard.h`). If the lists and the certificate bundle grow, this limit may become tight.

## Fixed in 1.5.5

| # | Problem | Fix | Check |
|---|---------|-----|-------|
| 9 | A `tt://` link with a certificate whose DER length was written in 8 bytes made the decoder loop until memory ran out | `plugins/vpn_plugin/lib/domain/deep_link_payload_codec.dart`: the DER length takes 1 to 4 bytes and is above zero | a decoder regression test |
| 10 | A `tt://` link or a config file from another person silently turned on the "Russian exit". With a key used from Russia, banks would go through the VPN | `lib/data/repository/deep_link_repository.dart`: on importing a link or a file, `ru_exit` is reset and `RuExitPrompt` asks on the first connection; subscriptions keep the flag | `test/deep_link_ru_exit_test.dart` |
| 11 | Importing a config file unescaped TOML a second time: a password with `\` was corrupted (`a\\nb` became a newline) | `lib/data/datasources/local_sources/server_config_import.dart`: only the INI reader unescapes | `test/config_file_import_test.dart` |
| 12 | Server and subscription names could contain control characters and text direction characters (U+202E shows the rest of the name backwards) | `lib/common/utils/display_name.dart`: C0 and C1, U+061C, U+200E and U+200F, U+202A to U+202E, U+2066 to U+2069 are removed; ZWJ and variation selectors (emoji) stay | `test/display_name_test.dart` |
| 13 | Responses of the subscription, the update manifest, the Russian lists and the APK were read without a size limit | `lib/common/utils/limited_http.dart`: subscription 4 MB, `latest.json` 256 KB (and a 4 KB signature), lists 16 MB, APK 400 MB; a declared `Content-Length` above the limit means refusal before reading | `test/limited_http_test.dart` |
| 14 | Desktop: if the system store could not be read, the core stayed on its default (the whole store with the Russian roots); Ministry certificates were filtered by name only | `desktop_ca_bundle.dart`: in that case only the Let's Encrypt roots are used; Ministry certificates are also filtered by the SHA-256 fingerprint of the public key (the root and both Sub CAs), on Android too (`SecurityChannel.kt`) | `test/feature/security/desktop_ca_bundle_test.dart`: real certificates from `test/fixtures/`, the same key under another name is filtered, the ISRG Root X1 key is pinned |
