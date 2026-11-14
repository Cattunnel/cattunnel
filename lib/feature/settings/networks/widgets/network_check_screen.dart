import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/network_check.dart';
import 'package:trusttunnel/feature/vpn/widgets/connection_diagnosis_dialog.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

class NetworkCheckScreen extends StatefulWidget {
  const NetworkCheckScreen({super.key});
  @override
  State<NetworkCheckScreen> createState() => _NetworkCheckScreenState();
}

class _NetworkCheckScreenState extends State<NetworkCheckScreen> {
  NetworkCheck? _check;
  final _results = <NetworkCheckResult>[];
  bool _running = false;

  @override
  void dispose() {
    _check?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final vpn = VpnScope.vpnControllerOf(context, listen: false);
    if (vpn.state != VpnState.disconnected) {
      context.showInfoSnackBar(message: context.ln.networkCheckStopVpn);
      return;
    }
    final servers = ServersScope.controllerOf(
      context,
      listen: false,
    ).servers.where((s) => s.serverData.subscriptionId != null || s.serverData.subscriptionName != null).toList();
    if (servers.isEmpty) {
      context.showInfoSnackBar(message: context.ln.networkCheckNoServers);
      return;
    }
    final preferences = context.dependencyFactory.sharedPreferences;
    final diagnostics = ConnectionDiagnostics(
      subscriptionRepository: context.repositoryFactory.subscriptionRepository,
      serverRepository: context.repositoryFactory.serverRepository,
      trustUserCas: SecuritySettings(preferences).trustUserCas,
      preferences: preferences,
    );
    final check = NetworkCheck(
      diagnose: (server) => diagnostics.run(server, otherServers: const [], onStep: (_, _) {}),
    );
    _check = check;
    setState(() {
      _running = true;
      _results.clear();
    });
    try {
      await check.run(
        servers,
        onResult: (result) {
          if (mounted) setState(() => _results.add(result));
        },
      );
    } on Object {
      if (mounted) context.showInfoSnackBar(message: context.ln.networkCheckFailed);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(title: context.ln.networkCheckTitle),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.ln.networkCheckDescription),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _running ? () => _check?.cancel() : _start,
            child: Text(_running ? context.ln.cancel : context.ln.networkCheckTitle),
          ),
          if (_running) const LinearProgressIndicator(),
          for (final result in _results)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.server.serverData.name, style: Theme.of(context).textTheme.titleMedium),
                    if (result.frozen)
                      Text(context.ln.diagVerdictAddressFrozen)
                    else ...[
                      Text(
                        result.dnsMatches == true
                            ? context.ln.networkCheckDnsMatch
                            : result.dnsMatches == false
                            ? context.ln.networkCheckDnsDifferent
                            : context.ln.networkCheckDnsUnknown,
                      ),
                      for (final port in result.tcp.entries)
                        Text(
                          'TCP ${port.key}: ${port.value ? context.ln.networkCheckReachable : context.ln.networkCheckUnreachable}',
                        ),
                      if (result.diagnosis != null)
                        TextButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) => ConnectionDiagnosisDialog(
                              server: result.server,
                              otherServers: const [],
                              completedDiagnosis: result.diagnosis,
                            ),
                          ),
                          child: Text(context.ln.networkCheckDiagnosis),
                        ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
