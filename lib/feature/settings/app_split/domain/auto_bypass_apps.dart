import 'package:trusttunnel/data/ru_lists/ru_lists_service.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/installed_apps_platform.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/ru_app_packages.dart';

/// The installed apps that bypass the VPN automatically, computed from what
/// is installed now (a newly installed bank is covered on the next connect):
/// - [ru]: Russian apps (prefixes, preset, the downloaded community lists) -
///   always directly, they can't be put into the VPN;
/// - [other]: Chinese/vendor apps, Uzbek apps and local tools - directly
///   while "Auto" is on, each can be put back into the VPN.
class AutoBypassApps {
  final Set<String> ru;
  final Set<String> other;

  const AutoBypassApps({required this.ru, required this.other});

  static const empty = AutoBypassApps(ru: {}, other: {});

  /// What actually bypasses the VPN: all Russian apps, plus the other
  /// automatic ones (if [otherOn]) except those in [forcedVpn].
  Set<String> bypassing({required bool otherOn, Iterable<String> forcedVpn = const []}) => {
    ...ru,
    if (otherOn) ...other.difference(forcedVpn.toSet()),
  };
}

Future<AutoBypassApps> autoBypassApps(RuListsService ruLists, {List<InstalledApp>? installed}) async {
  final packagesFuture = installed != null
      ? Future.value([for (final app in installed) app.packageName])
      : InstalledAppsPlatform.packages();
  final lists = await ruLists.load();
  final packages = await packagesFuture;
  final ru = suggestRuApps(packages, downloaded: lists.apps);

  return AutoBypassApps(
    ru: ru,
    other: {...suggestCnApps(packages), ...suggestOtherApps(packages)}.difference(ru),
  );
}
