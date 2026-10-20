import 'package:vpn_plugin/models/net_diagnostic.dart';

/// What the engine said about the last session to each server.
///
/// The engine sees what happens to the connection itself: the app only knows
/// that the tunnel went down. This keeps the last verdict per server, so the
/// UI can explain the death and the auto-balancer (later) can act on it.
abstract final class NetDiagnostics {
  /// How long a verdict counts as the current state of the connection.
  static const freshWindow = Duration(minutes: 10);

  static final _last = <String, (DateTime, NetDiagnostic)>{};

  static void record(String serverId, NetDiagnostic diagnostic, {DateTime? at}) =>
      _last[serverId] = (at ?? DateTime.now(), diagnostic);

  /// The server connected: whatever died before is over.
  static void clear(String serverId) => _last.remove(serverId);

  /// The last verdict for [serverId], if it happened within [within].
  static NetDiagnostic? recent(String serverId, {required Duration within, DateTime? now}) {
    final last = _last[serverId];
    if (last == null || (now ?? DateTime.now()).difference(last.$1) >= within) {
      return null;
    }

    return last.$2;
  }

  /// The last verdict for [serverId], if it is still fresh.
  static NetDiagnostic? fresh(String serverId, {DateTime? now}) =>
      recent(serverId, within: freshWindow, now: now);
}
