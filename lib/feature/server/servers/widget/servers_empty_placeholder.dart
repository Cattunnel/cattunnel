import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/onboarding/widgets/onboarding_tutorial.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_popup.dart';
import 'package:trusttunnel/feature/server/servers/widget/add_server_flow.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/widgets/default_page.dart';

class ServersEmptyPlaceholder extends StatelessWidget {
  const ServersEmptyPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => DefaultPage.responsive(
    title: context.ln.serversEmptyTitle,
    descriptionText: context.ln.serversEmptyDescription,
    imagePath: AssetImages.catShield,
    buttonText: context.ln.create,
    buttonKey: onboardingAddServerButtonKey,
    onButtonPressed: () => presentAddServerFlow(context, pushServerDetails: ({preloadedData}) => _pushServerDetailsScreen(context, preloadedData: preloadedData)),
  );

  Future<void> _pushServerDetailsScreen(BuildContext context, {ServerData? preloadedData}) async {
    final controller = ServersScope.controllerOf(context, listen: false);

    await context.push(
      preloadedData != null ? ServerDetailsPopUp.preloaded(preloadedData: preloadedData) : const ServerDetailsPopUp(),
    );

    controller.fetchServers();
  }
}
