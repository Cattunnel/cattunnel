import 'package:vpn_plugin/models/connect_failure.dart';

/// What the engine said about the last failed connection to each server
/// (ConnectFailure - our engine build on Android and Linux), so that nothing
/// in the app keeps knocking on an address a filter has frozen: anti-DPI
/// "auto" stops switching techniques (VpnScope) and Marsik skips his own
/// handshakes to it (ConnectionDiagnostics). VpnScope records and clears.
abstract final class ConnectFailures {
  /// How long a ClientHello without an answer counts as a frozen address.
  /// The June 2026 TSPU reports give ~120 s per freeze; the engine itself
  /// waits 60 s between its attempts then (vpn_fsm.cpp handshake_pause).
  static const freezeWindow = Duration(minutes: 2);

  static final _last = <String, (DateTime, ConnectFailure)>{};

  static void record(String serverId, ConnectFailure failure, {DateTime? at}) =>
      _last[serverId] = (at ?? DateTime.now(), failure);

  /// The server connected: whatever failed before is over.
  static void clear(String serverId) => _last.remove(serverId);

  /// The last failure for [serverId], if it happened within [within].
  static ConnectFailure? recent(String serverId, {required Duration within, DateTime? now}) {
    final last = _last[serverId];
    if (last == null || (now ?? DateTime.now()).difference(last.$1) >= within) {
      return null;
    }

    return last.$2;
  }

  /// Whether [serverId]'s address looks frozen right now.
  static bool isFrozen(String serverId, {DateTime? now}) =>
      recent(serverId, within: freezeWindow, now: now) == ConnectFailure.helloNoAnswer;
}
