import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/deep_link_payload_codec.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/endpoint.dart';

const _deepLinkScheme = 'tt';

abstract class DeepLinkManager {
  Future<Configuration> getConfigurationByBase64({
    required String base64,
  });

  /// Builds a shareable `tt://` link encoding [endpoint], for exporting a
  /// server the app already knows about (e.g. via QR code or copy/share).
  String buildLink({required Endpoint endpoint});
}

class DeepLinkManagerImpl implements DeepLinkManager {
  DeepLinkManagerImpl()
    : _codec = const ConfigurationCodec(),
      _payloadEncoder = const DeepLinkPayloadEncoder();

  final ConfigurationCodec _codec;
  final DeepLinkPayloadEncoder _payloadEncoder;

  @override
  Future<Configuration> getConfigurationByBase64({required String base64}) async {
    // Our decoder on every platform: the engine's native one (IDeepLink on
    // Android) drops CatTunnel's tags 0x40..0x45 - Russian exit, anti-DPI
    // technique and string, TLS fingerprint, HTTP/2 padding.
    final result = const DeepLinkPayloadDecoder().convert(base64);
    final decodeResult = _codec.decode(result);

    return decodeResult;
  }

  @override
  String buildLink({required Endpoint endpoint}) =>
      Uri(scheme: _deepLinkScheme, host: '', query: _payloadEncoder.convert(endpoint)).toString();
}
