import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';

/// Where the last value per server is kept between launches.
abstract class PingStore {
  Map<String, ServerLatencyResult> load();

  Future<void> save(Map<String, ServerLatencyResult> results);
}

/// [PingStore] in the app's shared preferences: `{serverId: [ms, epochMillis]}`.
class SharedPreferencesPingStore implements PingStore {
  static const key = 'server_ping_v1';

  final SharedPreferences _preferences;

  SharedPreferencesPingStore(this._preferences);

  @override
  Map<String, ServerLatencyResult> load() {
    try {
      final raw = _preferences.getString(key);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map<String, dynamic>;

      return {
        for (final entry in decoded.entries)
          entry.key: ServerLatencyResult(
            latency: Duration(milliseconds: (entry.value as List)[0] as int),
            testedAt: DateTime.fromMillisecondsSinceEpoch((entry.value as List)[1] as int),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> save(Map<String, ServerLatencyResult> results) => _preferences.setString(
    key,
    jsonEncode({
      for (final entry in results.entries)
        if (entry.value.latency != null)
          entry.key: [entry.value.latency!.inMilliseconds, entry.value.testedAt.millisecondsSinceEpoch],
    }),
  );
}

/// The last "ping" of every server: the number the engine sends once per
/// connect, after it has picked the endpoint (`{"cattunnel_ping_ms":N}`, see
/// VpnPlugin.tunnelPings; item 13 of 1.5.9.5). The app makes no request of
/// its own for it and never connects to a server's address.
///
/// The value belongs to the server the current connection was started for:
/// the one selected when the state went to "connecting". Picking another
/// server while connected does not move it there.
class ServerLatencyController extends ChangeNotifier {
  final PingStore? _store;
  final DateTime Function() _now;

  ServerLatencyController({
    PingStore? store,
    DateTime Function() now = DateTime.now,
  }) : _store = store,
       _now = now {
    _results.addAll(_store?.load() ?? const {});
  }

  final Map<String, ServerLatencyResult> _results = {};

  /// The server of the connection in progress; null while disconnected.
  String? _connectionFor;
  String? _selected;
  bool _disposed = false;

  Map<String, ServerLatencyResult> get results => Map.unmodifiable(_results);

  ServerLatencyResult? resultFor(String serverId) => _results[serverId];

  /// The VPN state or the selected server changed.
  void connectionChanged(VpnState state, {String? serverId}) {
    _selected = serverId;
    switch (state) {
      case VpnState.disconnected:
        _connectionFor = null;
      case VpnState.connecting:
        // A new attempt is for the server selected now.
        _connectionFor = serverId;
      default:
        _connectionFor ??= serverId;
    }
  }

  /// The engine's ping of the endpoint it picked. It can come before the
  /// "connecting" state reaches the app: then it is the selected server's.
  void pingReported(int milliseconds) {
    if (_disposed || milliseconds < 0) return;
    final serverId = _connectionFor ?? _selected;
    if (serverId == null) return;

    _results[serverId] = ServerLatencyResult(
      latency: Duration(milliseconds: milliseconds),
      testedAt: _now(),
    );
    unawaited(_store?.save(_results));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
