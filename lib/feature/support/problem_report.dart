import 'dart:io';

import 'package:adg_share/adg_share.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:vpn_plugin/vpn_plugin.dart';

/// "Report a problem": what an admin needs to understand why the VPN
/// doesn't work for someone - phone, Android, operator, network, app and
/// engine versions, the settings that change routing, the server (name and
/// address only) and the tail of the engine log - as text plus a .txt file
/// through the share sheet. Nothing is sent anywhere by the app itself (no
/// secrets in the code, works in any build); the person picks the chat.
///
/// Logins, passwords, age keys, tt:// links and subscription tokens are cut
/// out ([sanitize]); the person sees the summary before sharing.
abstract final class ProblemReport {
  static const _channel = MethodChannel('cattunnel/apps');
  static const _logLines = 300;

  /// Builds the report, shows the summary and opens the share sheet.
  /// [diagnosis]: Marsik's verdict, when opened from his dialog.
  static Future<void> share(BuildContext context, {String? diagnosis}) async {
    final (summary, full) = await _build(context, diagnosis: diagnosis);
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: dialogContext.ln.reportTitle,
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dialogContext.ln.reportDescription),
              const SizedBox(height: 12),
              SelectableText(summary, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
        ),
        actionsBuilder: (_) => [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(dialogContext.ln.cancel)),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(dialogContext.ln.share)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
    final file = File('${(await getTemporaryDirectory()).path}/cattunnel-report-$stamp.txt');
    await file.writeAsString(full);
    if (!context.mounted) return;
    await const AdgShare().share(
      ShareRequest(
        content: [
          ShareText(summary),
          ShareFile(path: file.path, mimeType: 'text/plain'),
        ],
        subject: context.ln.reportTitle,
        chooserTitle: context.ln.share,
      ),
    );
  }

  static Future<(String, String)> _build(BuildContext context, {String? diagnosis}) async {
    final repositories = context.repositoryFactory;
    final dependencies = context.dependencyFactory;
    final vpnState = VpnScope.vpnControllerOf(context, listen: false).state;
    final server = ServersScope.controllerOf(context, listen: false).selectedServer?.serverData;

    final package = await PackageInfo.fromPlatform();
    final device = await _deviceInfo();
    final ruEnabled = await _orNull(repositories.ruServicesSettingsRepository.isEnabled);
    final ruLists = await _orNull(dependencies.ruListsService.load);
    final splitMode = await _orNull(repositories.appSplitSettingsRepository.getMode);
    final splitApps = splitMode == null
        ? null
        : await _orNull(() => repositories.appSplitSettingsRepository.getApps(splitMode));
    final splitAuto = await _orNull(repositories.appSplitSettingsRepository.getAutoRuCn);
    final killSwitch = await _orNull(repositories.killSwitchSettingsRepository.isEnabled);
    final mtu = await _orNull(repositories.mtuSettingsRepository.getValue);
    final engineVersion = await _orNull(() => rootBundle.loadString('ENGINE_VERSION'));

    String? d(String key) => device[key]?.toString();
    final android = defaultTargetPlatform == TargetPlatform.android;
    final adapters = android ? null : await _orNull(_adapterNames);
    final now = DateTime.now();
    final lines = <String>[
      'CatTunnel ${package.version} (${package.buildNumber})${engineVersion == null ? '' : ', engine ${engineVersion.trim()}'}',
      if (android) ...[
        '${d('manufacturer') ?? '?'} ${d('model') ?? ''} (${d('device') ?? '?'}), Android ${d('android') ?? '?'} / API ${d('sdk') ?? '?'}',
        if (d('firmware') != null) 'Firmware: ${d('firmware')}, patch ${d('securityPatch') ?? '?'}, ${d('abi') ?? '?'}',
        'Operator: ${_or(d('operator'))} (${_or(d('operatorCode'))}), SIM: ${_or(d('simOperator'))} ${d('simCountry') ?? ''}'
            '${device['roaming'] == true ? ', ROAMING' : ''}',
        'Network: ${d('network') ?? '?'}, private DNS: ${d('privateDns') ?? '?'}'
            '${device['powerSave'] == true ? ', power saving ON' : ''}'
            '${device['batteryUnrestricted'] == false ? ', battery restricted' : ''}',
      ] else ...[
        '${defaultTargetPlatform.name} ${Platform.operatingSystemVersion}, ${Platform.numberOfProcessors} CPU',
        // Names only (no addresses): another VPN or a virtual switch here
        // explains a lot of "doesn't connect".
        'Adapters: ${adapters == null || adapters.isEmpty ? '?' : adapters.join(', ')}',
      ],
      'VPN: ${vpnState.name}${diagnosis == null ? '' : ', Marsik: $diagnosis'}',
      if (server != null)
        'Server: ${server.name} - ${server.domain} / ${server.ipAddress}, ${server.vpnProtocol.name}'
            '${server.antiDpi ? ', anti-DPI ${switch (server.antiDpiMode) {
                    ServerData.antiDpiAuto => 'auto',
                    ServerData.antiDpiCustom => '"${server.antiDpiDesync}"',
                    final mode => mode,
                  }}' : ''}${server.tlsProfile.isNotEmpty ? ', TLS ${server.tlsProfile}' : ''}${server.ruExit ? ', RUSSIAN EXIT' : ''}${(server.customSni ?? '').isNotEmpty ? ', custom SNI' : ''}'
            '${server.ipv6 ? ', IPv6' : ''}${server.subscriptionName == null ? '' : ', subscription "${server.subscriptionName}"'}',
      'Russian services bypass: ${_onOff(ruEnabled)}'
          '${ruLists == null || ruLists.updatedAt == null ? '' : ', lists ${ruLists.networkCount} nets from ${_date(ruLists.updatedAt!)}'}',
      'App split: ${splitMode?.name ?? '?'}${splitApps == null ? '' : ' (${splitApps.length})'}, auto RU/CN: ${_onOff(splitAuto)}',
      'Kill switch: ${_onOff(killSwitch)}, MTU: ${mtu ?? '?'}',
      'Time: ${now.toIso8601String().substring(0, 19)} ${now.timeZoneName}, ${Platform.localeName}',
    ];
    final summary = sanitize(lines.join('\n'));

    final log = await _engineLog(dependencies.vpnPlugin);
    final full = '$summary\n\n--- engine log, last $_logLines lines ---\n${sanitize(log)}\n';

    return (summary, full);
  }

  /// Up network adapters (not loopback), desktop only.
  static Future<List<String>> _adapterNames() async {
    final interfaces = await NetworkInterface.list();

    return interfaces.map((i) => i.name).toSet().toList();
  }

  static Future<Map<Object?, Object?>> _deviceInfo() async {
    if (defaultTargetPlatform != TargetPlatform.android) return const {};
    try {
      return await _channel.invokeMapMethod<Object?, Object?>('deviceInfo') ?? const {};
    } on Object {
      return const {};
    }
  }

  static Future<String> _engineLog(VpnPlugin vpnPlugin) async {
    try {
      final records = await vpnPlugin.exportLogsFor(await vpnPlugin.fetchLogsPath());
      final tail = records.length > _logLines ? records.sublist(records.length - _logLines) : records;

      return tail.map((r) => '${r.dateTime.toIso8601String()} ${r.level.name} ${r.message}').join('\n');
    } on Object catch (e) {
      return '(no engine log: $e)';
    }
  }

  /// Cuts out what must never leave the phone.
  @visibleForTesting
  static String sanitize(String text) => text
      .replaceAll(RegExp(r'AGE-SECRET-KEY-1[0-9A-Z]+'), 'AGE-SECRET-KEY-<cut>')
      .replaceAll(RegExp(r'tt://\S+'), 'tt://<cut>')
      .replaceAll(
        RegExp(
          r'''((?:password|passwd|username|user|login|token|secret|key)["']?\s*[:=]\s*["']?)[^\s"',}]+''',
          caseSensitive: false,
        ),
        r'$1<cut>',
      )
      .replaceAllMapped(
        RegExp(r'(https?://[^\s/]+)(/[^\s]*)'),
        (m) => '${m[1]}${m[2]!.length > 1 ? '/<path cut>' : ''}',
      );

  static Future<T?> _orNull<T>(Future<T> Function() read) async {
    try {
      return await read();
    } on Object {
      return null;
    }
  }

  static String _or(String? value) => value == null || value.isEmpty ? '-' : value;

  static String _onOff(bool? value) => value == null ? '?' : (value ? 'on' : 'off');

  static String _date(DateTime t) => '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
}
