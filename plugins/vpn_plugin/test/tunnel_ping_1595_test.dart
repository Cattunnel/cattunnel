import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/models/tunnel_ping.dart';
import 'package:vpn_plugin/vpn_plugin.dart';

// Item 13 of 1.5.9.5: the engine sends {"cattunnel_ping_ms":N} through
// onConnectionInfo after it has picked the endpoint. Android forwards N as an
// int (PingRecord.kt) on vpn_plugin_event_channel_pings.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the value from Android and the raw engine record are both read', () {
    expect(TunnelPing.fromValue(87), 87);
    expect(TunnelPing.fromValue('{"cattunnel_ping_ms":12}'), 12);
    expect(TunnelPing.fromValue('{"cattunnel_ping_ms": 0}'), 0);
  });

  test('anything else is not a ping', () {
    expect(TunnelPing.fromValue(-1), isNull);
    expect(TunnelPing.fromValue(60001), isNull);
    expect(TunnelPing.fromValue('{"cattunnel_ping_ms":"12"}'), isNull);
    expect(TunnelPing.fromValue('{"cattunnel_failure":"tls_reset"}'), isNull);
    expect(TunnelPing.fromValue('{"cattunnel_ping_ms":12,"x":1}'), isNull);
    expect(TunnelPing.fromValue('not json'), isNull);
    expect(TunnelPing.fromValue(null), isNull);
  });

  test('the plugin stream gives the pings in order and skips junk', () async {
    const channel = EventChannel('vpn_plugin_event_channel_pings');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events
            ..success(87)
            ..success('junk')
            ..success(70000)
            ..success('{"cattunnel_ping_ms":12}')
            ..endOfStream();
        },
      ),
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(channel, null),
    );

    expect(await VpnPluginImpl().tunnelPings.toList(), [87, 12]);
  });

  test('a platform without the channel gives no pings and no error', () async {
    expect(
      await VpnPluginImpl().tunnelPings
          .timeout(const Duration(milliseconds: 200), onTimeout: (sink) => sink.close())
          .toList(),
      isEmpty,
    );
  });
}
