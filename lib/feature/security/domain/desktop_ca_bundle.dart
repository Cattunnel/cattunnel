import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// The endpoint CA bundle on Windows and Linux: the system roots minus the
/// Russian Ministry of Digital Development ones - what SecurityChannel.kt
/// builds on Android. Without it the engine verifies against the whole
/// system store, and the Gosuslugi installer puts the Russian Trusted Root
/// CA into the Windows one: whoever holds it could forge the endpoint
/// certificate and read the tunnel.
abstract final class DesktopCaBundle {
  /// Same markers as SecurityChannel.kt. Matched in the DER, which carries
  /// subject and issuer names as plain ASCII.
  static const russianMarkers = ['Russian Trusted Root CA', 'Russian Trusted Sub CA'];

  /// Distro bundles: Debian/Ubuntu, Arch, Fedora, Alpine/others.
  static const linuxBundles = [
    '/etc/ssl/certs/ca-certificates.crt',
    '/etc/ca-certificates/extracted/tls-ca-bundle.pem',
    '/etc/pki/tls/certs/ca-bundle.crt',
    '/etc/ssl/cert.pem',
  ];

  /// PEM bundle, or null when the system store can't be read (the engine then
  /// keeps its own default).
  static String? build() {
    try {
      if (Platform.isWindows) return bundleOf(_windowsRoots());
      if (Platform.isLinux) {
        for (final path in linuxBundles) {
          final file = File(path);
          if (file.existsSync()) return bundleOf(derOfPem(file.readAsStringSync()));
        }
      }
    } on Object {
      // Unreadable store: leave the engine on its default.
    }

    return null;
  }

  /// [roots] minus the Russian ones, plus Let's Encrypt's roots: Windows
  /// fetches missing roots on demand, so its store may not hold the one our
  /// servers chain to yet.
  static String bundleOf(Iterable<Uint8List> roots) {
    final out = StringBuffer();
    final seen = <String>{};
    for (final der in [...roots, ...derOfPem(_isrgRoots)]) {
      final key = base64.encode(der);
      if (isRussian(der) || !seen.add(key)) continue;
      out.write('-----BEGIN CERTIFICATE-----\n');
      for (var i = 0; i < key.length; i += 64) {
        out.write('${key.substring(i, i + 64 > key.length ? key.length : i + 64)}\n');
      }
      out.write('-----END CERTIFICATE-----\n');
    }

    return out.toString();
  }

  static bool isRussian(Uint8List der) {
    final text = latin1.decode(der, allowInvalid: true);

    return russianMarkers.any(text.contains);
  }

  static List<Uint8List> derOfPem(String pem) => [
    for (final match in RegExp(r'-----BEGIN CERTIFICATE-----([^-]+)-----END CERTIFICATE-----').allMatches(pem))
      base64.decode(match.group(1)!.replaceAll(RegExp(r'\s'), '')),
  ];

  /// The current user's ROOT store (it includes the machine's roots).
  static List<Uint8List> _windowsRoots() {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final open = crypt32
        .lookupFunction<Pointer<Void> Function(IntPtr, Pointer<Utf16>), Pointer<Void> Function(int, Pointer<Utf16>)>(
          'CertOpenSystemStoreW',
        );
    final next = crypt32
        .lookupFunction<
          Pointer<_CertContext> Function(Pointer<Void>, Pointer<_CertContext>),
          Pointer<_CertContext> Function(Pointer<Void>, Pointer<_CertContext>)
        >('CertEnumCertificatesInStore');
    final close = crypt32.lookupFunction<Int32 Function(Pointer<Void>, Uint32), int Function(Pointer<Void>, int)>(
      'CertCloseStore',
    );

    final name = 'ROOT'.toNativeUtf16();
    final store = open(0, name);
    calloc.free(name);
    if (store == nullptr) return const [];

    final roots = <Uint8List>[];
    try {
      // Each call frees the previous context.
      for (var cert = next(store, nullptr); cert != nullptr; cert = next(store, cert)) {
        roots.add(Uint8List.fromList(cert.ref.pbCertEncoded.asTypedList(cert.ref.cbCertEncoded)));
      }
    } finally {
      close(store, 0);
    }

    return roots;
  }

  static const _isrgRoots = '''
-----BEGIN CERTIFICATE-----
MIIFazCCA1OgAwIBAgIRAIIQz7DSQONZRGPgu2OCiwAwDQYJKoZIhvcNAQELBQAw
TzELMAkGA1UEBhMCVVMxKTAnBgNVBAoTIEludGVybmV0IFNlY3VyaXR5IFJlc2Vh
cmNoIEdyb3VwMRUwEwYDVQQDEwxJU1JHIFJvb3QgWDEwHhcNMTUwNjA0MTEwNDM4
WhcNMzUwNjA0MTEwNDM4WjBPMQswCQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJu
ZXQgU2VjdXJpdHkgUmVzZWFyY2ggR3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBY
MTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAK3oJHP0FDfzm54rVygc
h77ct984kIxuPOZXoHj3dcKi/vVqbvYATyjb3miGbESTtrFj/RQSa78f0uoxmyF+
0TM8ukj13Xnfs7j/EvEhmkvBioZxaUpmZmyPfjxwv60pIgbz5MDmgK7iS4+3mX6U
A5/TR5d8mUgjU+g4rk8Kb4Mu0UlXjIB0ttov0DiNewNwIRt18jA8+o+u3dpjq+sW
T8KOEUt+zwvo/7V3LvSye0rgTBIlDHCNAymg4VMk7BPZ7hm/ELNKjD+Jo2FR3qyH
B5T0Y3HsLuJvW5iB4YlcNHlsdu87kGJ55tukmi8mxdAQ4Q7e2RCOFvu396j3x+UC
B5iPNgiV5+I3lg02dZ77DnKxHZu8A/lJBdiB3QW0KtZB6awBdpUKD9jf1b0SHzUv
KBds0pjBqAlkd25HN7rOrFleaJ1/ctaJxQZBKT5ZPt0m9STJEadao0xAH0ahmbWn
OlFuhjuefXKnEgV4We0+UXgVCwOPjdAvBbI+e0ocS3MFEvzG6uBQE3xDk3SzynTn
jh8BCNAw1FtxNrQHusEwMFxIt4I7mKZ9YIqioymCzLq9gwQbooMDQaHWBfEbwrbw
qHyGO0aoSCqI3Haadr8faqU9GY/rOPNk3sgrDQoo//fb4hVC1CLQJ13hef4Y53CI
rU7m2Ys6xt0nUW7/vGT1M0NPAgMBAAGjQjBAMA4GA1UdDwEB/wQEAwIBBjAPBgNV
HRMBAf8EBTADAQH/MB0GA1UdDgQWBBR5tFnme7bl5AFzgAiIyBpY9umbbjANBgkq
hkiG9w0BAQsFAAOCAgEAVR9YqbyyqFDQDLHYGmkgJykIrGF1XIpu+ILlaS/V9lZL
ubhzEFnTIZd+50xx+7LSYK05qAvqFyFWhfFQDlnrzuBZ6brJFe+GnY+EgPbk6ZGQ
3BebYhtF8GaV0nxvwuo77x/Py9auJ/GpsMiu/X1+mvoiBOv/2X/qkSsisRcOj/KK
NFtY2PwByVS5uCbMiogziUwthDyC3+6WVwW6LLv3xLfHTjuCvjHIInNzktHCgKQ5
ORAzI4JMPJ+GslWYHb4phowim57iaztXOoJwTdwJx4nLCgdNbOhdjsnvzqvHu7Ur
TkXWStAmzOVyyghqpZXjFaH3pO3JLF+l+/+sKAIuvtd7u+Nxe5AW0wdeRlN8NwdC
jNPElpzVmbUq4JUagEiuTDkHzsxHpFKVK7q4+63SM1N95R1NbdWhscdCb+ZAJzVc
oyi3B43njTOQ5yOf+1CceWxG1bQVs5ZufpsMljq4Ui0/1lvh+wjChP4kqKOJ2qxq
4RgqsahDYVvTH9w7jXbyLeiNdd8XM2w9U/t7y0Ff/9yi0GE44Za4rF2LN9d11TPA
mRGunUHBcnWEvgJBQl9nJEiU0Zsnvgc/ubhPgXRR4Xq37Z0j4r7g1SgEEzwxA57d
emyPxgcYxn/eR44/KJ4EBs+lVDR3veyJm+kXQ99b21/+jh5Xos1AnX5iItreGCc=
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
MIICGzCCAaGgAwIBAgIQQdKd0XLq7qeAwSxs6S+HUjAKBggqhkjOPQQDAzBPMQsw
CQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJuZXQgU2VjdXJpdHkgUmVzZWFyY2gg
R3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBYMjAeFw0yMDA5MDQwMDAwMDBaFw00
MDA5MTcxNjAwMDBaME8xCzAJBgNVBAYTAlVTMSkwJwYDVQQKEyBJbnRlcm5ldCBT
ZWN1cml0eSBSZXNlYXJjaCBHcm91cDEVMBMGA1UEAxMMSVNSRyBSb290IFgyMHYw
EAYHKoZIzj0CAQYFK4EEACIDYgAEzZvVn4CDCuwJSvMWSj5cz3es3mcFDR0HttwW
+1qLFNvicWDEukWVEYmO6gbf9yoWHKS5xcUy4APgHoIYOIvXRdgKam7mAHf7AlF9
ItgKbppbd9/w+kHsOdx1ymgHDB/qo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0T
AQH/BAUwAwEB/zAdBgNVHQ4EFgQUfEKWrt5LSDv6kviejM9ti6lyN5UwCgYIKoZI
zj0EAwMDaAAwZQIwe3lORlCEwkSHRhtFcP9Ymd70/aTSVaYgLXTWNLxBo1BfASdW
tL4ndQavEi51mI38AjEAi/V3bNTIZargCyzuFJ0nN6T5U6VR5CmD1/iQMVtCnwr1
/q4AaOeMSQ+2b1tbFfLn
-----END CERTIFICATE-----
''';
}

/// CERT_CONTEXT (wincrypt.h).
final class _CertContext extends Struct {
  @Uint32()
  external int dwCertEncodingType;

  external Pointer<Uint8> pbCertEncoded;

  @Uint32()
  external int cbCertEncoded;

  external Pointer<Void> pCertInfo;

  external Pointer<Void> hCertStore;
}
