import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/ru_lists/ru_lists_service.dart';
import 'package:trusttunnel/feature/routing/routing_details/domain/service/routing_spell_check_service.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/widgets/common/scaffold_messenger_provider.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/discard_changes_dialog.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

final String _divider = Platform.lineTerminator;

/// Editor for the built-in "Russian services" bypass rule list (domains/IPs/
/// CIDR, one per line - same format and validation as the Routing feature).
class RuServicesRulesScreen extends StatefulWidget {
  const RuServicesRulesScreen({super.key});

  @override
  State<RuServicesRulesScreen> createState() => _RuServicesRulesScreenState();
}

class _RuServicesRulesScreenState extends State<RuServicesRulesScreen> {
  List<String> _initialRules = [];
  List<String> _rules = [];
  bool _hasInvalidRules = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    context.repositoryFactory.ruServicesSettingsRepository.getRules().then((rules) {
      if (!mounted) {
        return;
      }

      setState(() {
        _initialRules = rules;
        _rules = rules;
        _loading = false;
      });
    });
  }

  bool get _hasChanges => !listEquals(_rules, _initialRules);

  bool get _canSave => _hasChanges && (!_hasInvalidRules || _rules.isEmpty);

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_hasChanges,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        _showNotSavedChangesWarning(context);
      }
    },
    child: ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.ruServicesRulesScreenTitle,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const _AutoListsStatus(),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: CustomTextField(
                        value: _rules.join(_divider),
                        spellCheckService: RoutingSpellCheckService(
                          onChecked: (valid) => setState(() => _hasInvalidRules = !valid),
                        ),
                        hint: context.ln.typeSomething,
                        minLines: 40,
                        maxLines: 40,
                        showClearButton: false,
                        onChanged: (text) => setState(
                          () => _rules = text.split(_divider).map((r) => r.trim()).where((r) => r.isNotEmpty).toList(),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: context.isMobileBreakpoint ? CrossAxisAlignment.stretch : CrossAxisAlignment.end,
                    children: [
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: FilledButton(
                          onPressed: _canSave ? _save : null,
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

  Future<void> _save() async {
    await context.repositoryFactory.ruServicesSettingsRepository.setRules(_rules);

    if (!mounted) {
      return;
    }

    setState(() => _initialRules = _rules);
    if (ServerConnectionActions.reconnectIfActive(context)) {
      context.showInfoSnackBar(message: context.ln.settingsAppliedReconnecting);
    }

    if (Navigator.canPop(context)) {
      context.pop();
    }
  }

  void _showNotSavedChangesWarning(BuildContext context) {
    final parentScaffoldMessenger = ScaffoldMessenger.maybeOf(context);

    showDialog(
      context: context,
      builder: (innerContext) => ScaffoldMessengerProvider(
        value: parentScaffoldMessenger ?? ScaffoldMessenger.of(innerContext),
        child: DiscardChangesDialog(
          onDiscardPressed: context.pop,
        ),
      ),
    );
  }
}

/// The downloaded Russian lists (RuListsService) that are added to this
/// list on connect: size, date, and a manual refresh.
class _AutoListsStatus extends StatefulWidget {
  const _AutoListsStatus();

  @override
  State<_AutoListsStatus> createState() => _AutoListsStatusState();
}

class _AutoListsStatusState extends State<_AutoListsStatus> {
  RuLists? _lists;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final lists = await context.dependencyFactory.ruListsService.load();
    if (mounted) setState(() => _lists = lists);
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await context.dependencyFactory.ruListsService.refreshIfDue(force: true);
    await _reload();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final lists = _lists;
    final updatedAt = lists?.updatedAt;
    final text = lists == null
        ? ''
        : lists.isEmpty || updatedAt == null
        ? context.ln.ruListsNotLoaded
        : context.ln.ruListsStatus(
            lists.networkCount,
            lists.domains.length,
            '${updatedAt.day.toString().padLeft(2, '0')}.${updatedAt.month.toString().padLeft(2, '0')}',
          );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(child: Text(text, style: context.textTheme.bodySmall)),
          _refreshing
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(onPressed: _refresh, child: Text(context.ln.ruListsRefresh)),
        ],
      ),
    );
  }
}
