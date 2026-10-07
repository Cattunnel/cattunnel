import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/feature/server/servers/widget/add_server_options_sheet.dart';
import 'package:trusttunnel/feature/server/servers/widget/import_link_dialog.dart';
import 'package:trusttunnel/feature/server/servers/widget/qr_scan_screen.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscriptions_screen.dart';

/// Shows [AddServerOptionsSheet] and dispatches to the chosen way of adding a
/// server. [pushServerDetails] is provided by the caller so each screen keeps
/// its own server-details navigation/ScaffoldMessenger wiring; this only
/// orchestrates which entry point (manual/QR/link/file) feeds it.
Future<void> presentAddServerFlow(
  BuildContext context, {
  required Future<void> Function({ServerData? preloadedData}) pushServerDetails,
}) async {
  final option = await AddServerOptionsSheet.show(context);

  if (option == null || !context.mounted) {
    return;
  }

  switch (option) {
    case AddServerOption.manual:
      await pushServerDetails();
    case AddServerOption.qrCode:
      final scanned = await context.push<Object>(
        QrScanScreen(repository: context.repositoryFactory.deepLinkRepository),
      );

      if (!context.mounted) {
        return;
      }

      switch (scanned) {
        case ServerData():
          await pushServerDetails(preloadedData: scanned);
        case SubscriptionData():
          await context.push(SubscriptionsScreen(imported: scanned));

          if (context.mounted) {
            ServersScope.controllerOf(context, listen: false).fetchServers();
          }
      }
    case AddServerOption.link:
      final server = await showDialog<ServerData>(
        context: context,
        builder: (_) => ImportLinkDialog(repository: context.repositoryFactory.deepLinkRepository),
      );

      if (server != null && context.mounted) {
        await pushServerDetails(preloadedData: server);
      }
    case AddServerOption.configFile:
      final server = await _pickConfigFile(context);

      if (server != null && context.mounted) {
        await pushServerDetails(preloadedData: server);
      }
    case AddServerOption.subscription:
      await context.push(const SubscriptionsScreen());

      if (context.mounted) {
        ServersScope.controllerOf(context, listen: false).fetchServers();
      }
  }
}

/// Lets the user pick a trusttunnel_client config (.toml) and parses it.
/// `null` if cancelled; on a file that isn't a config, says so and returns `null`.
Future<ServerData?> _pickConfigFile(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['toml', 'conf', 'txt'],
  );
  final path = result?.files.firstOrNull?.path;

  if (path == null || !context.mounted) {
    return null;
  }

  try {
    // A config with the Russian lists is ~150 KiB; anything much bigger isn't one.
    final file = File(path);
    if (await file.length() > 2 * 1024 * 1024) {
      throw const FormatException('too large');
    }
    final config = await file.readAsString();

    if (!context.mounted) {
      return null;
    }

    return context.repositoryFactory.deepLinkRepository.parseDataFromConfig(config: config);
  } on Object {
    if (context.mounted) {
      context.showInfoSnackBar(message: context.ln.importConfigFileInvalidError);
    }

    return null;
  }
}
