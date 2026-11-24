import 'package:trusttunnel/data/model/server_group_settings.dart';

/// Group keys in the order to show them. [defaultKeys] is the order without
/// any user choice (subscriptions as fetched, then the manual group, as the
/// owner asked: «подписка 1, подписка 2, Свои ключи»). A group the user has
/// ordered goes by its position; a new one has none and goes after them, the
/// manual group after new subscriptions.
List<String> orderGroupKeys(List<String> defaultKeys, Map<String, ServerGroupSettings> settings) {
  int rank(String key, int index) =>
      settings[key]?.position ?? (key == manualGroupKey ? 1 << 31 : (1 << 30) + index);

  final indexed = [for (final (index, key) in defaultKeys.indexed) (key: key, index: index)];
  indexed.sort((a, b) {
    final byRank = rank(a.key, a.index).compareTo(rank(b.key, b.index));

    return byRank != 0 ? byRank : a.index.compareTo(b.index);
  });

  return [for (final entry in indexed) entry.key];
}

/// Name to show: the user's label, or [original] when there is none.
String groupDisplayName(String original, ServerGroupSettings? settings) {
  final label = settings?.label.trim() ?? '';

  return label.isEmpty ? original : label;
}

/// [keys] with [key] moved one place by [delta] (-1 up, 1 down); same list
/// when it cannot move.
List<String> moveGroupKey(List<String> keys, String key, int delta) {
  final from = keys.indexOf(key);
  final to = from + delta;
  if (from < 0 || to < 0 || to >= keys.length) return keys;

  final moved = [...keys]..removeAt(from);

  return moved..insert(to, key);
}
