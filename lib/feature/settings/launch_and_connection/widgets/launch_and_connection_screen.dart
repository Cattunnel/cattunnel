import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_connection_actions.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope.dart';
import 'package:trusttunnel/feature/server/servers/widget/scope/servers_scope_aspect.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/controller/mtu_controller.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/widgets/scope/launch_and_connection_scope.dart';
import 'package:trusttunnel/feature/settings/launch_and_connection/widgets/scope/launch_and_connection_scope_controller.dart';
import 'package:trusttunnel/feature/settings/ru_services/widgets/ru_services_rules_screen.dart';
import 'package:trusttunnel/widgets/common/custom_switch_tile.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

class LaunchAndConnectionScreen extends StatefulWidget {
  const LaunchAndConnectionScreen({super.key});

  @override
  State<LaunchAndConnectionScreen> createState() => _LaunchAndConnectionScreenState();
}

class _LaunchAndConnectionScreenState extends State<LaunchAndConnectionScreen> {
  late LaunchAndConnectionScopeController _controller;
  late bool _isLaunchAtLoginEnabled;
  late bool _isLaunchAtLoginLoading;
  late bool _isOpenMainWindowOnLoginEnabled;
  late bool _isOpenMainWindowOnLoginLoading;
  late bool _isAutoConnectOnLaunchEnabled;
  late bool _isAutoConnectOnLaunchLoading;
  late bool _isKillSwitchEnabled;
  late bool _isKillSwitchLoading;
  late bool _isServersListEmpty;
  bool _isRuServicesBypassEnabled = true;
  bool _isConnectionNotificationsEnabled = true;
  late final TextEditingController _mtuTextController;
  late final TextEditingController _testTimeoutTextController;

  @override
  void initState() {
    super.initState();
    final initialMtu = LaunchAndConnectionScope.controllerOf(context, listen: false).mtuValue;
    _mtuTextController = TextEditingController(text: initialMtu.toString());

    _testTimeoutTextController = TextEditingController();
    context.repositoryFactory.serverTestTimeoutRepository.getValueSeconds().then((value) {
      if (mounted) {
        _testTimeoutTextController.text = value.toString();
      }
    });

    context.repositoryFactory.ruServicesSettingsRepository.isEnabled().then((value) {
      if (mounted) {
        setState(() => _isRuServicesBypassEnabled = value);
      }
    });

    context.repositoryFactory.connectionNotificationsSettingsRepository.isEnabled().then((value) {
      if (mounted) {
        setState(() => _isConnectionNotificationsEnabled = value);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = LaunchAndConnectionScope.controllerOf(context);
    _isLaunchAtLoginEnabled = _controller.isLaunchAtLoginEnabled;
    _isLaunchAtLoginLoading = _controller.isLaunchAtLoginLoading;
    _isOpenMainWindowOnLoginEnabled = _controller.isOpenMainWindowOnLoginEnabled;
    _isOpenMainWindowOnLoginLoading = _controller.isOpenMainWindowOnLoginLoading;
    _isAutoConnectOnLaunchEnabled = _controller.isAutoConnectOnLaunchEnabled;
    _isAutoConnectOnLaunchLoading = _controller.isAutoConnectOnLaunchLoading;
    _isKillSwitchEnabled = _controller.isKillSwitchEnabled;
    _isKillSwitchLoading = _controller.isKillSwitchLoading;
    _isServersListEmpty = ServersScope.controllerOf(
      context,
      aspect: ServersScopeAspect.servers,
    ).servers.isEmpty;
  }

  @override
  void dispose() {
    _mtuTextController.dispose();
    _testTimeoutTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(
        title: context.ln.launchAndConnection,
        centerTitle: true,
        leadingIconType: AppBarLeadingIconType.back,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Image.asset(AssetImages.catShield, height: 36),
          ),
        ],
      ),
      body: ListView(
        children: [
          if (defaultTargetPlatform == TargetPlatform.macOS) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.ln.launch,
                style: context.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            CustomSwitchTile(
              title: context.ln.launchAppAtSystemLogin,
              value: _isLaunchAtLoginEnabled,
              onChanged: _isLaunchAtLoginLoading ? null : _setLaunchAtSystemLogin,
            ),
            CustomSwitchTile(
              title: context.ln.openHomeScreenAutomatically,
              value: _isOpenMainWindowOnLoginEnabled,
              onChanged: _isLaunchAtLoginEnabled && !_isOpenMainWindowOnLoginLoading
                  ? _setOpenHomeScreenAutomatically
                  : null,
            ),
            const Divider(),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              context.ln.connection,
              style: context.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          CustomSwitchTile(
            title: context.ln.autoConnectOnAppLaunch,
            subtitle: _isAutoConnectOnLaunchEnabled && _isServersListEmpty
                ? context.ln.autoConnectNoServersAdded
                : null,
            subtitleColor: context.colors.orange1,
            value: _isAutoConnectOnLaunchEnabled,
            onChanged: _isAutoConnectOnLaunchLoading ? null : _setAutoConnectOnAppLaunch,
          ),
          CustomSwitchTile(
            title: context.ln.killSwitch,
            subtitle: context.ln.killSwitchDescription,
            value: _isKillSwitchEnabled,
            onChanged: _isKillSwitchLoading ? null : _setKillSwitchEnabled,
          ),
          CustomSwitchTile(
            title: context.ln.ruServicesBypass,
            subtitle: context.ln.ruServicesBypassDescription,
            value: _isRuServicesBypassEnabled,
            onChanged: _setRuServicesBypassEnabled,
            action: IconButton(
              icon: CustomIcon(
                icon: AssetIcons.modeEdit,
                size: 24,
                color: context.colors.neutralDark,
              ),
              tooltip: context.ln.edit,
              onPressed: () => _pushRuServicesRulesScreen(context),
            ),
          ),
          CustomSwitchTile(
            title: context.ln.connectionNotifications,
            subtitle: context.ln.connectionNotificationsDescription,
            value: _isConnectionNotificationsEnabled,
            onChanged: _setConnectionNotificationsEnabled,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CustomTextField(
              controller: _mtuTextController,
              label: context.ln.mtuLabel,
              helper: context.ln.mtuHelper(mtuMinValue, mtuMaxValue),
              hint: '1500',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              onChanged: _onMtuChanged,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: CustomTextField(
              controller: _testTimeoutTextController,
              label: context.ln.testTimeoutLabel,
              helper: context.ln.testTimeoutHelper,
              hint: '5',
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              onChanged: _onTestTimeoutChanged,
            ),
          ),
        ],
      ),
    ),
  );

  void _setLaunchAtSystemLogin(bool value) => _controller.setLaunchAtLoginEnabled(value);

  void _setOpenHomeScreenAutomatically(bool value) => _controller.setOpenMainWindowOnLoginEnabled(value);

  void _setAutoConnectOnAppLaunch(bool value) => _controller.setAutoConnectOnLaunchEnabled(value);

  void _setKillSwitchEnabled(bool value) => _controller.setKillSwitchEnabled(value);

  Future<void> _setRuServicesBypassEnabled(bool value) async {
    setState(() => _isRuServicesBypassEnabled = value);

    final repository = context.repositoryFactory.ruServicesSettingsRepository;
    if (value) {
      await repository.enable();
    } else {
      await repository.disable();
    }
    if (mounted && ServerConnectionActions.reconnectIfActive(context)) {
      context.showInfoSnackBar(message: context.ln.settingsAppliedReconnecting);
    }
  }

  void _pushRuServicesRulesScreen(BuildContext context) => context.push(
    const RuServicesRulesScreen(),
  );

  void _setConnectionNotificationsEnabled(bool value) {
    setState(() => _isConnectionNotificationsEnabled = value);

    final repository = context.repositoryFactory.connectionNotificationsSettingsRepository;
    if (value) {
      repository.enable();
    } else {
      repository.disable();
    }
  }

  void _onMtuChanged(String value) {
    final mtu = int.tryParse(value);

    if (mtu == null || mtu < mtuMinValue || mtu > mtuMaxValue) {
      return;
    }

    _controller.setMtuValue(mtu);
  }

  void _onTestTimeoutChanged(String value) {
    final seconds = int.tryParse(value);

    if (seconds == null || seconds < 1 || seconds > 30) {
      return;
    }

    context.repositoryFactory.serverTestTimeoutRepository.setValueSeconds(seconds);
  }
}
