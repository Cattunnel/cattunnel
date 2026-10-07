import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/server_latency_scope.dart';
import 'package:trusttunnel/feature/subscriptions/controller/subscriptions_controller.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_card.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_edit_dialog.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_share_dialog.dart';
import 'package:trusttunnel/widgets/arb_parser/arb_parser.dart';
import 'package:trusttunnel/widgets/buttons/custom_floating_action_button.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/default_page.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

class SubscriptionsScreen extends StatefulWidget {
  /// Scanned from a share QR (see [SubscriptionShareLink]) - opens the add
  /// form pre-filled with it right away.
  final SubscriptionData? imported;

  const SubscriptionsScreen({super.key, this.imported});

  @override
  State<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends State<SubscriptionsScreen> {
  late final SubscriptionsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SubscriptionsController(
      repository: context.repositoryFactory.subscriptionRepository,
    );
    _controller.addListener(_onStateChanged);
    _controller.fetch();

    final imported = widget.imported;
    if (imported != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _onAdd(context, prefill: imported);
        }
      });
    }
  }

  void _onStateChanged() {
    final error = _controller.state.error;

    if (error != null && mounted) {
      context.showInfoSnackBar(message: context.ln.somethingWentWrongSnackbar);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) => ScaffoldWrapper(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.subscriptions,
          centerTitle: true,
          leadingIconType: AppBarLeadingIconType.back,
          onBackPressed: () => Navigator.of(context).maybePop(),
        ),
        body: _controller.state.subscriptions.isEmpty
            ? DefaultPage.responsive(
                title: context.ln.subscriptions,
                descriptionText: context.ln.noSubscriptionsPlaceholder,
                imagePath: AssetImages.catSleeping,
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: _controller.state.subscriptions.length,
                itemBuilder: (_, index) {
                  final subscription = _controller.state.subscriptions[index];

                  return Column(
                    children: [
                      SubscriptionCard(
                        subscription: subscription,
                        refreshing: _controller.state.refreshingIds.contains(subscription.id),
                        onRefresh: () => _controller.refresh(subscription),
                        onEdit: () => _onEdit(context, subscription),
                        onShare: () => showDialog<void>(
                          context: context,
                          builder: (_) => SubscriptionShareDialog(subscription: subscription),
                        ),
                        onDelete: () => _onDelete(context, subscription),
                      ),
                      if (index != _controller.state.subscriptions.length - 1) const Divider(),
                    ],
                  );
                },
              ),
        floatingActionButton: CustomFloatingActionButton.extended(
          icon: AssetIcons.add,
          label: context.ln.addSubscription,
          onPressed: () => _onAdd(context),
        ),
      ),
    ),
  );

  Future<void> _onAdd(BuildContext context, {SubscriptionData? prefill}) async {
    final result = await showDialog<SubscriptionData>(
      context: context,
      builder: (_) => SubscriptionEditDialog(prefill: prefill),
    );

    if (result == null) {
      return;
    }

    await _controller.add(result);

    final added = _controller.state.subscriptions.where((s) => s.url == result.url).lastOrNull;

    if (added == null) {
      return;
    }

    await _controller.refresh(added);

    if (context.mounted) {
      await _offerToTestServers(context, added);
    }
  }

  Future<void> _offerToTestServers(BuildContext context, SubscriptionData subscription) async {
    final shouldTest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: context.ln.testServersDialogTitle,
        content: Text(context.ln.testServersDialogDescription),
        actionsBuilder: (spacing) => [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: Text(context.ln.cancel),
          ),
          TextButton(
            onPressed: () => dialogContext.pop(result: true),
            child: Text(context.ln.testServersAction),
          ),
        ],
      ),
    );

    if (shouldTest != true || !context.mounted) {
      return;
    }

    final servers = await context.repositoryFactory.serverRepository.getAllServers();
    final subscriptionServers = servers.where((s) => s.serverData.subscriptionName == subscription.name).toList();

    if (subscriptionServers.isEmpty || !context.mounted) {
      return;
    }

    context.showInfoSnackBar(message: context.ln.testingServersSnackbar);
    ServerLatencyScope.of(context, listen: false).testAll(subscriptionServers);
  }

  Future<void> _onEdit(BuildContext context, SubscriptionData subscription) async {
    final result = await showDialog<SubscriptionData>(
      context: context,
      builder: (_) => SubscriptionEditDialog(initial: subscription),
    );

    if (result != null && subscription.id != null) {
      await _controller.update(subscription.id!, result);
    }
  }

  Future<void> _onDelete(BuildContext context, SubscriptionData subscription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => CustomAlertDialog(
        title: context.ln.deleteSubscriptionDialogTitle,
        scrollable: true,
        content: ArbParser(data: context.ln.deleteSubscriptionDescription(subscription.name)),
        actionsBuilder: (spacing) => [
          TextButton(
            onPressed: () => dialogContext.pop(),
            child: Text(context.ln.cancel),
          ),
          TextButton(
            onPressed: () => dialogContext.pop(result: true),
            child: Text(context.ln.delete),
          ),
        ],
      ),
    );

    if (confirmed == true && subscription.id != null) {
      await _controller.remove(subscription.id!);
    }
  }
}
