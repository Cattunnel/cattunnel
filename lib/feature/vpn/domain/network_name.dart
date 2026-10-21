import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';

/// The name of the network in the person's language: what they called it,
/// or an automatic one (the kind of the network and a short piece of the
/// key, so that two networks do not look alike in the report).
String networkName(BuildContext context, SharedPreferences preferences, NetworkFingerprint fingerprint) {
  final custom = NetworkFingerprint.customName(preferences, fingerprint.key);
  if (custom != null) return custom;

  return '${networkKindName(context, fingerprint.kind)} ${fingerprint.shortId}';
}

/// The name of the kind of the network.
String networkKindName(BuildContext context, String kind) => switch (kind) {
  'wifi' => context.ln.networkKindWifi,
  'mobile' => context.ln.networkKindMobile,
  'ethernet' => context.ln.networkKindEthernet,
  _ => context.ln.networkKindOther,
};
