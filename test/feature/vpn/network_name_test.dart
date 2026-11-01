import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/localization/generated/l10n.dart';
import 'package:trusttunnel/feature/vpn/domain/network_name.dart';

void main() {
  test('the automatic name of a network has no minus from the hash', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final ln = await AppLocalizations.load(const Locale('en'));

    // S22 01.11: "Wi-Fi -6a0".
    expect(networkNameByKey(ln, preferences, '-6a0f3c2b1d', 'wifi'), 'Wi-Fi 6a0f');
    expect(networkNameByKey(ln, preferences, '60d2aa91', 'wifi'), 'Wi-Fi 60d2');
    // No fingerprint: the key is the kind, nothing to add.
    expect(networkNameByKey(ln, preferences, 'ethernet', 'ethernet'), ln.networkKindEthernet);
  });
}
