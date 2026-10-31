import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/utils/device_orientation_policy.dart';

void main() {
  test('0x0 -> portrait only', () {
    expect(
      DeviceOrientationPolicy.allowedOrientations([const Size(0, 0)]),
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  });

  test('phone -> portrait only', () {
    expect(
      DeviceOrientationPolicy.allowedOrientations([const Size(360, 800)]),
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  });

  test('tablet portrait -> all four', () {
    expect(
      DeviceOrientationPolicy.allowedOrientations([const Size(800, 1280)]),
      [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  });

  test('tablet landscape -> all four', () {
    expect(
      DeviceOrientationPolicy.allowedOrientations([const Size(1280, 800)]),
      [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  });

  test('foldable closed (phone) -> portrait only', () {
    expect(
      DeviceOrientationPolicy.allowedOrientations([const Size(320, 780)]),
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  });

  test('foldable open (tablet) -> all four', () {
    expect(
      DeviceOrientationPolicy.allowedOrientations([const Size(840, 1080)]),
      [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
    );
  });

  test('all views must be wide', () {
    expect(
      DeviceOrientationPolicy.isWideScreen([const Size(1280, 800), const Size(360, 800)]),
      isFalse,
    );
  });
}
