import 'package:flutter_test/flutter_test.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/deep_link_payload_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';

// A throwaway self-signed chain (leaf + CA), generated for this test only.
const _chain = '''-----BEGIN CERTIFICATE-----
MIIBijCCAS+gAwIBAgIUbhbvBw5Lu/aICbNWcZ44newJY/AwCgYIKoZIzj0EAwIw
GjEYMBYGA1UEAwwPdnBuLmV4YW1wbGUuY29tMB4XDTI2MDkyNTIwNTIyN1oXDTM2
MDkyMjIwNTIyN1owGjEYMBYGA1UEAwwPdnBuLmV4YW1wbGUuY29tMFkwEwYHKoZI
zj0CAQYIKoZIzj0DAQcDQgAEiLQOarkdcF/elBDmRXwxWz3DZ11QlLXPevpmdHYq
RvjS7+E4VYQ9aTvbAFiEmTnJVXF/kzi9JZjTNpmnP+UkT6NTMFEwHQYDVR0OBBYE
FGfqCOT0T35uK6fCIwNvhfI0uwgHMB8GA1UdIwQYMBaAFGfqCOT0T35uK6fCIwNv
hfI0uwgHMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSQAwRgIhAOPNau0l
S9pI22Ea+IO0GopupMzDs5h4PfOnFUtghlo0AiEAgH0eoMgOjs4875B6Imyt0Buu
mDyYuXHTKAIgX6/zv+4=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIIBeTCCAR+gAwIBAgIUZrOHTRbYvBO0037kUh8HtvsQwc4wCgYIKoZIzj0EAwIw
EjEQMA4GA1UEAwwHdGVzdC1jYTAeFw0yNjA5MjUyMDUyMjdaFw0zNjA5MjIyMDUy
MjdaMBIxEDAOBgNVBAMMB3Rlc3QtY2EwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNC
AASGje8h3MzvSkUbUuZoD/PcJuiI9zJFl+8oA9C1veRN/DXwnIf+IcM9tXGOzMwR
7ei061X5EJAjZs7m6rInXwXwo1MwUTAdBgNVHQ4EFgQUDc5bv17iKThDyW1WObJK
tkDXHVswHwYDVR0jBBgwFoAUDc5bv17iKThDyW1WObJKtkDXHVswDwYDVR0TAQH/
BAUwAwEB/zAKBggqhkjOPQQDAgNIADBFAiAzPFHZDlRpjNLspwWVlZGveH8JlNiE
Z0RguWJ+cMcd7AIhAKKlZLlCaUwNg4OBqDBpYklMUHys3Kbt88gCXH517bXG
-----END CERTIFICATE-----''';

const _full = Endpoint(
  name: 'Германия "main"',
  hostName: 'vpn.example.com',
  addresses: ['203.0.113.5:443', '[2001:db8::1]:8443'],
  username: 'alice',
  password: 's3cr3t',
  clientRandom: 'aabb/ff00',
  customSni: 'sni.example.com',
  certificate: _chain,
  upStreamProtocol: UpStreamProtocol.http3,
  hasIpv6: false,
  antiDpi: true,
  antiDpiMode: 4,
  tlsProfile: 'firefox',
  ruExit: true,
  skipVerification: true,
  dnsUpStreams: ['tls://dns.example.com', '8.8.8.8'],
);

const _minimal = Endpoint(
  name: 'Server',
  hostName: 'www.example.org',
  addresses: ['198.51.100.7:443'],
  username: 'bob',
  password: 'pw',
  upStreamProtocol: UpStreamProtocol.http2,
  hasIpv6: true,
);

Endpoint _roundTrip(Endpoint endpoint) {
  final link = 'tt://?${const DeepLinkPayloadEncoder().convert(endpoint)}';
  // Printed for the cross-check against the official setup_wizard.
  // ignore: avoid_print
  print('LINK ${endpoint.hostName} $link');

  return const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert(link)).endpoint;
}

void main() {
  for (final endpoint in [_full, _minimal]) {
    test('round trip: ${endpoint.hostName}', () {
      final decoded = _roundTrip(endpoint);
      expect(decoded.name, endpoint.name);
      expect(decoded.hostName, endpoint.hostName);
      expect(decoded.addresses, endpoint.addresses);
      expect(decoded.username, endpoint.username);
      expect(decoded.password, endpoint.password);
      expect(decoded.clientRandom, endpoint.clientRandom);
      expect(decoded.customSni, endpoint.customSni);
      expect(decoded.certificate.trim(), endpoint.certificate.trim());
      expect(decoded.upStreamProtocol, endpoint.upStreamProtocol);
      expect(decoded.hasIpv6, endpoint.hasIpv6);
      expect(decoded.antiDpi, endpoint.antiDpi);
      expect(decoded.antiDpiMode, endpoint.antiDpiMode);
      expect(decoded.tlsProfile, endpoint.tlsProfile);
      expect(decoded.ruExit, endpoint.ruExit);
      expect(decoded.skipVerification, endpoint.skipVerification);
      expect(decoded.dnsUpStreams, endpoint.dnsUpStreams);
    });
  }

  test('ru_exit stays app-side: never in the config handed to the engine', () {
    final link = 'tt://?${const DeepLinkPayloadEncoder().convert(_full)}';
    final configuration = const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert(link));
    expect(configuration.endpoint.ruExit, isTrue);
    expect(const ConfigurationCodec().encode(configuration), isNot(contains('ru_exit')));
  });

  test('anti_dpi_mode: only the DPI2 techniques 1..3 reach the engine', () {
    String engineConfig({required bool antiDpi, required int mode}) {
      final link =
          'tt://?${const DeepLinkPayloadEncoder().convert(Endpoint(
            name: 'Server',
            hostName: 'www.example.org',
            addresses: const ['198.51.100.7:443'],
            username: 'bob',
            password: 'pw',
            upStreamProtocol: UpStreamProtocol.http2,
            hasIpv6: true,
            antiDpi: antiDpi,
            antiDpiMode: mode,
          ))}';

      return const ConfigurationCodec().encode(
        const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert(link)),
      );
    }

    expect(engineConfig(antiDpi: true, mode: 2), contains('anti_dpi_mode = 2'));
    // Auto is resolved by the app; the plain split and "off" write nothing.
    expect(engineConfig(antiDpi: true, mode: 4), isNot(contains('anti_dpi_mode')));
    expect(engineConfig(antiDpi: true, mode: 0), isNot(contains('anti_dpi_mode')));
    expect(engineConfig(antiDpi: false, mode: 3), isNot(contains('anti_dpi_mode')));
  });

  test('tls_profile: tag 0x42 reaches the engine; unknown values are dropped', () {
    String engineConfig(String profile) {
      final link =
          'tt://?${const DeepLinkPayloadEncoder().convert(Endpoint(
            name: 'Server',
            hostName: 'www.example.org',
            addresses: const ['198.51.100.7:443'],
            username: 'bob',
            password: 'pw',
            upStreamProtocol: UpStreamProtocol.http2,
            hasIpv6: true,
            tlsProfile: profile,
          ))}';

      return const ConfigurationCodec().encode(
        const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert(link)),
      );
    }

    expect(engineConfig('chrome'), contains('tls_profile = "chrome"'));
    expect(engineConfig('okhttp'), contains('tls_profile = "okhttp"'));
    // "No mimicry" profiles look like no browser at all - never written.
    expect(engineConfig('openssl'), isNot(contains('tls_profile')));
    expect(engineConfig(''), isNot(contains('tls_profile')));
  });

  test('anti_dpi_desync: tag 0x43 reaches the engine as mode 5; invalid strings are dropped', () {
    Configuration roundTrip(String desync, {bool antiDpi = true}) => const ConfigurationCodec().decode(
      const DeepLinkPayloadDecoder().convert(
        'tt://?${const DeepLinkPayloadEncoder().convert(Endpoint(
          name: 'Server',
          hostName: 'www.example.org',
          addresses: const ['198.51.100.7:443'],
          username: 'bob',
          password: 'pw',
          upStreamProtocol: UpStreamProtocol.http2,
          hasIpv6: true,
          antiDpi: antiDpi,
          antiDpiDesync: desync,
        ))}',
      ),
    );

    final custom = roundTrip('  -o1+s   -d3+s ');
    expect(custom.endpoint.antiDpiDesync, '-o1+s -d3+s');
    expect(custom.endpoint.antiDpiMode, 5);
    expect(const ConfigurationCodec().encode(custom), contains('anti_dpi_desync = "-o1+s -d3+s"'));
    expect(roundTrip('-o3').endpoint.antiDpiDesync, '');
    expect(roundTrip('-r1+s').endpoint.antiDpiDesync, '');
    expect(roundTrip('-d7', antiDpi: false).endpoint.antiDpiDesync, '');
    expect(const ConfigurationCodec().encode(roundTrip('-d7', antiDpi: false)), isNot(contains('anti_dpi_desync')));
  });

  test('h2_padding_frames: tag 0x44 reaches the engine; out of range is dropped', () {
    Configuration roundTrip(int frames) => const ConfigurationCodec().decode(
      const DeepLinkPayloadDecoder().convert(
        'tt://?${const DeepLinkPayloadEncoder().convert(Endpoint(
          name: 'Server',
          hostName: 'www.example.org',
          addresses: const ['198.51.100.7:443'],
          username: 'bob',
          password: 'pw',
          upStreamProtocol: UpStreamProtocol.http2,
          hasIpv6: true,
          h2PaddingFrames: frames,
        ))}',
      ),
    );

    expect(roundTrip(8).endpoint.h2PaddingFrames, 8);
    expect(const ConfigurationCodec().encode(roundTrip(8)), contains('h2_padding_frames = 8'));
    expect(roundTrip(500).endpoint.h2PaddingFrames, 64);
    expect(const ConfigurationCodec().encode(roundTrip(0)), isNot(contains('h2_padding_frames')));
  });

  test('block_quic: tag 0x45 reaches the engine; absent - off', () {
    Configuration roundTrip(bool blockQuic) => const ConfigurationCodec().decode(
      const DeepLinkPayloadDecoder().convert(
        'tt://?${const DeepLinkPayloadEncoder().convert(Endpoint(
          name: 'Server',
          hostName: 'www.example.org',
          addresses: const ['198.51.100.7:443'],
          username: 'bob',
          password: 'pw',
          upStreamProtocol: UpStreamProtocol.http2,
          hasIpv6: true,
          blockQuic: blockQuic,
        ))}',
      ),
    );

    expect(roundTrip(true).endpoint.blockQuic, isTrue);
    expect(const ConfigurationCodec().encode(roundTrip(true)), contains('block_quic = true'));
    expect(roundTrip(false).endpoint.blockQuic, isFalse);
    expect(const ConfigurationCodec().encode(roundTrip(false)), isNot(contains('block_quic')));
  });

  test('also takes tt://<payload> without the question mark', () {
    final payload = const DeepLinkPayloadEncoder().convert(_minimal);
    final decoded = const ConfigurationCodec().decode(const DeepLinkPayloadDecoder().convert('tt://$payload')).endpoint;
    expect(decoded.hostName, 'www.example.org');
  });

  test('rejects what the reference decoder rejects', () {
    const decoder = DeepLinkPayloadDecoder();
    expect(() => decoder.convert('https://example.com'), throwsFormatException);
    expect(() => decoder.convert('tt://?***'), throwsFormatException);
    // version 2
    expect(() => decoder.convert('tt://?AAEC'), throwsFormatException);
    // hostname only - no address/username/password
    expect(() => decoder.convert('tt://?AQFh'), throwsFormatException);
    // truncated: hostname claims 5 bytes, has 1
    expect(() => decoder.convert('tt://?AQVh'), throwsFormatException);
  });
}
