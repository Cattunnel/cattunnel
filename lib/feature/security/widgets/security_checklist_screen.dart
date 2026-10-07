import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

enum _CheckStatus { ok, warning, info }

class _CheckItem {
  final String title;
  final String details;
  final _CheckStatus status;
  final SecuritySettingsTarget? fix;

  const _CheckItem(this.title, this.details, this.status, [this.fix]);
}

/// Marsik looks the phone over: CAs (Russian Ministry root first), screen
/// lock, Private DNS, USB debugging, battery limits, IPv6 leak, always-on
/// VPN. Each finding comes with a "Fix" button into the right Settings page.
class SecurityChecklistScreen extends StatefulWidget {
  const SecurityChecklistScreen({super.key});

  @override
  State<SecurityChecklistScreen> createState() => _SecurityChecklistScreenState();
}

class _SecurityChecklistScreenState extends State<SecurityChecklistScreen> with WidgetsBindingObserver {
  List<_CheckItem>? _items;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from a "Fix" trip to Settings - look again.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _run();
    }
  }

  Future<void> _run() async {
    final trustUserCas = SecuritySettings(context.dependencyFactory.sharedPreferences).trustUserCas;
    final (certs, device, network) = await (
      SecurityPlatform.certificateReport(),
      SecurityPlatform.deviceReport(),
      SecurityPlatform.vpnNetworkReport(),
    ).wait;
    if (!mounted) {
      return;
    }

    final ln = context.ln;
    final russian = certs.any((c) => c.russianTrusted);
    final otherUserCas = certs.where((c) => c.userInstalled && !c.russianTrusted).length;

    setState(() {
      _items = [
        _CheckItem(
          ln.checkRussianCa,
          !russian ? ln.checkRussianCaNone : (trustUserCas ? ln.checkRussianCaExposed : ln.checkRussianCaProtected),
          !russian ? _CheckStatus.ok : _CheckStatus.warning,
          russian ? SecuritySettingsTarget.security : null,
        ),
        _CheckItem(
          ln.checkUserCas,
          otherUserCas == 0 ? ln.checkUserCasNone : ln.checkUserCasFound(otherUserCas),
          otherUserCas == 0 ? _CheckStatus.ok : _CheckStatus.warning,
          otherUserCas == 0 ? null : SecuritySettingsTarget.security,
        ),
        if (device != null) ...[
          _CheckItem(
            ln.checkScreenLock,
            device.deviceSecure ? ln.checkScreenLockOk : ln.checkScreenLockMissing,
            device.deviceSecure ? _CheckStatus.ok : _CheckStatus.warning,
            device.deviceSecure ? null : SecuritySettingsTarget.lock,
          ),
          _CheckItem(
            ln.checkPrivateDns,
            device.customPrivateDns ? ln.checkPrivateDnsCustom(device.privateDnsHost ?? '?') : ln.checkPrivateDnsOk,
            device.customPrivateDns ? _CheckStatus.warning : _CheckStatus.ok,
            device.customPrivateDns ? SecuritySettingsTarget.network : null,
          ),
          _CheckItem(
            ln.checkAdb,
            device.adbEnabled ? ln.checkAdbOn : ln.checkAdbOk,
            device.adbEnabled ? _CheckStatus.warning : _CheckStatus.ok,
            device.adbEnabled ? SecuritySettingsTarget.developer : null,
          ),
          _CheckItem(
            ln.checkBattery,
            device.batteryOptimizationIgnored ? ln.checkBatteryOk : ln.checkBatteryLimited,
            device.batteryOptimizationIgnored ? _CheckStatus.ok : _CheckStatus.warning,
            device.batteryOptimizationIgnored ? null : SecuritySettingsTarget.battery,
          ),
        ],
        _CheckItem(
          ln.checkIpv6,
          network == null || !network.vpnActive
              ? ln.checkNeedVpn
              : (network.ipv6Leak ? ln.checkIpv6Leak : ln.checkIpv6Ok),
          network == null || !network.vpnActive
              ? _CheckStatus.info
              : (network.ipv6Leak ? _CheckStatus.warning : _CheckStatus.ok),
        ),
        _CheckItem(ln.checkAlwaysOn, ln.checkAlwaysOnInfo, _CheckStatus.info, SecuritySettingsTarget.vpn),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final warnings = items?.where((i) => i.status == _CheckStatus.warning).length ?? 0;

    return ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.phoneChecklist,
          leadingIconType: AppBarLeadingIconType.back,
          onBackPressed: () => Navigator.of(context).maybePop(),
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            Center(
              child: Image.asset(
                items == null ? AssetImages.catMagnifier : (warnings == 0 ? AssetImages.catShield : AssetImages.catAlert),
                height: 110,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                items == null ? context.ln.checklistIntro : (warnings == 0 ? context.ln.checkOk : '⚠ $warnings'),
                style: context.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (items == null)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final item in items) _CheckTile(item: item),
          ],
        ),
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  final _CheckItem item;

  const _CheckTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (item.status) {
      _CheckStatus.ok => (Icons.check_circle_rounded, const Color(0xFF2E9E5B)),
      _CheckStatus.warning => (Icons.warning_amber_rounded, context.colors.error),
      _CheckStatus.info => (Icons.info_outline_rounded, context.colors.accent),
    };
    final fix = item.fix;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: context.textTheme.bodyLarge),
                Text(item.details, style: context.textTheme.bodyMedium?.copyWith(color: context.colors.neutralLight)),
                if (fix != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => SecurityPlatform.openSettings(fix),
                      child: Text(context.ln.checkFix),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
