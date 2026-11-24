import 'dart:convert';

import 'package:drift/drift.dart';

/// Ready SNI names of a server (ServerData.sniPool), stored as a JSON array
/// in one text column. An empty string is "no pool".
class SniPoolColumn extends TypeConverter<List<String>, String> {
  const SniPoolColumn();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    try {
      final value = jsonDecode(fromDb);
      if (value is List) {
        return value.whereType<String>().where((name) => name.isNotEmpty).toList();
      }
    } on FormatException {
      // An older or corrupted value: no pool is better than a broken row.
    }
    return const [];
  }

  @override
  String toSql(List<String> value) {
    final names = value.where((name) => name.isNotEmpty).toList();
    return names.isEmpty ? '' : jsonEncode(names);
  }
}
