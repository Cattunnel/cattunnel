import 'package:flutter/foundation.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/repository/server_test_timeout_repository.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_result.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';

/// Holds reachability-test results for servers, keyed by server id.
///
/// Deliberately in-memory only (not persisted) - this is a live "test now"
/// signal, not a fact about the server that should survive an app restart.
class ServerLatencyController extends ChangeNotifier {
  final ServerLatencyTester _tester;
  final ServerTestTimeoutRepository _timeoutRepository;

  ServerLatencyController({
    required ServerTestTimeoutRepository timeoutRepository,
    ServerLatencyTester tester = const ServerLatencyTester(),
  }) : _tester = tester,
       _timeoutRepository = timeoutRepository;

  final Map<String, ServerLatencyResult> _results = {};
  final Set<String> _testingIds = {};

  Map<String, ServerLatencyResult> get results => Map.unmodifiable(_results);

  Set<String> get testingIds => Set.unmodifiable(_testingIds);

  ServerLatencyResult? resultFor(String serverId) => _results[serverId];

  bool isTesting(String serverId) => _testingIds.contains(serverId);

  Future<void> testServer(Server server) async {
    if (_testingIds.contains(server.id)) {
      return;
    }

    _testingIds.add(server.id);
    notifyListeners();

    final timeoutSeconds = await _timeoutRepository.getValueSeconds();
    final result = await _tester.test(
      server.serverData.ipAddress,
      timeout: Duration(seconds: timeoutSeconds),
    );

    _results[server.id] = result;
    _testingIds.remove(server.id);
    notifyListeners();
  }

  Future<void> testAll(List<Server> servers) => Future.wait(servers.map(testServer));

  /// Clears a stale *unreachable* mark for [serverId], used when a live
  /// successful VPN connection to that server is itself proof it's
  /// reachable. Never touches an already-reachable result - doing so would
  /// wipe a real, useful latency reading (and, while sorted by latency,
  /// send the very server the user just connected to jump to the bottom of
  /// the list) for no reason.
  void clearResult(String serverId) {
    final existing = _results[serverId];

    if (existing != null && !existing.reachable) {
      _results.remove(serverId);
      notifyListeners();
    }
  }
}
