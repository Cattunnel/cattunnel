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
}
