import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/error/model/enum/presentation_field_name.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_protocol.dart';
import 'package:trusttunnel/feature/server/server_details/domain/service/server_details_service.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';
import 'package:vpn_plugin/models/vpn_mode.dart';

const _codec = ConfigurationCodec();

Configuration _config(Endpoint endpoint) => Configuration(
  vpnMode: VpnMode.general,
  endpoint: endpoint,
  tun: const Tun(),
  socks: const Socks(),
);

Endpoint _endpoint({
  int h2PaddingFrames = 0,
  int h2PaddingFramesMin = Endpoint.h2PaddingFramesMinDefault,
  bool h2PaddingPerStream = true,
  int h2PaddingMinBytes = Endpoint.h2PaddingMinBytesDefault,
  int h2PaddingMaxBytes = Endpoint.h2PaddingMaxBytesDefault,
  int h2PaddingStreamBytes = Endpoint.h2PaddingStreamBytesDefault,
  int h2PaddingSessionBytes = Endpoint.h2PaddingSessionBytesDefault,
  int keepaliveIntervalSecs = 0,
  String keepaliveSignal = '',
  int sessionLifetimeSecs = 0,
  bool xhttpEnabled = false,
  String xhttpPath = '',
}) => Endpoint(
  name: 'S',
  hostName: 'vpn.example.com',
  addresses: const ['203.0.113.5:443'],
  username: 'u',
  password: 'p',
  upStreamProtocol: UpStreamProtocol.http2,
  hasIpv6: true,
  h2PaddingFrames: h2PaddingFrames,
  h2PaddingFramesMin: h2PaddingFramesMin,
  h2PaddingPerStream: h2PaddingPerStream,
  h2PaddingMinBytes: h2PaddingMinBytes,
  h2PaddingMaxBytes: h2PaddingMaxBytes,
  h2PaddingStreamBytes: h2PaddingStreamBytes,
  h2PaddingSessionBytes: h2PaddingSessionBytes,
  keepaliveIntervalSecs: keepaliveIntervalSecs,
  keepaliveSignal: keepaliveSignal,
  sessionLifetimeSecs: sessionLifetimeSecs,
  xhttpEnabled: xhttpEnabled,
  xhttpPath: xhttpPath,
);

ServerData _server({
  int h2PaddingFrames = 0,
  int h2PaddingFramesMin = Endpoint.h2PaddingFramesMinDefault,
  int h2PaddingMinBytes = Endpoint.h2PaddingMinBytesDefault,
  int h2PaddingMaxBytes = Endpoint.h2PaddingMaxBytesDefault,
  int h2PaddingStreamBytes = Endpoint.h2PaddingStreamBytesDefault,
  int h2PaddingSessionBytes = Endpoint.h2PaddingSessionBytesDefault,
  int keepaliveIntervalSecs = 0,
  int sessionLifetimeSecs = 0,
  bool xhttpEnabled = false,
  String xhttpPath = '',
}) => ServerData(
  name: 'Server',
  ipAddress: '203.0.113.5',
  domain: 'vpn.example.com',
  username: 'u',
  password: 'p',
  vpnProtocol: VpnProtocol.http2,
  dnsServers: const [],
  routingProfileId: '1',
  ipv6: true,
  h2PaddingFrames: h2PaddingFrames,
  h2PaddingFramesMin: h2PaddingFramesMin,
  h2PaddingMinBytes: h2PaddingMinBytes,
  h2PaddingMaxBytes: h2PaddingMaxBytes,
  h2PaddingStreamBytes: h2PaddingStreamBytes,
  h2PaddingSessionBytes: h2PaddingSessionBytes,
  keepaliveIntervalSecs: keepaliveIntervalSecs,
  sessionLifetimeSecs: sessionLifetimeSecs,
  xhttpEnabled: xhttpEnabled,
  xhttpPath: xhttpPath,
);

void main() {
  group('the expert settings reach the engine config', () {
    test('the shaper numbers are written while the padding is on', () {
      final text = _codec.encode(
        _config(
          _endpoint(
            h2PaddingFrames: 4,
            h2PaddingFramesMin: 2,
            h2PaddingPerStream: true,
            h2PaddingMinBytes: 1,
            h2PaddingMaxBytes: 64,
            h2PaddingStreamBytes: 2048,
            h2PaddingSessionBytes: 4096,
          ),
        ),
      );

      expect(text, contains('h2_padding_frames = 4'));
      expect(text, contains('h2_padding_frames_min = 2'));
      expect(text, contains('h2_padding_per_stream = true'));
      expect(text, contains('h2_padding_min_bytes = 1'));
      expect(text, contains('h2_padding_max_bytes = 64'));
      expect(text, contains('h2_padding_stream_bytes = 2048'));
      expect(text, contains('h2_padding_session_bytes = 4096'));
    });

    test('the shaper numbers stay out of the config while the padding is off', () {
      final text = _codec.encode(_config(_endpoint()));

      expect(text, isNot(contains('h2_padding_frames_min')));
      expect(text, isNot(contains('h2_padding_max_bytes')));
      expect(text, isNot(contains('h2_padding_session_bytes')));
    });

    test('keepalive and XHTTP are written when they are on', () {
      final text = _codec.encode(
        _config(
          _endpoint(
            keepaliveIntervalSecs: 60,
            keepaliveSignal: 'ping',
            sessionLifetimeSecs: 1800,
            xhttpEnabled: true,
            xhttpPath: '/api/v2/',
          ),
        ),
      );

      expect(text, contains('keepalive_interval_secs = 60'));
      expect(text, contains('keepalive_signal = "ping"'));
      expect(text, contains('session_lifetime_secs = 1800'));
      expect(text, contains('xhttp_enable = true'));
      expect(text, contains('xhttp_path = "/api/v2/"'));
    });

    test('an off keepalive and XHTTP stay out of the config', () {
      final text = _codec.encode(_config(_endpoint()));

      expect(text, isNot(contains('keepalive_interval_secs')));
      expect(text, isNot(contains('xhttp_enable')));
    });

    test('an XHTTP path without a slash is not written', () {
      final text = _codec.encode(
        _config(_endpoint(xhttpEnabled: true, xhttpPath: 'api/v2')),
      );

      expect(text, contains('xhttp_enable = true'));
      expect(text, isNot(contains('xhttp_path')));
    });

    test('the values survive the round trip', () {
      final decoded = _codec.decode(
        _codec.encode(
          _config(
            _endpoint(
              h2PaddingFrames: 8,
              h2PaddingFramesMin: 3,
              h2PaddingPerStream: false,
              h2PaddingMinBytes: 8,
              h2PaddingMaxBytes: 32,
              h2PaddingStreamBytes: 1024,
              h2PaddingSessionBytes: 2048,
              keepaliveIntervalSecs: 120,
              keepaliveSignal: 'check',
              sessionLifetimeSecs: 900,
              xhttpEnabled: true,
              xhttpPath: '/x/',
            ),
          ),
        ),
      ).endpoint;

      expect(decoded.h2PaddingFrames, 8);
      expect(decoded.h2PaddingFramesMin, 3);
      expect(decoded.h2PaddingPerStream, false);
      expect(decoded.h2PaddingMinBytes, 8);
      expect(decoded.h2PaddingMaxBytes, 32);
      expect(decoded.h2PaddingStreamBytes, 1024);
      expect(decoded.h2PaddingSessionBytes, 2048);
      expect(decoded.keepaliveIntervalSecs, 120);
      expect(decoded.keepaliveSignal, 'check');
      expect(decoded.sessionLifetimeSecs, 900);
      expect(decoded.xhttpEnabled, true);
      expect(decoded.xhttpPath, '/x/');
    });

    test('a value out of range is clamped to what the engine takes', () {
      final decoded = _codec.decode(
        _codec.encode(
          _config(
            _endpoint(
              h2PaddingFrames: 1000,
              h2PaddingFramesMin: 1000,
              h2PaddingMinBytes: 1000,
              h2PaddingMaxBytes: 1000,
              h2PaddingStreamBytes: 100000000,
              h2PaddingSessionBytes: 100000000,
              keepaliveIntervalSecs: 100000,
              sessionLifetimeSecs: 100000,
            ),
          ),
        ),
      ).endpoint;

      expect(decoded.h2PaddingFrames, ConfigurationCodecKeys.h2PaddingFramesMax);
      expect(decoded.h2PaddingFramesMin, ConfigurationCodecKeys.h2PaddingFramesMinMax);
      expect(decoded.h2PaddingMinBytes, ConfigurationCodecKeys.h2PaddingBytesMax);
      expect(decoded.h2PaddingMaxBytes, ConfigurationCodecKeys.h2PaddingBytesMax);
      expect(decoded.h2PaddingStreamBytes, ConfigurationCodecKeys.h2PaddingBytesBudgetMax);
      expect(decoded.h2PaddingSessionBytes, ConfigurationCodecKeys.h2PaddingBytesBudgetMax);
      expect(decoded.keepaliveIntervalSecs, ConfigurationCodecKeys.keepaliveIntervalSecsMax);
      expect(decoded.sessionLifetimeSecs, ConfigurationCodecKeys.sessionLifetimeSecsMax);
    });

    test('an unknown keepalive signal is dropped', () {
      final decoded = _codec.decode(
        _codec.encode(
          _config(_endpoint(keepaliveIntervalSecs: 60, keepaliveSignal: 'pong')),
        ),
      ).endpoint;

      expect(decoded.keepaliveIntervalSecs, 60);
      expect(decoded.keepaliveSignal, isEmpty);
    });
  });

  group('the form stops a wrong value before the engine gets it', () {
    final service = ServerDetailsServiceImpl();

    test('the default values pass', () {
      final errors = service.validateData(data: _server());

      expect(errors, isEmpty);
    });

    test('a number out of range is flagged', () {
      final errors = service.validateData(
        data: _server(h2PaddingFrames: 4, h2PaddingFramesMin: 1000),
      );

      expect(errors, hasLength(1));
      expect(errors.first.fieldName, PresentationFieldName.expertSettings);
    });

    test('an emptied number is flagged', () {
      final errors = service.validateData(
        data: _server(h2PaddingFrames: 4, h2PaddingMaxBytes: -1),
      );

      expect(errors, hasLength(1));
      expect(errors.first.fieldName, PresentationFieldName.expertSettings);
    });

    test('a keepalive interval out of range is flagged', () {
      final errors = service.validateData(
        data: _server(keepaliveIntervalSecs: 100000),
      );

      expect(errors, hasLength(1));
      expect(errors.first.fieldName, PresentationFieldName.expertSettings);
    });

    test('an XHTTP path without a slash is flagged', () {
      final errors = service.validateData(
        data: _server(xhttpEnabled: true, xhttpPath: 'api/v2'),
      );

      expect(errors, hasLength(1));
      expect(errors.first.fieldName, PresentationFieldName.expertSettings);
    });

    test('an empty XHTTP path is the engine default, not an error', () {
      final errors = service.validateData(
        data: _server(xhttpEnabled: true),
      );

      expect(errors, isEmpty);
    });
  });
}
