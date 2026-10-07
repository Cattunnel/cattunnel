import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/security/widgets/leak_check_screen.dart';
import 'package:trusttunnel/feature/security/widgets/marsik_confirm.dart';
import 'package:trusttunnel/feature/security/widgets/security_checklist_screen.dart';
import 'package:trusttunnel/widgets/common/custom_arrow_list_tile.dart';
import 'package:trusttunnel/widgets/common/custom_switch_tile.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// Settings -> Cyber security: Marsik's checks, the user-CA protection (on by
/// default) and the opt-in extras (panic button, disguise, app lock).
class CyberSecurityScreen extends StatefulWidget {
  const CyberSecurityScreen({super.key});

  @override
  State<CyberSecurityScreen> createState() => _CyberSecurityScreenState();
}

class _CyberSecurityScreenState extends State<CyberSecurityScreen> {
  late final SecuritySettings _settings;
  final _localAuth = LocalAuthentication();

  late bool _trustUserCas;
  late bool _panicButton;
  late bool _appLock;
  bool _disguise = false;

  @override
  void initState() {
    super.initState();
    _settings = SecuritySettings(context.dependencyFactory.sharedPreferences);
    _trustUserCas = _settings.trustUserCas;
    _panicButton = _settings.panicButton;
    _appLock = _settings.appLock;
    _disguise = _settings.disguise;

    // The launcher alias is the source of truth (e.g. after a panic wipe
    // the preference is gone but the disguise stays).
    unawaited(
      SecurityPlatform.isDisguised().then((disguised) async {
        if (disguised != _settings.disguise) {
          await _settings.setDisguise(disguised);
        }
        if (mounted) {
          setState(() => _disguise = disguised);
        }
      }),
    );
  }

  Future<void> _setTrustUserCas(bool value) async {
    if (value) {
      final confirmed = await marsikConfirmSteps(
        context,
        steps: [context.ln.trustCasStep1, context.ln.trustCasStep2, context.ln.trustCasStep3],
      );
      if (!confirmed) {
        return;
      }
    }

    await _settings.setTrustUserCas(value);
    if (!mounted) {
      return;
    }

    setState(() => _trustUserCas = value);
    context.showInfoSnackBar(message: context.ln.reconnectToApply);
  }

  Future<void> _setPanicButton(bool value) async {
    await _settings.setPanicButton(value);
    if (!mounted) {
      return;
    }

    setState(() => _panicButton = value);
    if (value) {
      context.showInfoSnackBar(message: context.ln.panicEnabledHint);
    }
  }

  Future<void> _setDisguise(bool value) async {
    await SecurityPlatform.setDisguised(value);
    await _settings.setDisguise(value);
    if (!mounted) {
      return;
    }

    setState(() => _disguise = value);
    if (value) {
      context.showInfoSnackBar(message: context.ln.disguiseEnabledHint);
    }
  }

  /// Both turning the lock on and off require passing it once - otherwise
  /// whoever picked up the unlocked phone could simply switch it off.
  Future<void> _setAppLock(bool value) async {
    final report = await SecurityPlatform.deviceReport();
    final supported = await _localAuth.isDeviceSupported();
    if (!mounted) {
      return;
    }

    final deviceSecure = supported && (report?.deviceSecure ?? false);
    if (!deviceSecure) {
      if (value) {
        context.showInfoSnackBar(message: context.ln.appLockUnavailable);
      } else {
        // Nothing to authenticate with anymore - just let it be turned off.
        await _settings.setAppLock(false);
        if (mounted) {
          setState(() => _appLock = false);
        }
      }

      return;
    }

    bool authenticated;
    try {
      authenticated = await _localAuth.authenticate(localizedReason: context.ln.appLockReason);
    } catch (_) {
      authenticated = false;
    }
    if (!authenticated) {
      return;
    }

    await _settings.setAppLock(value);
    if (mounted) {
      setState(() => _appLock = value);
    }
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(text, style: context.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
  );

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(
        title: context.ln.cyberSecurity,
        leadingIconType: AppBarLeadingIconType.back,
        onBackPressed: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        children: [
          _header(context.ln.cyberChecksHeader),
          CustomArrowListTile(
            title: context.ln.phoneChecklist,
            onTap: () => context.push(const SecurityChecklistScreen()),
          ),
          CustomArrowListTile(
            title: context.ln.leakCheck,
            onTap: () => context.push(const LeakCheckScreen()),
          ),
          const Divider(),
          _header(context.ln.cyberProtectionHeader),
          // Shown as "strict check: on" - the stored setting is its inverse
          // (trusting user CAs = the engine's default, no system bundle).
          CustomSwitchTile(
            title: context.ln.trustUserCas,
            subtitle: context.ln.trustUserCasDescription,
            value: !_trustUserCas,
            onChanged: (strict) => _setTrustUserCas(!strict),
          ),
          const Divider(),
          _header(context.ln.cyberOptionalHeader),
          CustomSwitchTile(
            title: context.ln.panicButton,
            subtitle: context.ln.panicButtonDescription,
            value: _panicButton,
            onChanged: _setPanicButton,
          ),
          CustomSwitchTile(
            title: context.ln.disguise,
            subtitle: context.ln.disguiseDescription,
            value: _disguise,
            onChanged: _setDisguise,
          ),
          CustomSwitchTile(
            title: context.ln.appLock,
            subtitle: context.ln.appLockDescription,
            value: _appLock,
            onChanged: _setAppLock,
          ),
        ],
      ),
    ),
  );
}
