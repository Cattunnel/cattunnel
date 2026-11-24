import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';

/// [servers] in the order of [option] - shared by the servers list and the
/// «Уютный» server picker. Favorites come first under every option and are
/// ordered by the same option among themselves. Unmeasured / unreachable
/// servers go last when sorting by latency.
List<Server> sortServers(
  List<Server> servers,
  ServerSortOption option,
  ServerLatencyController latency,
) {
  final sorted = [...servers];

  int byOption(Server a, Server b) {
    switch (option) {
      case ServerSortOption.origin:
        return 0;
      case ServerSortOption.name:
        return a.serverData.name.toLowerCase().compareTo(
          b.serverData.name.toLowerCase(),
        );
      case ServerSortOption.latency:
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
    }
  }

  sorted.sort((a, b) {
    if (a.favorite != b.favorite) {
      return a.favorite ? -1 : 1;
    }

    final result = byOption(a, b);

    return result != 0 ? result : _byOrigin(a, b);
  });

  return sorted;
}

/// Manual servers by row id, then each subscription's servers by their place
/// in the subscription response (row id when the position is unknown). The
/// order is total, so ties in other sorts do not depend on the sort algorithm.
int _byOrigin(Server a, Server b) {
  final subscriptionA = int.tryParse(a.serverData.subscriptionId ?? '') ?? -1;
  final subscriptionB = int.tryParse(b.serverData.subscriptionId ?? '') ?? -1;
  if (subscriptionA != subscriptionB) {
    return subscriptionA.compareTo(subscriptionB);
  }

  final idA = int.parse(a.id);
  final idB = int.parse(b.id);
  if (subscriptionA != -1) {
    final positionA = a.subscriptionPosition ?? idA;
    final positionB = b.subscriptionPosition ?? idB;
    if (positionA != positionB) {
      return positionA.compareTo(positionB);
    }
  }

  return idA.compareTo(idB);
}
