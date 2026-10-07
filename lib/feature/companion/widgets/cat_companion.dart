import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// Cat shown in the servers screen's app bar: purely a live VPN-state
/// indicator (sleeping/working/shielded), no interaction of its own -
/// petting lives in [CatPettingButton]/[CatPettingDialog] instead.
class CatCompanion extends StatelessWidget {
  const CatCompanion({super.key});

  static String assetFor(VpnState state) => switch (state) {
    VpnState.connected => AssetImages.catShield,
    VpnState.connecting ||
    VpnState.recovering ||
    VpnState.waitingForRecovery ||
    VpnState.waitingForNetwork => AssetImages.catGear,
    VpnState.disconnected => AssetImages.catSleeping,
  };

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(VpnScope.vpnControllerOf(context).state);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Image.asset(asset, key: ValueKey(asset), height: 36),
    );
  }
}
