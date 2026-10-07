import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/feature/companion/domain/cat_owner_preferences.dart';

/// One-time introduction shown the first time the cat petting button is
/// opened: Marsik introduces himself and (entirely optionally) asks for a
/// name and gender so [catCompliments] can address you correctly and by
/// name. Explains up front that this stays on-device - CatTunnel has no
/// server to send it to.
class CatIntroDialog extends StatefulWidget {
  const CatIntroDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black45,
    builder: (_) => const CatIntroDialog(),
  );

  @override
  State<CatIntroDialog> createState() => _CatIntroDialogState();
}

class _CatIntroDialogState extends State<CatIntroDialog> {
  int _step = 0;
  CatOwnerGender? _gender;
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final preferences = CatOwnerPreferences(context.dependencyFactory.sharedPreferences);
    await preferences.save(name: _nameController.text, gender: _gender);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: context.colors.backgroundSystem,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    // Scrolls with a large system font - the buttons fell off the dialog.
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AssetImages.catWave, height: 120),
          const SizedBox(height: 16),
          switch (_step) {
            0 => _IntroStep(
              text:
                  'Привет! Я Марсик 👋\n\n'
                  'Хочешь, чтобы мои комплименты звучали естественнее? '
                  'Тогда расскажи мне о себе пару вещей — это останется только у тебя на телефоне. '
                  'У CatTunnel даже своего сервера для этого нет: я ничего никуда не отправляю.',
              buttonText: 'Давай',
              onNext: () => setState(() => _step = 1),
              onSkip: _finish,
            ),
            1 => _IntroStep(
              text: 'Ты хозяин или хозяйка?',
              onSkip: () => setState(() => _step = 2),
              customAction: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: () {
                      _gender = CatOwnerGender.host;
                      setState(() => _step = 2);
                    },
                    child: const Text('Хозяин'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () {
                      _gender = CatOwnerGender.hostess;
                      setState(() => _step = 2);
                    },
                    child: const Text('Хозяйка'),
                  ),
                ],
              ),
            ),
            _ => _IntroStep(
              text: 'А как тебя зовут?',
              customAction: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TextField(
                  controller: _nameController,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(hintText: 'Имя (необязательно)'),
                ),
              ),
              buttonText: 'Готово',
              onNext: _finish,
              onSkip: _finish,
            ),
          },
        ],
      ),
    ),
  );
}

class _IntroStep extends StatelessWidget {
  final String text;
  final Widget? customAction;
  final String? buttonText;
  final VoidCallback? onNext;
  final VoidCallback onSkip;

  const _IntroStep({
    required this.text,
    required this.onSkip,
    this.customAction,
    this.buttonText,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text, textAlign: TextAlign.center, style: context.textTheme.bodyMedium),
      const SizedBox(height: 16),
      if (customAction != null) customAction!,
      if (buttonText != null) FilledButton(onPressed: onNext, child: Text(buttonText!)) else const SizedBox(height: 4),
      TextButton(onPressed: onSkip, child: const Text('Пропустить')),
    ],
  );
}
