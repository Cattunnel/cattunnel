import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';
import 'package:trusttunnel/feature/vpn/domain/network_name.dart';
import 'package:trusttunnel/feature/vpn/domain/networks_memory.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// The networks the app knows something about.
///
/// The app remembers two things about a network: that the plain connection
/// does not work there, and which technique worked there. Both are facts
/// about the network, and the person may want to see them, to rename a
/// network, or to make the app forget it.
///
/// The gateway and the DNS servers are not on this screen: they stay on
/// the phone.
class NetworksScreen extends StatefulWidget {
  const NetworksScreen({super.key});

  @override
  State<NetworksScreen> createState() => _NetworksScreenState();
}

class _NetworksScreenState extends State<NetworksScreen> {
  List<RememberedNetwork> _networks = const [];

  @override
  void initState() {
    super.initState();

    unawaited(_load());
  }

  Future<void> _load() async {
    final networks = NetworksMemory.all(context.dependencyFactory.sharedPreferences);
    if (!mounted) return;
    setState(() => _networks = networks);
  }

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(title: context.ln.networksTitle),
      body: ListView(
        children: [
          if (_networks.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(context.ln.networksEmpty, textAlign: TextAlign.center),
            )
          else
            for (final network in _networks)
              _NetworkTile(
                network: network,
                onRename: () => _rename(network),
                onForget: () => _forget(network),
              ),
          if (_networks.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: _forgetAll,
                child: Text(context.ln.networksForgetAll),
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Future<void> _rename(RememberedNetwork network) async {
    final preferences = context.dependencyFactory.sharedPreferences;
    final field = TextEditingController(text: network.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: dialogContext.ln.diagNetworkRenameTitle,
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: InputDecoration(hintText: dialogContext.ln.diagNetworkRenameHint),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actionsBuilder: (_) => [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(dialogContext.ln.cancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(field.text),
            child: Text(dialogContext.ln.diagNetworkRenameSave),
          ),
        ],
      ),
    );
    field.dispose();
    if (name == null) return;
    await NetworkFingerprint.rename(preferences, network.key, name);
    await _load();
  }

  Future<void> _forget(RememberedNetwork network) async {
    final preferences = context.dependencyFactory.sharedPreferences;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: dialogContext.ln.networksForgetTitle,
        content: Text(dialogContext.ln.networksForgetDescription),
        actionsBuilder: (_) => [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.ln.cancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.ln.networksForget),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NetworksMemory.forget(preferences, network.key);
    await _load();
  }

  Future<void> _forgetAll() async {
    final preferences = context.dependencyFactory.sharedPreferences;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: dialogContext.ln.networksForgetAllTitle,
        content: Text(dialogContext.ln.networksForgetAllDescription),
        actionsBuilder: (_) => [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.ln.cancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(dialogContext.ln.networksForgetAll),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await NetworksMemory.forgetAll(preferences);
    await _load();
  }
}

/// One network: the name, what the app knows about it and the two actions.
class _NetworkTile extends StatelessWidget {
  final RememberedNetwork network;
  final VoidCallback onRename;
  final VoidCallback onForget;

  const _NetworkTile({
    required this.network,
    required this.onRename,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final preferences = context.dependencyFactory.sharedPreferences;

    return ListTile(
      title: Text(networkNameByKey(context.ln, preferences, network.key, network.kind)),
      subtitle: Text(_facts(context)),
      trailing: PopupMenuButton<String>(
        onSelected: (action) => switch (action) {
          'rename' => onRename(),
          _ => onForget(),
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'rename', child: Text(context.ln.networksRename)),
          PopupMenuItem(value: 'forget', child: Text(context.ln.networksForget)),
        ],
      ),
    );
  }

  /// What the app knows about the network, in a line or two.
  String _facts(BuildContext context) {
    final facts = <String>[];
    final until = network.directFailsUntil;
    if (until != null) {
      facts.add(context.ln.networksDirectUntil(_date(until)));
    }
    if (network.modes.length == 1) {
      facts.add(context.ln.networksMode(network.modes.first.toString()));
    } else if (network.modes.isNotEmpty) {
      facts.add(context.ln.networksModes(network.modes.join(', ')));
    }
    if (facts.isEmpty) {
      return networkKindName(context.ln, network.kind);
    }

    return facts.join('\n');
  }

  static String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}';
}
