abstract class LaunchAndConnectionScopeController {
  abstract final bool isLaunchAtLoginEnabled;
  abstract final bool isLaunchAtLoginLoading;

  abstract final bool isOpenMainWindowOnLoginEnabled;
  abstract final bool isOpenMainWindowOnLoginLoading;

  abstract final bool isAutoConnectOnLaunchEnabled;
  abstract final bool isAutoConnectOnLaunchLoading;

  abstract final bool isKillSwitchEnabled;
  abstract final bool isKillSwitchLoading;

  abstract final int mtuValue;
  abstract final bool isMtuLoading;

  abstract final void Function(bool enabled) setLaunchAtLoginEnabled;
  abstract final void Function(bool enabled) setOpenMainWindowOnLoginEnabled;
  abstract final void Function(bool enabled) setAutoConnectOnLaunchEnabled;
  abstract final void Function(bool enabled) setKillSwitchEnabled;
  abstract final void Function(int mtu) setMtuValue;
}
