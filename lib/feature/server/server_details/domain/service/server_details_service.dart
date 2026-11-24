import 'package:trusttunnel/common/error/model/enum/presentation_field_exception_code.dart';
import 'package:trusttunnel/common/error/model/enum/presentation_field_name.dart';
import 'package:trusttunnel/common/error/model/presentation_field.dart';
import 'package:trusttunnel/common/utils/validation_utils.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:vpn_plugin/domain/cattail_settings.dart';
import 'package:vpn_plugin/domain/configuration_codec.dart';
import 'package:vpn_plugin/domain/desync_string.dart';
import 'package:vpn_plugin/domain/rotation_addresses.dart';

abstract class ServerDetailsService {
  List<PresentationField> validateData({
    required ServerData data,
    Set<String> otherServersNames = const {},
  });

  String fallbackDuplicateNames(String baseName, Set<String> otherNames);

  /// The manually added server that [incoming] is a new version of, if any.
  ///
  /// Same account on the same server = same domain, login and password.
  /// Re-importing a link after the server's port or address changed should
  /// then update that entry instead of adding a «Name 2» duplicate.
  /// Subscription-managed servers are never matched - their sync owns them.
  Server? findServerToReplace(ServerData incoming, List<Server> servers);
}

class ServerDetailsServiceImpl implements ServerDetailsService {
  @override
  List<PresentationField> validateData({
    required ServerData data,
    Set<String> otherServersNames = const {},
  }) {
    final List<PresentationField> fields = [];

    _addIfNotNull(
      fields,
      _validateServerName(
        data.name,
        otherServersNames,
      ),
    );

    _addIfNotNull(
      fields,
      _validateAntiDpiDesync(data),
    );

    _addIfNotNull(
      fields,
      _validateServerAddress(
        data.ipAddress,
      ),
    );

    _addIfNotNull(
      fields,
      _validateDomain(
        data.domain,
      ),
    );

    _addIfNotNull(
      fields,
      _validateSni(
        data.customSni,
      ),
    );

    _addIfNotNull(
      fields,
      _validateUsername(
        data.username,
      ),
    );

    _addIfNotNull(
      fields,
      _validatePassword(
        data.password,
      ),
    );

    _addIfNotNull(
      fields,
      _validateDnsServers(
        data.dnsServers,
      ),
    );

    // The TLS auth key: empty, or at least 16 bytes of even-length hex.
    final authKey = data.tlsAuthKey.trim();
    if (authKey.isNotEmpty && !ConfigurationCodecKeys.isValidAuthKey(authKey)) {
      _addIfNotNull(fields, _getFieldWrongValue(PresentationFieldName.tlsAuthKey));
    }

    final rotationPort = RotationAddresses.portOf(data.ipAddress);
    if (data.rotationEnabled &&
        (data.rotationAddresses.isEmpty ||
            data.rotationAddresses.length > RotationAddresses.maxCount ||
            data.rotationAddresses.any((entry) => RotationAddresses.parseEntry(entry, rotationPort) == null))) {
      fields.add(_getFieldWrongValue(PresentationFieldName.rotationAddresses));
    }

    // A term bound is 0 (the session lifetime) or 60..86400 s, and the lower one is not above the upper.
    bool termOk(int secs) => secs == 0 || (secs >= RotationAddresses.minSecs && secs <= RotationAddresses.maxSecs);
    if (data.rotationEnabled &&
        (!termOk(data.rotationMinSecs) ||
            !termOk(data.rotationMaxSecs) ||
            (data.rotationMinSecs > 0 && data.rotationMaxSecs > 0 && data.rotationMinSecs > data.rotationMaxSecs))) {
      fields.add(_getFieldWrongValue(PresentationFieldName.rotationTerm));
    }

    // CatTail needs its ports and key to dial.
    if (data.cattailEnabled &&
        (CattailSettings.normalizePorts(data.cattailPorts) == null ||
            !CattailSettings.isValidKey(data.cattailKey.trim()) ||
            CattailSettings.normalizePattern(data.cattailPattern) == null)) {
      fields.add(_getFieldWrongValue(PresentationFieldName.cattail));
    }

    _addIfNotNull(
      fields,
      _validateExpertSettings(data),
    );

    return fields;
  }

  /// The numbers of the expert settings: the engine clamps them, but a value
  /// out of range means the person typed something wrong, and the save must
  /// stop before the engine gets it.
  PresentationField? _validateExpertSettings(ServerData data) {
    var outOfRange = data.h2PaddingFrames < 0 || data.h2PaddingFrames > ConfigurationCodecKeys.h2PaddingFramesMax;

    if (data.h2PaddingFrames > 0) {
      outOfRange =
          outOfRange ||
          data.h2PaddingFramesMin < 0 ||
          data.h2PaddingFramesMin > ConfigurationCodecKeys.h2PaddingFramesMinMax;
      outOfRange =
          outOfRange || data.h2PaddingMinBytes < 0 || data.h2PaddingMinBytes > ConfigurationCodecKeys.h2PaddingBytesMax;
      outOfRange =
          outOfRange || data.h2PaddingMaxBytes < 0 || data.h2PaddingMaxBytes > ConfigurationCodecKeys.h2PaddingBytesMax;
      outOfRange =
          outOfRange ||
          data.h2PaddingStreamBytes < 0 ||
          data.h2PaddingStreamBytes > ConfigurationCodecKeys.h2PaddingBytesBudgetMax;
      outOfRange =
          outOfRange ||
          data.h2PaddingSessionBytes < 0 ||
          data.h2PaddingSessionBytes > ConfigurationCodecKeys.h2PaddingBytesBudgetMax;
    }

    outOfRange =
        outOfRange ||
        data.keepaliveIntervalSecs < 0 ||
        data.keepaliveIntervalSecs > ConfigurationCodecKeys.keepaliveIntervalSecsMax;
    outOfRange =
        outOfRange ||
        data.sessionLifetimeSecs < 0 ||
        data.sessionLifetimeSecs > ConfigurationCodecKeys.sessionLifetimeSecsMax;

    if (outOfRange) {
      return _getFieldOutOfBounds(PresentationFieldName.expertSettings);
    }

    // The XHTTP path is a path: the engine refuses a prefix without a slash.
    if (data.xhttpEnabled && data.xhttpPath.isNotEmpty && !data.xhttpPath.startsWith('/')) {
      return _getFieldWrongValue(PresentationFieldName.expertSettings);
    }

    return null;
  }

  @override
  String fallbackDuplicateNames(String baseName, Set<String> otherNames) {
    final duplicateCandidates = otherNames.where((e) => e.startsWith(baseName));

    for (int i = 1; i < duplicateCandidates.length + 1; i++) {
      final candidate = '$baseName ${i + 1}';
      if (!duplicateCandidates.contains(candidate)) {
        return candidate;
      }
    }

    return baseName;
  }

  @override
  Server? findServerToReplace(ServerData incoming, List<Server> servers) {
    final domain = incoming.domain.trim().toLowerCase();
    if (domain.isEmpty || incoming.username.isEmpty || incoming.password.isEmpty) {
      return null;
    }

    for (final server in servers) {
      final existing = server.serverData;
      if (existing.subscriptionName != null) {
        continue;
      }

      if (existing.domain.trim().toLowerCase() == domain &&
          existing.username == incoming.username &&
          existing.password == incoming.password) {
        return server;
      }
    }

    return null;
  }

  PresentationField? _validateServerName(
    String serverName,
    Set<String> otherServerNames,
  ) {
    final fieldName = PresentationFieldName.serverName;
    final normalizedName = serverName.trim();

    if (normalizedName.isEmpty) {
      return _getRequiredField(fieldName);
    }

    final normalizedOtherNames = otherServerNames.map((e) => e.trim().toLowerCase()).toSet();

    if (normalizedOtherNames.contains(normalizedName.toLowerCase())) {
      return _getAlreadyExistsField(fieldName);
    }

    return null;
  }

  PresentationField? _validateServerAddress(String value) {
    final normalizedValue = value.trim();
    if (normalizedValue.isEmpty) {
      return _getRequiredField(PresentationFieldName.ipAddress);
    }

    final valid = ValidationUtils.validateServerAddress(normalizedValue);

    return valid ? null : _getFieldWrongValue(PresentationFieldName.ipAddress);
  }

  PresentationField? _validateSni(String? sni) {
    if (sni?.trim().isEmpty ?? true) {
      return null;
    }

    sni = sni!.trim();

    final valid = ValidationUtils.tryParseDomain(sni) != null;

    if (!valid) {
      return _getFieldWrongValue(PresentationFieldName.sni);
    }

    return null;
  }

  PresentationField? _validateDnsServers(List<String> dnsServers) {
    final fieldName = PresentationFieldName.dnsServers;

    if (dnsServers.join().trim().isEmpty) {
      return null;
    }

    for (var dnsServer in dnsServers) {
      dnsServer = dnsServer.trim();

      if (dnsServer.isEmpty) {
        return _getFieldWrongValue(fieldName);
      }

      // 1. DNS stamp
      if (dnsServer.startsWith('sdns://')) {
        if (!ValidationUtils.validateDnsStamp(dnsServer)) {
          return _getFieldWrongValue(fieldName);
        }
        continue;
      }

      // 2. URI-based DNS
      if (RegExp(r'^(tls:\/\/|https:\/\/|http:\/\/|quic:\/\/|h3:\/\/)').hasMatch(dnsServer)) {
        final parsedUri = Uri.tryParse(dnsServer);
        if (parsedUri == null || parsedUri.host.isEmpty) {
          return _getFieldWrongValue(fieldName);
        }

        dnsServer = parsedUri.host + (parsedUri.hasPort ? ':${parsedUri.port}' : '');
      }

      // 3. host[:port] / ip[:port]
      String? port;
      final divided = dnsServer.split(':');

      if (dnsServer.startsWith('[')) {
        port = divided.removeLast();
        dnsServer = divided.join(':').replaceAll(RegExp(r'[\[\]]'), '');
      } else if (divided.length == 2) {
        port = divided.last;
        dnsServer = divided.first;
      }

      final parsedPort = int.tryParse(port ?? '');
      if (port != null && parsedPort == null) {
        return _getFieldWrongValue(fieldName);
      }

      if (parsedPort != null && (parsedPort < 1 || parsedPort > 65535)) {
        return _getFieldWrongValue(fieldName);
      }

      if (!ValidationUtils.validateIpAddress(dnsServer, allowPort: false) &&
          ValidationUtils.tryParseDomain(dnsServer) == null) {
        return _getFieldWrongValue(fieldName);
      }
    }

    return null;
  }

  PresentationField? _validateDomain(String domain) {
    final fieldName = PresentationFieldName.domain;
    final normalizedDomain = domain.trim();

    if (normalizedDomain.isEmpty) {
      return _getRequiredField(fieldName);
    }

    final valid =
        ValidationUtils.validateIpAddress(normalizedDomain, allowPort: false) ||
        ValidationUtils.parseServerHost(normalizedDomain) != null;

    return valid ? null : _getFieldWrongValue(fieldName);
  }

  PresentationField? _validateUsername(String username) {
    final fieldName = PresentationFieldName.userName;
    if (username.trim().isEmpty) {
      return _getRequiredField(fieldName);
    }

    return null;
  }

  PresentationField? _validatePassword(String password) {
    final fieldName = PresentationFieldName.password;
    if (password.isEmpty) {
      return _getRequiredField(fieldName);
    }

    return null;
  }

  /// The custom split must be there and parse when it is the chosen mode;
  /// otherwise the engine would reject the key (or the mode would fall back
  /// to the basic split without telling anyone).
  PresentationField? _validateAntiDpiDesync(ServerData data) {
    if (!data.antiDpi || data.antiDpiMode != ServerData.antiDpiCustom) {
      return null;
    }
    if (data.antiDpiDesync.trim().isEmpty) {
      return _getRequiredField(PresentationFieldName.antiDpiDesync);
    }

    return DesyncString.validate(data.antiDpiDesync) == null
        ? null
        : _getFieldWrongValue(PresentationFieldName.antiDpiDesync);
  }

  void _addIfNotNull(
    List<PresentationField> fields,
    PresentationField? field,
  ) {
    if (field != null) {
      fields.add(field);
    }
  }

  PresentationField _getRequiredField(PresentationFieldName fieldName) => PresentationField(
    code: PresentationFieldExceptionCode.fieldRequired,
    fieldName: fieldName,
  );

  PresentationField _getAlreadyExistsField(PresentationFieldName fieldName) => PresentationField(
    code: PresentationFieldExceptionCode.alreadyExists,
    fieldName: fieldName,
  );

  PresentationField _getFieldWrongValue(PresentationFieldName fieldName) => PresentationField(
    code: PresentationFieldExceptionCode.fieldWrongValue,
    fieldName: fieldName,
  );

  PresentationField _getFieldOutOfBounds(PresentationFieldName fieldName) => PresentationField(
    code: PresentationFieldExceptionCode.outOfBounds,
    fieldName: fieldName,
  );
}
