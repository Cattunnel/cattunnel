import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/widgets/citypop/city_world.dart';

// Geometry close-ups, without the home controls or the scene's shader.
// The normal home screenshots cover the composited scene separately.
void main() {
  test('City pop geometry: both flights and roof equipment across seeds', () async {
    const size = Size(360, 800);
    for (final (seed, tod) in [
      (7, 0.0),
      (19, 0.0),
      (31, 0.0),
      (55, 0.0),
      (7, 0.5),
      (7, 1.0),
    ]) {
      for (final dir in [-1, 1]) {
        final world = CityWorld(seed: seed)
          ..planeForce = true
          ..planeForceDir = dir
          ..planeForceAge = 8.5;
        final params = CityParams(tod: tod, alive: 1, fault: 0);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(4);
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = tod == 0 ? const Color(0xffb9ced6) : const Color(0xff30213e),
        );
        world.resize(size);
        world.warmUp(14, params);
        world.paint(canvas, size, 14, params);
        final picture = recorder.endRecording();
        final image = await picture.toImage(1440, 3200);
        final cropRecorder = ui.PictureRecorder();
        Canvas(cropRecorder).drawImageRect(
          image,
          const Rect.fromLTWH(0, 560, 1440, 760),
          const Rect.fromLTWH(0, 0, 1440, 760),
          Paint(),
        );
        final cropPicture = cropRecorder.endRecording();
        final crop = await cropPicture.toImage(1440, 760);
        final data = await crop.toByteData(format: ui.ImageByteFormat.png);
        final suffix = tod == 0 ? '' : (tod == 1 ? '_night' : '_dusk');
        final flight = dir > 0 ? 'takeoff' : 'landing';
        final name = 'geometry_${seed}_$flight$suffix';
        final file = File('qa/citypop/shots/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        if (seed == 7) {
          final detailRecorder = ui.PictureRecorder();
          Canvas(detailRecorder)
            ..scale(4)
            ..translate(-640, -840)
            ..drawPicture(picture);
          final detailPicture = detailRecorder.endRecording();
          final detail = await detailPicture.toImage(720, 560);
          final png = await detail.toByteData(format: ui.ImageByteFormat.png);
          await File('qa/citypop/shots/plane_$flight$suffix.png').writeAsBytes(png!.buffer.asUint8List());
          detail.dispose();
          detailPicture.dispose();
        }
        crop.dispose();
        cropPicture.dispose();
        image.dispose();
        picture.dispose();
      }
    }
  });
}
