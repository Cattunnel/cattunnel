import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/router/app_routes.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/server_sort_option.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_companion.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_petting_dialog.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/servers/controller/server_latency_controller.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_sorting.dart';
import 'package:trusttunnel/feature/server/servers/widget/add_server_flow.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/server/servers/widget/server_sort_sheet.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_card.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_empty_placeholder.dart';
import 'package:trusttunnel/feature/server/servers/widget/subscription_servers_group.dart';
import 'package:trusttunnel/widgets/buttons/custom_floating_action_button.dart';
import 'package:trusttunnel/widgets/common/scaffold_messenger_provider.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';
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
    final subscriptions = await context.repositoryFactory.subscriptionRepository.getAllSubscriptions();

    if (mounted) {
      setState(() => _subscriptions = subscriptions);
    }
  }

  @override
  Widget build(BuildContext context) {
    final latencyController = ServerLatencyScope.of(context);
    final sortedServers = _sortedServers(latencyController);

    return ScaffoldWrapper(
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
                  children: _buildSections(sortedServers),
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
                                onTest: () => _onTestServers(context),
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

  /// Servers with no [ServerData.subscriptionName] are shown flat at the top;
  /// the rest are grouped into a collapsible [SubscriptionServersGroup] per
  /// subscription, in the order [_subscriptions] were fetched.
  List<Widget> _buildSections(List<Server> sortedServers) {
    final showLatencyBadge = _sortOption == ServerSortOption.latency;
    final byName = groupBy(sortedServers, (server) => server.serverData.subscriptionName);
    final ungrouped = byName[null] ?? [];

    final widgets = <Widget>[];

    for (var i = 0; i < ungrouped.length; i++) {
      widgets.add(ServersCard(server: ungrouped[i], showLatencyBadge: showLatencyBadge));
      if (i != ungrouped.length - 1) widgets.add(const Divider());
    }

    for (final subscription in _subscriptions) {
      final servers = byName[subscription.name];
      if (servers == null || servers.isEmpty) {
        continue;
      }

      if (widgets.isNotEmpty) {
        widgets.add(const Divider());
      }

      widgets.add(
        SubscriptionServersGroup(
          key: ValueKey(subscription.name),
          subscription: subscription,
          servers: servers,
          showLatencyBadge: showLatencyBadge,
          refreshing: _refreshingSubscriptionIds.contains(subscription.name),
          onRefresh: () => _onRefreshSubscription(subscription),
        ),
      );
    }

    return widgets;
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

  Future<void> _onTestServers(BuildContext context) async {
    final latencyController = ServerLatencyScope.of(context, listen: false);

    context.showInfoSnackBar(message: context.ln.testingServersSnackbar);
    await latencyController.testAll(_servers);

    if (!context.mounted) {
      return;
    }

    final reachableCount = _servers.where((s) => latencyController.resultFor(s.id)?.reachable ?? false).length;

    context.showInfoSnackBar(
      message: context.ln.testServersResultSnackbar(reachableCount, _servers.length),
    );
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
/// a menu with "Test servers" / "Sort by" - placed above the main FAB rather
/// than in the app bar.
class _ServersActionsButton extends StatelessWidget {
  final VoidCallback onTest;
  final VoidCallback onSort;

  const _ServersActionsButton({
    required this.onTest,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) => CustomFloatingActionButton.small(
    icon: AssetIcons.moreVert,
    onPressed: () => _showMenu(context),
  );

  Future<void> _showMenu(BuildContext context) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final selected = await showMenu<VoidCallback>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: onTest,
          child: Row(
            children: [
              CustomIcon.medium(icon: Icons.speed, color: context.colors.accent),
              const SizedBox(width: 12),
              Text(context.ln.testServersAction, style: context.textTheme.bodyLarge),
            ],
          ),
        ),
        PopupMenuItem(
          value: onSort,
          child: Row(
            children: [
              CustomIcon.medium(icon: AssetIcons.sort, color: context.colors.accent),
              const SizedBox(width: 12),
              Text(context.ln.sortByTitle, style: context.textTheme.bodyLarge),
            ],
          ),
        ),
      ],
    );

    selected?.call();
  }
}
