import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/widgets/citypop/city_scene.dart';
import 'package:trusttunnel/widgets/citypop/city_world.dart';

/// Paints the world alone (no shader) on black and returns RGBA bytes.
Future<Uint8List> _render(CityWorld w, Size size, CityParams p, {double time = 10}) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
  w.warmUp(time, p);
  w.paint(canvas, size, time, p);
  final img = await rec.endRecording().toImage(size.width.toInt(), size.height.toInt());
  final data = await img.toByteData();
  img.dispose();

  return data!.buffer.asUint8List();
}

double _lum(Uint8List px, int w, int x, int y) {
  final i = (y * w + x) * 4;

  return 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
}

const _night = CityParams(tod: 1, alive: 1, fault: 0);

void main() {
  const size = Size(360, 800);

  test('the street has every Japanese building type', () {
    for (final s in [const Size(360, 800), const Size(412, 915)]) {
      final w = CityWorld()..resize(s);
      final k = w.debugBuildingKinds;
      // zakkyo, ribbon office, apartments, low tiled houses and a tower on the far shore
      for (final t in ['far0', 'far1', 'far2', 'far3', 'far4']) {
        expect(k[t] ?? 0, greaterThan(0), reason: '$t missing at $s: $k');
      }
      // and on the street side: zakkyo, offices, tiled houses, apartments
      for (final t in ['fac0', 'fac1', 'fac2', 'fac3']) {
        expect(k[t] ?? 0, greaterThan(0), reason: '$t missing at $s: $k');
      }
    }
  });

  test('every lit far-shore window sits inside a far building', () async {
    final w = CityWorld();
    await _render(w, size, _night);
    final houses = w.debugFarBuildings;
    final lit = w.debugLitFarWindows;
    expect(lit, isNotEmpty);
    for (final r in lit) {
      expect(houses.any((h) => h.inflate(0.6).contains(r.center)), isTrue, reason: 'window $r is not on a building');
    }
  });

  test('far-shore windows never show through a street facade', () async {
    // The left strip is covered by the street's facades. Forcing all far-shore
    // windows on or off must not change a single pixel of it.
    final a = CityWorld()..debugForceFarWindows = true;
    final b = CityWorld()..debugForceFarWindows = false;
    final pa = await _render(a, size, _night);
    final pb = await _render(b, size, _night);
    var diff = 0;
    for (var y = (0.20 * size.height).toInt(); y < 0.39 * size.height; y++) {
      for (var x = 0; x < 0.10 * size.width; x++) {
        if ((_lum(pa, 360, x, y) - _lum(pb, 360, x, y)).abs() > 1) diff++;
      }
    }
    expect(diff, 0, reason: '$diff pixels of the facade differ with far windows on and off');
  });

  test('the water under a lit far-shore window glows, and not under a dark one', () async {
    final w = CityWorld();
    final px = await _render(w, size, _night);
    const hy = 0.40 * 800;
    final lit = w.debugLitFarWindows
        .where((r) => r.left > 0.50 * 360 && r.right < 360 - 2 && r.bottom > hy - 40)
        .toList();
    expect(lit, isNotEmpty);
    // the same world with no lit windows and no signs: the reflection must be darker
    final dark = CityWorld()..debugForceFarWindows = false;
    final pd = await _render(dark, size, const CityParams(tod: 1, alive: 0, fault: 0));
    var brighter = 0;
    for (final r in lit) {
      final y = (hy + (hy - r.bottom) + 3).toInt(), x = r.center.dx.toInt();
      if (y < 800 && _lum(px, 360, x, y) > _lum(pd, 360, x, y) + 4) brighter++;
    }
    expect(brighter, greaterThan(lit.length ~/ 3), reason: 'only $brighter of ${lit.length} reflections visible');
  });

  testWidgets('the scene shader loads (a silent null made water and road flat colour)', (tester) async {
    final ok = await tester.runAsync(cityShaderLoads);
    expect(ok, isTrue);
  });

  test('the world paints in every time of day and state without errors', () async {
    for (final tod in [0.0, 0.5, 1.0]) {
      for (final alive in [0.0, 1.0]) {
        for (final fault in [0.0, 1.0]) {
          final w = CityWorld();
          await _render(w, size, CityParams(tod: tod, alive: alive, fault: fault));
          await _render(w, const Size(412, 915), CityParams(tod: tod, alive: alive, fault: fault), time: 20);
        }
      }
    }
  });

  group('sign letters', () {
    test('the starter tube blinks three times at the start of every 30 s and burns evenly after', () {
      for (final base in [0.0, 30.0, 60.0, 600.0]) {
        // three separate flashes with dark between them
        var flashes = 0;
        var prev = 0.0;
        for (var t = 0.0; t < 1.39; t += 0.01) {
          final g = cityStarterGlow(base + t);
          if (g > 0.3 && prev <= 0.3) flashes++;
          prev = g;
        }
        expect(flashes, 3, reason: 'at $base');
        for (var t = 1.5; t < 30; t += 0.25) {
          expect(cityStarterGlow(base + t), 1.0, reason: 'at ${base + t}');
        }
      }
    });

    test('every other letter of every sign is lit all the time', () {
      final w = CityWorld()..resize(const Size(360, 800));
      for (var blade = 0; blade < 7; blade++) {
        for (var letter = 0; letter < 6; letter++) {
          for (var t = 0.0; t < 90; t += 0.37) {
            final g = w.debugLetterGlow(blade, letter, t);
            if (blade == 2 && letter == 1) continue;
            expect(g, 1.0, reason: 'blade $blade letter $letter at $t');
          }
        }
      }
    });
  });

  group('traffic signal', () {
    test('cars wait on green while nobody presses, and a pedestrian gets the walk after yellow and red', () {
      final w = CityWorld()..resize(const Size(360, 800));
      final p = CityParams(tod: 0, alive: 1, fault: 0);
      w.debugPedestrians = false;
      for (var i = 0; i < 20 * 90; i++) {
        w.step(0.05, p);
        expect(w.debugSignal.car, 0);
        expect(w.debugSignal.ped, 0);
      }
      w.debugPedestrians = true;
      final seen = <int>{};
      var walked = 0;
      for (var i = 0; i < 20 * 60; i++) {
        w.step(0.05, p);
        final sig = w.debugSignal;
        seen.add(sig.car);
        if (sig.ped != 0) {
          walked++;
          expect(sig.car, 2, reason: 'ped walk while cars go');
        }
      }
      expect(seen, {0, 1, 2});
      expect(walked, greaterThan(20));
    });

    test('after crossing a pedestrian walks away and disappears instead of waiting on the other side', () {
      final w = CityWorld()..resize(const Size(360, 800));
      final p = CityParams(tod: 0, alive: 1, fault: 0);
      w.debugPedestrians = false;
      for (var i = 0; i < 20 * 30; i++) {
        w.step(0.05, p);
      }
      w.debugPedestrians = true;
      var left = false, gone = false;
      for (var i = 0; i < 20 * 120; i++) {
        w.step(0.05, p);
        for (final c in w.debugCrossers) {
          if (c.leaving) left = true;
          if (c.gone) gone = true;
        }
      }
      expect(left, isTrue, reason: 'nobody walked away along the pavement');
      expect(gone, isTrue, reason: 'nobody disappeared after walking away');
    });

    for (final cfg in [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]) {
      test(
        'cars never enter the zebra on red, pedestrians cross only in their phase (alive ${cfg.$1}, fault ${cfg.$2})',
        () {
          final w = CityWorld()..resize(const Size(360, 800));
          final p = CityParams(tod: 1, alive: cfg.$1, fault: cfg.$2);
          var prev = <int, double>{};
          var entered = 0, crossedWhileWalk = 0, carsSeen = 0;
          var crossersWalked = 0;
          for (var i = 0; i < 20 * 400; i++) {
            w.step(0.05, p);
            final sig = w.debugSignal;
            final now = {for (final c in w.debugCars) c.id: c.s};
            carsSeen = carsSeen < now.length ? now.length : carsSeen;
            for (final c in w.debugCars) {
              final before = prev[c.id];
              if (before == null) continue;
              final inside = c.s > CityWorld.zebraNear && c.s < CityWorld.zebraFar;
              final wasInside = before > CityWorld.zebraNear && before < CityWorld.zebraFar;
              if (inside && !wasInside && sig.car == 2) entered++;
            }
            prev = now;
            final walking = w.debugCrossers.where((c) => c.crossing).toList();
            if (walking.isNotEmpty) {
              crossersWalked++;
              // somebody is on the road: no car on the zebra, and the walk phase began
              if (w.debugCars.any((c) => c.s > CityWorld.zebraNear && c.s < CityWorld.zebraFar)) crossedWhileWalk++;
              expect(sig.ped, isNot(0), reason: 'pedestrian on the road outside the walk phase');
              expect(sig.car, 2, reason: 'pedestrian on the road while cars go');
            }
          }
          expect(entered, 0, reason: 'cars entered the zebra on red');
          expect(crossedWhileWalk, 0, reason: 'a car stood on the zebra with people on it');
          expect(crossersWalked, greaterThan(20), reason: 'pedestrians never crossed');
          expect(carsSeen, greaterThan(0));
        },
      );
    }
  });

  group('metro train', () {
    for (final cfg in [(0.0, 0.0), (1.0, 1.0)]) {
      test('a train of 6-10 cars comes every 20-40 s, in turn from each side (alive ${cfg.$1}, fault ${cfg.$2})', () {
        final w = CityWorld()..resize(const Size(360, 800));
        final p = CityParams(tod: 1, alive: cfg.$1, fault: cfg.$2);
        final starts = <double>[];
        final dirs = <int>[];
        final cars = <int>[];
        var lastT0 = -1.0;
        for (var i = 0; i < 20 * 600; i++) {
          w.step(0.05, p);
          final t = w.debugTrain;
          if (t.active && t.t0 != lastT0) {
            lastT0 = t.t0;
            starts.add(t.t0);
            dirs.add(t.dir);
            cars.add(t.cars);
          }
        }
        expect(starts.length, greaterThan(14), reason: '600 s must bring at least 15 trains: $starts');
        for (var i = 1; i < starts.length; i++) {
          final d = starts[i] - starts[i - 1];
          expect(d, inInclusiveRange(20, 40), reason: 'interval $d between train ${i - 1} and $i');
          expect(dirs[i], -dirs[i - 1], reason: 'trains must alternate direction');
        }
        for (final c in cars) {
          expect(c, inInclusiveRange(6, 10));
        }
      });
    }
  });

  test('the signal serves people with the VPN off too, day and night (owner 02.11)', () {
    for (final tod in [0.0, 1.0]) {
      final w = CityWorld()..resize(const Size(360, 800));
      final p = CityParams(tod: tod, alive: 0, fault: 0);
      final seen = <int>{};
      var crossed = false;
      for (var i = 0; i < 20 * 240; i++) {
        w.step(0.05, p);
        seen.add(w.debugSignal.car);
        if (w.debugCrossers.any((c) => c.crossing)) crossed = true;
      }
      expect(seen, containsAll([0, 1, 2]), reason: 'the signal never changed with the VPN off (tod $tod)');
      expect(crossed, isTrue, reason: 'nobody crossed with the VPN off (tod $tod)');
    }
  });
}
