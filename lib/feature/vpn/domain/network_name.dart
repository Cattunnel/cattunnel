import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/localization/generated/l10n.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';

/// The name of the network in the person's language: what they called it,
/// or an automatic one (the kind of the network and a short piece of the
/// key, so that two networks do not look alike in the report).
String networkName(AppLocalizations ln, SharedPreferences preferences, NetworkFingerprint fingerprint) =>
    networkNameByKey(ln, preferences, fingerprint.key, fingerprint.kind);

/// The name of a network the app knows by its key alone.
String networkNameByKey(AppLocalizations ln, SharedPreferences preferences, String key, String kind) {
  final custom = NetworkFingerprint.customName(preferences, key);
  if (custom != null) return custom;

  // A mobile network is named after its operator: that is what the person
  // sees in the status bar, and the gateway there changes with the city.
  if (kind == 'mobile') {
    final operator = NetworkFingerprint.operatorNameOf(preferences, key);

    return operator ?? networkKindName(ln, kind);
  }

  final kindName = networkKindName(ln, kind);
  // The key of a network with a fingerprint is a hash; without one it is
  // the kind itself, and there is nothing to tell it apart with.
  final short = key.length > 4 ? key.substring(0, 4) : '';

  return short.isEmpty ? kindName : '$kindName $short';
}

/// The name of the kind of the network.
String networkKindName(AppLocalizations ln, String kind) => switch (kind) {
  'wifi' => ln.networkKindWifi,
  'mobile' => ln.networkKindMobile,
  'ethernet' => ln.networkKindEthernet,
  _ => ln.networkKindOther,
};
