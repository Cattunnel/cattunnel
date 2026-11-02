import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';

/// The «City pop» theme: the app's own song (Surge XT, owner 02.11), played in
/// a loop while the City pop home is on screen and the person turned it on.
///
/// Off by default and remembered. It pauses when the app goes to the
/// background and stops when the City pop home goes away.
abstract interface class CityMusicPlayer {
  Future<void> play();

  Future<void> pause();

  Future<void> dispose();
}

/// The real player: created on the first play, so nothing touches the audio
/// plugin while the music is off.
class AudioplayersCityMusic implements CityMusicPlayer {
  static const asset = 'music/citypop_theme.ogg';

  AudioPlayer? _player;
  bool _ready = false;

  Future<AudioPlayer> _get() async {
    final player = _player ??= AudioPlayer();
    if (!_ready) {
      // The music is asked for: it takes the audio focus like any music app
      // and so pauses the person's own player.
      await player.setAudioContext(AudioContextConfig().build());
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(0.7);
      await player.setSource(AssetSource(asset));
      _ready = true;
    }

    return player;
  }

  @override
  Future<void> play() async => (await _get()).resume();

  @override
  Future<void> pause() async => _player?.pause();

  @override
  Future<void> dispose() async => _player?.dispose();
}

/// Holds the music while the City pop home is shown; [builder] draws the
/// button (on/off and the tap).
class CityMusicScope extends StatefulWidget {
  static const prefKey = 'citypop_music_on';

  final Widget Function(BuildContext context, bool on, VoidCallback toggle) builder;

  /// Tests put a fake player and their own preferences here.
  final CityMusicPlayer Function()? playerFactory;
  final SharedPreferences? preferences;

  const CityMusicScope({super.key, required this.builder, this.playerFactory, this.preferences});

  @override
  State<CityMusicScope> createState() => _CityMusicScopeState();
}

class _CityMusicScopeState extends State<CityMusicScope> with WidgetsBindingObserver {
  late final CityMusicPlayer _player = (widget.playerFactory ?? AudioplayersCityMusic.new)();
  bool _on = false;
  bool _foreground = true;

  SharedPreferences get _prefs => widget.preferences ?? context.dependencyFactory.sharedPreferences;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _on = _prefs.getBool(CityMusicScope.prefKey) ?? false;
      setState(() {});
      _sync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
  }

  void _sync() {
    final play = _on && _foreground;
    unawaited((play ? _player.play() : _player.pause()).catchError((_) {}));
  }

  void _toggle() {
    setState(() => _on = !_on);
    unawaited(_prefs.setBool(CityMusicScope.prefKey, _on));
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_player.pause().catchError((_) {}).whenComplete(() => _player.dispose().catchError((_) {})));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _on, _toggle);
}
