import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';

/// [servers] in the order of [option] - shared by the servers list and the
/// «Уютный» server picker. Unmeasured / unreachable servers go last when
/// sorting by latency.
List<Server> sortServers(List<Server> servers, ServerSortOption option, ServerLatencyController latency) {
  final sorted = [...servers];

  switch (option) {
    case ServerSortOption.origin:
      sorted.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));
    case ServerSortOption.name:
      sorted.sort((a, b) => a.serverData.name.toLowerCase().compareTo(b.serverData.name.toLowerCase()));
    case ServerSortOption.latency:
      sorted.sort((a, b) {
        final latencyA = latency.resultFor(a.id)?.latency;
        final latencyB = latency.resultFor(b.id)?.latency;

        if (latencyA == null && latencyB == null) {
          return 0;
        }
        if (latencyA == null) {
          return 1;
        }
        if (latencyB == null) {
          return -1;
        }

        return latencyA.compareTo(latencyB);
      });
  }

  return sorted;
}
