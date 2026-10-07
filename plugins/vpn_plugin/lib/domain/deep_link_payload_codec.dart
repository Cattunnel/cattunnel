// deep_link_payload_codec.dart
//
// Encoder for the TrustTunnel shareable deep-link payload.
//
// This is a different wire format from [ConfigurationCodec]'s INI-like text:
// it's the compact binary TLV (tag-length-value) format used inside a
// `tt://?<payload>` link, matching the reference implementation published on
// the official TrustTunnel website's offline QR-code generator page. Tags and
// lengths use QUIC-style variable-length integers (RFC 9000 §16): the two
// high bits of the first byte select a 1/2/4/8-byte encoding, the remaining
// bits (plus any following bytes) hold the value, big-endian.
//
// Decoding on Android/iOS/macOS goes through the native `DeepLink.decode`
// (see [DeepLinkManager]). Windows and Linux have no native decoder, so
// [DeepLinkPayloadDecoder] does the same in Dart, following the reference
// implementation (TrustTunnel `deeplink` crate v1.0.33, decode.rs/cert.rs,
// and TrustTunnelClient's deeplink-ffi, which wraps it for the native side).

import 'dart:convert';

import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/desync_string.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/ini_document.dart';
import 'package:vpn_plugin/models/upstream_protocol.dart';

abstract final class _DeepLinkPayloadTag {
  static const version = 0x00;
  static const hostname = 0x01;
  static const address = 0x02;
  static const customSni = 0x03;
  static const hasIpv6 = 0x04;
  static const username = 0x05;
  static const password = 0x06;
  static const skipVerification = 0x07;
  static const certificate = 0x08;
  static const upstreamProtocol = 0x09;
  static const antiDpi = 0x0A;
  static const clientRandomPrefix = 0x0B;
  static const name = 0x0C;
  static const dnsUpstreams = 0x0D;

  /// CatTunnel: Russian-exit key. Far from the upstream range, so a future
  /// upstream tag can't collide; the upstream decoder skips unknown tags.
  static const ruExit = 0x40;

  /// CatTunnel: anti-DPI technique, one byte: 1..3 or 4 = auto (see
  /// Endpoint.antiDpiMode). Absent - the app keeps its own pick.
  static const antiDpiMode = 0x41;

  /// CatTunnel: ClientHello fingerprint, UTF-8 (chrome, firefox, safari,
  /// okhttp; see Endpoint.tlsProfile). Absent - the app keeps its own pick.
  static const tlsProfile = 0x42;

  /// CatTunnel: custom anti-DPI split, UTF-8 byedpi syntax (see
  /// Endpoint.antiDpiDesync); the app shows it as mode 5. An invalid string
  /// is dropped. Absent - the app keeps its own pick.
  static const antiDpiDesync = 0x43;

  /// CatTunnel: HTTP/2 padding, one byte: frames to pad, 1..64 (see
  /// Endpoint.h2PaddingFrames). Absent - the app keeps its own pick.
  static const h2PaddingFrames = 0x44;

  /// CatTunnel: refuse QUIC (UDP 443), bool (see Endpoint.blockQuic).
  /// Absent - the app keeps its own pick.
  static const blockQuic = 0x45;
}

const _payloadVersion = 0x01;

/// {@template deep_link_payload_encoder}
/// Encodes an [Endpoint] into the base64url TLV payload used by `tt://` links.
///
/// The returned string is the payload only (no `tt://?` prefix), so callers
/// can build either a full URI or an embeddable QR value as needed.
/// {@endtemplate}
final class DeepLinkPayloadEncoder extends Converter<Endpoint, String> {
  const DeepLinkPayloadEncoder();

  @override
  String convert(Endpoint input) {
    final chunks = <List<int>>[
      _tlv(_DeepLinkPayloadTag.version, [_payloadVersion]),
      if (input.name.isNotEmpty) _tlvString(_DeepLinkPayloadTag.name, input.name),
      _tlvString(_DeepLinkPayloadTag.hostname, input.hostName),
      for (final address in input.addresses) _tlvString(_DeepLinkPayloadTag.address, address),
      _tlvString(_DeepLinkPayloadTag.username, input.username),
      _tlvString(_DeepLinkPayloadTag.password, input.password),
      _tlv(_DeepLinkPayloadTag.upstreamProtocol, [_upstreamProtocolByte(input.upStreamProtocol)]),
      if (input.customSni.isNotEmpty) _tlvString(_DeepLinkPayloadTag.customSni, input.customSni),
      if (input.clientRandom.isNotEmpty) _tlvString(_DeepLinkPayloadTag.clientRandomPrefix, input.clientRandom),
      if (!input.hasIpv6) _tlvBool(_DeepLinkPayloadTag.hasIpv6, false),
      if (input.antiDpi) _tlvBool(_DeepLinkPayloadTag.antiDpi, true),
      if (input.ruExit) _tlvBool(_DeepLinkPayloadTag.ruExit, true),
      if (input.antiDpi && input.antiDpiMode >= 1 && input.antiDpiMode <= 4)
        _tlv(_DeepLinkPayloadTag.antiDpiMode, [input.antiDpiMode]),
      if (input.tlsProfile.isNotEmpty) _tlvString(_DeepLinkPayloadTag.tlsProfile, input.tlsProfile),
      if (input.antiDpi && input.antiDpiDesync.isNotEmpty && DesyncString.validate(input.antiDpiDesync) == null)
        _tlvString(_DeepLinkPayloadTag.antiDpiDesync, DesyncString.normalize(input.antiDpiDesync)),
      if (input.h2PaddingFrames > 0)
        _tlv(_DeepLinkPayloadTag.h2PaddingFrames, [
          input.h2PaddingFrames.clamp(1, ConfigurationCodecKeys.h2PaddingFramesMax),
        ]),
      if (input.blockQuic) _tlvBool(_DeepLinkPayloadTag.blockQuic, true),
      if (input.skipVerification) _tlvBool(_DeepLinkPayloadTag.skipVerification, true),
      if (input.certificate.isNotEmpty) _tlv(_DeepLinkPayloadTag.certificate, _pemToDer(input.certificate)),
      if (input.dnsUpStreams.isNotEmpty)
        _tlv(_DeepLinkPayloadTag.dnsUpstreams, _encodeStringSequence(input.dnsUpStreams)),
    ];

    return base64Url.encode(chunks.expand((chunk) => chunk).toList()).replaceAll('=', '');
  }

  int _upstreamProtocolByte(UpStreamProtocol protocol) => switch (protocol) {
    UpStreamProtocol.http2 => 0x01,
    UpStreamProtocol.http3 => 0x02,
  };

  List<int> _encodeStringSequence(List<String> values) => [
    for (final value in values) ...[
      ..._writeVarint(utf8.encode(value).length),
      ...utf8.encode(value),
    ],
  ];

  /// Decodes one or more concatenated PEM `CERTIFICATE` blocks into their
  /// raw DER bytes, concatenated — matching the reference encoder.
  List<int> _pemToDer(String pem) {
    final der = <int>[];
    final buffer = StringBuffer();
    var inBlock = false;

    for (final rawLine in pem.split('\n')) {
      final line = rawLine.trim();

      if (line == '-----BEGIN CERTIFICATE-----') {
        inBlock = true;
        buffer.clear();
        continue;
      }

      if (line == '-----END CERTIFICATE-----') {
        inBlock = false;
        if (buffer.isNotEmpty) {
          der.addAll(base64.decode(buffer.toString()));
        }
        continue;
      }

      if (inBlock && line.isNotEmpty) {
        buffer.write(line);
      }
    }

    return der;
  }

  List<int> _tlvString(int tag, String value) => _tlv(tag, utf8.encode(value));

  List<int> _tlvBool(int tag, bool value) => _tlv(tag, [value ? 0x01 : 0x00]);

  List<int> _tlv(int tag, List<int> value) => [
    ..._writeVarint(tag),
    ..._writeVarint(value.length),
    ...value,
  ];

  List<int> _writeVarint(int value) {
    if (value <= 0x3f) {
      return [value];
    }

    if (value <= 0x3fff) {
      return [(value >> 8) | 0x40, value & 0xff];
    }

    if (value <= 0x3fffffff) {
      return [(value >> 24) | 0x80, (value >> 16) & 0xff, (value >> 8) & 0xff, value & 0xff];
    }

    throw ArgumentError.value(value, 'value', 'Varint value too large to encode');
  }
}

/// {@template deep_link_payload_decoder}
/// Decodes a `tt://?<payload>` (or `tt://<payload>`) link into the same
/// `[endpoint]` configuration text the native `DeepLink.decode` returns, so
/// [ConfigurationDecoder] fills in every other setting the same way on all
/// platforms.
///
/// Throws [FormatException] on anything the reference decoder rejects:
/// another scheme, bad base64, a truncated TLV, a newer payload version,
/// invalid UTF-8/booleans/protocol, a non-hex client random prefix, or a
/// missing hostname/address/username/password.
/// {@endtemplate}
final class DeepLinkPayloadDecoder extends Converter<String, String> {
  const DeepLinkPayloadDecoder();

  @override
  String convert(String input) {
    const prefix = 'tt://';
    final uri = input.trim();
    if (!uri.startsWith(prefix)) {
      throw const FormatException('Not a tt:// link');
    }
    final encoded = uri.substring(prefix.length).replaceFirst(RegExp(r'^\?'), '');

    final List<int> payload;
    try {
      payload = base64Url.decode(base64Url.normalize(encoded));
    } on FormatException {
      throw const FormatException('tt:// link: invalid base64');
    }

    String? hostname;
    String? username;
    String? password;
    String? name;
    var customSni = '';
    var clientRandom = '';
    var hasIpv6 = true;
    var skipVerification = false;
    var antiDpi = false;
    var ruExit = false;
    var antiDpiMode = 0;
    var tlsProfile = '';
    var antiDpiDesync = '';
    var h2PaddingFrames = 0;
    var blockQuic = false;
    var protocol = UpStreamProtocol.http2;
    var certificate = '';
    final addresses = <String>[];
    var dnsUpstreams = <String>[];

    var offset = 0;
    while (offset < payload.length) {
      final (tag, afterTag) = _readVarint(payload, offset);
      final (length, afterLength) = _readVarint(payload, afterTag);
      if (afterLength + length > payload.length) {
        throw FormatException('tt:// link: truncated field $tag');
      }
      final value = payload.sublist(afterLength, afterLength + length);
      offset = afterLength + length;

      switch (tag) {
        case _DeepLinkPayloadTag.version:
          final (version, _) = _readVarint(value, 0);
          if (version > _payloadVersion) {
            throw FormatException('tt:// link: unsupported version $version');
          }
        case _DeepLinkPayloadTag.hostname:
          hostname = _string(value);
        case _DeepLinkPayloadTag.address:
          addresses.add(_string(value));
        case _DeepLinkPayloadTag.customSni:
          customSni = _string(value);
        case _DeepLinkPayloadTag.hasIpv6:
          hasIpv6 = _bool(value);
        case _DeepLinkPayloadTag.username:
          username = _string(value);
        case _DeepLinkPayloadTag.password:
          password = _string(value);
        case _DeepLinkPayloadTag.skipVerification:
          skipVerification = _bool(value);
        case _DeepLinkPayloadTag.certificate:
          certificate = _derToPem(value);
        case _DeepLinkPayloadTag.upstreamProtocol:
          protocol = switch (value) {
            [0x01] => UpStreamProtocol.http2,
            [0x02] => UpStreamProtocol.http3,
            _ => throw const FormatException('tt:// link: invalid upstream protocol'),
          };
        case _DeepLinkPayloadTag.antiDpi:
          antiDpi = _bool(value);
        case _DeepLinkPayloadTag.ruExit:
          ruExit = _bool(value);
        case _DeepLinkPayloadTag.antiDpiMode:
          // An unknown value from a newer generator: keep the app's pick.
          antiDpiMode = value.length == 1 && value[0] >= 1 && value[0] <= 4 ? value[0] : 0;
        case _DeepLinkPayloadTag.tlsProfile:
          // Unknown values (a newer generator) leave the app's pick alone.
          final profile = _string(value);
          tlsProfile = ConfigurationCodecKeys.tlsProfiles.contains(profile) ? profile : '';
        case _DeepLinkPayloadTag.antiDpiDesync:
          final desync = DesyncString.normalize(_string(value));
          antiDpiDesync = DesyncString.validate(desync) == null ? desync : '';
        case _DeepLinkPayloadTag.h2PaddingFrames:
          h2PaddingFrames = value.length == 1 && value[0] <= ConfigurationCodecKeys.h2PaddingFramesMax ? value[0] : 0;
        case _DeepLinkPayloadTag.blockQuic:
          blockQuic = _bool(value);
        case _DeepLinkPayloadTag.clientRandomPrefix:
          clientRandom = _string(value);
          final hexPattern = RegExp(r'^([0-9a-fA-F]{2})*$');
          final parts = clientRandom.split('/');
          if (parts.length > 2 || !parts.every(hexPattern.hasMatch)) {
            throw const FormatException('tt:// link: client random prefix must be hex');
          }
        case _DeepLinkPayloadTag.name:
          name = _string(value);
        case _DeepLinkPayloadTag.dnsUpstreams:
          dnsUpstreams = _stringSequence(value);
        default:
          // Unknown tags from a newer generator are skipped, like the reference.
          break;
      }
    }

    if (hostname == null) throw const FormatException('tt:// link: no hostname');
    if (addresses.isEmpty) throw const FormatException('tt:// link: no address');
    if (username == null) throw const FormatException('tt:// link: no username');
    if (password == null) throw const FormatException('tt:// link: no password');

    final document = IniDocument();
    final endpoint =
        document.section('endpoint')
          ..setString('hostname', hostname)
          ..setStringList('addresses', addresses)
          ..setBool('has_ipv6', hasIpv6)
          ..setString('username', username)
          ..setString('password', password)
          ..setString('client_random', clientRandom)
          ..setBool('skip_verification', skipVerification)
          ..setMultilinePem('certificate', certificate)
          ..setString('upstream_protocol', protocol.value)
          ..setBool('anti_dpi', antiDpi)
          ..setBool('ru_exit', ruExit)
          ..setInt('anti_dpi_mode', antiDpiMode)
          ..setString('tls_profile', tlsProfile)
          ..setString('anti_dpi_desync', antiDpiDesync)
          ..setInt('h2_padding_frames', h2PaddingFrames)
          ..setBool('block_quic', blockQuic)
          ..setString('custom_sni', customSni)
          ..setStringList('dns_upstreams', dnsUpstreams);
    if (name != null) {
      // ConfigurationDecoder un-escapes the name (JSON string rules).
      final escaped = jsonEncode(name);
      endpoint.setString('name', escaped.substring(1, escaped.length - 1));
    }

    return document.toString();
  }

  static String _string(List<int> value) {
    try {
      return utf8.decode(value);
    } on FormatException {
      throw const FormatException('tt:// link: invalid UTF-8');
    }
  }

  static bool _bool(List<int> value) => switch (value) {
    [0x00] => false,
    [0x01] => true,
    _ => throw const FormatException('tt:// link: invalid boolean'),
  };

  static List<String> _stringSequence(List<int> data) {
    final result = <String>[];
    var offset = 0;
    while (offset < data.length) {
      final (length, start) = _readVarint(data, offset);
      if (start + length > data.length) {
        throw const FormatException('tt:// link: truncated list entry');
      }
      result.add(_string(data.sublist(start, start + length)));
      offset = start + length;
    }

    return result;
  }

  /// QUIC-style varint (see the encoder): returns the value and the offset
  /// right after it.
  static (int, int) _readVarint(List<int> data, int offset) {
    if (offset >= data.length) {
      throw const FormatException('tt:// link: truncated varint');
    }
    final length = 1 << (data[offset] >> 6);
    if (offset + length > data.length) {
      throw const FormatException('tt:// link: truncated varint');
    }
    var value = data[offset] & 0x3f;
    for (var i = 1; i < length; i++) {
      value = (value << 8) | data[offset + i];
    }

    return (value, offset + length);
  }

  /// Concatenated DER certificates (the link's form) back to PEM blocks, as
  /// the reference `der_to_pem` does: split on the outer ASN.1 SEQUENCEs,
  /// base64 in 64-character lines.
  static String _derToPem(List<int> der) {
    final blocks = <String>[];
    var offset = 0;
    while (offset < der.length) {
      if (der[offset] != 0x30 || offset + 1 >= der.length) {
        throw const FormatException('tt:// link: invalid certificate');
      }
      var bodyLength = der[offset + 1];
      var headerEnd = offset + 2;
      if (bodyLength >= 0x80) {
        final count = bodyLength & 0x7f;
        if (count == 0 || headerEnd + count > der.length) {
          throw const FormatException('tt:// link: invalid certificate');
        }
        bodyLength = 0;
        for (var i = 0; i < count; i++) {
          bodyLength = (bodyLength << 8) | der[headerEnd + i];
        }
        headerEnd += count;
      }
      final end = headerEnd + bodyLength;
      if (end > der.length) {
        throw const FormatException('tt:// link: truncated certificate');
      }

      final b64 = base64.encode(der.sublist(offset, end));
      final lines = [
        for (var i = 0; i < b64.length; i += 64) b64.substring(i, i + 64 > b64.length ? b64.length : i + 64),
      ];
      blocks.add('-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----');
      offset = end;
    }

    return blocks.isEmpty ? '' : '${blocks.join('\n')}\n';
  }
}
