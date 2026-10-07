import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/datasources/app_split_settings_datasource.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/auto_bypass_apps.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/installed_apps_platform.dart';
import 'package:trusttunnel/widgets/common/custom_checkbox_list_tile.dart';
import 'package:trusttunnel/widgets/common/custom_radio_list_tile.dart';
import 'package:trusttunnel/widgets/common/custom_switch_tile.dart';
import 'package:trusttunnel/widgets/common/scaffold_messenger_provider.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/discard_changes_dialog.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// Per-app split tunneling (Android): all apps through the VPN, the picked
/// ones around it, or only the picked ones through it. Each mode keeps its
/// own list. Russian apps always bypass the VPN (ticked and locked; they
/// can't be picked for "only selected through the VPN" either). Chinese/
/// vendor, Uzbek apps and local tools bypass it automatically while "Auto"
/// is on - ticked, and unticking one puts it back into the VPN. Recomputed
/// on every connect.
class AppSplitScreen extends StatefulWidget {
  const AppSplitScreen({super.key});

  @override
  State<AppSplitScreen> createState() => _AppSplitScreenState();
}

class _AppSplitScreenState extends State<AppSplitScreen> {
  final Map<AppSplitMode, Set<String>> _initialApps = {};
  final Map<AppSplitMode, Set<String>> _apps = {};
  final Map<String, Future<Uint8List?>> _icons = {};

  AppSplitMode _initialMode = AppSplitMode.off;
  AppSplitMode _mode = AppSplitMode.off;
  bool _initialAuto = true;
  bool _auto = true;
  AutoBypassApps _autoApps = AutoBypassApps.empty;
  Set<String> _initialForced = const {};
  Set<String> _forced = {};
  List<InstalledApp> _installed = const [];
  bool _loading = true;
  bool _showSystem = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ruLists = context.dependencyFactory.ruListsService;
    final repository = context.repositoryFactory.appSplitSettingsRepository;
    final mode = await repository.getMode();
    final auto = await repository.getAutoRuCn();
    final excluded = await repository.getApps(AppSplitMode.exclude);
    final included = await repository.getApps(AppSplitMode.include);
    final forced = await repository.getForcedVpn();
    List<InstalledApp> installed;
    try {
      installed = await InstalledAppsPlatform.list();
    } on Object {
      installed = const [];
    }
    final autoApps = await autoBypassApps(ruLists, installed: installed);
    if (!mounted) return;

    setState(() {
      _initialMode = _mode = mode;
      _initialAuto = _auto = auto;
      _initialForced = forced.toSet();
      _forced = forced.toSet();
      _initialApps[AppSplitMode.exclude] = excluded.toSet();
      _initialApps[AppSplitMode.include] = included.toSet();
      _apps[AppSplitMode.exclude] = excluded.toSet();
      _apps[AppSplitMode.include] = included.toSet();
      _installed = installed;
      _autoApps = autoApps;
      _loading = false;
    });

    // Fresh community lists (no-op if recent) - may add auto apps.
    await ruLists.refreshIfDue();
    final refreshed = await autoBypassApps(ruLists, installed: installed);
    if (mounted) setState(() => _autoApps = refreshed);
  }

  Set<String> get _picked => _apps[_mode] ?? <String>{};

  bool get _include => _mode == AppSplitMode.include;

  bool _isRu(String package) => _autoApps.ru.contains(package);

  /// A non-Russian automatic app while "Auto" applies (not in "only selected").
  bool _isOtherAuto(String package) => _auto && !_include && _autoApps.other.contains(package);

  /// Ticked = bypasses the VPN, or in "only selected" mode, goes through it.
  bool _isSelected(String package) {
    if (_include) return _picked.contains(package) && !_isRu(package);
    if (_isRu(package)) return true;
    if (_isOtherAuto(package)) return !_forced.contains(package);

    return _picked.contains(package);
  }

  bool get _hasChanges =>
      _mode != _initialMode ||
      _auto != _initialAuto ||
      !setEquals(_forced, _initialForced) ||
      !setEquals(_apps[AppSplitMode.exclude], _initialApps[AppSplitMode.exclude]) ||
      !setEquals(_apps[AppSplitMode.include], _initialApps[AppSplitMode.include]);

  int get _selectedCount => _installed.where((app) => _isSelected(app.packageName)).length;

  int get _selectedSystemCount => _installed.where((app) => app.isSystem && _isSelected(app.packageName)).length;

  List<InstalledApp> get _visibleApps {
    final query = _query.trim().toLowerCase();
    final visible = _installed.where((app) {
      // Vendor services get auto-selected by the hundred - hidden with the
      // other system apps; the header counts them.
      if (app.isSystem && !_showSystem) return false;
      if (query.isEmpty) return true;

      return app.label.toLowerCase().contains(query) || app.packageName.toLowerCase().contains(query);
    }).toList();
    // Selected apps first, the rest alphabetically (the platform list is sorted).
    visible.sort((a, b) => (_isSelected(a.packageName) ? 0 : 1) - (_isSelected(b.packageName) ? 0 : 1));

    return visible;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_hasChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _showNotSavedChangesWarning(context);
    },
    child: ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(title: context.ln.appSplitTitle),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverList.list(
                          children: [
                            for (final mode in AppSplitMode.values)
                              CustomRadioListTile<AppSplitMode>(
                                value: mode,
                                groupValue: _mode,
                                title: _modeTitle(context, mode),
                                subTitle: _modeDescription(context, mode),
                                onChanged: (value) => setState(() => _mode = value ?? _mode),
                              ),
                            const Divider(),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                              child: Text(
                                context.ln.appSplitRuNote(_autoApps.ru.length),
                                style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
                              ),
                            ),
                            CustomSwitchTile(
                              title: context.ln.appSplitAuto,
                              subtitle: _mode == AppSplitMode.include
                                  ? context.ln.appSplitAutoInclude
                                  : context.ln.appSplitAutoDescription(_autoApps.other.length),
                              value: _auto,
                              onChanged: _mode == AppSplitMode.include ? null : (value) => setState(() => _auto = value),
                            ),
                            ..._pickerHeader(context),
                          ],
                        ),
                        _appList(context),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: context.isMobileBreakpoint ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
                    children: [
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton(
                          onPressed: _hasChanges ? _save : null,
                          child: Text(context.ln.save),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    ),
  );

  List<Widget> _pickerHeader(BuildContext context) => [
    const Divider(),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        _selectedSystemCount > 0 && !_showSystem
            ? context.ln.appSplitSelectedCountWithSystem(_selectedCount, _selectedSystemCount)
            : context.ln.appSplitSelectedCount(_selectedCount),
        style: context.textTheme.titleSmall,
      ),
    ),
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: CustomTextField(
        value: _query,
        hint: context.ln.appSplitSearch,
        onChanged: (text) => setState(() => _query = text),
      ),
    ),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: TextButton(
        onPressed: () => setState(() => _showSystem = !_showSystem),
        child: Text(_showSystem ? context.ln.appSplitHideSystem : context.ln.appSplitShowSystem),
      ),
    ),
    if (_installed.isEmpty)
      Padding(
        padding: const EdgeInsets.all(16),
        child: Text(context.ln.appSplitNoApps, textAlign: TextAlign.center),
      ),
  ];

  Widget _appList(BuildContext context) {
    final apps = _visibleApps;

    return SliverList.builder(
      itemCount: apps.length,
      itemBuilder: (context, index) {
        final app = apps[index];
        final package = app.packageName;
        final ru = _isRu(package);
        final otherAuto = _isOtherAuto(package);
        final tag = ru
            ? context.ln.appSplitRuTag
            : otherAuto
            ? (_forced.contains(package) ? context.ln.appSplitForcedTag : context.ln.appSplitAutoTag)
            : null;

        return CustomCheckboxListTile(
          key: ValueKey(package),
          value: _isSelected(package),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          onChanged: ru
              // Russian apps: always direct, never through the VPN.
              ? null
              : otherAuto
              // Unticking puts it back into the VPN, ticking returns it to auto.
              ? (checked) => setState(() => checked ? _forced.remove(package) : _forced.add(package))
              // "Off" has no picked list: ticking an app there switches to
              // "selected bypass the VPN".
              : (checked) => setState(() {
                  if (_mode == AppSplitMode.off) _mode = AppSplitMode.exclude;
                  final set = _apps.putIfAbsent(_mode, () => <String>{});
                  checked ? set.add(package) : set.remove(package);
                }),
          title: Row(
            children: [
              _AppIcon(future: _icons.putIfAbsent(app.packageName, () => InstalledAppsPlatform.icon(app.packageName))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      tag != null ? '$tag · $package' : package,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _modeTitle(BuildContext context, AppSplitMode mode) => switch (mode) {
    AppSplitMode.off => context.ln.appSplitModeOff,
    AppSplitMode.exclude => context.ln.appSplitModeExclude,
    AppSplitMode.include => context.ln.appSplitModeInclude,
  };

  String _modeDescription(BuildContext context, AppSplitMode mode) => switch (mode) {
    AppSplitMode.off => context.ln.appSplitModeOffDescription,
    AppSplitMode.exclude => context.ln.appSplitModeExcludeDescription,
    AppSplitMode.include => context.ln.appSplitModeIncludeDescription,
  };

  Future<void> _save() async {
    final repository = context.repositoryFactory.appSplitSettingsRepository;
    await repository.setApps(AppSplitMode.exclude, (_apps[AppSplitMode.exclude] ?? {}).toList()..sort());
    await repository.setApps(AppSplitMode.include, (_apps[AppSplitMode.include] ?? {}).toList()..sort());
    await repository.setAutoRuCn(_auto);
    await repository.setForcedVpn(_forced.toList()..sort());
    await repository.setMode(_mode);
    if (!mounted) return;

    setState(() {
      _initialMode = _mode;
      _initialAuto = _auto;
      _initialForced = {..._forced};
      _initialApps[AppSplitMode.exclude] = {...?_apps[AppSplitMode.exclude]};
      _initialApps[AppSplitMode.include] = {...?_apps[AppSplitMode.include]};
    });
    final reconnecting = ServerConnectionActions.reconnectIfActive(context);
    context.showInfoSnackBar(message: reconnecting ? context.ln.settingsAppliedReconnecting : context.ln.appSplitSaved);
    if (Navigator.canPop(context)) context.pop();
  }

  void _showNotSavedChangesWarning(BuildContext context) {
    final parentScaffoldMessenger = ScaffoldMessenger.maybeOf(context);

    showDialog(
      context: context,
      builder: (innerContext) => ScaffoldMessengerProvider(
        value: parentScaffoldMessenger ?? ScaffoldMessenger.of(innerContext),
        child: DiscardChangesDialog(onDiscardPressed: context.pop),
      ),
    );
  }
}

class _AppIcon extends StatelessWidget {
  static const _size = 36.0;

  final Future<Uint8List?> future;

  const _AppIcon({required this.future});

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: _size,
    child: FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return Icon(Icons.android, color: context.colors.neutralDark);

        return Image.memory(bytes, width: _size, height: _size, gaplessPlayback: true);
      },
    ),
  );
}
