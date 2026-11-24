import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:trusttunnel/common/error/model/enum/presentation_field_name.dart';
import 'package:trusttunnel/data/database/app_database.dart';
import 'package:trusttunnel/data/datasources/local_sources/server_config_import.dart';
import 'package:trusttunnel/data/datasources/local_sources/subscription_datasource_impl.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/server_details/domain/service/server_details_service.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/deep_link_payload_codec.dart';

// The subscription owns its keys (1.5.9 rule): a sync writes every value,
// rotation (0x53-0x55) and CatTail (0x56-0x59) too, unless the key is
// "above the subscription". The links are built byte by byte the way the bot
// writes them (services/trusttunnel.py, claude/bot-1595).
List<int> _varint(int value) => value <= 0x3f ? [value] : [(value >> 8) | 0x40, value & 0xff];

List<int> _tlv(int tag, List<int> value) => [..._varint(tag), ..._varint(value.length), ...value];

List<int> _str(int tag, String value) => _tlv(tag, utf8.encode(value));

final _key = List<int>.generate(32, (i) => 255 - i);

String _link({bool rotation = true, bool cattail = true}) {
  final bytes = [
    ..._tlv(0x00, [0x01]),
    ..._str(0x0C, 'Германия 0'),
    ..._str(0x01, 'a1.example.com'),
    ..._str(0x02, '198.51.100.20:443'),
    ..._str(0x05, 'u'),
    ..._str(0x06, 'p'),
    if (rotation) ...[
      ..._tlv(0x53, [
        for (final entry in [
          'a1.example.com:443 a1.example.com a2.example.com',
          'b1.example.com:443 b1.example.com b2.example.com',
        ]) ...[..._varint(utf8.encode(entry).length), ...utf8.encode(entry)],
      ]),
      ..._tlv(0x54, _varint(600)),
      ..._tlv(0x55, _varint(900)),
    ],
    if (cattail) ...[
      ..._tlv(0x56, [0x01]),
      ..._str(0x57, '20000-40000'),
      ..._tlv(0x58, _key),
      ..._str(0x59, 'stop=2\n0=400-1400\n1=100-400'),
    ],
  ];
  return 'tt://?${base64Url.encode(bytes).replaceAll('=', '')}';
}

ServerData _fromLink(String link) => serverDataFromEndpoint(
  const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert(link)).endpoint,
  routingProfileId: '1',
);

void main() {
  setUpAll(() {
    if (Platform.isLinux && File('/usr/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
      open.overrideFor(OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
    }
  });

  late AppDatabase database;
  late SubscriptionDataSourceImpl datasource;
  late int subscriptionId;

  setUp(() async {
    database = AppDatabase.inMemory(NativeDatabase.memory());
    datasource = SubscriptionDataSourceImpl(database: database);
    subscriptionId = await database
        .into(database.subscriptions)
        .insert(
          SubscriptionsCompanion.insert(name: 'Family', url: 'https://example.org/sub'),
        );
  });

  tearDown(() => database.close());

  Future<void> sync(String link) =>
      datasource.syncServersForSubscription(id: subscriptionId.toString(), servers: [_fromLink(link)]);

  Future<Server> row() => database.select(database.servers).getSingle();

  Future<void> editByHand({bool override = false}) => (database.update(database.servers)).write(
    ServersCompanion(
      rotationEnabled: const Value(false),
      rotationAddresses: const Value(['192.0.2.99:443']),
      rotationMinSecs: const Value(60),
      rotationMaxSecs: const Value(61),
      cattailEnabled: const Value(false),
      cattailPorts: const Value('443'),
      subscriptionOverride: Value(override),
    ),
  );

  test('a subscription key gets the rotation servers with their names and CatTail', () async {
    await sync(_link());
    final server = await row();

    expect(server.rotationEnabled, isTrue);
    expect(server.rotationAddresses, [
      'a1.example.com:443 a1.example.com a2.example.com',
      'b1.example.com:443 b1.example.com b2.example.com',
    ]);
    expect([server.rotationMinSecs, server.rotationMaxSecs], [600, 900]);
    expect(server.cattailEnabled, isTrue);
    expect(server.cattailPorts, '20000-40000');
    expect(server.cattailKey, base64Encode(_key));
    expect(server.cattailPattern, 'stop=2\n0=400-1400\n1=100-400');
  });

  test('the next sync puts the subscription values back over a manual change', () async {
    await sync(_link());
    await editByHand();
    await sync(_link());
    final server = await row();

    expect(server.rotationEnabled, isTrue);
    expect(server.rotationAddresses, hasLength(2));
    expect([server.rotationMinSecs, server.rotationMaxSecs], [600, 900]);
    expect(server.cattailEnabled, isTrue);
    expect(server.cattailPorts, '20000-40000');
  });

  test('"above the subscription" keeps the manual values through a sync', () async {
    await sync(_link());
    await editByHand(override: true);
    await sync(_link());
    final server = await row();

    expect(server.rotationEnabled, isFalse);
    expect(server.rotationAddresses, ['192.0.2.99:443']);
    expect([server.rotationMinSecs, server.rotationMaxSecs], [60, 61]);
    expect(server.cattailEnabled, isFalse);
    expect(server.cattailPorts, '443');
  });

  test('a subscription that drops the tags turns rotation and CatTail off', () async {
    await sync(_link());
    await sync(_link(rotation: false, cattail: false));
    final server = await row();

    expect(server.rotationEnabled, isFalse);
    expect(server.rotationAddresses, isEmpty);
    expect([server.rotationMinSecs, server.rotationMaxSecs], [0, 0]);
    expect(server.cattailEnabled, isFalse);
    expect([server.cattailPorts, server.cattailKey, server.cattailPattern], ['', '', '']);
  });

  group('the server form (CatTail switch and the rotation tab)', () {
    final service = ServerDetailsServiceImpl();
    final fromSubscription = _fromLink(_link());

    List<PresentationFieldName> errors(ServerData data) =>
        service.validateData(data: data).map((field) => field.fieldName).toList();

    test('a key from the subscription saves as it is', () {
      expect(errors(fromSubscription), isEmpty);
    });

    test('CatTail switched on without a key or with wrong ports stops the save', () {
      const own = ServerData.empty(
        name: 'Own',
        ipAddress: '203.0.113.5:443',
        domain: 'vpn.example.com',
        username: 'u',
        password: 'p',
      );
      expect(errors(own.copyWith(cattailEnabled: true)), [PresentationFieldName.cattail]);
      expect(
        errors(own.copyWith(cattailEnabled: true, cattailKey: base64Encode(_key), cattailPorts: '70000')),
        [PresentationFieldName.cattail],
      );
      expect(
        errors(own.copyWith(cattailEnabled: true, cattailKey: base64Encode(_key), cattailPorts: '20000-40000')),
        isEmpty,
      );
      // Switched off, the saved values do not matter.
      expect(errors(own.copyWith(cattailPorts: 'junk')), isEmpty);
    });

    test('a wrong address, a wrong SNI name or a wrong term range is flagged', () {
      expect(errors(fromSubscription.copyWith(rotationAddresses: ['1.2.3.4:0'])), [
        PresentationFieldName.rotationAddresses,
      ]);
      expect(errors(fromSubscription.copyWith(rotationAddresses: ['1.2.3.4 bad_name'])), [
        PresentationFieldName.rotationAddresses,
      ]);
      expect(errors(fromSubscription.copyWith(rotationMinSecs: 30)), [PresentationFieldName.rotationTerm]);
      expect(errors(fromSubscription.copyWith(rotationMinSecs: 900, rotationMaxSecs: 600)), [
        PresentationFieldName.rotationTerm,
      ]);
      expect(errors(fromSubscription.copyWith(rotationMinSecs: 0, rotationMaxSecs: 0)), isEmpty);
    });
  });
}
