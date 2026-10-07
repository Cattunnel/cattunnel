import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/feature/security/domain/desktop_ca_bundle.dart';

// Throwaway self-signed certs made with openssl for this test only.
const _russian = '''
-----BEGIN CERTIFICATE-----
MIICNTCCAdugAwIBAgIUTQD4ZbzGOR964yaoj2xIGqk4AK0wCgYIKoZIzj0EAwIw
cDELMAkGA1UEBhMCUlUxPzA9BgNVBAoMNlRoZSBNaW5pc3RyeSBvZiBEaWdpdGFs
IERldmVsb3BtZW50IGFuZCBDb21tdW5pY2F0aW9uczEgMB4GA1UEAwwXUnVzc2lh
biBUcnVzdGVkIFJvb3QgQ0EwHhcNMjYxMDAzMTc0OTE3WhcNMjYxMDA0MTc0OTE3
WjBwMQswCQYDVQQGEwJSVTE/MD0GA1UECgw2VGhlIE1pbmlzdHJ5IG9mIERpZ2l0
YWwgRGV2ZWxvcG1lbnQgYW5kIENvbW11bmljYXRpb25zMSAwHgYDVQQDDBdSdXNz
aWFuIFRydXN0ZWQgUm9vdCBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABKcv
JrApoiFKVlBO/VPMQCXhlfCQO6UykZf57Lxk9rxxIqjNQOgv0Ah+1z0F/Xak1MvT
36bki+mEiew6GkORUkOjUzBRMB0GA1UdDgQWBBTt9fjdAYmugp9YO8l96qVQ1Bn6
0TAfBgNVHSMEGDAWgBTt9fjdAYmugp9YO8l96qVQ1Bn60TAPBgNVHRMBAf8EBTAD
AQH/MAoGCCqGSM49BAMCA0gAMEUCIQC+rbCbdp+A0WRyHGU1l1wbF1KqvwUOBKB1
KKf12TTa8AIgWQdL2UTfbyFlmnFb8JkMnsw+wbiKakFs5hFbgktgK9M=
-----END CERTIFICATE-----
''';

const _plain = '''
-----BEGIN CERTIFICATE-----
MIIBiTCCAS+gAwIBAgIUKOz3wsZVDFzCocX6m1tRjnJObJAwCgYIKoZIzj0EAwIw
GjEYMBYGA1UEAwwPUGxhaW4gVGVzdCBSb290MB4XDTI2MTAwMzE3NDkxN1oXDTI2
MTAwNDE3NDkxN1owGjEYMBYGA1UEAwwPUGxhaW4gVGVzdCBSb290MFkwEwYHKoZI
zj0CAQYIKoZIzj0DAQcDQgAEfBAICYDaFhXTNS5GJf0TZFFtE69j0M7C38qdxYf4
LtgjmPISsAPPe3j0sUP5aSxDVMkyoHQ8PRZ2yzGecesFXaNTMFEwHQYDVR0OBBYE
FAIWvGHw5kEEOf5QfVPNk20r/h7WMB8GA1UdIwQYMBaAFAIWvGHw5kEEOf5QfVPN
k20r/h7WMA8GA1UdEwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIhANLQgLea
T08aDMAOTmplbvpB3ZOLLDPu883yu3jiHSaFAiBf1RBsGsoVN6rSbdTnGsyv9M4F
qgoXF663WBRX3VxANw==
-----END CERTIFICATE-----
''';

void main() {
  test("the Russian root is dropped, others kept, Let's Encrypt always present", () {
    final roots = DesktopCaBundle.derOfPem(_russian + _plain);
    expect(roots, hasLength(2));
    expect(DesktopCaBundle.isRussian(roots[0]), isTrue);
    expect(DesktopCaBundle.isRussian(roots[1]), isFalse);

    final bundle = DesktopCaBundle.derOfPem(DesktopCaBundle.bundleOf(roots));
    expect(bundle.where(DesktopCaBundle.isRussian), isEmpty);
    expect(bundle, hasLength(3)); // plain + ISRG X1 + X2
  });

  test('duplicates collapse (ISRG already in the system store)', () {
    final once = DesktopCaBundle.derOfPem(DesktopCaBundle.bundleOf(const []));
    final twice = DesktopCaBundle.derOfPem(DesktopCaBundle.bundleOf(once));
    expect(twice, hasLength(once.length));
  });

  test("this machine's bundle parses back and stays a sane size", () {
    final path = DesktopCaBundle.linuxBundles.firstWhere((p) => File(p).existsSync(), orElse: () => '');
    if (path.isEmpty) return;
    final pem = DesktopCaBundle.bundleOf(DesktopCaBundle.derOfPem(File(path).readAsStringSync()));
    expect(DesktopCaBundle.derOfPem(pem).length, greaterThan(50));
    expect(pem.length, lessThan(400 * 1024));
  }, testOn: 'linux');
}
