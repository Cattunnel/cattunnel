import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/onboarding/widgets/onboarding_tutorial.dart';
import 'package:video_player/video_player.dart';

/// Marsik's ~24 s intro film (two Veo clips + our ending with the wordmark).
/// Played once before the onboarding on a fresh install, and on demand from
/// About. video_player has no Windows/Linux implementation, so desktop builds
/// skip it and hide the About button.
class IntroFilm {
  static const asset = 'assets/video/marsik_intro.mp4';
  static const _seenKey = 'intro_film_seen';

  const IntroFilm._();

  static bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Fresh installs only: someone who already went through the onboarding
  /// updated from an older version and isn't shown the film unasked.
  static Future<void> maybeShow(BuildContext context) async {
    final preferences = context.dependencyFactory.sharedPreferences;
    if (preferences.getBool(_seenKey) ?? false) {
      return;
    }
    await preferences.setBool(_seenKey, true);
    final freshInstall = !(preferences.getBool(OnboardingTutorial.seenKey) ?? false);
    if (!supported || !freshInstall || !context.mounted) {
      return;
    }
    await show(context, firstLaunch: true);
  }

  static Future<void> show(BuildContext context, {bool firstLaunch = false}) =>
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder<void>(
          pageBuilder: (_, _, _) => _IntroFilmView(firstLaunch: firstLaunch),
          transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
        ),
      );
}

class _IntroFilmView extends StatefulWidget {
  /// First launch starts muted (sound could startle) and says "Skip";
  /// from About it plays with sound and says "Close".
  final bool firstLaunch;

  const _IntroFilmView({required this.firstLaunch});

  @override
  State<_IntroFilmView> createState() => _IntroFilmViewState();
}

class _IntroFilmViewState extends State<_IntroFilmView> {
  // The film's own backdrop and Marsik's outline colour, so the frame blends
  // into the screen in both themes.
  static const _backdrop = Color(0xFFEAF2FF);
  static const _ink = Color(0xFF0F2147);

  late final VideoPlayerController _controller;
  late bool _muted = widget.firstLaunch;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      IntroFilm.asset,
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    )..addListener(_onTick);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      await _controller.setVolume(_muted ? 0 : 1);
      await _controller.play();
      if (mounted) setState(() {});
    } catch (_) {
      // A broken decoder must never block the first launch.
      _close();
    }
  }

  void _onTick() {
    final value = _controller.value;
    if (value.isInitialized && !value.isPlaying && value.position >= value.duration) {
      _close();
    }
  }

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  Future<void> _toggleSound() async {
    setState(() => _muted = !_muted);
    await _controller.setVolume(_muted ? 0 : 1);
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onTick)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _backdrop,
    body: SafeArea(
      child: Stack(
        children: [
          Center(
            child: _controller.value.isInitialized
                ? AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  )
                : const SizedBox.shrink(),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: TextButton(
              style: TextButton.styleFrom(foregroundColor: _ink),
              onPressed: _close,
              child: Text(widget.firstLaunch ? context.ln.onboardingSkip : context.ln.introFilmClose),
            ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: IconButton(
              color: _ink,
              tooltip: _muted ? context.ln.introFilmSoundOn : context.ln.introFilmSoundOff,
              icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
              onPressed: _toggleSound,
            ),
          ),
        ],
      ),
    ),
  );
}
