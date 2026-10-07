import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/companion/domain/cat_compliments.dart';
import 'package:trusttunnel/feature/companion/domain/cat_owner_preferences.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_companion.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_intro_dialog.dart';
import 'package:trusttunnel/feature/companion/widgets/cat_poem_dialogs.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/security/widgets/marsik_confirm.dart';
import 'package:trusttunnel/feature/vpn/widgets/vpn_scope.dart';

/// The actual "petting" interaction, opened from [CatPettingButton]: stroke
/// (drag) across the cat to pet it, or tap it several times fast and it
/// tells you off instead.
///
/// Every stroke sends a heart floating up and fills the progress bar a bit;
/// a full bar earns a compliment (plus a random "petted" pose) and drops back
/// to half, so the next one takes half as many strokes. Occasionally the
/// compliment is swapped for an easter egg - a random [catRareFacts] line,
/// or a guaranteed [catMilestoneLine] on round total pet counts.
class CatPettingDialog extends StatefulWidget {
  const CatPettingDialog({super.key});

  /// Resolves to whether the user actually petted him at least once this
  /// session (false/null if they just looked, or he stormed off early).
  static Future<bool?> show(BuildContext context) => showDialog<bool>(
    context: context,
    barrierColor: Colors.black45,
    builder: (_) => const CatPettingDialog(),
  );

  @override
  State<CatPettingDialog> createState() => _CatPettingDialogState();
}

class _CatPettingDialogState extends State<CatPettingDialog> with SingleTickerProviderStateMixin {
  static const _hitTapThreshold = 4;
  static const _hitTapWindow = Duration(seconds: 1);
  static const _petDragThreshold = 28.0;

  /// Strokes to fill the bar from empty; after a compliment it restarts
  /// from [_progressAfterCompliment].
  static const _strokesPerFullBar = 10;
  static const _progressAfterCompliment = 0.5;

  /// 1 in N compliments becomes a [catRareFacts] easter egg instead.
  static const _rareFactChance = 10;

  /// Purring keeps going this long after the last stroke.
  static const _purrTail = Duration(milliseconds: 1200);

  /// CC0 recording (freesound.org/s/496275), trimmed to a seamless 10s loop.
  static const _purrAsset = 'sounds/cat_purr.ogg';

  /// How many separate rapid-tap bursts (each already an "Эй, гладь, а не
  /// бей!" reaction) it takes before Marsik has had enough and leaves.
  static const _hitBurstsBeforeLeaving = 3;

  static final _random = Random();

  late final AnimationController _wobbleController;
  late final CatOwnerPreferences _owner;
  final _purrPlayer = AudioPlayer();

  final _recentTaps = <DateTime>[];
  double _dragSinceLastPet = 0;
  int _hitBursts = 0;
  bool _pettedThisSession = false;
  bool _leaving = false;
  String? _overrideAsset;
  Timer? _overrideTimer;

  double _progress = 0;
  late int _petCount;
  late bool _purrEnabled;
  bool _purring = false;
  Timer? _purrStopTimer;

  final _hearts = <_HeartData>[];
  int _nextHeartId = 0;

  String? _lastCompliment;
  String? _lastPose;

  /// The compliment bubble and the hit-reaction bubble (rapid taps) are
  /// independent - a compliment mid-display shouldn't get eaten by, or
  /// block, a hit reaction and vice versa.
  String? _complimentText;
  Timer? _complimentTimer;
  String? _hitText;
  Timer? _hitTimer;

  @override
  void initState() {
    super.initState();
    _wobbleController = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _owner = CatOwnerPreferences(context.dependencyFactory.sharedPreferences);
    _petCount = _owner.petCount;
    _purrEnabled = _owner.purrEnabled;
    unawaited(_preparePurr());
  }

  @override
  void dispose() {
    _wobbleController.dispose();
    _overrideTimer?.cancel();
    _complimentTimer?.cancel();
    _hitTimer?.cancel();
    _purrStopTimer?.cancel();
    unawaited(_purrPlayer.dispose());
    super.dispose();
  }

  Future<void> _preparePurr() async {
    try {
      // Mix with whatever else is playing instead of taking audio focus -
      // petting the cat must never pause the user's music.
      await _purrPlayer.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      await _purrPlayer.setReleaseMode(ReleaseMode.loop);
      await _purrPlayer.setSource(AssetSource(_purrAsset));
    } catch (_) {
      // No sound is fine - petting still works without it.
    }
  }

  void _purrWhilePetting() {
    if (!_purrEnabled) {
      return;
    }

    if (!_purring) {
      _purring = true;
      unawaited(_purrPlayer.resume().catchError((_) {}));
    }

    _purrStopTimer?.cancel();
    _purrStopTimer = Timer(_purrTail, _stopPurring);
  }

  void _stopPurring() {
    _purrStopTimer?.cancel();
    if (_purring) {
      _purring = false;
      unawaited(_purrPlayer.pause().catchError((_) {}));
    }
  }

  Future<void> _togglePurr() async {
    final enabled = !_purrEnabled;
    setState(() => _purrEnabled = enabled);
    if (!enabled) {
      _stopPurring();
    }
    await _owner.setPurrEnabled(enabled);
  }

  void _showBubble(String text, {required Duration duration}) {
    _complimentTimer?.cancel();
    setState(() => _complimentText = text);
    _complimentTimer = Timer(duration, () {
      if (mounted) {
        setState(() => _complimentText = null);
      }
    });
  }

  void _showCatOverride(String asset, {required Duration duration}) {
    _overrideTimer?.cancel();
    setState(() => _overrideAsset = asset);
    _overrideTimer = Timer(duration, () {
      if (mounted) {
        setState(() => _overrideAsset = null);
      }
    });
  }

  /// Picks from [options], avoiding [previous] when there's any choice.
  static String _pickDifferent(List<String> options, String? previous) {
    final candidates = options.length > 1 ? options.where((option) => option != previous).toList() : options;

    return candidates[_random.nextInt(candidates.length)];
  }

  void _onPetStroke(Offset position) {
    if (_leaving) {
      return;
    }

    _pettedThisSession = true;
    unawaited(_wobbleController.forward(from: 0).then((_) => _wobbleController.reverse()));
    _purrWhilePetting();

    _petCount += 1;
    unawaited(_owner.setPetCount(_petCount));

    setState(() {
      _hearts.add(_HeartData(id: _nextHeartId++, position: position));
      _progress = min(1, _progress + 1 / _strokesPerFullBar);
    });

    final milestone = catMilestoneLine(_petCount);
    if (milestone != null) {
      _reward(milestone, bubbleDuration: const Duration(seconds: 5));

      return;
    }

    if (_progress < 1) {
      return;
    }

    if (_random.nextInt(_rareFactChance) == 0) {
      _reward(catRareFacts[_random.nextInt(catRareFacts.length)], bubbleDuration: const Duration(seconds: 4));

      return;
    }

    final pool = catComplimentsFor(name: _owner.name, gender: _owner.gender);
    final compliment = _pickDifferent(pool, _lastCompliment);
    _lastCompliment = compliment;
    _reward(compliment, bubbleDuration: const Duration(seconds: 2));
  }

  /// A compliment (or easter egg): speech bubble, a fresh "petted" pose, and
  /// the bar drops back to half.
  void _reward(String text, {required Duration bubbleDuration}) {
    final pose = _pickDifferent(AssetImages.catsPetted, _lastPose);
    _lastPose = pose;

    setState(() => _progress = _progressAfterCompliment);
    _showBubble(text, duration: bubbleDuration);
    _showCatOverride(pose, duration: const Duration(seconds: 2));
  }

  void _onTapDown() {
    if (_leaving) {
      return;
    }

    final now = DateTime.now();
    _recentTaps
      ..add(now)
      ..removeWhere((t) => now.difference(t) > _hitTapWindow);

    if (_recentTaps.length < _hitTapThreshold) {
      return;
    }

    _recentTaps.clear();
    _hitBursts += 1;

    if (_hitBursts >= _hitBurstsBeforeLeaving) {
      unawaited(_leave());

      return;
    }

    _showCatOverride(AssetImages.catAlert, duration: const Duration(milliseconds: 1500));
    _hitTimer?.cancel();
    setState(() => _hitText = context.ln.catHitReaction);
    _hitTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _hitText = null);
      }
    });
  }

  /// Marsik has had enough: he storms off, and won't be pettable again for
  /// [CatOwnerPreferences.sulkDuration].
  Future<void> _leave() async {
    _overrideTimer?.cancel();
    _hitTimer?.cancel();
    _complimentTimer?.cancel();
    _stopPurring();

    await _owner.startSulking();
    if (!mounted) {
      return;
    }

    setState(() {
      _leaving = true;
      _overrideAsset = AssetImages.catAlert;
      _hitText = null;
      _complimentText = null;
    });

    await Future.delayed(const Duration(milliseconds: 1800));
    if (mounted) {
      Navigator.of(context).pop(_pettedThisSession);
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_leaving) {
      return;
    }

    _dragSinceLastPet += details.delta.distance;
    if (_dragSinceLastPet < _petDragThreshold) {
      return;
    }

    _dragSinceLastPet = 0;
    _onPetStroke(details.localPosition);
  }

  @override
  Widget build(BuildContext context) {
    final stateAsset = CatCompanion.assetFor(VpnScope.vpnControllerOf(context).state);
    final asset = _overrideAsset ?? stateAsset;
    final bubbleText = _leaving ? context.ln.catLeavingMessage : (_hitText ?? _complimentText);
    final isHitBubble = _leaving || _hitText != null;

    // Large system fonts (grandparents' phones): the bubble grows with the
    // text, the cat shrinks a little, and the dialog scrolls if it still
    // doesn't fit.
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 3.0);

    return Dialog(
      backgroundColor: context.colors.backgroundSystem,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: _leaving ? null : _togglePurr,
                tooltip: _purrEnabled ? context.ln.catPurrOn : context.ln.catPurrOff,
                icon: Icon(
                  _purrEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                  color: _purrEnabled ? context.colors.accent : context.colors.neutralLight,
                ),
              ),
            ),
            SizedBox(
              height: 60 * textScale,
              child: Center(
                child: AnimatedOpacity(
                  opacity: bubbleText != null ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    bubbleText ?? '',
                    textAlign: TextAlign.center,
                    style: context.textTheme.bodyMedium?.copyWith(
                      color: isHitBubble ? context.colors.error : context.colors.accent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTapDown: (_) => _onTapDown(),
              onPanUpdate: _onPanUpdate,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedBuilder(
                    animation: _wobbleController,
                    builder: (_, child) => Transform.rotate(
                      angle: sin(_wobbleController.value * pi * 3) * 0.06,
                      child: child,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Image.asset(asset, key: ValueKey(asset), height: 200 / textScale.clamp(1.0, 1.6)),
                    ),
                  ),
                  for (final heart in _hearts)
                    _FloatingHeart(
                      key: ValueKey(heart.id),
                      position: heart.position,
                      onDone: () {
                        if (mounted) {
                          setState(() => _hearts.remove(heart));
                        }
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _PetProgressBar(value: _progress),
            const SizedBox(height: 8),
            Text(
              context.ln.catPetCounter(_petCount),
              style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralLight),
            ),
            const SizedBox(height: 12),
            Text(
              context.ln.catPetHint,
              style: context.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (!_leaving)
              TextButton(
                onPressed: () => Navigator.of(context).pop(_pettedThisSession),
                child: Text(context.ln.gotIt),
              ),
          ],
        ),
      ),
    );
  }
}

class _PetProgressBar extends StatelessWidget {
  final double value;

  const _PetProgressBar({required this.value});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: value),
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
    builder: (_, animatedValue, _) => ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: animatedValue,
        minHeight: 8,
        color: context.colors.accent,
        backgroundColor: context.colors.accent.withValues(alpha: 0.15),
      ),
    ),
  );
}

class _HeartData {
  final int id;
  final Offset position;

  const _HeartData({required this.id, required this.position});
}

/// One heart rising from where the finger stroked, drifting sideways a
/// little and fading out, then removing itself via [onDone].
class _FloatingHeart extends StatefulWidget {
  final Offset position;
  final VoidCallback onDone;

  const _FloatingHeart({required this.position, required this.onDone, super.key});

  @override
  State<_FloatingHeart> createState() => _FloatingHeartState();
}

class _FloatingHeartState extends State<_FloatingHeart> with SingleTickerProviderStateMixin {
  static const _size = 22.0;
  static const _rise = 110.0;

  static final _random = Random();

  late final AnimationController _controller;
  late final double _drift;
  late final double _phase;

  @override
  void initState() {
    super.initState();
    _drift = 8 + _random.nextDouble() * 10;
    _phase = _random.nextDouble() * pi * 2;
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (_, child) {
      final t = Curves.easeOut.transform(_controller.value);

      return Positioned(
        left: widget.position.dx - _size / 2 + sin(_phase + t * pi * 2) * _drift,
        top: widget.position.dy - _size / 2 - t * _rise,
        child: IgnorePointer(
          child: Opacity(
            opacity: 1 - _controller.value,
            child: Transform.scale(scale: 0.7 + t * 0.5, child: child),
          ),
        ),
      );
    },
    child: const Icon(Icons.favorite_rounded, color: Colors.pinkAccent, size: _size),
  );
}

/// Square tile (matching the "Add servers" FAB's size) placed at the
/// bottom-left of the servers screen - opens [CatPettingDialog].
class CatPettingButton extends StatelessWidget {
  const CatPettingButton({super.key});

  @override
  Widget build(BuildContext context) {
    final asset = CatCompanion.assetFor(VpnScope.vpnControllerOf(context).state);

    return Material(
      color: context.theme.floatingActionButtonTheme.backgroundColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _onTap(context),
        onLongPress: () => _onLongPress(context),
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Image.asset(asset, height: 36),
          ),
        ),
      ),
    );
  }

  /// Panic button (Cyber security section, opt-in): one confirmation - it
  /// has to be quick - then everything the app holds is wiped.
  Future<void> _onLongPress(BuildContext context) async {
    if (!SecuritySettings(context.dependencyFactory.sharedPreferences).panicButton) {
      return;
    }

    final confirmed = await marsikConfirmSteps(
      context,
      steps: [context.ln.panicConfirmBody],
      title: context.ln.panicConfirmTitle,
      confirmLabel: context.ln.panicConfirmAction,
      destructive: true,
    );
    if (confirmed) {
      await SecurityPlatform.wipeAllData();
    }
  }

  Future<void> _onTap(BuildContext context) async {
    final owner = CatOwnerPreferences(context.dependencyFactory.sharedPreferences);

    final sulking = owner.sulkingRemaining;
    if (sulking != null) {
      context.showInfoSnackBar(
        message: context.ln.catSulkingMessage(sulking.inHours, sulking.inMinutes.remainder(60)),
      );

      return;
    }

    if (!owner.introDone) {
      await CatIntroDialog.show(context);
    }

    if (!context.mounted) {
      return;
    }

    final petted = await CatPettingDialog.show(context);

    // Occasionally offer a poem after an actual petting session - never
    // right after he stormed off, and never if there's nothing to offer.
    if (petted == true && context.mounted && Random().nextInt(3) == 0) {
      await CatPoemOfferDialog.maybeShow(context);
    }
  }
}
