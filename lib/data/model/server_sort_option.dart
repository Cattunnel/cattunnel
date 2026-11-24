/// How the servers list is ordered.
enum ServerSortOption {
  /// Manual servers in the order they were added; a subscription's servers in
  /// the order of the subscription itself. This is the default until the user
  /// picks something else. Favorites come first under every option.
  origin,

  name,

  /// By last measured latency, ascending. Servers with no test result yet
  /// sort after every tested one.
  latency,
}
