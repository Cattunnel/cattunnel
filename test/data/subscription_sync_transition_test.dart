import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';

Server _server(String id, {required bool antiDpi}) => Server(
  id: id,
  serverData: ServerData.empty(name: id, antiDpi: antiDpi),
);

void main() {
  test('anti-DPI turned on by the subscription: only false -> true', () {
    final before = {'1': false, '2': false, '3': true, '4': false};

    expect(
      SubscriptionSyncService.turnedOnAntiDpi(before, [
        _server('1', antiDpi: true),
        _server('2', antiDpi: false),
        _server('3', antiDpi: true),
        _server('4', antiDpi: false),
      ]),
      ['1'],
    );
  });

  test('a server new to the app has nothing to forget', () {
    expect(SubscriptionSyncService.turnedOnAntiDpi({}, [_server('5', antiDpi: true)]), isEmpty);
  });
}
