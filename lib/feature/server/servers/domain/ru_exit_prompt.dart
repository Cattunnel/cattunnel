import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/ru_lists/cidr_set.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// Before the first connect to a key the person added themselves (not from
/// a subscription - ours mark their Russian-exit keys, and the cascade,
/// which enters in Russia but exits abroad, isn't one): if its name or
/// address looks Russian, Marsik asks once whether it's a key for trips
/// abroad (ServerData.ruExit). Never switched on silently - on a key used
/// from Russia it would send the banks through the VPN.
abstract final class RuExitPrompt {
  static const _askedKeyPrefix = 'ru_exit_asked_';

  static final _ruName = RegExp(
    r'(^|[^\p{L}\p{N}])(россия|рф|ru|rus|russia|москва|мск|спб|питер)($|[^\p{L}\p{N}])',
    caseSensitive: false,
    unicode: true,
  );

  /// A whole-word Russian hint in a server name, or the Russian flag.
  static bool looksRussianName(String name) => name.contains('🇷🇺') || _ruName.hasMatch(name);

  /// [server] as it should be connected - with ruExit set if the person said
  /// so. Returns it unchanged when there's nothing to ask.
  static Future<Server> maybeAsk(BuildContext context, Server server) async {
    final data = server.serverData;
    final preferences = context.dependencyFactory.sharedPreferences;
    final askedKey = '$_askedKeyPrefix${server.id}';
    if (data.ruExit || data.subscriptionName != null || preferences.getBool(askedKey) == true) return server;

    final byName = looksRussianName(data.name);
    final byAddress = await _addressInRussia(context, data.ipAddress);
    if (!byName && !byAddress) return server;
    if (!context.mounted) return server;

    final yes = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => CustomAlertDialog(
        title: dialogContext.ln.ruExitPromptTitle,
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(AssetImages.catMagnifier, height: 96),
            const SizedBox(height: 12),
            Text(dialogContext.ln.ruExitPromptBody(data.name)),
          ],
        ),
        actionsBuilder: (_) => [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.ln.ruExitPromptNo)),
          if (byName && byAddress)
            FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.ln.ruExitPromptYes))
          else
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.ln.ruExitPromptYes)),
        ],
      ),
    );
    await preferences.setBool(askedKey, true);
    if (yes != true || !context.mounted) return server;

    final updated = data.copyWith(ruExit: true);
    await context.repositoryFactory.serverRepository.setNewServer(id: server.id, request: updated);
    if (context.mounted) ServersScope.controllerOf(context, listen: false).fetchServers();

    return server.copyWith(serverData: updated);
  }

  static Future<bool> _addressInRussia(BuildContext context, String ipAddress) async {
    var host = ipAddress.trim();
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      host = host.substring(1, end < 0 ? host.length : end);
    } else if (host.split(':').length == 2) {
      host = host.split(':').first;
    }
    final lists = await context.dependencyFactory.ruListsService.load();
    final cidrs = host.contains(':') ? lists.v6Cidrs : lists.v4Cidrs;
    if (InternetAddress.tryParse(host) != null) return cidrsContain(cidrs, host);

    try {
      final resolved = await InternetAddress.lookup(host).timeout(const Duration(seconds: 2));

      return resolved.any((a) => cidrsContain(a.type == InternetAddressType.IPv6 ? lists.v6Cidrs : lists.v4Cidrs, a.address));
    } on Object {
      return false;
    }
  }
}
