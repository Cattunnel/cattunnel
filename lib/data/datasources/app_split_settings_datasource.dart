/// Which apps the VPN captures on Android (per-app split tunneling).
enum AppSplitMode {
  /// Every app uses the VPN.
  off,

  /// The selected apps bypass the VPN, everything else uses it.
  exclude,

  /// Only the selected apps use the VPN.
  include,
}

abstract class AppSplitSettingsDataSource {
  Future<AppSplitMode> getMode();

  Future<void> setMode(AppSplitMode mode);

  /// Package names picked for the current mode's list. The two modes keep
  /// separate lists, so switching back and forth loses nothing.
  Future<List<String>> getApps(AppSplitMode mode);

  Future<void> setApps(AppSplitMode mode, List<String> packages);

  /// Russian and Chinese/vendor apps always bypass the VPN (outside the
  /// "only selected" mode), recomputed on every connect. On by default.
  Future<bool> getAutoRuCn();

  Future<void> setAutoRuCn(bool enabled);

  /// Automatic non-Russian apps (Chinese, vendor, Uzbek, local tools) the
  /// person put back into the VPN. Russian apps can't be.
  Future<List<String>> getForcedVpn();

  Future<void> setForcedVpn(List<String> packages);
}
