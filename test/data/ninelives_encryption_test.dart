import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server_data.dart';

ServerData _server({required String key, required bool xhttp, required bool encryption}) => ServerData.empty(
  name: 'S',
  xhttpEnabled: xhttp,
  xhttpServerKey: key,
  xhttpEncryptionEnabled: encryption,
);

void main() {
  test('the engine gets the NineLives key when XHTTP and encryption are on', () {
    expect(_server(key: 'public-key', xhttp: true, encryption: true).engineXhttpServerKey, 'public-key');
  });

  test('the key is kept but not sent when the local switch is off', () {
    final server = _server(key: 'public-key', xhttp: true, encryption: false);

    expect(server.xhttpServerKey, 'public-key');
    expect(server.engineXhttpServerKey, '');
  });

  test('a server without a key never sends one', () {
    expect(_server(key: '', xhttp: true, encryption: true).engineXhttpServerKey, '');
  });

  test('the key is not sent when XHTTP itself is off', () {
    expect(_server(key: 'public-key', xhttp: false, encryption: true).engineXhttpServerKey, '');
  });
}
