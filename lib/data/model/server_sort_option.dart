/// How the servers list is ordered.
enum ServerSortOption {
  /// Natural insertion order (oldest first) - i.e. by when each server was
  /// added, whether manually, via a link/QR, or by a subscription. This is
  /// the default until the user picks something else.
  origin,

  name,

  /// By last measured latency, ascending. Servers with no test result yet
  /// sort after every tested one.
  latency,
}
