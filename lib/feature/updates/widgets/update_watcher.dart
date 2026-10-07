import 'package:flutter/material.dart';
import 'package:trusttunnel/feature/updates/domain/update_service.dart';
import 'package:trusttunnel/feature/updates/widgets/update_dialogs.dart';

/// Checks for a new CatTunnel shortly after launch and whenever the app
/// comes back to the foreground (a VPN app can live in memory for days), at
/// most about once a day (UpdateService.autoCheckDue), and lets Marsik
/// offer it. Quiet on
/// any error - the manual check in About reports those.
///
/// Must sit below the root `Navigator` (it shows a dialog).
class UpdateWatcher extends StatefulWidget {
  final Widget child;

  const UpdateWatcher({super.key, required this.child});

  @override
  State<UpdateWatcher> createState() => _UpdateWatcherState();
}

class _UpdateWatcherState extends State<UpdateWatcher> with WidgetsBindingObserver {
  static const _delayAfterLaunch = Duration(seconds: 5);

  bool _checking = false;

  @override
  void initState() {
    super.initState();
    if (!UpdateService.enabled) return;
    WidgetsBinding.instance.addObserver(this);
    Future.delayed(_delayAfterLaunch, _autoCheck);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoCheck();
  }

  Future<void> _autoCheck() async {
    // One check (and one offer dialog) at a time.
    if (_checking) return;
    _checking = true;
    try {
      if (!mounted || !await UpdateService.autoCheckDue()) return;
      final update = await UpdateService.check();
      if (update != null && mounted) await showUpdateOffer(context, update);
    } on Object {
      // Offline, server down, bad file or signature - try again later.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
