import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/asset_icons.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';

enum AddServerOption { manual, qrCode, link, subscription, configFile }

/// Bottom sheet offering every way to add a server: manual entry, QR scan,
/// pasted link or a subscription; on Linux/Windows a config file (the bot's
/// Linux/PC .toml) takes the QR scanner's place. Pops with the chosen
/// [AddServerOption], or `null` if dismissed without a choice.
class AddServerOptionsSheet extends StatelessWidget {
  const AddServerOptionsSheet({super.key});

  static bool get _desktop =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.linux || defaultTargetPlatform == TargetPlatform.windows);

  static Future<AddServerOption?> show(BuildContext context) => showModalBottomSheet<AddServerOption>(
    context: context,
    showDragHandle: true,
    // Can grow (and scroll) with a large system font.
    isScrollControlled: true,
    builder: (_) => const AddServerOptionsSheet(),
  );

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // A fixed-width slot (rather than the image's own intrinsic
              // width) mirrored by the empty SizedBox below - keeps the
              // title centered on the whole row regardless of this asset's
              // aspect ratio.
              const SizedBox(
                width: 56,
                child: Center(
                  child: Image(image: AssetImage(AssetImages.catFace), height: 36, fit: BoxFit.contain),
                ),
              ),
              Expanded(
                child: Text(
                  context.ln.addServerSheetTitle,
                  textAlign: TextAlign.center,
                  style: context.textTheme.titleMedium,
                ),
              ),
              const SizedBox(width: 56),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _OptionBox(
                    icon: AssetIcons.modeEdit,
                    label: context.ln.addManuallyOption,
                    onTap: () => Navigator.of(context).pop(AddServerOption.manual),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  // The in-app scanner works on phones only; a desktop gets
                  // the bot's config file in that slot instead - an even 2x2
                  // grid either way.
                  child: _desktop
                      ? _OptionBox(
                          icon: Icons.file_open_outlined,
                          label: context.ln.importConfigFileOption,
                          onTap: () => Navigator.of(context).pop(AddServerOption.configFile),
                        )
                      : _OptionBox(
                          icon: Icons.qr_code_scanner,
                          label: context.ln.scanQrCode,
                          onTap: () => Navigator.of(context).pop(AddServerOption.qrCode),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _OptionBox(
                    icon: AssetIcons.attach,
                    label: context.ln.importLinkOption,
                    onTap: () => Navigator.of(context).pop(AddServerOption.link),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _OptionBox(
                    icon: Icons.rss_feed,
                    label: context.ln.subscriptions,
                    onTap: () => Navigator.of(context).pop(AddServerOption.subscription),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _OptionBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OptionBox({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: context.colors.backgroundSystem,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        // center (not the default start) so that once IntrinsicHeight
        // equalizes both tiles in a row, the shorter label's icon+text
        // still sits centered in the extra height instead of hugging top.
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomIcon(icon: icon, size: 28, color: context.colors.accent),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    ),
  );
}
