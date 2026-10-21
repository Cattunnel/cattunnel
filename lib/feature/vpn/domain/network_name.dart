import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';

/// The name of the network in the person's language: what they called it,
/// or an automatic one (the kind of the network and a short piece of the
/// key, so that two networks do not look alike in the report).
String networkName(BuildContext context, SharedPreferences preferences, NetworkFingerprint fingerprint) =>
    networkNameByKey(context, preferences, fingerprint.key, fingerprint.kind);

/// The name of a network the app knows by its key alone.
String networkNameByKey(BuildContext context, SharedPreferences preferences, String key, String kind) {
  final custom = NetworkFingerprint.customName(preferences, key);
  if (custom != null) return custom;

  final kindName = networkKindName(context, kind);
  // The key of a network with a fingerprint is a hash; without one it is
  // the kind itself, and there is nothing to tell it apart with.
  final short = key.length > 4 ? key.substring(0, 4) : '';

  return short.isEmpty ? kindName : '$kindName $short';
}

/// The name of the kind of the network.
String networkKindName(BuildContext context, String kind) => switch (kind) {
  'wifi' => context.ln.networkKindWifi,
  'mobile' => context.ln.networkKindMobile,
  'ethernet' => context.ln.networkKindEthernet,
  _ => context.ln.networkKindOther,
};
