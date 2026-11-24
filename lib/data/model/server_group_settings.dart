/// Key of the group of manual servers.
const manualGroupKey = 'm';

/// Key of the group of one subscription.
String subscriptionGroupKey(String subscriptionId) => 's:$subscriptionId';

/// The user's own look of a group on the servers screen. [label] is only a
/// display name, empty means the original one; [position] is null until the
/// user has ordered the groups.
class ServerGroupSettings {
  final String label;
  final int? position;

  const ServerGroupSettings({this.label = '', this.position});
}
