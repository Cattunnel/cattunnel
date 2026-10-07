import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/security/domain/leak_check.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';

/// Marsik's leak check: exit address through the selected server vs the
/// real one (see [LeakCheck]), DNS and IPv6 of the VPN network, plus a
/// button to a browser-based test for what the app can't see (DNS/WebRTC in
/// the browser).
class LeakCheckScreen extends StatefulWidget {
  const LeakCheckScreen({super.key});

  @override
  State<LeakCheckScreen> createState() => _LeakCheckScreenState();
}

class _LeakCheckScreenState extends State<LeakCheckScreen> {
  static final _browserTest = Uri.parse('https://ipleak.net/');

  bool _running = false;
  bool _noServer = false;
  TraceInfo? _exit;
  TraceInfo? _direct;
  VpnNetworkReport? _network;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final server = ServersScope.controllerOf(context, listen: false).selectedServer;
    if (server == null) {
      setState(() => _noServer = true);

      return;
    }

    final trustUserCas = SecuritySettings(context.dependencyFactory.sharedPreferences).trustUserCas;
    setState(() {
      _running = true;
      _noServer = false;
    });

    final (exit, direct, network) = await (
      LeakCheck.throughServer(server, trustUserCas: trustUserCas),
      LeakCheck.direct(),
      SecurityPlatform.vpnNetworkReport(),
    ).wait;
    if (!mounted) {
      return;
    }

    setState(() {
      _running = false;
      _exit = exit;
      _direct = direct;
      _network = network;
    });
  }

  String _verdict(BuildContext context) {
    final exit = _exit;
    if (exit == null) {
      return context.ln.leakVerdictFail;
    }
    if (_direct?.ip == exit.ip) {
      return context.ln.leakVerdictSame;
    }

    return context.ln.leakVerdictOk('${exit.flag} ${exit.country ?? '?'}'.trim(), exit.ip);
  }

  bool get _allGood => _exit != null && _direct?.ip != _exit?.ip && !(_network?.ipv6Leak ?? false);

  @override
  Widget build(BuildContext context) {
    final network = _network;
    final vpnActive = network?.vpnActive ?? false;

    return ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.leakCheck,
          leadingIconType: AppBarLeadingIconType.back,
          onBackPressed: () => Navigator.of(context).maybePop(),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Image.asset(
                _running || (_exit == null && _direct == null && !_noServer)
                    ? AssetImages.catMagnifier
                    : (_allGood ? AssetImages.catShield : AssetImages.catAlert),
                height: 110,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _noServer ? context.ln.leakNoServer : (_running ? context.ln.leakIntro : _verdict(context)),
              textAlign: TextAlign.center,
              style: context.textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            if (_running) const Center(child: CircularProgressIndicator()),
            if (!_running && !_noServer) ...[
              _row(context, context.ln.leakExitIp, _trace(_exit)),
              _row(context, context.ln.leakDirectIp, _trace(_direct)),
              _row(
                context,
                context.ln.leakVpnDns,
                vpnActive && network!.vpnDnsServers.isNotEmpty ? network.vpnDnsServers.join(', ') : context.ln.checkNeedVpn,
              ),
              _row(
                context,
                context.ln.checkIpv6,
                !vpnActive ? context.ln.checkNeedVpn : (network!.ipv6Leak ? context.ln.checkIpv6Leak : context.ln.checkIpv6Ok),
                warning: vpnActive && network!.ipv6Leak,
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _run, child: Text(context.ln.leakRunAgain)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => launchUrl(_browserTest, mode: LaunchMode.externalApplication),
              child: Text(context.ln.leakBrowserCheck),
            ),
            const SizedBox(height: 8),
            Text(
              context.ln.leakBrowserHint,
              textAlign: TextAlign.center,
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralLight),
            ),
          ],
        ),
      ),
    );
  }

  static String _trace(TraceInfo? info) => info == null ? '—' : '${info.flag} ${info.ip}'.trim();

  Widget _row(BuildContext context, String title, String value, {bool warning = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: Text(title, style: context.textTheme.bodyMedium)),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: context.textTheme.bodyMedium?.copyWith(
              color: warning ? context.colors.error : null,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
