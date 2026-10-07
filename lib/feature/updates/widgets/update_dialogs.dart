import 'dart:io';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/updates/domain/app_update.dart';
import 'package:trusttunnel/feature/updates/domain/update_platform.dart';
import 'package:trusttunnel/feature/updates/domain/update_service.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';

/// Marsik offers [update]; "Update" downloads and installs it.
Future<void> showUpdateOffer(BuildContext context, AppUpdate update) async {
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => CustomAlertDialog(
      title: dialogContext.ln.updateAvailableTitle(update.version),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AssetImages.catWave, height: 110),
          const SizedBox(height: 16),
          Text(dialogContext.ln.updateAvailableBody, textAlign: TextAlign.center),
          if (update.notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(update.notes, style: dialogContext.textTheme.bodyMedium),
          ],
        ],
      ),
      actionsBuilder: (spacing) => [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.ln.updateLater),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.ln.updateInstall),
        ),
      ],
    ),
  );
  if (accepted != true || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateInstallDialog(update: update),
  );
}

/// "Check for updates" in About: says so when there's nothing new.
Future<void> checkForUpdatesManually(BuildContext context) async {
  final AppUpdate? update;
  try {
    update = await UpdateService.check();
  } on Object {
    if (context.mounted) context.showInfoSnackBar(message: context.ln.updateCheckFailed);
    return;
  }
  if (!context.mounted) return;

  if (update == null) {
    context.showInfoSnackBar(message: context.ln.updateUpToDate);
  } else {
    await showUpdateOffer(context, update);
  }
}

enum _Stage { downloading, needPermission, downloadFailed, hashMismatch, untrusted }

class _UpdateInstallDialog extends StatefulWidget {
  final AppUpdate update;

  const _UpdateInstallDialog({required this.update});

  @override
  State<_UpdateInstallDialog> createState() => _UpdateInstallDialogState();
}

class _UpdateInstallDialogState extends State<_UpdateInstallDialog> {
  _Stage _stage = _Stage.downloading;
  double? _progress;
  File? _apk;
  AppUpdateApk? _apkInfo;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    try {
      _apkInfo = widget.update.apkFor(await UpdatePlatform.supportedAbis());
      if (_apkInfo == null) throw StateError('no APK for this phone');
      _apk = await UpdateService.download(
        _apkInfo!,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
    } on Object {
      _fail(_Stage.downloadFailed);
      return;
    }
    await _install();
  }

  Future<void> _install() async {
    if (!await UpdatePlatform.canInstall()) {
      if (mounted) setState(() => _stage = _Stage.needPermission);
      return;
    }

    final UpdateInstallResult result;
    try {
      if (Platform.isWindows && mounted) {
        // The installer replaces the files the tunnel runs from: take the
        // VPN down cleanly (routes, DNS) before it starts.
        await VpnScope.vpnControllerOf(context, listen: false).stop();
      }
      result = await UpdatePlatform.install(path: _apk!.path, sha256: _apkInfo!.sha256);
    } on Object {
      _fail(_Stage.downloadFailed);
      return;
    }
    if (!mounted) return;

    switch (result) {
      case UpdateInstallResult.ok:
        if (Platform.isWindows) exit(0);
        Navigator.of(context).pop();
      case UpdateInstallResult.hashMismatch:
        _fail(_Stage.hashMismatch);
      case UpdateInstallResult.untrusted:
        _fail(_Stage.untrusted);
      case UpdateInstallResult.noPermission:
        setState(() => _stage = _Stage.needPermission);
    }
  }

  void _fail(_Stage stage) {
    if (mounted) setState(() => _stage = stage);
  }

  bool get _failed => _stage == _Stage.downloadFailed || _stage == _Stage.hashMismatch || _stage == _Stage.untrusted;

  @override
  Widget build(BuildContext context) => CustomAlertDialog(
    title: context.ln.updateAvailableTitle(widget.update.version),
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(_failed ? AssetImages.catWires : AssetImages.catGear, height: 110),
        const SizedBox(height: 16),
        ...switch (_stage) {
          _Stage.downloading => [
            Text(context.ln.updateDownloading, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
          ],
          _Stage.needPermission => [Text(context.ln.updatePermissionBody, textAlign: TextAlign.center)],
          _Stage.downloadFailed => [Text(context.ln.updateDownloadFailed, textAlign: TextAlign.center)],
          _Stage.hashMismatch => [Text(context.ln.updateHashMismatch, textAlign: TextAlign.center)],
          _Stage.untrusted => [Text(context.ln.updateUntrusted, textAlign: TextAlign.center)],
        },
      ],
    ),
    actionsBuilder: (spacing) => switch (_stage) {
      _Stage.downloading => const [],
      _Stage.needPermission => [
        TextButton(
          onPressed: UpdatePlatform.openInstallPermission,
          child: Text(context.ln.updatePermissionAllow),
        ),
        TextButton(
          onPressed: _install,
          child: Text(context.ln.updateInstallRetry),
        ),
      ],
      _Stage.downloadFailed || _Stage.hashMismatch || _Stage.untrusted => [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.ln.updateClose),
        ),
      ],
    },
  );
}
