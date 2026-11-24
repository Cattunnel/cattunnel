import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/router/app_routes.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/server_group_settings.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_companion.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_petting_dialog.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_groups.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_sorting.dart';
import 'package:trusttunnel/feature/server/servers/widget/add_server_flow.dart';
import 'package:trusttunnel/feature/server/servers/widget/group_rename_dialog.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/server/servers/widget/server_sort_sheet.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_card.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_empty_placeholder.dart';
import 'package:trusttunnel/feature/server/servers/widget/subscription_servers_group.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_badge_hint.dart';
import 'package:trusttunnel/widgets/buttons/custom_floating_action_button.dart';
import 'package:trusttunnel/widgets/common/scaffold_messenger_provider.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

class ServersScreenView extends StatefulWidget {
  final ServerData? deepLinkData;

  const ServersScreenView({
    super.key,
    this.deepLinkData,
  });

  @override
  State<ServersScreenView> createState() => _ServersScreenViewState();
}

class _ServersScreenViewState extends State<ServersScreenView> {
  late List<Server> _servers;
  late final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey;
  ServerSortOption _sortOption = ServerSortOption.origin;
  List<SubscriptionData> _subscriptions = [];
  Map<String, ServerGroupSettings> _groupSettings = {};
  Set<String> _refreshingSubscriptionIds = {};

  @override
  void initState() {
    super.initState();
    final initialController = ServersScope.controllerOf(context, listen: false);
    _servers = initialController.servers;
    _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
    context.repositoryFactory.serverSortPreferenceRepository.getValue().then((value) {
      if (mounted) {
        setState(() => _sortOption = value);
      }
    });
    _fetchSubscriptions();
    if (widget.deepLinkData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pushServerDetailsScreen(
          preloadedData: widget.deepLinkData,
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _servers = ServersScope.controllerOf(
      context,
      aspect: ServersScopeAspect.servers,
    ).servers;
  }

  Future<void> _fetchSubscriptions() async {
    final repository = context.repositoryFactory.subscriptionRepository;
    final subscriptions = await repository.getAllSubscriptions();
    final groupSettings = await repository.getGroupSettings();

    if (mounted) {
      setState(() {
        _subscriptions = subscriptions;
        _groupSettings = groupSettings;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final latencyController = ServerLatencyScope.of(context);
    final sortedServers = _sortedServers(latencyController);

    return ScaffoldWrapper(
      readable: false,
      child: ScaffoldMessenger(
        key: _scaffoldMessengerKey,
        child: Scaffold(
          appBar: CustomAppBar(
            title: context.ln.servers,
            actions: [
              const Padding(
                padding: EdgeInsets.only(right: 16),
                child: CatCompanion(),
              ),
            ],
          ),
          body: sortedServers.isEmpty
              ? const ServersEmptyPlaceholder()
              // Bottom padding clears the floating small "actions" button +
              // the extended "Add servers" button stacked above it, so the
              // last row is never hidden behind them even fully scrolled.
              : ListView(
                  padding: const EdgeInsets.only(bottom: 140),
                  children: [
                    const VpnBadgeHint(padding: EdgeInsets.fromLTRB(16, 12, 16, 4)),
                    ..._buildSections(sortedServers),
                  ],
                ),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
          floatingActionButton: sortedServers.isEmpty
              ? null
              : Builder(
                  builder: (context) => SizedBox(
                    width: double.infinity,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(left: 16),
                          child: CatPettingButton(),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _ServersActionsButton(
                                onSort: () => _onSort(context),
                              ),
                              const SizedBox(height: 12),
                              CustomFloatingActionButton.extended(
                                icon: AssetIcons.add,
                                onPressed: () =>
                                    presentAddServerFlow(context, pushServerDetails: _pushServerDetailsScreen),
                                label: context.ln.addServers,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  List<Server> _sortedServers(ServerLatencyController latencyController) =>
      sortServers(_servers, _sortOption, latencyController);

  /// Groups in the user's order: the manual keys and one per subscription.
  /// Servers are matched to a subscription by its real name; a group's own
  /// label only changes what the header shows. The manual group gets a header
  /// only next to a subscription: alone it stays a flat list.
  List<Widget> _buildSections(List<Server> sortedServers) {
    final byName = groupBy(sortedServers, (server) => server.serverData.subscriptionName);
    final manual = byName[null] ?? [];

    final subscriptionsByKey = {for (final s in _subscriptions) subscriptionGroupKey(s.id!): s};
    final serversByKey = <String, List<Server>>{
      manualGroupKey: manual,
      for (final entry in subscriptionsByKey.entries) entry.key: byName[entry.value.name] ?? [],
    };
    final orderedKeys = orderGroupKeys([manualGroupKey, ...subscriptionsByKey.keys], _groupSettings);
    final visibleKeys = orderedKeys.where((key) => serversByKey[key]!.isNotEmpty).toList();

    final hasSubscriptionGroup = visibleKeys.any((key) => key != manualGroupKey);
    if (!hasSubscriptionGroup) {
      return [
        for (var i = 0; i < manual.length; i++) ...[
          ServersCard(server: manual[i]),
          if (i != manual.length - 1) const Divider(),
        ],
      ];
    }

    final widgets = <Widget>[];
    for (final (index, key) in visibleKeys.indexed) {
      if (widgets.isNotEmpty) {
        widgets.add(const Divider());
      }

      final subscription = subscriptionsByKey[key];
      final original = subscription?.name ?? context.ln.groupManualName;

      widgets.add(
        SubscriptionServersGroup(
          key: ValueKey(key),
          subscription: subscription,
          displayName: groupDisplayName(original, _groupSettings[key]),
          servers: serversByKey[key]!,
          refreshing: subscription != null && _refreshingSubscriptionIds.contains(subscription.name),
          onRefresh: subscription == null ? null : () => _onRefreshSubscription(subscription),
          onRename: () => _onRenameGroup(key),
          onMoveUp: index == 0 ? null : () => _onMoveGroup(key, -1, visibleKeys, orderedKeys),
          onMoveDown: index == visibleKeys.length - 1 ? null : () => _onMoveGroup(key, 1, visibleKeys, orderedKeys),
        ),
      );
    }

    return widgets;
  }

  Future<void> _onRenameGroup(String key) async {
    final repository = context.repositoryFactory.subscriptionRepository;
    final label = await GroupRenameDialog.show(context, initial: _groupSettings[key]?.label ?? '');
    if (label == null || !mounted) {
      return;
    }

    await repository.setGroupLabel(key: key, label: label);
    await _fetchSubscriptions();
  }

  Future<void> _onMoveGroup(String key, int delta, List<String> visibleKeys, List<String> orderedKeys) async {
    final repository = context.repositoryFactory.subscriptionRepository;
    final moved = moveGroupKey(visibleKeys, key, delta);

    // Groups with no servers on screen keep their relative order at the end.
    await repository.setGroupOrder(keys: [...moved, ...orderedKeys.where((k) => !visibleKeys.contains(k))]);
    await _fetchSubscriptions();
  }

  Future<void> _onRefreshSubscription(SubscriptionData subscription) async {
    final name = subscription.name;
    if (_refreshingSubscriptionIds.contains(name)) {
      return;
    }

    setState(() => _refreshingSubscriptionIds = {..._refreshingSubscriptionIds, name});

    try {
      await context.repositoryFactory.subscriptionRepository.refresh(subscription: subscription);
      if (!mounted) {
        return;
      }
      ServersScope.controllerOf(context, listen: false).fetchServers();
      await _fetchSubscriptions();
    } catch (_) {
      if (mounted) {
        context.showInfoSnackBar(message: context.ln.somethingWentWrongSnackbar);
      }
    } finally {
      if (mounted) {
        setState(() => _refreshingSubscriptionIds = _refreshingSubscriptionIds.where((e) => e != name).toSet());
      }
    }
  }

  Future<void> _onSort(BuildContext context) async {
    final option = await ServerSortSheet.show(context, current: _sortOption);

    if (option == null || !context.mounted) {
      return;
    }

    setState(() => _sortOption = option);
    await context.repositoryFactory.serverSortPreferenceRepository.setValue(option);
  }

  Future<void> _pushServerDetailsScreen({
    ServerData? preloadedData,
  }) async {
    final controller = ServersScope.controllerOf(context, listen: false);
    final Widget serverDetailsScreen;

    if (preloadedData != null) {
      serverDetailsScreen = ServerDetailsPopUp.preloaded(
        preloadedData: preloadedData,
      );
    } else {
      serverDetailsScreen = const ServerDetailsPopUp();
    }

    await context.push(
      ScaffoldMessengerProvider(
        value: _scaffoldMessengerKey.currentState ?? ScaffoldMessenger.of(context),
        child: serverDetailsScreen,
      ),
      route: AppRoutes.serverDetails,
    );

    controller.fetchServers();
  }
}

/// Small square FAB (matching the main "Add servers" FAB's style) that opens
/// the sort sheet - placed above the main FAB rather than in the app bar.
class _ServersActionsButton extends StatelessWidget {
  final VoidCallback onSort;

  const _ServersActionsButton({required this.onSort});

  @override
  Widget build(BuildContext context) => CustomFloatingActionButton.small(
    icon: AssetIcons.sort,
    onPressed: onSort,
  );
}
