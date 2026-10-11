import 'dart:math';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/own_style.dart';
import 'package:trusttunnel/feature/companion/domain/cat_poems.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';

/// Small "want to read one of my poems?" prompt, offered occasionally after
/// petting (see [CatPettingDialog]) - only ever shown when [catPoems] isn't
/// empty.
class CatPoemOfferDialog extends StatelessWidget {
  const CatPoemOfferDialog({super.key});

  static Future<void> maybeShow(BuildContext context) async {
    if (catPoems.isEmpty || !context.mounted) {
      return;
    }

    final wantsToRead = await showDialog<bool>(
      context: context,
      builder: (_) => const CatPoemOfferDialog(),
    );

    if (wantsToRead == true && context.mounted) {
      await CatPoemDialog.show(context);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.hasOwnStyle ? null : context.colors.backgroundSystem,
    shape: context.hasOwnStyle ? null : RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MarsikImage(AssetImages.catFace, height: 72),
          const SizedBox(height: 12),
          Text(
            context.ln.catPoemOfferQuestion,
            textAlign: TextAlign.center,
            style: context.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.ln.catPoemOfferNo),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(context.ln.catPoemOfferYes),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Shows one random poem from [catPoems], with its real author credited in
/// small print - the poems are by the CatTunnel author, Marsik is just reciting them.
class CatPoemDialog extends StatefulWidget {
  const CatPoemDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const CatPoemDialog(),
  );

  @override
  State<CatPoemDialog> createState() => _CatPoemDialogState();
}

class _CatPoemDialogState extends State<CatPoemDialog> {
  /// Picked once, so a rebuild doesn't swap the poem mid-reading.
  int? _index;

  @override
  Widget build(BuildContext context) {
    // English for everyone but Russian readers, when the translation is there.
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    final poems = russian || catPoemsEn.length != catPoems.length ? catPoems : catPoemsEn;
    final poem = poems[_index ??= Random().nextInt(poems.length)];

    return Dialog(
      backgroundColor: context.hasOwnStyle ? null : context.colors.backgroundSystem,
      shape: context.hasOwnStyle ? null : RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              poem,
              textAlign: TextAlign.center,
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text(
              context.ln.catPoemAuthor,
              style: context.textTheme.bodySmall?.copyWith(color: context.theme.disabledColor),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.ln.gotIt),
            ),
          ],
        ),
      ),
    );
  }
}
