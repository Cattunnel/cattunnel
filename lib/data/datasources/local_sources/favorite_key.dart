/// Key of a favorite in the favorite_servers table.
///
/// A subscription server is deleted and inserted again (new row id) when it
/// leaves the subscription and returns, so its key is the subscription id plus
/// the name, the same pair the sync matches rows by. A manual server has no
/// such pair and is keyed by its row id.
String favoriteKey({
  required int rowId,
  required String name,
  required int? subscriptionId,
}) => subscriptionId == null ? 'm:$rowId' : 's:$subscriptionId:$name';

/// SQL LIKE pattern of every favorite of one subscription.
String favoriteKeyPrefixOf(int subscriptionId) => 's:$subscriptionId:%';
