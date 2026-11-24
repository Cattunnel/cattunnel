import 'dart:convert';

import 'package:drift/drift.dart';

/// The list stays saved when the local rotation switch is off.
class RotationAddressesColumn extends TypeConverter<List<String>, String> {
  const RotationAddressesColumn();

  @override
  List<String> fromSql(String fromDb) {
    if (fromDb.isEmpty) return const [];
    try {
      final value = jsonDecode(fromDb);
      if (value is List) return value.whereType<String>().where((address) => address.isNotEmpty).toList();
    } on FormatException {
      // An older or damaged value is treated as an empty list.
    }
    return const [];
  }

  @override
  String toSql(List<String> value) {
    final addresses = value.where((address) => address.isNotEmpty).toList();
    return addresses.isEmpty ? '' : jsonEncode(addresses);
  }
}
