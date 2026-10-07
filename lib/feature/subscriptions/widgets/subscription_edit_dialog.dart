import 'package:dage/dage.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/widgets/common/custom_switch_tile.dart';
import 'package:trusttunnel/widgets/custom_alert_dialog.dart';
import 'package:trusttunnel/widgets/inputs/custom_text_field.dart';
import 'package:trusttunnel/widgets/secure_screen.dart';

/// Add/edit dialog for a subscription. Pops with the resulting
/// [SubscriptionData], or `null` if cancelled.
class SubscriptionEditDialog extends StatefulWidget {
  final SubscriptionData? initial;

  /// Add mode, but with the fields filled in (e.g. from a scanned share QR).
  /// Ignored when [initial] is set.
  final SubscriptionData? prefill;

  const SubscriptionEditDialog({
    super.key,
    this.initial,
    this.prefill,
  });

  @override
  State<SubscriptionEditDialog> createState() => _SubscriptionEditDialogState();
}

class _SubscriptionEditDialogState extends State<SubscriptionEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _ageKeyController;
  late bool _skipVerification;
  String? _urlError;
  String? _ageKeyError;
  bool _ageKeyVisible = false;

  @override
  void initState() {
    super.initState();
    final seed = widget.initial ?? widget.prefill;
    _nameController = TextEditingController(text: seed?.name ?? '');
    _urlController = TextEditingController(text: seed?.url ?? '');
    _ageKeyController = TextEditingController(text: seed?.agePrivateKey ?? '');
    _skipVerification = seed?.skipVerification ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _ageKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SecureScreen(child: _buildDialog(context));

  Widget _buildDialog(BuildContext context) => CustomAlertDialog(
    title: widget.initial == null ? context.ln.addSubscription : context.ln.editSubscription,
    scrollable: true,
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CustomTextField(
          controller: _nameController,
          label: context.ln.subscriptionNameLabel,
          hint: context.ln.subscriptionNameHint,
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: _urlController,
          label: context.ln.subscriptionUrlLabel,
          hint: 'https://...',
          error: _urlError,
        ),
        const SizedBox(height: 8),
        CustomSwitchTile(
          title: context.ln.subscriptionSkipVerification,
          value: _skipVerification,
          onChanged: (value) => setState(() => _skipVerification = value),
        ),
        const SizedBox(height: 16),
        CustomTextField.customSuffixIcon(
          controller: _ageKeyController,
          label: context.ln.subscriptionAgeKeyLabel,
          hint: context.ln.subscriptionAgeKeyHint,
          helper: context.ln.subscriptionAgeKeyHelper,
          error: _ageKeyError,
          obscureText: !_ageKeyVisible,
          suffixIcon: IconButton(
            icon: Icon(_ageKeyVisible ? AssetIcons.eye : AssetIcons.eyeClosed),
            onPressed: () => setState(() => _ageKeyVisible = !_ageKeyVisible),
          ),
        ),
      ],
    ),
    actionsBuilder: (spacing) => [
      TextButton(
        onPressed: context.pop,
        child: Text(context.ln.cancel),
      ),
      TextButton(
        onPressed: _onSave,
        child: Text(context.ln.save),
      ),
    ],
  );

  void _onSave() {
    // Several mirrors of one subscription may be given as "a | b".
    final urls = SubscriptionData.splitUrls(_urlController.text).map(Uri.tryParse).toList();

    if (urls.isEmpty || urls.any((url) => url == null || !url.hasScheme || !url.isAbsolute)) {
      setState(() => _urlError = context.ln.subscriptionInvalidUrlError);

      return;
    }

    if (urls.any((url) => url!.scheme != 'https')) {
      setState(() => _urlError = context.ln.subscriptionHttpsOnlyError);

      return;
    }

    final url = urls.first!;

    final ageKeyText = _ageKeyController.text.trim();
    String? ageKey;

    if (ageKeyText.isNotEmpty) {
      try {
        AgeIdentity.fromBech32(ageKeyText);
        ageKey = ageKeyText;
      } catch (_) {
        setState(() => _ageKeyError = context.ln.subscriptionAgeKeyInvalidError);

        return;
      }
    }

    final name = _nameController.text.trim();

    context.pop(
      result: SubscriptionData(
        name: name.isEmpty ? url.host : name,
        url: SubscriptionData.joinUrls(urls.map((url) => url.toString()).toList()),
        skipVerification: _skipVerification,
        autoRefreshEnabled: widget.initial?.autoRefreshEnabled ?? true,
        agePrivateKey: ageKey,
      ),
    );
  }
}
