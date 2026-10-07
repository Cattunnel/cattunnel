import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/generated/l10n.dart';
import 'package:trusttunnel/common/localization/localization.dart';

/// Target for the "add a server" spotlight step - [ServersEmptyPlaceholder]
/// attaches this to its button. A plain top-level [GlobalKey] instead of a
/// constructor parameter threaded through every intermediate widget, since
/// this is the standard, low-footprint way to wire up a single coach-mark
/// target without prop-drilling through unrelated widgets.
final onboardingAddServerButtonKey = GlobalKey(debugLabel: 'onboarding_add_server_button');

class _OnboardingStep {
  final String cat;
  final String Function(AppLocalizations ln) title;
  final String Function(AppLocalizations ln) description;

  /// If set, this step spotlights (cuts a hole around) that widget's current
  /// bounds. Left null when there is nothing reliable to point at yet (e.g.
  /// a specific bottom-nav tab, which Flutter's NavigationBar doesn't expose
  /// a per-item key for) - the step is then just an informational card.
  final GlobalKey? spotlightKey;

  const _OnboardingStep({
    required this.cat,
    required this.title,
    required this.description,
    this.spotlightKey,
  });
}

final _steps = [
  _OnboardingStep(
    cat: AssetImages.catWave,
    title: (ln) => ln.onboardingWelcomeTitle,
    description: (ln) => ln.onboardingWelcomeDescription,
  ),
  _OnboardingStep(
    cat: AssetImages.catMagnifier,
    title: (ln) => ln.onboardingAddTitle,
    description: (ln) => ln.onboardingAddDescription,
    spotlightKey: onboardingAddServerButtonKey,
  ),
  _OnboardingStep(
    cat: AssetImages.catShield,
    title: (ln) => ln.onboardingConnectTitle,
    description: (ln) => ln.onboardingConnectDescription,
  ),
  _OnboardingStep(
    cat: AssetImages.catGear,
    title: (ln) => ln.onboardingAutoConnectTitle,
    description: (ln) => ln.onboardingAutoConnectDescription,
  ),
];

/// A short, once-per-install cat-illustrated walkthrough shown from
/// [NavigationScreen] on first launch. Uses an [OverlayEntry] (not a route/
/// dialog) so the real screen stays visible and reachable behind the dimmed
/// spotlight hole - a dialog's own opaque route would hide it instead.
class OnboardingTutorial {
  /// Also read by [IntroFilm]: set means this is not a fresh install.
  static const seenKey = 'onboarding_tutorial_seen';

  const OnboardingTutorial._();

  static Future<void> maybeShow(BuildContext context) async {
    final preferences = context.dependencyFactory.sharedPreferences;

    if (preferences.getBool(seenKey) ?? false) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    final completer = Completer<void>();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _OnboardingOverlayView(
        onFinished: () {
          entry.remove();
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(entry);
    await completer.future;
    await preferences.setBool(seenKey, true);
  }
}

class _OnboardingOverlayView extends StatefulWidget {
  final VoidCallback onFinished;

  const _OnboardingOverlayView({required this.onFinished});

  @override
  State<_OnboardingOverlayView> createState() => _OnboardingOverlayViewState();
}

class _OnboardingOverlayViewState extends State<_OnboardingOverlayView> {
  int _step = 0;

  Rect? _spotlightRect() {
    final key = _steps[_step].spotlightKey;
    final renderObject = key?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) {
      return null;
    }

    final origin = renderObject.localToGlobal(Offset.zero);

    return (origin & renderObject.size).inflate(8);
  }

  void _advance() {
    if (_step == _steps.length - 1) {
      widget.onFinished();

      return;
    }

    setState(() => _step += 1);
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_step];
    final spotlightRect = _spotlightRect();
    final screenSize = MediaQuery.sizeOf(context);

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _advance,
              child: CustomPaint(
                painter: _SpotlightPainter(spotlightRect),
                size: Size.infinite,
              ),
            ),
          ),
          _SpeechBubble(
            step: step,
            spotlightRect: spotlightRect,
            screenSize: screenSize,
            isLast: _step == _steps.length - 1,
            onSkip: widget.onFinished,
            onNext: _advance,
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? rect;

  const _SpotlightPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.72);

    final rect = this.rect;
    if (rect == null) {
      canvas.drawPath(overlay, dim);

      return;
    }

    final hole = Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(20)));

    canvas.drawPath(Path.combine(PathOperation.difference, overlay, hole), dim);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.rect != rect;
}

/// A cat with a speech-bubble card, placed above the spotlighted area when
/// there's room, below it otherwise, or centered when there's nothing to
/// spotlight this step.
class _SpeechBubble extends StatelessWidget {
  final _OnboardingStep step;
  final Rect? spotlightRect;
  final Size screenSize;
  final bool isLast;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _SpeechBubble({
    required this.step,
    required this.spotlightRect,
    required this.screenSize,
    required this.isLast,
    required this.onSkip,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final rect = spotlightRect;
    final belowSpotlight = rect != null && rect.top > screenSize.height * 0.55;

    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.colors.backgroundSystem,
        borderRadius: BorderRadius.circular(24),
      ),
      // Scrolls inside when a large system font makes it taller than the
      // space next to the spotlight.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Image.asset(step.cat, height: 64),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.title(context.ln),
                    style: context.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              step.description(context.ln),
              style: context.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            // Wraps onto two lines instead of overflowing with a large font.
            OverflowBar(
              alignment: MainAxisAlignment.spaceBetween,
              overflowAlignment: OverflowBarAlignment.end,
              overflowSpacing: 8,
              children: [
                TextButton(
                  onPressed: onSkip,
                  child: Text(context.ln.onboardingSkip),
                ),
                FilledButton(
                  onPressed: onNext,
                  child: Text(isLast ? context.ln.onboardingDone : context.ln.onboardingNext),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (rect == null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenSize.height - 48),
          child: card,
        ),
      );
    }

    final room = belowSpotlight ? rect.top - 16 - 24 : screenSize.height - rect.bottom - 16 - 24;

    return Positioned(
      left: 0,
      right: 0,
      top: belowSpotlight ? null : rect.bottom + 16,
      bottom: belowSpotlight ? screenSize.height - rect.top + 16 : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: room < 160 ? 160 : room),
        child: card,
      ),
    );
  }
}
