import 'package:flutter/material.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/servers/widget/cozy/cozy_servers_view.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/servers_screen_view.dart';

class ServersScreen extends StatefulWidget {
  final ServerData? deepLinkData;

  const ServersScreen({
    super.key,
    this.deepLinkData,
  });

  @override
  State<ServersScreen> createState() => _ServersScreenState();
}

class _ServersScreenState extends State<ServersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ServersScope.controllerOf(context, listen: false).fetchServers();
    });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: AppearancePreferences.style,
    builder: (context, style, _) => switch (style) {
      AppStyle.cozy => CozyServersView(deepLinkData: widget.deepLinkData),
      AppStyle.minimal => ServersScreenView(deepLinkData: widget.deepLinkData),
    },
  );
}
