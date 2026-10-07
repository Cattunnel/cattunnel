import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/widgets/secure_screen.dart';

/// App lock (Cyber security section): covers the whole UI - dialogs included,
/// it wraps the Navigator via MaterialApp.builder - with Marsik asleep
/// on start and after [_relockAfter] in the background, until the phone's
/// own biometrics/PIN pass (local_auth - no PIN of our own to store). The
/// app underneath keeps running, so VPN state and screens are untouched.
class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> {
  static const _relockAfter = Duration(minutes: 1);

  final _localAuth = LocalAuthentication();
  late final SecuritySettings _settings;
  late final AppLifecycleListener _lifecycle;

  late bool _locked;
  bool _authenticating = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    _settings = SecuritySettings(context.dependencyFactory.sharedPreferences);
    _locked = _settings.appLock;
    _lifecycle = AppLifecycleListener(
      // Only a real trip to the background counts - the system biometric
      // dialog itself makes the app merely inactive.
      // The PIN/pattern fallback is a separate system activity - time spent
      // there while unlocking isn't "in the background".
      onHide: () {
        if (!_authenticating) {
          _backgroundedAt ??= DateTime.now();
        }
      },
      onShow: _onShow,
    );
    if (_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onShow() {
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    if (!_settings.appLock || backgroundedAt == null || _locked) {
      return;
    }

    if (DateTime.now().difference(backgroundedAt) >= _relockAfter) {
      setState(() => _locked = true);
      unawaited(_unlock());
    }
  }

  Future<void> _unlock() async {
    if (_authenticating || !mounted) {
      return;
    }

    final reason = context.ln.appLockReason;
    _authenticating = true;
    try {
      // The screen lock was removed after the app lock was turned on: the
      // phone can't authenticate anyone anymore, and staying locked would
      // lock the user out for good. Drop the app lock instead.
      final device = await SecurityPlatform.deviceReport();
      if (device != null && !device.deviceSecure) {
        await _settings.setAppLock(false);
        if (mounted) {
          setState(() => _locked = false);
        }

        return;
      }

      final ok = await _localAuth.authenticate(
        localizedReason: reason,
        persistAcrossBackgrounding: true,
      );
      if (ok && mounted) {
        setState(() => _locked = false);
      }
    } catch (_) {
      // Cancelled / too many attempts - stay locked, the button retries.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      // Kept out of the accessibility tree and hit testing while locked.
      ExcludeSemantics(
        excluding: _locked,
        child: AbsorbPointer(absorbing: _locked, child: widget.child),
      ),
      if (_locked)
        // Also hides the unlocked UI from the Recents thumbnail/screenshots.
        SecureScreen(
          child: Positioned.fill(
            // Material, not ColoredBox: this sits above the Navigator (in
            // MaterialApp.builder), where nothing else provides one.
            child: Material(
              color: context.colors.backgroundSystem,
              child: SafeArea(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(AssetImages.catSleeping, height: 140),
                      const SizedBox(height: 16),
                      Text(context.ln.appLockLockedTitle, style: context.textTheme.titleMedium),
                      const SizedBox(height: 24),
                      FilledButton(onPressed: _unlock, child: Text(context.ln.appLockUnlock)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}
