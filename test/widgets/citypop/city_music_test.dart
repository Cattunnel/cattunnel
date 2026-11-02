import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/widgets/citypop/city_music.dart';

class _FakePlayer implements CityMusicPlayer {
  final log = <String>[];

  @override
  Future<void> play() async => log.add('play');

  @override
  Future<void> pause() async => log.add('pause');

  @override
  Future<void> dispose() async => log.add('dispose');
}

void main() {
  testWidgets('the City pop music: off by default, the button turns it on and off, remembered, pauses in the background', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final player = _FakePlayer();

    Widget app() => MaterialApp(
      home: CityMusicScope(
        preferences: prefs,
        playerFactory: () => player,
        builder: (context, on, toggle) => TextButton(onPressed: toggle, child: Text(on ? 'on' : 'off')),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump();
    expect(find.text('off'), findsOneWidget);
    expect(player.log.where((e) => e == 'play'), isEmpty, reason: 'nothing plays by default');

    await tester.tap(find.text('off'));
    await tester.pump();
    expect(find.text('on'), findsOneWidget);
    expect(player.log.last, 'play');
    expect(prefs.getBool(CityMusicScope.prefKey), isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(player.log.last, 'pause', reason: 'the app went to the background');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(player.log.last, 'play', reason: 'back in front, still on');

    await tester.tap(find.text('on'));
    await tester.pump();
    expect(player.log.last, 'pause');
    expect(prefs.getBool(CityMusicScope.prefKey), isFalse);

    // turned on again, then the City pop home goes away: the music stops
    await tester.tap(find.text('off'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();
    expect(player.log.sublist(player.log.length - 2), ['pause', 'dispose']);
  });

  testWidgets('the City pop music comes back on by itself if it was on last time', (tester) async {
    SharedPreferences.setMockInitialValues({CityMusicScope.prefKey: true});
    final prefs = await SharedPreferences.getInstance();
    final player = _FakePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: CityMusicScope(
          preferences: prefs,
          playerFactory: () => player,
          builder: (context, on, toggle) => Text(on ? 'on' : 'off'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('on'), findsOneWidget);
    expect(player.log, ['play']);
  });
}
