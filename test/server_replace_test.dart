import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/feature/server/server_details/domain/service/server_details_service.dart';

ServerData data({
  String address = 'vpn.example.org:8443',
  String domain = 'vpn.example.org',
  String user = 'alice',
  String pass = 'secret',
  String? prefix,
  String? subscription,
}) => ServerData(
  name: 'Home',
  ipAddress: address,
  domain: domain,
  username: user,
  password: pass,
  vpnProtocol: VpnProtocol.http2,
  dnsServers: const [],
  routingProfileId: '1',
  ipv6: true,
  tlsPrefix: prefix,
  subscriptionName: subscription,
);

void main() {
  final service = ServerDetailsServiceImpl();

  test('a new link to the same manual server (port changed) updates it', () {
    final existing = Server(id: '7', serverData: data());
    final found = service.findServerToReplace(data(address: 'vpn.example.org:9443', domain: 'VPN.example.org '), [existing]);
    expect(found?.id, '7');
  });

  test('another account, another key or a subscription server - no replacement', () {
    final manual = Server(id: '1', serverData: data());
    final fromSubscription = Server(id: '2', serverData: data(subscription: 'Family'));
    expect(service.findServerToReplace(data(user: 'bob'), [manual]), isNull);
    expect(service.findServerToReplace(data(pass: 'other'), [manual]), isNull);
    expect(service.findServerToReplace(data(prefix: 'abcd'), [manual]), isNull);
    expect(service.findServerToReplace(data(), [fromSubscription]), isNull);
  });
}
