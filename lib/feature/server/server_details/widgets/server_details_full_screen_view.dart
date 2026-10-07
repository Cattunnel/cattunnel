import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/scope/server_details_scope.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/scope/server_details_scope_aspect.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_details_delete_dialog.dart';
import 'package:trusttunnel/feature/server/server_details/widgets/server_export_dialog.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';
import 'package:trusttunnel/widgets/buttons/custom_icon_button.dart';
import 'package:trusttunnel/widgets/common/scaffold_messenger_provider.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';

class ServerDetailsFullScreenView extends StatefulWidget {
  final Widget body;

  const ServerDetailsFullScreenView({
    super.key,
    required this.body,
  });

  @override
  State<ServerDetailsFullScreenView> createState() => _ServerDetailsFullScreenViewState();
}

class _ServerDetailsFullScreenViewState extends State<ServerDetailsFullScreenView> {
  late bool _hasChanges;
  late final bool _editing;
  late ServerData _data;
  late bool loading;

  @override
  void initState() {
    super.initState();
    final initialDataScope = ServerDetailsScope.controllerOf(context, listen: false);
    _hasChanges = initialDataScope.hasChanges;
    _editing = initialDataScope.editing;
    _data = initialDataScope.data;
    loading = initialDataScope.loading;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final dataUpdate = ServerDetailsScope.controllerOf(
      context,
      aspect: ServerDetailsScopeAspect.data,
    );

    _hasChanges = dataUpdate.hasChanges;
    _data = dataUpdate.data;

    final loadingUpdate = ServerDetailsScope.controllerOf(
      context,
      aspect: ServerDetailsScopeAspect.loading,
    );

    loading = loadingUpdate.loading;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: CustomAppBar(
            actions: [
              if (_editing) ...[
                CustomIconButton.square(
                  icon: AssetIcons.share,
                  size: 24,
                  onPressed: () => _onExport(context),
                ),
                CustomIconButton.square(
                  icon: AssetIcons.delete,
                  color: context.colors.error,
                  size: 24,
                  onPressed: () => _onDelete(context),
                ),
              ],
            ],
            leadingIconType: AppBarLeadingIconType.back,
            centerTitle: true,
            onBackPressed: () => Navigator.of(context).maybePop(),
            title: _editing ? context.ln.editServer : context.ln.addServer,
          ),
        ),
        SliverToBoxAdapter(
          child: loading ? const SizedBox.shrink() : widget.body,
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          fillOverscroll: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Divider(),
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _hasChanges ? () => _submit(context) : null,
                  child: Text(
                    _editing || ServerDetailsScope.controllerOf(context).replacedAddress != null
                        ? context.ln.save
                        : context.ln.add,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _submit(BuildContext context) => ServerDetailsScope.controllerOf(context, listen: false).submit(_onSubmitted);

  void _onExport(BuildContext context) {
    final link = context.repositoryFactory.serverRepository.getDeepLinkForServer(server: _data);

    showDialog(
      context: context,
      builder: (_) => ServerExportDialog(link: link),
    );
  }

  void _onDelete(BuildContext context) {
    final parentScaffoldMessenger = ScaffoldMessenger.maybeOf(context);

    showDialog(
      context: context,
      builder: (innerContext) => ScaffoldMessengerProvider(
        value: parentScaffoldMessenger ?? ScaffoldMessenger.of(innerContext),
        child: ServerDetailsDeleteDialog(
          serverName: _data.name,
          onDeletePressed: () => ServerDetailsScope.controllerOf(context, listen: false).delete(_onDeleted),
        ),
      ),
    );
  }

  void _onDeleted(String name) {
    if (!mounted) {
      return;
    }
    final vpnController = VpnScope.vpnControllerOf(context, listen: false);
    vpnController.stop();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final serverScope = ServersScope.controllerOf(context, listen: false);
      final server = ServerDetailsScope.controllerOf(context, listen: false);
      serverScope.fetchServers();

      if (server.data.selected) {
        final updatedData = serverScope.servers.firstWhereOrNull((s) => s.id != server.id);
        serverScope.pickServer(updatedData?.id);
      }

      if (Navigator.of(context).canPop()) {
        context.pop();
      }
      context.showInfoSnackBar(message: context.ln.serverDeletedSnackbar(name));
    });
  }

  void _onSubmitted(String name) {
    final String snackbarText;

    ServersScope.controllerOf(context, listen: false).fetchServers();

    if (!mounted) {
      return;
    }

    final details = ServerDetailsScope.controllerOf(context, listen: false);
    final replacedAddress = details.replacedAddress;
    if (_editing) {
      snackbarText = context.ln.changesSavedSnackbar;
    } else if (replacedAddress != null) {
      snackbarText = _updatedSnackbarText(name, replacedAddress, details.data.ipAddress);
    } else {
      snackbarText = context.ln.serverCreatedSnackbar(name);
    }

    if (Navigator.canPop(context)) {
      context.pop();
    }

    context.showInfoSnackBar(message: snackbarText);
  }

  /// A new link for an existing manual server: say what changed, usually
  /// just the port ("port updated 8443 -> 9443").
  String _updatedSnackbarText(String name, String oldAddress, String newAddress) {
    final (oldHost, oldPort) = _splitHostPort(oldAddress);
    final (newHost, newPort) = _splitHostPort(newAddress);
    if (oldAddress.trim() == newAddress.trim()) {
      return context.ln.serverUpdatedSnackbar(name);
    }
    if (oldHost == newHost && oldPort != null && newPort != null) {
      return context.ln.serverPortUpdatedSnackbar(name, oldPort, newPort);
    }

    return context.ln.serverAddressUpdatedSnackbar(name, oldAddress.trim(), newAddress.trim());
  }

  /// "host:port", "[v6]:port" or a bare host.
  static (String, String?) _splitHostPort(String address) {
    final value = address.trim().toLowerCase();
    final match = RegExp(r'^(\[[^\]]+\]|[^:\[\]]+):(\d+)$').firstMatch(value);

    return match == null ? (value, null) : (match.group(1)!, match.group(2));
  }
}
