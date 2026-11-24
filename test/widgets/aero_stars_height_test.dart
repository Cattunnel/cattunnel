import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/widgets/aero/aero_scene.dart';

void main() {
  test('phone: stars keep the band 150 units above the horizon', () {
    // 390 x 844 portrait, not calm: h0 = 0.6 * 844, scale 1.
    const h0 = 844 * 0.6;
    expect(aeroStarsHeight(h0, 1), h0 - 150);
  });

  test('wide desktop window: stars fill most of the sky, not a strip at the top', () {
    // 1200 x 750: scale 1200 / 390, h0 = 0.6 * 750. The phone formula gives about -12 px here.
    const h0 = 750 * 0.6;
    const scale = 1200 / 390;
    expect(h0 - 150 * scale, lessThan(0));
    expect(aeroStarsHeight(h0, scale), greaterThanOrEqualTo(h0 * 0.6));
  });
}
