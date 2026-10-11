import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Time of day of the «Аэро» style; the backdrop and the theme follow the
/// phone's clock (see AeroClock).
enum AeroPhase { morning, day, evening, night }

/// Colors of one time of day. Positions in the scene are given on a
/// 390-wide frame whose horizon is at y 476 (the design mockup) and are
/// scaled to the real screen around the horizon line.
class AeroScene {
  final List<Color> sky;
  final List<double> skyStops;
  final double starsAlpha;

  /// Sun centre and size (night: the moon).
  final Offset sun;
  final double sunSize;
  final List<Color> sunCore;
  final Color sunGlow, sunGlowFar;
  final Color ray, beam;
  final List<double> beams;

  final Alignment puffLight;
  final List<Color> puff;
  final List<double> puffStops;
  final List<Color> cloudBase;
  final double farCloudAlpha;

  final Alignment farHillLight;
  final List<Color> farHill;
  final Color farRim, haze;

  final List<Color> lake;
  final List<double> lakeStops;
  final List<Color>? lakeTint;
  final Color ripple, glint, shore;

  final Alignment midHillLight;
  final List<Color> midHill;
  final List<double> midHillStops;
  final Color midRim, midGlow;

  final Alignment nearLight, nearLight2;
  final List<Color> nearHill, nearHill2;
  final List<double> nearStops;
  final Color nearRim, nearGlow;
  final double hillGloss;

  final List<Color> orbBody;
  final List<Color> orbWorld;
  final Color orbRim, orbLow;
  final double orbGloss;

  final Color leafHi, leafLo, leafRim;
  final double leafGloss;
  final Color bokeh, bokehRim;
  final double flareAlpha;

  /// Calm screens get this veil over the scene so lists stay readable.
  final Color veil;

  /// Status bar and bottom bar colors around the scene.
  final Color top, ground;

  const AeroScene({
    required this.sky,
    required this.skyStops,
    required this.starsAlpha,
    required this.sun,
    required this.sunSize,
    required this.sunCore,
    required this.sunGlow,
    required this.sunGlowFar,
    required this.ray,
    required this.beam,
    required this.beams,
    required this.puffLight,
    required this.puff,
    required this.puffStops,
    required this.cloudBase,
    required this.farCloudAlpha,
    required this.farHillLight,
    required this.farHill,
    required this.farRim,
    required this.haze,
    required this.lake,
    required this.lakeStops,
    this.lakeTint,
    required this.ripple,
    required this.glint,
    required this.shore,
    required this.midHillLight,
    required this.midHill,
    required this.midHillStops,
    required this.midRim,
    required this.midGlow,
    required this.nearLight,
    required this.nearLight2,
    required this.nearHill,
    required this.nearHill2,
    required this.nearStops,
    required this.nearRim,
    required this.nearGlow,
    required this.hillGloss,
    required this.orbBody,
    required this.orbWorld,
    required this.orbRim,
    required this.orbLow,
    required this.orbGloss,
    required this.leafHi,
    required this.leafLo,
    required this.leafRim,
    required this.leafGloss,
    required this.bokeh,
    required this.bokehRim,
    required this.flareAlpha,
    required this.veil,
    required this.top,
    required this.ground,
  });

  static AeroScene of(AeroPhase phase) => switch (phase) {
    AeroPhase.morning => morning,
    AeroPhase.day => day,
    AeroPhase.evening => evening,
    AeroPhase.night => night,
  };

  static const _w = Color(0xFFFFFFFF);
  static Color _a(int rgb, double alpha) => Color(0xFF000000 | rgb).withValues(alpha: alpha);

  static final day = AeroScene(
    sky: const [Color(0xFF0750C4), Color(0xFF1F7FF0), Color(0xFF5FB4FF), Color(0xFFA9DCFF), Color(0xFFE4F6FF)],
    skyStops: const [0, .24, .44, .54, .57],
    starsAlpha: 0,
    sun: const Offset(325, 85),
    sunSize: 58,
    sunCore: [_w, _w, const Color(0xFFFFFBE0), _a(0xFFFFFF, 0)],
    sunGlow: _a(0xFFFFFF, .8),
    sunGlowFar: _a(0xFFFFF0, .38),
    ray: _a(0xFFFFFF, .32),
    beam: _a(0xFFFFFF, .45),
    beams: const [28, 46, 12],
    puffLight: const Alignment(-.08, -.48),
    puff: const [_w, _w, Color(0xFFF0F7FF), Color(0xFFCFE2F5), Color(0xFFA8C4E2)],
    puffStops: const [0, .34, .52, .74, 1],
    cloudBase: const [Color(0xFFEEF6FD), Color(0xFFC3D9EF), Color(0xFFA9C3E0)],
    farCloudAlpha: .75,
    farHillLight: const Alignment(.24, -.64),
    farHill: const [Color(0xFFD9F3E2), Color(0xFFB2DFC6), Color(0xFF93CDB3)],
    farRim: _a(0xFFFFFF, .6),
    haze: _a(0xEBF8FF, .85),
    lake: const [Color(0xFFF2FBFF), Color(0xFFA9E0FF), Color(0xFF4DAAF0), Color(0xFF1F7AD6)],
    lakeStops: const [0, .18, .6, 1],
    lakeTint: [_a(0xFFFFFF, 0), _a(0xFFFFFF, .12), _a(0xFFFFFF, .3), _a(0xFFFFFF, 0)],
    ripple: _a(0xFFFFFF, .32),
    glint: _a(0xFFFFFF, .95),
    shore: _a(0xFFFFFF, .8),
    midHillLight: const Alignment(.28, -.76),
    midHill: const [Color(0xFFE0FB96), Color(0xFFA2E346), Color(0xFF5DBB2A), Color(0xFF33901D)],
    midHillStops: const [0, .26, .6, 1],
    midRim: _a(0xFFFFFF, .65),
    midGlow: _a(0xDCFF96, .35),
    nearLight: const Alignment(.32, -.84),
    nearLight2: const Alignment(-.2, -.84),
    nearHill: const [Color(0xFFECFFB0), Color(0xFFB2EE52), Color(0xFF6CCC2C), Color(0xFF2E8C1C), Color(0xFF165F12)],
    nearHill2: const [Color(0xFFE4FFA2), Color(0xFFA6E84A), Color(0xFF5CBF26), Color(0xFF23801A), Color(0xFF145A12)],
    nearStops: const [0, .16, .42, .74, 1],
    nearRim: _a(0xFFFFFF, .75),
    nearGlow: _a(0xD2FF8C, .35),
    hillGloss: .55,
    orbBody: [_a(0xFFFFFF, .08), _a(0x96D7FF, .28), _a(0xFFFFFF, .8)],
    orbWorld: const [Color(0xFFD6FB86), Color(0xFF84D634), Color(0xFF3D9C22)],
    orbRim: _a(0xFFFFFF, .75),
    orbLow: _a(0xD2FF8C, .7),
    orbGloss: .92,
    leafHi: const Color(0xFFD9FF80),
    leafLo: const Color(0xFF3F9E22),
    leafRim: _a(0xFFFFFF, .7),
    leafGloss: 1,
    bokeh: _a(0xFFFFFF, .14),
    bokehRim: _a(0xFFFFFF, .6),
    flareAlpha: 1,
    veil: _a(0xF4FBFF, .3),
    top: const Color(0xFF0750C4),
    ground: const Color(0xFF1E6E16),
  );

  static final morning = AeroScene(
    sky: const [
      Color(0xFF2A72D8),
      Color(0xFF63A7EF),
      Color(0xFFB2D3F3),
      Color(0xFFFFD8C4),
      Color(0xFFFFF0E0),
      Color(0xFFFFF6EC),
    ],
    skyStops: const [0, .22, .38, .50, .56, .57],
    starsAlpha: .12,
    sun: const Offset(96, 92),
    sunSize: 64,
    sunCore: [_w, const Color(0xFFFFFAF0), const Color(0xFFFFE7B8), _a(0xFFE6B4, 0)],
    sunGlow: _a(0xFFF0D7, .8),
    sunGlowFar: _a(0xFFD2AA, .4),
    ray: _a(0xFFF0DC, .32),
    beam: _a(0xFFECD2, .5),
    beams: const [-24, -44, -8],
    puffLight: const Alignment(-.32, -.48),
    puff: const [_w, Color(0xFFFFFAF3), Color(0xFFFFE8DA), Color(0xFFEAD2E2), Color(0xFFC8C2E4)],
    puffStops: const [0, .32, .54, .76, 1],
    cloudBase: const [Color(0xFFFFF1E8), Color(0xFFEAD6E6), Color(0xFFCFC8E8)],
    farCloudAlpha: .8,
    farHillLight: const Alignment(-.4, -.64),
    farHill: const [Color(0xFFE8F2EA), Color(0xFFC3DCCF), Color(0xFFA6C8BB)],
    farRim: _a(0xFFFFFF, .6),
    haze: _a(0xFFEEE2, .9),
    lake: const [Color(0xFFFFF3E8), Color(0xFFFFD9C4), Color(0xFF9CCBF2), Color(0xFF3F8FDA)],
    lakeStops: const [0, .16, .55, 1],
    lakeTint: [_a(0xFFF0DC, 0), _a(0xFFE6D2, .35), _a(0xFFFFFF, .1), _a(0xFFFFFF, 0)],
    ripple: _a(0xFFFFFF, .32),
    glint: _a(0xFFF5E1, .95),
    shore: _a(0xFFFFFF, .8),
    midHillLight: const Alignment(-.4, -.76),
    midHill: const [Color(0xFFE9FDB0), Color(0xFFADE65A), Color(0xFF66BF32), Color(0xFF3A9422)],
    midHillStops: const [0, .26, .6, 1],
    midRim: _a(0xFFFFFF, .65),
    midGlow: _a(0xFFE6C8, .35),
    nearLight: const Alignment(-.32, -.84),
    nearLight2: const Alignment(-.6, -.84),
    nearHill: const [Color(0xFFF2FFC4), Color(0xFFBDF060), Color(0xFF74CF32), Color(0xFF328F1E), Color(0xFF1A6214)],
    nearHill2: const [Color(0xFFEAFFB6), Color(0xFFAEE856), Color(0xFF62C22A), Color(0xFF27841C), Color(0xFF165C12)],
    nearStops: const [0, .16, .42, .74, 1],
    nearRim: _a(0xFFFFFF, .75),
    nearGlow: _a(0xFFE6BE, .35),
    hillGloss: .55,
    orbBody: [_a(0xFFFFFF, .08), _a(0xB4D7FF, .28), _a(0xFFFFFF, .8)],
    orbWorld: const [Color(0xFFDFFB96), Color(0xFF8CD63C), Color(0xFF42A024)],
    orbRim: _a(0xFFFFFF, .75),
    orbLow: _a(0xFFDCBE, .7),
    orbGloss: .92,
    leafHi: const Color(0xFFE2FF90),
    leafLo: const Color(0xFF45A226),
    leafRim: _a(0xFFFFFF, .7),
    leafGloss: 1,
    bokeh: _a(0xFFF5EB, .16),
    bokehRim: _a(0xFFFFFF, .6),
    flareAlpha: 1,
    veil: _a(0xFFF8F2, .3),
    top: const Color(0xFF2A72D8),
    ground: const Color(0xFF226C18),
  );

  static final evening = AeroScene(
    sky: const [
      Color(0xFF17286E),
      Color(0xFF4A4AA0),
      Color(0xFFA35A9E),
      Color(0xFFF07A68),
      Color(0xFFFFB06A),
      Color(0xFFFFD79A),
    ],
    skyStops: const [0, .20, .36, .47, .53, .57],
    starsAlpha: .35,
    sun: const Offset(290, 412),
    sunSize: 110,
    sunCore: [const Color(0xFFFFF6D8), const Color(0xFFFFD27A), const Color(0xFFFF9A4A), _a(0xFF783C, 0)],
    sunGlow: _a(0xFFAA5A, .6),
    sunGlowFar: _a(0xFF6E50, .35),
    ray: _a(0xFFC88C, .22),
    beam: _a(0xFFBE78, .42),
    beams: const [62, 78, 92],
    puffLight: const Alignment(.4, .56),
    puff: const [Color(0xFFFFD8A0), Color(0xFFFFA88E), Color(0xFFC27FB0), Color(0xFF7A5EA6), Color(0xFF574A8E)],
    puffStops: const [0, .26, .56, .82, 1],
    cloudBase: const [Color(0xFF8A64A8), Color(0xFFD9849A), Color(0xFFFFB88A)],
    farCloudAlpha: .5,
    farHillLight: const Alignment(.6, -.64),
    farHill: const [Color(0xFFB07AA0), Color(0xFF6E5A96), Color(0xFF463F7A)],
    farRim: _a(0xFFC896, .55),
    haze: _a(0xFFBE8C, .65),
    lake: const [Color(0xFFFFD59A), Color(0xFFFF9F72), Color(0xFF9A63A6), Color(0xFF2D2F72)],
    lakeStops: const [0, .16, .55, 1],
    lakeTint: [_a(0xFFA05A, 0), _a(0xFFAA64, .1), _a(0xFFBE78, .35), _a(0xFFA05A, 0)],
    ripple: _a(0xFFDCB4, .3),
    glint: _a(0xFFD78C, .95),
    shore: _a(0xFFD296, .8),
    midHillLight: const Alignment(.64, -.8),
    midHill: const [Color(0xFFF2C860), Color(0xFFA3AE3E), Color(0xFF4E862C), Color(0xFF24521C)],
    midHillStops: const [0, .22, .56, 1],
    midRim: _a(0xFFD282, .75),
    midGlow: _a(0xFFA05A, .35),
    nearLight: const Alignment(.72, -.88),
    nearLight2: const Alignment(.4, -.88),
    nearHill: const [Color(0xFFFFD77A), Color(0xFFB9BC44), Color(0xFF5E9A2C), Color(0xFF2A6A1C), Color(0xFF133E10)],
    nearHill2: const [Color(0xFFFFCF70), Color(0xFFAAB540), Color(0xFF548F28), Color(0xFF235E18), Color(0xFF11380E)],
    nearStops: const [0, .14, .40, .72, 1],
    nearRim: _a(0xFFD78C, .8),
    nearGlow: _a(0xFFAA5A, .4),
    hillGloss: .3,
    orbBody: [_a(0xFFE6C8, .1), _a(0xFFAA8C, .25), _a(0xFFEBD2, .8)],
    orbWorld: const [Color(0xFFF2D070), Color(0xFF8AA83A), Color(0xFF3A6E24)],
    orbRim: _a(0xFFFFFF, .75),
    orbLow: _a(0xFFC878, .75),
    orbGloss: .92,
    leafHi: const Color(0xFFF2E070),
    leafLo: const Color(0xFF3E7A22),
    leafRim: _a(0xFFFFFF, .7),
    leafGloss: 1,
    bokeh: _a(0xFFDCB4, .14),
    bokehRim: _a(0xFFDCB4, .6),
    flareAlpha: .8,
    veil: _a(0xFFF4EC, .3),
    top: const Color(0xFF17286E),
    ground: const Color(0xFF1A4A14),
  );

  static final night = AeroScene(
    sky: const [Color(0xFF010612), Color(0xFF031330), Color(0xFF082A58), Color(0xFF0F4A72), Color(0xFF165F78)],
    skyStops: const [0, .28, .46, .54, .57],
    starsAlpha: 1,
    sun: const Offset(321, 101),
    sunSize: 58,
    sunCore: const [Color(0xFFFFFFFF), Color(0xFFEEF6FF), Color(0xFFC4D7EF), Color(0xFF9FB7D8)],
    sunGlow: _a(0xBEE1FF, .45),
    sunGlowFar: _a(0x8CBEFF, .2),
    ray: _a(0xFFFFFF, 0),
    beam: _a(0xFFFFFF, 0),
    beams: const [],
    puffLight: const Alignment(.12, -.56),
    puff: [_a(0xD7E6FF, .6), _a(0x82A0D7, .42), _a(0x32508C, .32), _a(0x14285A, .22)],
    puffStops: const [0, .32, .66, 1],
    cloudBase: [_a(0x5A78B4, .35), _a(0x1E376E, .3), _a(0x1E376E, .3)],
    farCloudAlpha: .55,
    farHillLight: const Alignment(.24, -.64),
    farHill: const [Color(0xFF1F5470), Color(0xFF143B56), Color(0xFF0C2942)],
    farRim: _a(0x96D2FF, .3),
    haze: _a(0x3C8CAA, .45),
    lake: const [Color(0xFF2F7A90), Color(0xFF145070), Color(0xFF0A3256), Color(0xFF061F3C)],
    lakeStops: const [0, .22, .6, 1],
    lakeTint: [_a(0x50FFAA, 0), _a(0x6EFFAA, .22), _a(0x50DCFF, .2), _a(0x50FFAA, 0)],
    ripple: _a(0xAADCFF, .18),
    glint: _a(0xDCEBFF, .85),
    shore: _a(0xBEFF78, .55),
    midHillLight: const Alignment(.28, -.76),
    midHill: const [Color(0xFF2A7A4A), Color(0xFF165434), Color(0xFF0C3922), Color(0xFF072616)],
    midHillStops: const [0, .32, .7, 1],
    midRim: _a(0xC4FF3D, .6),
    midGlow: _a(0xA0FF50, .35),
    nearLight: const Alignment(.32, -.84),
    nearLight2: const Alignment(-.2, -.84),
    nearHill: const [Color(0xFF2A7444), Color(0xFF134A2B), Color(0xFF0A3320), Color(0xFF071F12), Color(0xFF04190E)],
    nearHill2: const [Color(0xFF256C3E), Color(0xFF114428), Color(0xFF082D1B), Color(0xFF051E11), Color(0xFF03160C)],
    nearStops: const [0, .26, .56, .8, 1],
    nearRim: _a(0xC8FF50, .85),
    nearGlow: _a(0xA0FF50, .4),
    hillGloss: .1,
    orbBody: [_a(0x78DCFF, .12), _a(0x1E5096, .4), _a(0x96DCFF, .6)],
    orbWorld: const [Color(0xFF4CAA5A), Color(0xFF1D6A3A), Color(0xFF0A3A20)],
    orbRim: _a(0x96DCFF, .6),
    orbLow: _a(0xC4FF3D, .75),
    orbGloss: .4,
    leafHi: const Color(0xFF3F9A52),
    leafLo: const Color(0xFF0B3A1F),
    leafRim: _a(0xC4FF3D, .75),
    leafGloss: .25,
    bokeh: _a(0x78DCFF, .07),
    bokehRim: _a(0x96DCFF, .35),
    flareAlpha: .45,
    veil: _a(0x041230, .35),
    top: const Color(0xFF010612),
    ground: const Color(0xFF03160C),
  );
}

/// Pre-rendered still parts of one scene (per time of day, screen size and
/// calm/lively), shared by every backdrop on screen. Only the moving bits
/// are drawn each frame; the rest are images moved by the parallax. This
/// keeps page transitions (two backdrops at once) smooth.
class _Baked {
  final ui.Image image;
  final Rect rect;

  _Baked(this.image, this.rect);

  void draw(Canvas canvas, {Offset shift = Offset.zero, double opacity = 1}) => canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    rect.shift(shift),
    Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0)),
  );
}

class _BakeSet {
  final _Baked sun, sky, farHills, lake, midHills, nearHills, grass, bokeh, orbFar, orbMid, orbNear;
  final List<_Baked> farClouds, clouds;

  _BakeSet({
    required this.sun,
    required this.sky,
    required this.farHills,
    required this.lake,
    required this.midHills,
    required this.nearHills,
    required this.grass,
    required this.bokeh,
    required this.orbFar,
    required this.orbMid,
    required this.orbNear,
    required this.farClouds,
    required this.clouds,
  });

  Iterable<_Baked> get all => [
    sun,
    sky,
    farHills,
    lake,
    midHills,
    nearHills,
    grass,
    bokeh,
    orbFar,
    orbMid,
    orbNear,
    ...farClouds,
    ...clouds,
  ];

  void dispose() {
    for (final baked in all) {
      baked.image.dispose();
    }
  }
}

abstract final class _BakeCache {
  static final _sets = <String, _BakeSet>{};

  static _BakeSet get(String key, _BakeSet Function() make) {
    final hit = _sets.remove(key);
    if (hit != null) return _sets[key] = hit;
    final made = _sets[key] = make();
    // A few sets at most (calm + lively, a phase change, a rotation).
    while (_sets.length > 4) {
      final oldest = _sets.keys.first;
      _sets.remove(oldest)!.dispose();
    }

    return made;
  }
}

/// Paints the whole Aero landscape back to front: sky, sun or moon with
/// rays and light ribbons (aurora at night), far clouds, hazy far hills,
/// the lake, big clouds, glass orbs (a goldfish in one), mid and near
/// hills, lens flare, bubbles or fireflies, butterflies, grass, near
/// leaves and bokeh. [tilt] (-1..1) shifts the layers by depth (parallax);
/// [time] is seconds of the running clock.
class AeroScenePainter extends CustomPainter {
  final AeroScene scene;
  final AeroPhase phase;
  final bool calm;
  final double time;
  final Offset tilt;
  final double pixelRatio;

  AeroScenePainter({
    required this.scene,
    required this.phase,
    required this.calm,
    required this.time,
    required this.tilt,
    required this.pixelRatio,
  });

  bool get night => phase == AeroPhase.night;

  static final _stars = () {
    final random = math.Random(7);

    return List.generate(80, (_) => (random.nextDouble(), random.nextDouble(), random.nextDouble()));
  }();

  late double _s, _h0;
  late Size _size;

  double _x(double x) => x * _s;
  double _y(double y) => _h0 + (y - 476) * _s;

  static const _farClouds = [
    (-10.0, 420.0, 110.0, 34.0, 30.0, 0.0),
    (110.0, 428.0, 80.0, 26.0, 34.0, .3),
    (200.0, 416.0, 120.0, 38.0, 28.0, .5),
    (312.0, 426.0, 90.0, 28.0, 32.0, .2),
  ];
  static const _clouds = [
    (-40.0, 118.0, 200.0, 92.0, 20.0, 0.0, 1.0),
    (196.0, 196.0, 140.0, 66.0, 24.0, .3, .92),
    (40.0, 330.0, 120.0, 54.0, 18.0, .2, .85),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _size = size;
    _s = size.width / 390;
    _h0 = size.height * (calm ? 0.72 : 0.6);
    final baked = _BakeCache.get(
      '${phase.name}|$calm|${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}|$pixelRatio',
      _bakeAll,
    );

    // Sky gradient, stars.
    baked.sky.draw(canvas);
    _layer(canvas, 1.5, () {
      _paintStars(canvas, size);
      if (!night) _paintRays(canvas);
      baked.sun.draw(canvas, opacity: night ? 1 : 0.9 + 0.1 * _wave(7));
    });
    // Light ribbons / aurora: a slow sway and breathing.
    _layer(canvas, 2, () {
      _paintRibbons(canvas);
    });
    _layer(canvas, 3, () {
      for (final (i, c) in _farClouds.indexed) {
        baked.farClouds[i].draw(canvas, shift: Offset(_wave(c.$5 * 2, c.$6) * 22 * _s, 0));
      }
    });
    _layer(canvas, 4.5, () => baked.farHills.draw(canvas));
    _layer(canvas, 6, () {
      baked.lake.draw(canvas);
      _paintLakeLife(canvas);
      baked.orbFar.draw(canvas, shift: Offset(0, _bob(7, 2)));
    });
    _layer(canvas, 5, () {
      for (final (i, c) in _clouds.indexed) {
        baked.clouds[i].draw(canvas, shift: Offset(_wave(c.$5 * 2, c.$6) * 22 * _s, 0));
      }
    });
    _layer(canvas, 8, () => baked.midHills.draw(canvas));
    _layer(canvas, 10, () {
      final bob = _bob(8, 0);
      baked.orbMid.draw(canvas, shift: Offset(0, bob));
      _paintFish(canvas, Offset(_x(328), _y(256) + bob), _x(42));
    });
    _layer(canvas, 13, () => baked.nearHills.draw(canvas));
    if (!calm) {
      if (!night) _layer(canvas, -9, () => _paintFlare(canvas));
      _paintRisers(canvas);
      if (!night) _layer(canvas, 11, () => _paintButterflies(canvas));
    }
    _layer(canvas, 16, () => baked.grass.draw(canvas));
    _layer(canvas, 20, () {
      if (!calm) baked.orbNear.draw(canvas, shift: Offset(0, _bob(9, 4)), opacity: 0.85);
      _paintLeaves(canvas);
      baked.bokeh.draw(canvas);
    });
    if (calm) {
      // Light at the top, denser lower down where lists run over the hills.
      final v = scene.veil;
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, size.height),
            [
              v.withValues(alpha: v.a * .7),
              v.withValues(alpha: v.a * 1.6),
              v.withValues(alpha: (v.a * 2.6).clamp(0, .85)),
            ],
            const [0, .5, 1],
          ),
      );
    }
  }

  // ---------------------------------------------------------------- baking

  _BakeSet _bakeAll() {
    final size = _size;
    final full = (Offset.zero & size).inflate(60 * _s);
    final wide = Rect.fromLTRB(-70 * _s, 0, size.width + 70 * _s, 0);

    _Baked orb(Offset c, double r, {bool cloud = false}) =>
        _bake(Rect.fromCircle(center: c, radius: r * 1.7), (canvas) => _orb(canvas, c, r, cloud: cloud));

    return _BakeSet(
      sky: _bake(Offset.zero & size, (canvas) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), scene.sky, [
              for (final stop in scene.skyStops) (_y(stop * 844) / size.height).clamp(0.0, 1.0),
            ]),
        );
      }, scale: 0.5),
      sun: _bake(full, (canvas) => night ? _paintMoon(canvas) : _paintSun(canvas), scale: 0.75),
      farClouds: [
        for (final (x, y, w, h, _, _) in _farClouds)
          _bake(
            Rect.fromLTWH(_x(x), _y(y), _x(w), _x(h)).inflate(6),
            (canvas) => _cloud(canvas, Rect.fromLTWH(_x(x), _y(y), _x(w), _x(h)), scene.farCloudAlpha),
          ),
      ],
      clouds: [
        for (final (x, y, w, h, _, _, alpha) in _clouds)
          _bake(Rect.fromLTWH(_x(x), _y(y), _x(w), _x(h)).inflate(40), (canvas) {
            final box = Rect.fromLTWH(_x(x), _y(y), _x(w), _x(h));
            if (!night) {
              canvas.drawOval(
                box.translate(0, box.height * .25).deflate(box.height * .2),
                Paint()
                  ..color = const Color(0x2E1E64BE)
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
              );
            }
            _cloud(canvas, box, alpha);
          }),
      ],
      farHills: _bake(Rect.fromLTRB(wide.left, _y(400), wide.right, _y(600)), _paintFarHills),
      lake: _bake(Rect.fromLTRB(wide.left, _y(476), wide.right, _y(596)), _paintLakeBase),
      midHills: _bake(Rect.fromLTRB(_x(-180), _y(500), _x(560), size.height + 60 * _s), _paintMidHills),
      nearHills: _bake(Rect.fromLTRB(_x(-280), _y(550), _x(690), size.height + 60 * _s), _paintNearHills),
      grass: _bake(Rect.fromLTRB(wide.left, size.height - 170 * _s, wide.right, size.height + 40 * _s), _paintGrass),
      bokeh: _bake(full, _paintBokeh, scale: 0.5),
      orbFar: orb(Offset(_x(322), _y(410)), _x(22)),
      orbMid: orb(Offset(_x(328), _y(256)), _x(42), cloud: true),
      orbNear: orb(Offset(_x(18), _y(364)), _x(64)),
    );
  }

  /// Renders [draw] (in screen coordinates) inside [rect] to an image at
  /// the screen's pixel ratio times [scale] (blurry things need less).
  _Baked _bake(Rect rect, void Function(Canvas canvas) draw, {double scale = 1}) {
    final ratio = math.min(pixelRatio, 2.5) * scale;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(ratio)
      ..translate(-rect.left, -rect.top);
    draw(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(
      math.max(1, (rect.width * ratio).ceil()),
      math.max(1, (rect.height * ratio).ceil()),
    );
    picture.dispose();

    return _Baked(image, rect);
  }

  // ---------------------------------------------------------------- frame

  void _layer(Canvas canvas, double depth, VoidCallback paint) {
    canvas.save();
    canvas.translate(tilt.dx * depth * _s, tilt.dy * depth * 0.6 * _s);
    paint();
    canvas.restore();
  }

  double _wave(double period, [double shift = 0]) => math.sin(2 * math.pi * (time / period + shift));

  double _bob(double period, double shift) => _wave(period, shift / period) * 6 * _s;

  void _paintStars(Canvas canvas, Size size) {
    if (scene.starsAlpha == 0) return;
    final twinkle = 0.78 + 0.22 * _wave(5);
    final paint = Paint();
    final height = _y(476 - 150);
    for (final (i, (x, y, r)) in _stars.indexed) {
      final own = 0.75 + 0.25 * _wave(3 + r * 4, i * .13);
      paint.color = Colors.white.withValues(alpha: (scene.starsAlpha * twinkle * own * (0.5 + 0.5 * r)).clamp(0, 1));
      canvas.drawCircle(Offset(x * size.width, y * height), r < 0.15 ? 1.6 : 0.9, paint);
    }
  }

  Offset get _sunCenter => Offset(_x(scene.sun.dx) - 5 * _s, _y(scene.sun.dy));

  /// Thin slices around the sun, turning slowly, fading outwards.
  void _paintRays(Canvas canvas) {
    final c = _sunCenter;
    final rays = Path();
    const count = 27;
    final turn = time / 120 * 2 * math.pi;
    final reach = 180 * _s;
    for (var i = 0; i < count; i++) {
      final a = turn + i * 2 * math.pi / count;
      rays
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a) * reach, c.dy + math.sin(a) * reach)
        ..lineTo(c.dx + math.cos(a + 0.07) * reach, c.dy + math.sin(a + 0.07) * reach)
        ..close();
    }
    final ray = scene.ray;
    canvas.drawPath(
      rays,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          reach,
          [
            ray,
            ray.withValues(alpha: ray.a * .5),
            ray.withValues(alpha: 0),
          ],
          const [0, .5, 1],
        ),
    );
  }

  /// Vista-style light ribbons across the sky (day), the aurora at night.
  /// Drawn as soft gradient strokes - cheap enough to move every frame.
  void _paintRibbons(Canvas canvas) {
    final List<Color> tint = switch (phase) {
      AeroPhase.morning => const [
        Color(0x00FFFFFF),
        Color(0x80FFFFFF),
        Color(0x66FFD8C0),
        Color(0x40B8F070),
        Color(0x00FFFFFF),
      ],
      AeroPhase.day => const [
        Color(0x00FFFFFF),
        Color(0x8CFFFFFF),
        Color(0x5C9BE8FF),
        Color(0x47B6F03C),
        Color(0x00FFFFFF),
      ],
      AeroPhase.evening => const [
        Color(0x00FFFFFF),
        Color(0x66FFE2B8),
        Color(0x59FF9ABE),
        Color(0x40FFD27A),
        Color(0x00FFFFFF),
      ],
      AeroPhase.night => const [
        Color(0x0050FFAA),
        Color(0x8078FFA0),
        Color(0x6650E6FF),
        Color(0x40A078FF),
        Color(0x0050FFAA),
      ],
    };
    const stops = [0.0, .25, .5, .75, 1.0];
    final sway = _wave(night ? 22 : 30) * 14 * _s;
    final breathe = 0.8 + 0.2 * _wave(night ? 9 : 12, .2);

    void ribbon(double y0, double c1, double c2, double y3, double width, double alpha) {
      final path = Path()
        ..moveTo(_x(-60) + sway, _y(y0))
        ..cubicTo(_x(120) + sway, _y(c1), _x(260) - sway, _y(c2), _x(450) - sway, _y(y3));
      final from = Offset(_x(-60), 0), to = Offset(_x(450), 0);
      // A soft wide glow and a thin bright core.
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * _s
          ..shader = ui.Gradient.linear(from, to, [
            for (final c in tint) c.withValues(alpha: c.a * alpha * breathe * .45),
          ], stops),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = width * .3 * _s
          ..shader = ui.Gradient.linear(from, to, [
            for (final c in tint) c.withValues(alpha: c.a * alpha * breathe * .6),
          ], stops),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4 * _s
          ..shader = ui.Gradient.linear(from, to, [
            for (final c in tint) c.withValues(alpha: (c.a * alpha * breathe * 1.4).clamp(0, 1)),
          ], stops),
      );
    }

    if (night) {
      ribbon(170, 110, 260, 150, 70, 1);
      ribbon(240, 190, 300, 230, 40, .8);
      ribbon(300, 250, 360, 280, 12, .7);
    } else {
      ribbon(280, 170, 400, 300, 56, 1);
      ribbon(330, 250, 430, 350, 22, .9);
      ribbon(360, 300, 460, 400, 8, .8);
    }
  }

  void _paintLakeLife(Canvas canvas) {
    final sc = scene;
    final lake = Rect.fromLTWH(-40 * _s, _y(476), 470 * _s, 120 * _s);
    // Ripples drifting towards the shore, thicker nearer.
    final offset = (time / 3 % 1) * 7 * _s;
    final ripple = Paint()..color = sc.ripple;
    for (var y = lake.top + offset; y < lake.bottom; y += 7 * _s) {
      ripple.strokeWidth = 0.6 + (y - lake.top) / lake.height;
      canvas.drawLine(Offset(lake.left, y), Offset(lake.right, y), ripple);
    }
    // The sun's (moon's) path on the water, shimmering.
    final width = 30 * _s * (1 + 0.25 * _wave(2.6));
    final gx = _x(sc.sun.dx + 25) - width / 2;
    final glint = Rect.fromLTWH(gx, lake.top, width, lake.height);
    canvas.drawRect(
      glint,
      Paint()
        ..shader = ui.Gradient.linear(
          glint.centerLeft,
          glint.centerRight,
          [
            sc.glint.withValues(alpha: 0),
            sc.glint.withValues(alpha: sc.glint.a * .8),
            sc.glint.withValues(alpha: 0),
          ],
          const [0, .5, 1],
        ),
    );
  }

  /// A small tropical fish swimming to and fro inside the middle orb.
  void _paintFish(Canvas canvas, Offset c, double r) {
    final swim = time / 7;
    final x = c.dx + math.sin(swim * 2 * math.pi) * r * .42;
    final y = c.dy + r * .02 + math.sin(time / 2.3 * 2 * math.pi) * r * .08;
    final facingRight = math.cos(swim * 2 * math.pi) > 0;
    final len = r * .42;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r * .96)));
    canvas.translate(x, y);
    if (!facingRight) canvas.scale(-1, 1);
    final wag = math.sin(time * 8) * len * .08;
    final tail = Path()
      ..moveTo(-len * .38, 0)
      ..lineTo(-len * .7, -len * .26 + wag)
      ..lineTo(-len * .62, 0)
      ..lineTo(-len * .7, len * .26 + wag)
      ..close();
    final colors = night ? const [Color(0xFFFFD27A), Color(0xFFFF8A3D)] : const [Color(0xFFFFB347), Color(0xFFFF5A1A)];
    canvas.drawPath(tail, Paint()..color = colors[1]);
    final body = Rect.fromCenter(center: Offset.zero, width: len, height: len * .56);
    canvas.drawOval(body, Paint()..shader = ui.Gradient.linear(body.topCenter, body.bottomCenter, colors));
    canvas.drawRect(
      Rect.fromCenter(center: Offset(len * .02, 0), width: len * .1, height: len * .5),
      Paint()..color = Colors.white.withValues(alpha: .85),
    );
    canvas.drawCircle(Offset(len * .28, -len * .06), len * .06, Paint()..color = const Color(0xFF10223A));
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, -len * .14), width: len * .6, height: len * .14),
      Paint()..color = Colors.white.withValues(alpha: .45),
    );
    canvas.restore();
  }

  void _paintMoon(Canvas canvas) {
    final c = Offset(_x(scene.sun.dx), _y(scene.sun.dy));
    final r = _x(scene.sunSize / 2);
    canvas.drawCircle(
      c,
      r * 1.9,
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          r * 1.9,
          [const Color(0x59C8E6FF), const Color(0x1F8CBEFF), const Color(0x008CBEFF)],
          const [0, .5, 1],
        ),
    );
    canvas.drawCircle(
      c,
      r * 1.2,
      Paint()
        ..color = scene.sunGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(c + Offset(-r * .28, -r * .32), r * 1.3, scene.sunCore, const [0, .45, .8, 1]),
    );
  }

  void _paintSun(Canvas canvas) {
    final sc = scene;
    final c = _sunCenter;
    // God rays: long soft beams falling from the sun.
    for (final (i, angle) in sc.beams.indexed) {
      final width = [90.0, 50.0, 70.0][i] * _s;
      final length = [620.0, 560.0, 520.0][i] * _s;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(angle * math.pi / 180);
      final rect = Rect.fromLTWH(-width / 2, 0, width, length);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topCenter,
            rect.bottomCenter,
            [
              sc.beam,
              sc.beam.withValues(alpha: sc.beam.a * .2),
              sc.beam.withValues(alpha: 0),
            ],
            const [0, .55, 1],
          )
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.restore();
    }
    final r = _x(sc.sunSize / 2);
    canvas.drawCircle(
      c,
      r * 3.2,
      Paint()
        ..color = sc.sunGlowFar
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60),
    );
    canvas.drawCircle(
      c,
      r * 1.3,
      Paint()
        ..color = sc.sunGlow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
    );
    canvas.drawCircle(c, r * 1.25, Paint()..shader = ui.Gradient.radial(c, r * 1.25, sc.sunCore, const [0, .4, .6, 1]));
  }

  /// A cumulus: a flat lit base and four puffs lit from [AeroScene.puffLight].
  void _cloud(Canvas canvas, Rect box, double alpha) {
    final sc = scene;
    final base = Rect.fromLTWH(
      box.left + box.width * .04,
      box.bottom - box.height * .38,
      box.width * .92,
      box.height * .38,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(base, Radius.circular(base.height / 2)),
      Paint()
        ..shader = ui.Gradient.linear(
          base.topCenter,
          base.bottomCenter,
          [
            for (final c in sc.cloudBase) c.withValues(alpha: c.a * alpha),
          ],
          const [0, .7, 1],
        ),
    );
    for (final (l, b, w, h) in const [
      (0.0, .1, .32, .58),
      (.18, .2, .4, .92),
      (.44, .14, .36, .8),
      (.66, .08, .32, .56),
    ]) {
      final rect = Rect.fromLTWH(
        box.left + box.width * l,
        box.bottom - box.height * (b + h),
        box.width * w,
        box.height * h,
      );
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.scale(1, rect.height / rect.width);
      final local = Offset(sc.puffLight.x * rect.width / 2, sc.puffLight.y * rect.width / 2);
      canvas.drawCircle(
        Offset.zero,
        rect.width / 2,
        Paint()
          ..shader = ui.Gradient.radial(local, rect.width * .85, [
            for (final c in sc.puff) c.withValues(alpha: c.a * alpha),
          ], sc.puffStops),
      );
      canvas.restore();
    }
  }

  /// An oval hill with a radial light falling from [light], a bright rim
  /// along its top and an optional glow above it.
  void _hill(
    Canvas canvas,
    Rect rect,
    Alignment light,
    List<Color> colors,
    List<double>? stops,
    Color rim,
    double rimWidth, {
    Color? glow,
  }) {
    if (glow != null) {
      canvas.drawOval(
        rect.inflate(6 * _s).translate(0, -4 * _s),
        Paint()
          ..color = glow
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
      );
    }
    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.scale(1, rect.height / rect.width);
    final focus = Offset(light.x * rect.width / 2, light.y * rect.width / 2);
    canvas.drawCircle(
      Offset.zero,
      rect.width / 2,
      Paint()..shader = ui.Gradient.radial(focus, rect.width * .9, colors, stops),
    );
    canvas.restore();
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(rect.left - 10, rect.top - 10, rect.right + 10, rect.top + rect.height * .3));
    canvas.drawOval(
      rect.deflate(rimWidth / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..shader = ui.Gradient.linear(
          rect.centerLeft,
          rect.centerRight,
          [
            rim.withValues(alpha: 0),
            rim,
            rim.withValues(alpha: 0),
          ],
          const [0, .5, 1],
        ),
    );
    canvas.restore();
  }

  void _paintFarHills(Canvas canvas) {
    for (final (x, y, w, h) in const [
      (-120.0, 440.0, 340.0, 120.0),
      (120.0, 448.0, 260.0, 90.0),
      (260.0, 436.0, 300.0, 130.0),
    ]) {
      _hill(
        canvas,
        Rect.fromLTWH(_x(x), _y(y), _x(w), _x(h)),
        scene.farHillLight,
        scene.farHill,
        const [0, .45, 1],
        scene.farRim,
        2 * _s,
      );
    }
    final haze = Rect.fromLTWH(-70 * _s, _y(452), 530 * _s, 40 * _s);
    canvas.drawRect(
      haze,
      Paint()
        ..shader = ui.Gradient.linear(haze.topCenter, haze.bottomCenter, [scene.haze, scene.haze.withValues(alpha: 0)]),
    );
  }

  void _paintLakeBase(Canvas canvas) {
    final sc = scene;
    final lake = Rect.fromLTWH(-70 * _s, _y(476), 530 * _s, 120 * _s);
    canvas.drawRect(
      lake,
      Paint()..shader = ui.Gradient.linear(lake.topCenter, lake.bottomCenter, sc.lake, sc.lakeStops),
    );
    final tint = sc.lakeTint;
    if (tint != null) {
      canvas.drawRect(
        lake,
        Paint()
          ..shader = ui.Gradient.linear(
            lake.centerLeft,
            lake.centerRight,
            tint,
            night ? const [0, .3, .6, 1] : const [0, .5, .8, 1],
          ),
      );
    }
    canvas.drawRect(Rect.fromLTWH(lake.left, lake.top, lake.width, 3 * _s), Paint()..color = sc.shore);
  }

  void _paintMidHills(Canvas canvas) {
    for (final (x, y, w, h) in const [(-160.0, 528.0, 380.0, 170.0), (170.0, 540.0, 360.0, 160.0)]) {
      _hill(
        canvas,
        Rect.fromLTWH(_x(x), _y(y), _x(w), _x(h)),
        scene.midHillLight,
        scene.midHill,
        scene.midHillStops,
        scene.midRim,
        3 * _s,
        glow: scene.midGlow,
      );
    }
  }

  void _paintNearHills(Canvas canvas) {
    final sc = scene;
    final first = Rect.fromLTWH(_x(-260), _y(572), _x(620), _x(520));
    final second = Rect.fromLTWH(_x(150), _y(600), _x(520), _x(480));
    _hill(canvas, first, sc.nearLight, sc.nearHill, sc.nearStops, sc.nearRim, 4 * _s, glow: sc.nearGlow);
    _hill(canvas, second, sc.nearLight2, sc.nearHill2, sc.nearStops, sc.nearRim, 4 * _s, glow: sc.nearGlow);
    final gloss = Rect.fromLTWH(_x(-200), _y(574), _x(520), _x(60));
    canvas.drawOval(
      gloss,
      Paint()
        ..shader = ui.Gradient.linear(gloss.topCenter, gloss.bottomCenter, [
          Colors.white.withValues(alpha: sc.hillGloss),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    // The hills fill everything below them (tall screens) and shade
    // towards the bottom, where the cards and the bar sit.
    final below = Rect.fromLTRB(_x(-280), math.max(_y(800), first.bottom - 2), _x(690), _size.height + 60 * _s);
    if (below.height > 0) canvas.drawRect(below, Paint()..color = sc.nearHill.last);
    final bottom = Rect.fromLTRB(_x(-280), _y(640), _x(690), _size.height + 60 * _s);
    canvas.drawRect(
      bottom,
      Paint()
        ..shader = ui.Gradient.linear(bottom.topCenter, Offset(0, bottom.top + 260 * _s), [
          sc.ground.withValues(alpha: 0),
          sc.ground.withValues(alpha: .55),
        ]),
    );
  }

  /// Macro grass along the bottom edge: glossy blades, darker at the root.
  void _paintGrass(Canvas canvas) {
    final random = math.Random(11);
    final bottom = _size.height + 30 * _s;
    final sc = scene;
    final tipColor = night
        ? const Color(0xFF5FCF6A)
        : (phase == AeroPhase.evening ? const Color(0xFFE8D060) : const Color(0xFFC8FF6A));
    final rootColor = night ? const Color(0xFF02120A) : sc.ground;
    for (var i = 0; i < 70; i++) {
      final x = -60 * _s + random.nextDouble() * 510 * _s;
      final h = (50 + random.nextDouble() * 110) * _s * (i.isEven ? 1 : .7);
      final lean = (random.nextDouble() - .5) * 60 * _s;
      final w = (5 + random.nextDouble() * 6) * _s;
      final tip = Offset(x + lean, bottom - h);
      final blade = Path()
        ..moveTo(x - w / 2, bottom)
        ..quadraticBezierTo(x - w / 4 + lean * .3, bottom - h * .55, tip.dx, tip.dy)
        ..quadraticBezierTo(x + w / 4 + lean * .3, bottom - h * .55, x + w / 2, bottom)
        ..close();
      canvas.drawPath(
        blade,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, bottom),
            tip,
            [rootColor, Color.lerp(rootColor, tipColor, .55)!, tipColor],
            const [0, .55, 1],
          ),
      );
      canvas.drawLine(
        Offset(x, bottom - h * .2),
        Offset(tip.dx - lean * .15, tip.dy + h * .15),
        Paint()
          ..strokeWidth = 1 * _s
          ..color = Colors.white.withValues(alpha: night ? .12 : .35),
      );
    }
  }

  /// A glass orb with a small world inside: a hill, sometimes a cloud, a top
  /// highlight, a second highlight below and a bright spot.
  void _orb(Canvas canvas, Offset c, double r, {bool cloud = false}) {
    final sc = scene;
    canvas.drawCircle(
      c + Offset(0, r * .35),
      r * 1.05,
      Paint()
        ..color = night ? const Color(0x4D5AC8FF) : const Color(0x380046A0)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * .4),
    );
    final circle = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(circle));
    canvas.drawCircle(
      c,
      r,
      Paint()..shader = ui.Gradient.radial(c - Offset(0, r * .1), r, sc.orbBody, const [0, .62, 1]),
    );
    if (cloud) _cloud(canvas, Rect.fromLTWH(c.dx - r * .6, c.dy - r * .5, r * .9, r * .45), 1);
    final world = Rect.fromLTRB(c.dx - r * 1.3, c.dy + r * .2, c.dx + r * 1.3, c.dy + r * 1.6);
    canvas.drawOval(
      world,
      Paint()..shader = ui.Gradient.radial(world.topCenter, world.height, sc.orbWorld, const [0, .35, 1]),
    );
    canvas.drawOval(
      world,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * .05
        ..color = (night ? sc.midRim : Colors.white.withValues(alpha: .6)).withValues(alpha: .6),
    );
    final low = Rect.fromCenter(center: c + Offset(0, r * .72), width: r * .96, height: r * .3);
    canvas.drawOval(
      low,
      Paint()..shader = ui.Gradient.radial(low.center, low.width / 2, [sc.orbLow, sc.orbLow.withValues(alpha: 0)]),
    );
    canvas.restore();
    final top = Rect.fromLTWH(c.dx - r * .72, c.dy - r * .92, r * 1.44, r * .88);
    canvas.drawOval(
      top,
      Paint()
        ..shader = ui.Gradient.linear(top.topCenter, top.bottomCenter, [
          Colors.white.withValues(alpha: sc.orbGloss),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    canvas.drawCircle(c + Offset(-r * .4, -r * .5), r * .08, Paint()..color = Colors.white.withValues(alpha: .9));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, r * .03)
        ..color = sc.orbRim,
    );
  }

  void _paintFlare(Canvas canvas) {
    final alpha = scene.flareAlpha;
    final sun = Offset(_x(scene.sun.dx), _y(scene.sun.dy));
    final towards = Offset(_x(195), _y(422)) - sun;
    for (final (k, size, ring) in const [
      (.32, 30.0, false),
      (.52, 12.0, false),
      (.7, 54.0, true),
      (.95, 18.0, false),
      (1.25, 80.0, true),
    ]) {
      final c = sun + towards * k;
      final r = size / 2 * _s;
      if (ring) {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0xFFBEF0FF).withValues(alpha: .35 * alpha),
        );
      } else {
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
              c,
              r,
              [
                const Color(0xFFC8FFFA).withValues(alpha: .35 * alpha),
                const Color(0xFF78DCFF).withValues(alpha: .18 * alpha),
                const Color(0x0078DCFF),
              ],
              const [0, .6, 1],
            ),
        );
      }
    }
  }

  /// Day: soap bubbles rising from the grass. Night: fireflies.
  void _paintRisers(Canvas canvas) {
    for (final (x, y, fy, size, period, shift, fsize) in const [
      (26.0, 760.0, 600.0, 22.0, 11.0, 0.0, 6.0),
      (70.0, 820.0, 640.0, 12.0, 9.0, .44, 4.0),
      (330.0, 790.0, 610.0, 28.0, 13.0, .15, 9.0),
      (300.0, 860.0, 690.0, 14.0, 10.0, .7, 4.0),
      (360.0, 700.0, 560.0, 10.0, 8.0, .62, 3.0),
      (12.0, 640.0, 700.0, 16.0, 12.0, .75, 12.0),
      (190.0, 880.0, 650.0, 18.0, 14.0, .8, 5.0),
    ]) {
      final f = (time / period + shift) % 1;
      if (night) {
        final c = Offset(_x(x) + math.sin(f * 2 * math.pi) * 12 * _s, _y(fy) - f * 40 * _s);
        final glow = (0.35 + 0.65 * math.sin(f * math.pi)).clamp(0.0, 1.0);
        final r = fsize * 1.8 * _s;
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(c, r, [
              const Color(0xFFC8FF5A).withValues(alpha: .55 * glow),
              const Color(0xFFA0F03C).withValues(alpha: 0),
            ]),
        );
        canvas.drawCircle(c, fsize / 2.4 * _s, Paint()..color = const Color(0xFFE8FF9A).withValues(alpha: glow));
      } else {
        final fade = f < .12 ? f / .12 : (f > .85 ? (1 - f) / .15 : 1.0);
        final c = Offset(_x(x) + _x(size) / 2 + math.sin(f * 9) * 4 * _s, _y(y) - f * 460 * _s);
        final r = _x(size) / 2 * (0.9 + 0.15 * f);
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = ui.Gradient.radial(
              c + Offset(-r * .36, -r * .44),
              r * 1.4,
              [
                Colors.white.withValues(alpha: .95 * fade),
                Colors.white.withValues(alpha: .1 * fade),
                const Color(0xFFFFB0E0).withValues(alpha: .12 * fade),
                const Color(0xFF96D7FF).withValues(alpha: .18 * fade),
                Colors.white.withValues(alpha: .6 * fade),
              ],
              const [0, .22, .45, .6, .72],
            ),
        );
        canvas.drawCircle(
          c,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = Colors.white.withValues(alpha: .85 * fade),
        );
      }
    }
  }

  /// Two butterflies (blue morpho by day, monarchs in the evening light)
  /// wandering over the meadow.
  void _paintButterflies(Canvas canvas) {
    final evening = phase == AeroPhase.evening;
    final wing = evening
        ? const [Color(0xFFFFD27A), Color(0xFFFF8A2E), Color(0xFF5A2A0A)]
        : const [Color(0xFFB8F4FF), Color(0xFF2A8BF0), Color(0xFF0B3D91)];
    for (final (bx, by, period, size, shift) in const [
      (120.0, 520.0, 17.0, 16.0, 0.0),
      (290.0, 470.0, 23.0, 12.0, .4),
    ]) {
      final t = time / period + shift;
      final c = Offset(
        _x(bx) + math.sin(t * 2 * math.pi) * 90 * _s,
        _y(by) + math.sin(t * 2 * math.pi * 1.7) * 36 * _s - math.sin(time * 3 + shift * 9).abs() * 6 * _s,
      );
      final heading = math.cos(t * 2 * math.pi);
      final flap = 0.25 + 0.75 * math.sin(time * 11 + shift * 5).abs();
      final r = size * _s;
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(heading * .25);
      for (final side in const [-1.0, 1.0]) {
        canvas.save();
        canvas.scale(side * flap, 1);
        final upper = Rect.fromLTWH(0, -r * .9, r * 1.1, r * .95);
        final lower = Rect.fromLTWH(0, -r * .05, r * .75, r * .7);
        for (final w in [upper, lower]) {
          canvas.drawOval(
            w,
            Paint()..shader = ui.Gradient.radial(w.centerLeft, w.width, wing, const [0, .55, 1]),
          );
        }
        canvas.drawOval(
          Rect.fromLTWH(r * .15, -r * .8, r * .55, r * .3),
          Paint()..color = Colors.white.withValues(alpha: .45),
        );
        canvas.restore();
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: r * .16, height: r * 1.1),
          Radius.circular(r),
        ),
        Paint()..color = const Color(0xFF1A1A2A),
      );
      canvas.restore();
    }
  }

  static final _leaf = Path()
    ..moveTo(6, 96)
    ..cubicTo(26, 30, 84, 6, 144, 14)
    ..cubicTo(122, 62, 74, 104, 6, 96)
    ..close();
  static final _vein = Path()
    ..moveTo(10, 92)
    ..cubicTo(52, 70, 96, 40, 140, 16);
  static final _shine = Path()
    ..moveTo(30, 40)
    ..cubicTo(56, 22, 90, 14, 120, 18);

  void _paintLeaves(Canvas canvas) {
    void leaf(double x, double y, double scale, double angle, bool mirror) {
      canvas.save();
      canvas.translate(_x(x), _y(y));
      canvas.rotate(angle * math.pi / 180);
      canvas.scale(scale * _s * (mirror ? -1 : 1), scale * _s);
      if (mirror) canvas.translate(-150, 0);
      canvas.drawPath(
        _leaf,
        Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(150, 120), [scene.leafHi, scene.leafLo]),
      );
      canvas.drawPath(
        _leaf,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = scene.leafRim,
      );
      canvas.drawPath(
        _vein,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..color = scene.leafRim.withValues(alpha: scene.leafRim.a * .8),
      );
      canvas.drawPath(
        _shine,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: .7 * scene.leafGloss),
      );
      // A dew drop on the leaf.
      const drop = Offset(92, 46);
      canvas.drawCircle(drop + const Offset(1.5, 2.5), 7, Paint()..color = const Color(0x33002810));
      canvas.drawCircle(
        drop,
        7,
        Paint()
          ..shader = ui.Gradient.radial(
            drop + const Offset(-2, -2.5),
            9,
            [
              Colors.white.withValues(alpha: .95),
              Colors.white.withValues(alpha: .25),
              Colors.white.withValues(alpha: .6),
            ],
            const [0, .45, 1],
          ),
      );
      canvas.restore();
    }

    final sway = _wave(6) * 2;
    leaf(-18, 540, 1, -18 + sway, false);
    leaf(304, 560, .8, 30 - sway, true);
  }

  void _paintBokeh(Canvas canvas) {
    final spots = calm
        ? const [(-20.0, 180.0, 90.0, 6.0)]
        : const [
            (300.0, 120.0, 70.0, 4.0),
            (250.0, 330.0, 40.0, 3.0),
            (-20.0, 180.0, 90.0, 6.0),
            (330.0, 420.0, 56.0, 5.0),
          ];
    for (final (x, y, size, blur) in spots) {
      final c = Offset(_x(x + size / 2), _y(y + size / 2));
      final r = _x(size / 2);
      final soft = MaskFilter.blur(BlurStyle.normal, blur);
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = scene.bokeh
          ..maskFilter = soft,
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = scene.bokehRim
          ..maskFilter = soft,
      );
    }
  }

  @override
  bool shouldRepaint(AeroScenePainter old) =>
      old.time != time || old.tilt != tilt || old.phase != phase || old.calm != calm || old.pixelRatio != pixelRatio;
}
