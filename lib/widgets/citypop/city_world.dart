import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// What the scene needs to know to draw one frame.
class CityParams {
  /// 0 day, 0.5 dusk, 1 night.
  final double tod;

  /// 0 the city sleeps, 1 it lives fully (VPN: off ... on).
  final double alive;

  /// 0..1 failure: part of the city goes dark, signs stutter.
  final double fault;

  /// Strength multiplier of the film grade (1 normal, 0 off).
  final double grade;

  const CityParams({required this.tod, required this.alive, required this.fault, this.grade = 1});
}

double _mix(double a, double b, double t) => a + (b - a) * t;
double _cl(double x, [double a = 0, double b = 1]) => x < a ? a : (x > b ? b : x);
double _sm(double a, double b, double x) {
  final t = _cl((x - a) / (b - a));

  return t * t * (3 - 2 * t);
}

List<double> _mixc(List<double> a, List<double> b, double t) => [
  _mix(a[0], b[0], t),
  _mix(a[1], b[1], t),
  _mix(a[2], b[2], t),
];
List<double> _p3(List<double> d, List<double> s, List<double> n, double t) =>
    t < 0.5 ? _mixc(d, s, t * 2) : _mixc(s, n, (t - 0.5) * 2);

/// Integer hash to 0..1, deterministic (window states, sign stutter).
double _ih(int a, int b) {
  var h = (a * 374761393 + b * 668265263) & 0xFFFFFFFF;
  h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF;

  return ((h ^ (h >> 16)) & 0xFFFFFFFF) / 4294967296.0;
}

const _neon = [
  [255.0, 72.0, 168.0],
  [72.0, 235.0, 245.0],
  [255.0, 178.0, 86.0],
  [160.0, 104.0, 255.0],
  [255.0, 96.0, 96.0],
];
const _paint = [
  [196.0, 62.0, 58.0],
  [232.0, 190.0, 80.0],
  [54.0, 128.0, 132.0],
  [226.0, 214.0, 190.0],
  [92.0, 90.0, 150.0],
  [210.0, 120.0, 70.0],
];
const _carColors = [
  [236.0, 178.0, 56.0],
  [150.0, 38.0, 66.0],
  [36.0, 108.0, 120.0],
  [214.0, 200.0, 170.0],
  [44.0, 52.0, 112.0],
  [226.0, 224.0, 232.0],
  [90.0, 130.0, 90.0],
];
const _winColors = [
  [255.0, 214.0, 128.0],
  [255.0, 168.0, 110.0],
  [150.0, 240.0, 245.0],
  [255.0, 236.0, 190.0],
];

/// Real Japanese words for signs, no brands: tea room, coffee, ramen,
/// karaoke, cinema, bookshop, izakaya, night, cat, pharmacy, hotel, sushi,
/// electronics, plus our own «Марсик» in katakana.
const citySignHorizontal = ['喫茶', '珈琲', 'ラーメン', 'カラオケ', '映画', '本屋', '居酒屋', 'ホテル', '寿司', '電器', 'マルシク'];
const citySignVertical = ['夜', '猫', '薬', '酒', '映画', '喫茶', 'ホテル', '珈琲', 'マルシク'];

class _Fac {
  final double s0, s1, z;
  final int idx, kind; // kind 0 narrow shop tower, 1 glass office, 2 low shops
  final bool dk, shop;
  final double pos, col;
  final List<double> awn;
  final String word;
  final List<double> wordNeon, board;
  _Fac(
    this.s0,
    this.s1,
    this.z,
    this.idx,
    this.kind,
    this.dk,
    this.shop,
    this.pos,
    this.col,
    this.awn,
    this.word,
    this.wordNeon,
    this.board,
  );
}

class _Far {
  final double x, w, h;
  final bool tower, beacon, dk;
  final int id, cols, rows;
  final double ph, tint, pos;
  _Far(
    this.x,
    this.w,
    this.h,
    this.tower,
    this.beacon,
    this.dk,
    this.id,
    this.cols,
    this.rows,
    this.ph,
    this.tint,
    this.pos,
  );
}

class _Blade {
  final double s, x, z0, wid;
  final String text;
  final List<double> neon, paintCol;
  final double pos;
  final bool dk;
  final int dead;
  _Blade(this.s, this.x, this.z0, this.wid, this.text, this.neon, this.paintCol, this.pos, this.dk, this.dead);
}

class _Car {
  String lane;
  double s, v;
  final int id;
  final bool front, taxi, coupe;
  final List<double> col;
  final double x;
  double brake = 0, bt = 0;
  _Car(this.lane, this.s, this.v, this.id, this.front, this.col, this.taxi, this.coupe, this.x);
}

class _Ped {
  double s;
  final double v, x, ph, gate;
  final bool umb;
  final List<double> col, umbCol;
  _Ped(this.s, this.v, this.x, this.ph, this.gate, this.umb, this.col, this.umbCol);
}

/// The «City pop» street scene: an evening/day/night Tokyo-like street seen
/// from a balcony. The shader draws sky, water and the wet road; this draws
/// the objects. Geometry is shared with shaders/city.frag:
/// x = 0.46 W + X k d, y = hy + (6 - Z) k d, d = 1 / s, k = 0.05 H, hy = 0.40 H.
///
/// Performance: buildings, awnings and the dark glass panes are one cached
/// [ui.Picture], rebuilt only when the size or the time-of-day bucket
/// changes; each frame draws the lit windows (batched into a few paths), signs,
/// cars, people, the plane and the beacons.
class CityWorld {
  CityWorld({this.seed = 7}) : _r = math.Random(seed * 7919);

  final int seed;
  final math.Random _r;
  Size _size = Size.zero;
  double _hy = 0, _k = 0, _vpx = 0, _u = 1;
  final List<_Far> _far = [];
  final List<_Fac> _fac = [];
  final List<_Blade> _blades = [];
  final List<_Car> _cars = [];
  final List<_Car> _parked = [];
  final List<_Ped> _peds = [];
  final List<double> _poles = const [2.0, 3.7, 6.0, 9.4, 15.0];
  final List<double> _lamps = const [1.5, 2.6, 4.2, 6.6, 10.5, 16.0];
  double _simT = 0;
  double _planeNext = 0, _planeT0 = -1;
  int _planeDir = 1;
  bool planeForce = false;

  // cached static layer
  ui.Picture? _static;
  Size _staticSize = Size.zero;
  int _staticBucket = -1;

  // per-frame state
  double _tod = 1, _night = 1, _dayK = 0, _neonK = 1, _gs = 0.4;
  CityParams _p = const CityParams(tod: 1, alive: 0, fault: 0);
  double _time = 0;

  final Map<String, TextPainter> _text = {};

  int get carCount => _cars.length;

  void resize(Size size) {
    if (size == _size) return;
    _size = size;
    _hy = 0.40 * size.height;
    _k = 0.05 * size.height;
    _vpx = 0.46 * size.width;
    _u = size.width / 360.0;
    _build();
    _text.clear();
    _static = null;
    _planeNext = 8 + 14 * math.Random(seed + 5).nextDouble();
    _cars.clear();
    _simT = 0;
  }

  // ---------------------------------------------------------------- geometry
  Offset _pt(double x, double z, double s) {
    final d = 1 / s;

    return Offset(_vpx + x * _k * d, _hy + (6 - z) * _k * d);
  }

  void _build() {
    final r = math.Random(seed);
    final w = _size.width, h = _size.height, u = _u;
    _far.clear();
    var x = -10 * u;
    var id = 0;
    while (x < w + 10 * u) {
      final bw = (9 + r.nextDouble() * 22) * u;
      final inBay = x > 0.60 * w;
      final centre = ((x + bw / 2) / w - 0.46).abs() < 0.2;
      var bh = (14 + r.nextDouble() * 62) * u * (inBay ? 0.55 : 1) * (centre ? 1.5 : 1);
      final tower = r.nextDouble() < 0.18 && !inBay;
      if (tower) bh = (95 + r.nextDouble() * 80) * u * (h / 800);
      bh = math.min(bh, 0.18 * h);
      _far.add(
        _Far(
          x,
          bw,
          bh,
          tower,
          tower || r.nextDouble() < 0.2,
          r.nextDouble() < 0.45,
          id,
          math.max(2, (bw / (4.2 * u)).floor()),
          math.max(2, (bh / (5.6 * u)).floor()),
          r.nextDouble(),
          r.nextDouble(),
          0.15 + 0.5 * (x / w),
        ),
      );
      id++;
      x += bw + (r.nextDouble() < 0.3 ? 3 * u : 0.5 * u);
    }
    _fac.clear();
    var s = 1.55;
    var idx = 0;
    const words = citySignHorizontal;
    while (s < 26) {
      final ls = math.max(0.5, s * (0.22 + r.nextDouble() * 0.26));
      final kind = idx % 3 == 1 ? 1 : (r.nextDouble() < 0.28 ? 2 : 0);
      _fac.add(
        _Fac(
          s,
          s + ls,
          28 + r.nextDouble() * 40,
          idx,
          kind,
          r.nextDouble() < 0.4,
          kind != 1 && r.nextDouble() < 0.92,
          0.05 + 0.6 * math.min(1, s / 26),
          r.nextDouble(),
          _paint[r.nextInt(_paint.length)],
          words[r.nextInt(words.length)],
          _neon[r.nextInt(_neon.length)],
          _paint[r.nextInt(_paint.length)],
        ),
      );
      s += ls;
      idx++;
    }
    _blades.clear();
    const bs = [2.2, 3.1, 4.1, 5.5, 7.4, 10.0, 13.5];
    for (var i = 0; i < bs.length; i++) {
      final t = citySignVertical[(i * 3 + seed) % citySignVertical.length];
      _blades.add(
        _Blade(
          bs[i],
          -5.75 + 0.15 * (i % 2),
          3.6 + (i % 3) * 0.4,
          1.15,
          t,
          _neon[(i + seed) % _neon.length],
          _paint[(i * 2 + 1) % _paint.length],
          0.1 + bs[i] / 28,
          i % 3 == 1,
          (_ih(i, seed) * t.runes.length).floor(),
        ),
      );
    }
    _parked.clear();
    const ps = [1.9, 3.6, 5.3, 8.4, 12.0];
    for (var i = 0; i < ps.length; i++) {
      _parked.add(_mkCar('P', ps[i], 0, i + 100, i.isEven));
    }
    _peds.clear();
    final pr = math.Random(seed + 321);
    for (var i = 0; i < 22; i++) {
      final side = pr.nextDouble() < 0.7 ? 1 : -1;
      _peds.add(
        _Ped(
          1.6 + pr.nextDouble() * 20,
          (0.12 + pr.nextDouble() * 0.12) * (pr.nextBool() ? 1 : -1),
          side > 0 ? 0.75 + pr.nextDouble() * 0.6 : -6.1 + pr.nextDouble() * 0.5,
          pr.nextDouble() * 6,
          pr.nextDouble() * 0.9,
          pr.nextDouble() < 0.28,
          _paint[pr.nextInt(_paint.length)],
          [_neon[i % 5], _paint[(i + 2) % 6]][i % 2],
        ),
      );
    }
  }

  _Car _mkCar(String lane, double s, double v, int id, bool front) {
    final r = math.Random(seed * 131 + id * 17);
    final taxi = r.nextDouble() < 0.22;
    final col = taxi ? _carColors[0] : _carColors[r.nextInt(_carColors.length)];

    return _Car(
      lane,
      s,
      v,
      id,
      lane == 'A' ? true : front,
      col,
      taxi,
      r.nextDouble() < 0.4,
      lane == 'A' ? -2.9 : (lane == 'B' ? -0.9 : -4.7),
    );
  }

  // -------------------------------------------------------------- simulation
  int _targetCars(CityParams p) {
    final t = p.tod;
    final base = t < 0.5 ? _mix(6, 9, t * 2) : _mix(9, 3, (t - 0.5) * 2);

    return math.max(1, (base * (0.35 + 0.65 * p.alive) * (1 - 0.45 * p.fault)).round());
  }

  void step(double dt, CityParams p) {
    _simT += dt;
    final spd = 1 - 0.9 * p.fault;
    if (_cars.length < _targetCars(p) && _r.nextDouble() < dt * 0.9) {
      final lane = _r.nextDouble() < 0.55 ? 'A' : 'B';
      final s = lane == 'A' ? 24.0 : 0.78;
      if (!_cars.any((c) => c.lane == lane && (c.s - s).abs() < (lane == 'A' ? 3 : 0.5))) {
        _cars.add(_mkCar(lane, s, (1.1 + _r.nextDouble() * 0.9) * (lane == 'A' ? -1 : 1), _r.nextInt(1000000), true));
      }
    }
    for (final c in _cars) {
      var v = c.v * spd;
      for (final o in _cars) {
        if (identical(o, c) || o.lane != c.lane) continue;
        final gap = (o.s - c.s) * (c.v < 0 ? -1 : 1);
        if (gap > 0 && gap < (c.lane == 'A' ? 2.2 * c.s * 0.25 + 0.5 : 0.4 + 0.12 * c.s)) {
          v = math.min(v.abs(), o.v.abs() * 0.6) * (c.v < 0 ? -1 : 1);
        }
      }
      c.s += v * dt * (c.lane == 'B' ? 1 + 0.18 * c.s : math.max(0.25, c.s * 0.25 + 0.4));
      c.bt -= dt;
      if (c.bt < 0 && _r.nextDouble() < dt * 0.15) c.bt = 0.6 + _r.nextDouble() * 0.8;
      c.brake = (p.fault > 0.4 || c.bt > 0) ? 1 : 0;
    }
    _cars.removeWhere((c) => c.s < 0.7 || c.s > 27);
    for (final pd in _peds) {
      pd.s += pd.v * dt * math.max(0.3, pd.s * 0.25);
      if (pd.s < 1.15) pd.s = 21;
      if (pd.s > 24) pd.s = 1.3;
    }
  }

  /// Runs the simulation for [seconds] (for still frames and tests).
  void warmUp(double seconds, CityParams p) {
    while (_simT < seconds) {
      step(0.05, p);
    }
  }

  // ------------------------------------------------------------------ colors
  /// The film grade of shaders/city.frag (filmGrade), for palette colors.
  List<double> _grade(List<double> c, double s) {
    if (s <= 0) return c;
    var r = c[0] * _mix(1, 1.10, s), g = c[1] * _mix(1, 1.01, s), b = c[2] * _mix(1, 0.86, s);
    final y = 0.299 * r + 0.587 * g + 0.114 * b;
    if (y > 0.68) {
      final f = (0.68 + (y - 0.68) * (1 - 0.38 * s)) / math.max(y, 1e-4);
      r *= f;
      g *= f;
      b *= f;
    }
    double sc(double x) => _mix(x, x * x * (3 - 2 * x), 0.30 * s);
    r = sc(r);
    g = sc(g);
    b = sc(b);
    final lf = 0.55 + 0.35 * s;
    r = _mix(r, 0.09 + r * 0.91, lf);
    g = _mix(g, 0.09 + g * 0.91, lf);
    b = _mix(b, 0.09 + b * 0.91, lf);
    final l = 0.299 * r + 0.587 * g + 0.114 * b;
    final sat = 1 - 0.17 * s;
    r = _mix(l, r, sat);
    g = _mix(l, g, sat);
    b = _mix(l, b, sat);
    final sh = (1 - _sm(0, 0.55, l)) * 0.5 * s;
    r = _mix(r, r * 0.55 + 0.184 * 0.62, sh);
    g = _mix(g, g * 0.55 + 0.435 * 0.62, sh);
    b = _mix(b, b * 0.55 + 0.416 * 0.62, sh);
    final w = _sm(0.5, 1, l) * s;

    return [r + 0.055 * w, g + 0.028 * w, b - 0.030 * w];
  }

  Color _c(List<double> c, [double a = 1]) {
    final g = _grade([c[0] / 255, c[1] / 255, c[2] / 255], _gs);

    return Color.from(alpha: _cl(a), red: _cl(g[0]), green: _cl(g[1]), blue: _cl(g[2]));
  }

  // ------------------------------------------------------------------- paint
  void paint(Canvas canvas, Size size, double time, CityParams p) {
    resize(size);
    _p = p;
    _time = time;
    _tod = p.tod;
    _night = _sm(0.45, 1, _tod);
    _dayK = 1 - _sm(0, 0.5, _tod);
    _neonK = _sm(0.22, 0.7, _tod);
    _gs = p.grade * _p3([1, 1, 1], [0.7, 0.7, 0.7], [0.4, 0.4, 0.4], _tod)[0];
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));
    _paintPlane(canvas);
    final bucket = (p.tod * 24).round() * 100 + (p.grade * 10).round();
    if (_static == null || _staticSize != size || _staticBucket != bucket) {
      final rec = ui.PictureRecorder();
      _paintStatic(Canvas(rec));
      _static = rec.endRecording();
      _staticSize = size;
      _staticBucket = bucket;
    }
    canvas.drawPicture(_static!);
    _paintLitWindows(canvas);
    _paintBeaconsAndTower(canvas);
    _paintSigns(canvas);
    final items = <(double, void Function())>[
      for (final c in _cars) (c.s, () => _paintCar(canvas, c)),
      for (final c in _parked) (c.s, () => _paintCar(canvas, c)),
      for (final pd in _peds) (pd.s, () => _paintPed(canvas, pd)),
      for (final l in _lamps) (l, () => _paintLamp(canvas, l)),
      for (final pl in _poles) (pl - 0.01, () => _paintPole(canvas, pl)),
      (3.0, () => _paintSignal(canvas)),
      (2.25, () => _paintRoadSign(canvas)),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    for (final it in items) {
      it.$2();
    }
    _paintWires(canvas);
    canvas.restore();
  }

  double _waveLit(double pos) => _sm(0, 1, _p.alive * 1.7 - pos * 1.2);
  double _lit(bool dk, double pos) => _waveLit(pos) * (1 - _p.fault * (dk ? 0.95 : 0.1));

  void _glow(Canvas canvas, Offset c, double r, List<double> col, double a) {
    if (a <= 0.02 || r < 0.5) return;
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(c, r, [_c(col, a), _c(col, 0)]);
    canvas.drawRect(Rect.fromCircle(center: c, radius: r), paint);
  }

  void _quad(Canvas canvas, List<Offset> pts, Color color) {
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  void _streak(Canvas canvas, double x, double y, double w, double h, List<double> col, double a) {
    if (a <= 0.02 || w < 0.4) return;
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.linear(Offset(0, y), Offset(0, y + h), [_c(col, a), _c(col, 0)]);
    canvas.drawRect(Rect.fromLTWH(x - w / 2, y, w, h), paint);
  }

  // ------------------------------------------------------------ static layer
  List<double> get _body => _p3([176, 160, 200], [112, 56, 118], [22, 14, 54], _tod);
  List<double> get _hz => _p3([255, 205, 160], [255, 130, 100], [200, 56, 130], _tod);

  void _paintStatic(Canvas canvas) {
    final hy = _hy, u = _u;
    final body = _body, hz = _hz;
    for (final b in _far) {
      final col = _mixc(body, hz, 0.28 + 0.15 * (1 - math.min(1, b.h / (90 * u))) + b.tint * 0.06);
      canvas.drawRect(Rect.fromLTWH(b.x, hy - b.h, b.w, b.h + 1), Paint()..color = _c(col));
      if (b.tower) {
        // glass office tower: a lighter curtain wall under the grid of windows
        canvas.drawRect(
          Rect.fromLTWH(b.x + b.w * 0.08, hy - b.h + 3 * u, b.w * 0.84, b.h - 3 * u),
          Paint()..color = _c(_mixc(col, [150, 200, 220], 0.25 * _dayK + 0.1), 0.55),
        );
        canvas.drawRect(
          Rect.fromLTWH(b.x + b.w / 2 - 0.5 * u, hy - b.h - 9 * u, 1 * u, 9 * u),
          Paint()..color = _c(col),
        );
      }
      if (_dayK > 0.05) {
        canvas.drawRect(
          Rect.fromLTWH(b.x + b.w * 0.72, hy - b.h, b.w * 0.28, b.h + 1),
          Paint()..color = _c([255, 226, 180], 0.35 * _dayK),
        );
      }
      // dark panes (glass) by day
      if (_dayK > 0.1) {
        final cw = b.w / b.cols, rh = b.h / b.rows;
        final paint = Paint()..color = _c([150, 196, 204], 0.45 * _dayK);
        for (var i = 0; i < b.cols; i++) {
          for (var j = 0; j < b.rows - 1; j++) {
            canvas.drawRect(
              Rect.fromLTWH(b.x + i * cw + cw * 0.25, hy - b.h + (j + 0.5) * rh + rh * 0.1, cw * 0.5, rh * 0.5),
              paint,
            );
          }
        }
      }
    }
    _paintFacadesStatic(canvas);
  }

  void _paintFacadesStatic(Canvas canvas) {
    const xf = -6.6;
    final hz = _hz;
    final wall0 = _p3([214, 196, 200], [118, 58, 112], [20, 12, 50], _tod);
    final wall1 = _p3([188, 170, 188], [88, 42, 96], [14, 8, 38], _tod);
    final glass0 = _p3([160, 196, 214], [96, 70, 140], [18, 22, 64], _tod);
    final list = _fac.toList()..sort((a, b) => b.s0.compareTo(a.s0));
    for (final f in list) {
      if (_pt(xf, 0, f.s0).dx < -0.4 * _size.width && _pt(xf, 0, f.s1).dx < -0.4 * _size.width) continue;
      final base = f.kind == 1 ? glass0 : _mixc(wall0, wall1, f.col);
      final col = _mixc(base, hz, math.min(0.5, 0.05 + 0.6 * math.exp(-3.0 / math.max(f.s0, 0.1) * 1.2)));
      final pA = _pt(xf, 0, f.s0), pB = _pt(xf, 0, f.s1), tA = _pt(xf, f.z, f.s0), tB = _pt(xf, f.z, f.s1);
      _quad(canvas, [pA, pB, tB, tA], _c(col));
      if (_dayK > 0.05) {
        _quad(canvas, [
          pA,
          Offset.lerp(pA, pB, 0.06)!,
          Offset.lerp(tA, tB, 0.06)!,
          tA,
        ], _c([255, 220, 170], 0.3 * _dayK));
      }
      // dark panes
      final cols = math.max(1, ((f.s1 - f.s0) / 0.55).floor());
      final cw = (f.s1 - f.s0) / cols;
      final dMid = 2 / (f.s0 + f.s1);
      final zTop = math.min(f.z - 2, 6 + _hy / (_k * dMid) + 1);
      if (cw * _k / (f.s1 * f.s1) < 0.6 * _u && f.s0 > 14) continue;
      final glassTone = f.kind == 1 ? 0.8 : 0.5;
      final pane = Paint()..color = _c(_mixc([120, 168, 178], [40, 30, 80], _night), glassTone);
      for (var c = 0; c < cols; c++) {
        final sa = f.s0 + c * cw + cw * (f.kind == 1 ? 0.06 : 0.18),
            sb = f.s0 + (c + 1) * cw - cw * (f.kind == 1 ? 0.06 : 0.18);
        for (var z = 4.6; z < zTop; z += f.kind == 1 ? 2.4 : 3.4) {
          final hgt = f.kind == 1 ? 1.5 : 1.9;
          _quad(canvas, [_pt(xf, z + hgt, sa), _pt(xf, z + hgt, sb), _pt(xf, z, sb), _pt(xf, z, sa)], pane.color);
        }
      }
      if (f.shop) _paintShopStatic(canvas, f, xf);
    }
  }

  void _paintShopStatic(Canvas canvas, _Fac f, double xf) {
    final s0 = f.s0 + (f.s1 - f.s0) * 0.06, s1 = f.s1 - (f.s1 - f.s0) * 0.06, dm = 2 / (f.s0 + f.s1);
    if (_k * dm * 1.2 < 0.7 * _u) return;
    final glass = _mixc([34, 84, 92], [255, 196, 120], _sm(0.2, 0.9, _tod) * 0.35);
    _quad(canvas, [_pt(xf, 2.7, s0), _pt(xf, 2.7, s1), _pt(xf, 0.4, s1), _pt(xf, 0.4, s0)], _c(glass, 0.96));
    if (_dayK > 0.05) {
      _quad(canvas, [
        _pt(xf, 2.7, s0),
        _pt(xf, 2.7, _mix(s0, s1, 0.35)),
        _pt(xf, 0.4, _mix(s0, s1, 0.2)),
        _pt(xf, 0.4, s0),
      ], _c([255, 244, 214], 0.22 * _dayK));
    }
    final xo = xf + 1.15;
    final awnDim = 1 - 0.65 * _night;
    for (var i = 0; i < 7; i++) {
      final a = _mix(s0, s1, i / 7), b = _mix(s0, s1, (i + 1) / 7);
      final c = i.isOdd ? const [236.0, 230.0, 214.0] : f.awn;
      _quad(canvas, [
        _pt(xf, 3.5, a),
        _pt(xf, 3.5, b),
        _pt(xo, 2.75, b),
        _pt(xo, 2.75, a),
      ], _c([c[0] * awnDim, c[1] * awnDim, c[2] * awnDim * (1 + 0.15 * _night)]));
    }
    // painted board above the awning (neon at night is drawn on top)
    _quad(canvas, [
      _pt(xf, 5.0, s0),
      _pt(xf, 5.0, s1),
      _pt(xf, 3.6, s1),
      _pt(xf, 3.6, s0),
    ], _c(_mixc(f.board, [14, 8, 36], _neonK)));
  }

  // ----------------------------------------------------------- lit windows
  void _paintLitWindows(Canvas canvas) {
    final hy = _hy;
    final dens = _mix(0.03, 0.06, _night);
    final paths = List.generate(4, (_) => Path());
    for (final b in _far) {
      final lit = _lit(b.dk, b.pos);
      final d = dens + 0.62 * lit * _sm(0.15, 0.7, _tod);
      final cw = b.w / b.cols, rh = b.h / b.rows;
      for (var i = 0; i < b.cols; i++) {
        for (var j = 0; j < b.rows - 1; j++) {
          final rr = _ih(b.id * 977 + i, j + 11), per = 18 + _ih(i, j + b.id) * 50;
          if (_ih(b.id * 131 + i * 7 + j, (_time / per + rr * 9).floor()) < d) {
            paths[(rr * 4).floor() % 4].addRect(
              Rect.fromLTWH(b.x + i * cw + cw * 0.25, hy - b.h + (j + 0.5) * rh + rh * 0.1, cw * 0.5, rh * 0.5),
            );
          }
        }
      }
    }
    const xf = -6.6;
    final dens2 = _mix(0.02, 0.05, _night);
    for (final f in _fac) {
      if (_pt(xf, 0, f.s0).dx < -0.4 * _size.width) continue;
      final lit = _lit(f.dk, f.pos);
      final d = dens2 + 0.60 * lit * _sm(0.15, 0.7, _tod);
      final cols = math.max(1, ((f.s1 - f.s0) / 0.55).floor());
      final cw = (f.s1 - f.s0) / cols;
      final dMid = 2 / (f.s0 + f.s1);
      final zTop = math.min(f.z - 2, 6 + _hy / (_k * dMid) + 1);
      if (f.s0 > 14) continue;
      for (var c = 0; c < cols; c++) {
        final sa = f.s0 + c * cw + cw * 0.18, sb = f.s0 + (c + 1) * cw - cw * 0.18;
        var row = 0;
        for (var z = 4.6; z < zTop; z += f.kind == 1 ? 2.4 : 3.4, row++) {
          final rr = _ih(f.idx * 53 + c, row + 3), per = 20 + _ih(c, row + f.idx) * 60;
          if (_ih(f.idx * 29 + c * 3 + row, (_time / per + rr * 7).floor()) < d + (f.kind == 1 ? 0.08 * lit : 0)) {
            final hgt = f.kind == 1 ? 1.5 : 1.9;
            paths[(rr * 4).floor() % 4].addPath(
              Path()..addPolygon([_pt(xf, z + hgt, sa), _pt(xf, z + hgt, sb), _pt(xf, z, sb), _pt(xf, z, sa)], true),
              Offset.zero,
            );
          }
        }
      }
    }
    for (var i = 0; i < 4; i++) {
      canvas.drawPath(paths[i], Paint()..color = _c(_winColors[i], 0.92));
    }
    // Near the camera a few windows glow softly
    if (_night > 0.3) {
      for (final f in _fac) {
        if (f.s0 > 5.5 || f.kind == 1) continue;
        final lit = _lit(f.dk, f.pos);
        _glow(canvas, _pt(xf, 8, (f.s0 + f.s1) / 2), 1.4 * _k / ((f.s0 + f.s1) / 2) * 1.6, const [
          255,
          190,
          110,
        ], 0.18 * lit);
      }
    }
  }

  // ----------------------------------------------- tower, beacons, wires etc.
  void _paintBeaconsAndTower(Canvas canvas) {
    final hy = _hy, u = _u;
    final vis = (0.25 + 0.75 * _sm(0.25, 0.7, _tod)) * (1 - _p.fault * 0.5);
    for (final b in _far) {
      if (!b.beacon) continue;
      final on = ((_time * 1.0 + b.ph * 3) % 1) < 0.34;
      if (on) {
        final c = Offset(b.x + b.w / 2, hy - b.h - 3 * u);
        _glow(canvas, c, 10 * u, const [255, 30, 30], 0.8 * vis);
        canvas.drawRect(
          Rect.fromCenter(center: c, width: 2 * u, height: 2 * u),
          Paint()..color = _c(const [255, 90, 90], vis),
        );
      }
    }
    // Radio tower: red and white lattice, with lights, on the far shore.
    final tx = _size.width * 0.72, th = 0.26 * _size.height, tw = 24 * u;
    final base = Offset(tx, hy);
    final white = _c(_mixc([236, 232, 236], [90, 70, 120], _night * 0.8));
    final red = _c(_mixc([214, 70, 60], [120, 30, 60], _night * 0.6));
    const segs = 9;
    for (var i = 0; i < segs; i++) {
      final t0 = i / segs, t1 = (i + 1) / segs;
      final w0 = tw * (1 - t0) * 0.5 + 1 * u, w1 = tw * (1 - t1) * 0.5 + 1 * u;
      final y0 = base.dy - th * t0, y1 = base.dy - th * t1;
      final path = Path()
        ..moveTo(tx - w0, y0)
        ..lineTo(tx + w0, y0)
        ..lineTo(tx + w1, y1)
        ..lineTo(tx - w1, y1)
        ..close();
      canvas.drawPath(path, Paint()..color = i.isEven ? red : white);
      // lattice cross-bracing
      final line = Paint()
        ..color = _c(const [60, 40, 70], 0.7)
        ..strokeWidth = 0.7 * u;
      canvas.drawLine(Offset(tx - w0, y0), Offset(tx + w1, y1), line);
      canvas.drawLine(Offset(tx + w0, y0), Offset(tx - w1, y1), line);
    }
    canvas.drawRect(Rect.fromLTWH(tx - 0.6 * u, base.dy - th - 9 * u, 1.2 * u, 9 * u), Paint()..color = red);
    for (var i = 0; i < 3; i++) {
      final on = ((_time * 0.9 + i * 0.33) % 1) < 0.5;
      final c = Offset(tx, base.dy - th * (0.35 + i * 0.3));
      if (on) _glow(canvas, c, 7 * u, const [255, 60, 60], 0.7 * vis);
      canvas.drawCircle(c, 1 * u, Paint()..color = _c(const [255, 120, 120], on ? vis : vis * 0.3));
    }
  }

  void _paintWires(Canvas canvas) {
    final paint = Paint()
      ..color = _c(_p3([60, 50, 66], [40, 22, 56], [10, 6, 26], _tod), 0.9)
      ..style = PaintingStyle.stroke;
    final ps = _poles.toList()..sort();
    for (var i = 0; i < ps.length - 1; i++) {
      for (final dx in const [-0.7, 0.0, 0.7]) {
        final a = _pt(-5.5 + dx, 9.25, ps[i]),
            b = _pt(-5.5 + dx, 9.25, ps[i + 1]),
            mid = _pt(-5.5 + dx, 7.65, (ps[i] + ps[i + 1]) / 2);
        paint.strokeWidth = math.max(0.7, 0.05 * _k / ps[i]);
        final path = Path()
          ..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(mid.dx, mid.dy + (b.dy - a.dy) * 0.1, b.dx, b.dy);
        canvas.drawPath(path, paint);
      }
    }
    final a = _pt(-5.5, 9.25, ps.first);
    canvas.drawPath(
      Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(a.dx - 0.2 * _size.width, a.dy + 0.04 * _size.height, -10, a.dy - 0.02 * _size.height),
      paint,
    );
  }

  void _paintPole(Canvas canvas, double s) {
    final a = _pt(-5.5, 0, s), b = _pt(-5.5, 9.2, s), m = _k / s;
    if (m < 2) return;
    final col = Paint()..color = _c(_p3([70, 56, 70], [48, 26, 62], [14, 8, 32], _tod));
    canvas.drawRect(Rect.fromLTRB(a.dx - 0.14 * m, b.dy, a.dx + 0.14 * m, a.dy), col);
    canvas.drawRect(Rect.fromLTWH(a.dx - 0.8 * m, b.dy + 0.15 * m, 1.6 * m, 0.14 * m), col);
    canvas.drawRect(Rect.fromLTWH(a.dx - 0.6 * m, b.dy + 0.9 * m, 1.2 * m, 0.12 * m), col);
  }

  void _paintLamp(Canvas canvas, double s) {
    final a = _pt(1.55, 0, s), h = _pt(1.55, 6.2, s), m = _k / s;
    if (m < 1.5) return;
    final col = Paint()..color = _c(_p3([60, 56, 70], [40, 24, 58], [12, 8, 30], _tod));
    canvas.drawRect(Rect.fromLTRB(a.dx - 0.09 * m, h.dy, a.dx + 0.09 * m, a.dy), col);
    canvas.drawRect(Rect.fromLTWH(h.dx - 0.5 * m, h.dy - 0.05 * m, 0.55 * m, 0.1 * m), col);
    final on = _mix(0.18, 1, _sm(0.1, 0.75, _tod)) * _lit(false, 0.1 + s / 28) * (_night * 0.9 + 0.1);
    canvas.drawRect(
      Rect.fromLTWH(h.dx - 0.55 * m, h.dy - 0.02 * m, 0.4 * m, 0.1 * m),
      Paint()..color = _c(_mixc([230, 230, 220], [255, 220, 150], on)),
    );
    if (on > 0.15 && s < 8) {
      _glow(canvas, Offset(h.dx - 0.35 * m, h.dy + 0.1 * m), 1.5 * m, const [255, 204, 120], 0.42 * on);
      _streak(canvas, a.dx, a.dy, 0.4 * m, 2.6 * m, const [255, 190, 120], 0.22 * on);
    }
  }

  void _paintSignal(Canvas canvas) {
    const s = 3.0;
    final a = _pt(0.1, 0, s), top = _pt(0.1, 5.2, s), m = _k / s;
    final pole = Paint()..color = _c(const [50, 50, 60]);
    canvas.drawRect(Rect.fromLTRB(a.dx - 0.08 * m, top.dy, a.dx + 0.08 * m, a.dy), pole);
    canvas.drawRect(Rect.fromLTWH(top.dx - 1.4 * m, top.dy, 1.4 * m, 0.1 * m), pole);
    final hx = top.dx - 1.45 * m, hy = top.dy + 0.05 * m;
    canvas.drawRect(Rect.fromLTWH(hx - 0.2 * m, hy, 1.2 * m, 0.4 * m), Paint()..color = _c(const [28, 28, 36]));
    var on = [0, 0, 0];
    if (_p.fault > 0.5) {
      on = [_ih(1, (_time * 9).floor()) < 0.7 ? 1 : 0, 0, 0];
    } else if (_p.alive > 0.97) {
      on = [0, 0, 1];
    } else if (_p.alive > 0.08) {
      on = [0, (_time % 1) < 0.5 ? 1 : 0, 0];
    }
    const cols = [
      [255.0, 60.0, 60.0],
      [255.0, 200.0, 60.0],
      [90.0, 240.0, 140.0],
    ];
    for (var i = 0; i < 3; i++) {
      final c = Offset(hx + i * 0.4 * m, hy + 0.2 * m);
      canvas.drawCircle(c, 0.14 * m, Paint()..color = _c(_mixc(const [36, 36, 44], cols[i], on[i].toDouble())));
      if (on[i] == 1) _glow(canvas, c, 1.0 * m, cols[i], 0.7 * (0.35 + 0.65 * _mix(0.18, 1, _sm(0.1, 0.75, _tod))));
    }
  }

  void _paintRoadSign(Canvas canvas) {
    const s = 2.25;
    final a = _pt(0.95, 0, s), top = _pt(0.95, 4.0, s), m = _k / s;
    canvas.drawRect(
      Rect.fromLTRB(a.dx - 0.05 * m, top.dy, a.dx + 0.05 * m, a.dy),
      Paint()..color = _c(const [120, 120, 130]),
    );
    final c = Offset(top.dx, top.dy - 0.2 * m);
    final blue = Paint()..color = _c(const [40, 90, 190]);
    final white = Paint()..color = _c(const [244, 244, 240]);
    canvas.drawCircle(c, 0.42 * m, blue);
    canvas.drawCircle(c, 0.36 * m, white);
    canvas.drawCircle(c, 0.31 * m, blue);
    canvas.drawRect(Rect.fromLTWH(c.dx - 0.05 * m, c.dy - 0.22 * m, 0.1 * m, 0.46 * m), white);
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 0.15 * m, c.dy - 0.1 * m)
        ..lineTo(c.dx, c.dy - 0.3 * m)
        ..lineTo(c.dx + 0.15 * m, c.dy - 0.1 * m)
        ..close(),
      white,
    );
  }

  // ------------------------------------------------------------------- signs
  TextPainter _tp(String ch, double size, Color color) {
    final key = '$ch|${size.round()}|${color.toARGB32()}';

    return _text.putIfAbsent(key, () {
      final p = TextPainter(
        text: TextSpan(
          text: ch,
          style: TextStyle(
            fontFamily: 'MPlus1p',
            fontFamilyFallback: const ['Noto Sans CJK JP', 'Yu Gothic', 'sans-serif'],
            fontWeight: FontWeight.w800,
            fontSize: size,
            color: color,
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      return p;
    });
  }

  double _signGate(bool dk, double pos, int id) {
    var g = _lit(dk, pos);
    if (_p.fault > 0.05) {
      final flick = _ih(id, (_time * 11).floor()) < 0.55 ? 1.0 : 0.05;
      g *= _mix(1, flick, _p.fault);
    }

    return g;
  }

  /// Letters of [text] in a row, each one lit or dark, with a soft glow.
  void _letters(
    Canvas canvas,
    String text,
    Offset c,
    double size,
    List<double> neonCol,
    double nk,
    List<double> paintCol,
    int id,
  ) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final adv = size * 1.0;
    var x = c.dx - adv * chars.length / 2;
    for (var i = 0; i < chars.length; i++) {
      final dead = _ih(id * 7 + i, 5) < 0.12;
      var on = nk;
      if (dead) on *= _ih(id + i, (_time * 6).floor()) < 0.18 ? 1 : 0;
      final off = _c(_mixc(paintCol, _mixc(neonCol, [10, 6, 24], 0.82), _neonK));
      _tp(chars[i], size, off).paint(canvas, Offset(x + (adv - _tp(chars[i], size, off).width) / 2, c.dy - size / 2));
      if (on > 0.05) {
        final lit = _c(_mixc(neonCol, [255, 255, 255], 0.45), 0.55 + 0.45 * on);
        final glow = Paint()
          ..blendMode = BlendMode.plus
          ..color = _c(neonCol, 0.5 * on)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, size * 0.35));
        canvas.drawCircle(Offset(x + adv / 2, c.dy), size * 0.55, glow);
        final tp = _tp(chars[i], size, lit);
        tp.paint(canvas, Offset(x + (adv - tp.width) / 2, c.dy - size / 2));
      }
      x += adv;
    }
  }

  void _paintSigns(Canvas canvas) {
    const xf = -6.6;
    for (final f in _fac) {
      if (!f.shop || _pt(xf, 0, f.s0).dx < -0.2 * _size.width) continue;
      final a = _pt(xf, 4.3, (f.s0 + f.s1) / 2), m = _k * 2 / (f.s0 + f.s1);
      if (m < 3) continue;
      final nk = _neonK * _signGate(f.dk, f.pos, f.idx);
      final len = f.word.runes.length;
      final size = math.min(m * 1.1, (f.s1 - f.s0) * _k / (f.s0 * 0.5 + f.s1 * 0.5) * 1.1 / math.max(1, len * 0.5));
      if (size < 3) continue;
      _letters(canvas, f.word, a.translate(0, -m * 0.2), size, f.wordNeon, nk, const [244, 236, 214], f.idx);
    }
    for (final b in _blades) {
      final d = 1 / b.s, m = _k * d;
      if (m < 1.2) continue;
      final p = _pt(b.x, b.z0, b.s);
      final chars = b.text.runes.length;
      final hgt = chars * 0.95 + 0.5;
      final x = p.dx, y = p.dy - hgt * m, w = b.wid * m;
      final nk = _neonK * _signGate(b.dk, b.pos, 300 + (b.s * 10).round());
      final wallx = _pt(-6.6, 0, b.s).dx;
      canvas.drawRect(
        Rect.fromLTWH(math.min(wallx, x), y + 0.3 * m, (x - wallx).abs(), math.max(1, 0.08 * m)),
        Paint()..color = _c(const [30, 24, 40], 0.9),
      );
      canvas.drawRect(
        Rect.fromLTWH(x - w / 2, y, w, hgt * m),
        Paint()..color = _c(_mixc(b.paintCol, [12, 8, 30], _neonK)),
      );
      canvas.drawRect(
        Rect.fromLTWH(x - w / 2 + 0.04 * m, y + 0.04 * m, w - 0.08 * m, hgt * m - 0.08 * m),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, 0.07 * m)
          ..color = _c(_mixc([240, 232, 214], b.neon, _neonK), 0.95),
      );
      final runes = b.text.runes.map(String.fromCharCode).toList();
      for (var i = 0; i < runes.length; i++) {
        final cy = y + (0.25 + (i + 0.5) * 0.95) * m;
        var on = nk;
        if (i == b.dead) on *= _ih(i, (_time * 5).floor()) < 0.2 ? 1 : 0;
        final size = math.max(4.0, 0.82 * m);
        final off = _c(_mixc([244, 236, 214], _mixc(b.neon, [10, 6, 24], 0.82), _neonK));
        final tp = _tp(runes[i], size, off);
        tp.paint(canvas, Offset(x - tp.width / 2, cy - size / 2));
        if (on > 0.05) {
          final glow = Paint()
            ..blendMode = BlendMode.plus
            ..color = _c(b.neon, 0.5 * on)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5, size * 0.3));
          canvas.drawCircle(Offset(x, cy), size * 0.5, glow);
          final lt = _tp(runes[i], size, _c(_mixc(b.neon, [255, 255, 255], 0.45), 0.55 + 0.45 * on));
          lt.paint(canvas, Offset(x - lt.width / 2, cy - size / 2));
        }
      }
      if (nk > 0.05) _streak(canvas, x, _pt(b.x, 0, b.s).dy, w * 0.8, 3.2 * m, b.neon, 0.28 * nk * _night);
    }
  }

  // -------------------------------------------------------------------- cars
  void _paintCar(Canvas canvas, _Car c) {
    final p = _pt(c.x, 0, c.s);
    final m = _k / c.s;
    if (m < 1.1 || p.dy > _size.height) return;
    final n = _night;
    final nb = _mix(1, 0.34, n);
    final body = [c.col[0] * nb, c.col[1] * nb, c.col[2] * nb + 14 * n];
    final front = c.front;
    final hl = (front ? 1.0 : 0.0) * _sm(0.15, 0.6, _tod) * (c.lane == 'P' ? 0 : 1);
    final tl = c.lane == 'P' ? 0.25 * n : 1.0;
    final brake = c.brake;
    final wet = n * 0.9;
    if (c.lane != 'P') {
      for (final sx in const [-1.0, 1.0]) {
        final col = front ? const [255.0, 244.0, 210.0] : const [255.0, 40.0, 40.0];
        _streak(
          canvas,
          p.dx + sx * 0.62 * m,
          p.dy - 0.1 * m,
          0.55 * m,
          3.4 * m * (front ? 1.2 : 0.9),
          col,
          (front ? 0.55 * hl : (0.30 + 0.45 * brake) * tl) * math.max(wet, 0.15 * _sm(0.2, 0.6, _tod)),
        );
      }
    }
    canvas.save();
    canvas.translate(p.dx, p.dy);
    canvas.scale(m);
    Color k(List<double> col, [double a = 1]) => _c(col, a);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-0.9 * _dayK, 0.04), width: 2 * (1.15 + 0.9 * _dayK), height: 0.6),
      Paint()..color = k(const [20, 14, 40], 0.34 * (1 - 0.6 * n)),
    );
    void rect(double x0, double y0, double x1, double y1, List<double> col, [double a = 1]) =>
        canvas.drawRect(Rect.fromLTRB(x0, -y1, x1, -y0), Paint()..color = k(col, a));
    const wheel = [18.0, 14.0, 28.0];
    rect(-0.96, 0, -0.74, 0.5, wheel);
    rect(0.74, 0, 0.96, 0.5, wheel);
    rect(-0.92, 0.18, 0.92, 0.85, body);
    if (_dayK > 0.05) rect(0.55, 0.18, 0.92, 0.85, const [255, 232, 190], 0.20 * _dayK);
    final roofH = c.coupe ? 1.38 : 1.52, cw = c.coupe ? 0.68 : 0.62;
    canvas.drawPath(
      Path()
        ..moveTo(-0.9, -0.85)
        ..lineTo(0.9, -0.85)
        ..lineTo(0.84, -1.0)
        ..lineTo(-0.84, -1.0)
        ..close(),
      Paint()..color = k([body[0] * 1.12 + 6, body[1] * 1.12 + 6, body[2] * 1.12 + 10]),
    );
    canvas.drawPath(
      Path()
        ..moveTo(-0.84, -1.0)
        ..lineTo(0.84, -1.0)
        ..lineTo(cw, -roofH)
        ..lineTo(-cw, -roofH)
        ..close(),
      Paint()..color = k([body[0] * 0.9, body[1] * 0.9, body[2] * 0.9]),
    );
    final glass = Paint()
      ..shader = ui.Gradient.linear(Offset(0, -roofH), const Offset(0, -1.0), [
        k(_mixc(const [120, 168, 190], const [30, 20, 70], n)),
        k(_mixc(const [36, 70, 92], const [14, 8, 36], n)),
      ]);
    canvas.drawPath(
      Path()
        ..moveTo(-0.74, -1.04)
        ..lineTo(0.74, -1.04)
        ..lineTo(cw - 0.1, -(roofH - 0.06))
        ..lineTo(-cw + 0.1, -(roofH - 0.06))
        ..close(),
      glass,
    );
    rect(-cw - 0.02, roofH, cw + 0.02, roofH + 0.1, [body[0] * 1.2 + 10, body[1] * 1.2 + 10, body[2] * 1.2 + 14]);
    rect(-0.95, 0.2, 0.95, 0.38, _mixc(const [210, 214, 224], const [96, 90, 130], n)); // chrome bumper
    rect(-0.5, 0.31, -0.1, 0.38, const [255, 255, 255], 0.6 * _dayK + 0.2);
    if (c.taxi) rect(-0.3, roofH + 0.1, 0.3, roofH + 0.32, _mixc(const [240, 236, 200], const [255, 220, 120], n));
    if (front) {
      rect(-0.4, 0.45, 0.4, 0.72, const [16, 12, 24]);
      for (final sx in const [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(sx * 0.66, -0.6), width: 0.4, height: 0.22),
          Paint()..color = k(_mixc(const [230, 230, 220], const [255, 246, 214], hl)),
        );
      }
    } else {
      for (final sx in const [-1.0, 1.0]) {
        final a = 0.55 + 0.45 * brake;
        canvas.drawRect(
          Rect.fromLTWH(sx > 0 ? 0.5 : -0.92, -0.98, 0.42, 0.2),
          Paint()..color = k(_mixc(const [120, 20, 24], const [255, 50, 50], tl * a)),
        );
      }
      rect(-0.22, 0.42, 0.22, 0.56, const [236, 232, 214]);
    }
    canvas.restore();
    // Light halos, outside the scaled space so the glow keeps its pixel size
    if (hl > 0.05) {
      for (final sx in const [-1.0, 1.0]) {
        _glow(canvas, Offset(p.dx + sx * 0.66 * m, p.dy - 0.6 * m), 0.95 * m, const [255, 240, 200], 0.55 * hl);
      }
    } else if (!front && tl > 0.1) {
      for (final sx in const [-1.0, 1.0]) {
        _glow(canvas, Offset(p.dx + sx * 0.7 * m, p.dy - 0.68 * m), (1.2 + 0.8 * brake) * m, const [
          255,
          40,
          40,
        ], (0.35 + 0.5 * brake) * tl);
      }
    }
  }

  // ------------------------------------------------------------------ people
  void _paintPed(Canvas canvas, _Ped p) {
    final pos = _pt(p.x, 0, p.s);
    final m = _k / p.s;
    if (m < 1.2 || pos.dy > _size.height) return;
    final density = _mix(1.0, 0.45, _night) * (0.35 + 0.65 * _p.alive) * (1 - 0.45 * _p.fault);
    if (p.gate > density) return;
    final ph = p.ph + _time * 5.2 * p.v.abs() / 0.12 * 0.7;
    final sw = math.sin(ph) * 0.22, bob = math.cos(ph).abs() * 0.03;
    final nk = _night;
    final ink = _mixc(_mixc(p.col, const [60, 54, 86], 0.3), const [20, 14, 40], nk * 0.9);
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.scale(m);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-0.8 * _dayK, 0.02), width: 2 * (0.3 + 0.9 * _dayK), height: 0.2),
      Paint()..color = _c(const [20, 14, 40], 0.28 * (1 - 0.6 * nk)),
    );
    final leg = Paint()
      ..color = _c(_mixc(const [42, 44, 70], const [16, 12, 34], nk))
      ..strokeWidth = 0.12
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-0.07, -0.88 - bob), Offset(-0.07 + sw, 0), leg);
    canvas.drawLine(Offset(0.07, -0.88 - bob), Offset(0.07 - sw, 0), leg);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(-0.2, -1.5 - bob, 0.4, 0.66), const Radius.circular(0.12)),
      Paint()..color = _c(ink),
    );
    final arm = Paint()
      ..color = _c(ink)
      ..strokeWidth = 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-0.2, -1.42 - bob), Offset(-0.2 - sw * 0.5, -0.95), arm);
    canvas.drawLine(Offset(0.2, -1.42 - bob), Offset(0.2 + sw * 0.5, -0.95), arm);
    canvas.drawCircle(
      Offset(0, -1.64 - bob),
      0.14,
      Paint()..color = _c(_mixc(const [226, 190, 160], const [40, 28, 60], nk)),
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset(0, -1.68 - bob), radius: 0.14),
      math.pi,
      math.pi,
      true,
      Paint()..color = _c(const [30, 22, 40]),
    );
    if (p.umb) {
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(0.05, -1.95), radius: 0.72),
        math.pi,
        math.pi,
        true,
        Paint()..color = _c(_mixc(p.umbCol, const [30, 20, 60], nk * 0.5)),
      );
      canvas.drawLine(
        const Offset(0.05, -1.95),
        const Offset(0.05, -1.5),
        Paint()
          ..color = _c(const [30, 22, 40])
          ..strokeWidth = 0.05,
      );
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------- plane
  void _paintPlane(Canvas canvas) {
    final w = _size.width, h = _size.height, u = _u, t = _time;
    if (planeForce) {
      _planeT0 = t - 7;
      _planeNext = 1e9;
      planeForce = false;
      _planeDir = -1;
    }
    if (_planeT0 < 0 && t > _planeNext) {
      _planeT0 = t;
      _planeDir = _r.nextBool() ? 1 : -1;
    }
    if (_planeT0 < 0) return;
    final uu = (t - _planeT0) / 17;
    if (uu > 1) {
      _planeT0 = -1;
      _planeNext = t + 20 + _r.nextDouble() * 20;
      return;
    }
    final x = _planeDir > 0 ? _mix(-0.08 * w, 1.08 * w, uu) : _mix(1.08 * w, -0.08 * w, uu);
    final y = 0.255 * h - uu * 0.02 * h;
    final half = 11 * u;
    final lights = _sm(0.3, 0.6, _tod);
    final bodyA = 0.9 * (1 - _night * 0.85);
    if (_dayK > 0.15) {
      final p0 = Offset(x, y), p1 = Offset(x - _planeDir * 160 * u, y + 3 * u);
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..strokeWidth = 2.2 * u
          ..shader = ui.Gradient.linear(p0, p1, [
            _c(const [255, 255, 255], 0.55 * _dayK),
            _c(const [255, 255, 255], 0),
          ]),
      );
    }
    final bodyColor = _c(_mixc(const [240, 238, 240], const [48, 24, 70], _tod > 0.4 ? 0.9 : 0), bodyA);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: half * 1.9, height: 3.2 * u),
      Paint()..color = bodyColor,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 3 * u, y)
        ..lineTo(x + 2 * u, y + 0.2 * u)
        ..lineTo(x - _planeDir * 2 * u, y + 4.8 * u)
        ..close(),
      Paint()..color = bodyColor,
    );
    if (lights < 0.02) return;
    final ph = (t * 0.83) % 1;
    final strobe = ph < 0.05 || (ph > 0.14 && ph < 0.19); // double flash like an Airbus
    final beacon = ((t * 1.1 + 0.3) % 1.5) < 0.18;
    for (final l in [
      (x - half, const [255.0, 40.0, 40.0]),
      (x + half, const [40.0, 255.0, 90.0]),
    ]) {
      _glow(canvas, Offset(l.$1, y + 1.8 * u), 9 * u, l.$2, 0.55 * lights);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(l.$1, y + 1.8 * u), width: 2 * u, height: 2 * u),
        Paint()..color = _c(l.$2, lights),
      );
    }
    if (strobe) {
      for (final sx in [x - half * 0.97, x + half * 0.97, x - _planeDir * half]) {
        _glow(canvas, Offset(sx, y + 1.3 * u), 16 * u, const [255, 255, 255], 0.85 * lights);
        canvas.drawRect(
          Rect.fromLTWH(sx - 1 * u, y + 0.3 * u, 2.4 * u, 2.4 * u),
          Paint()..color = _c(const [255, 255, 255], lights),
        );
      }
    }
    if (beacon) {
      _glow(canvas, Offset(x, y + 2.4 * u), 11 * u, const [255, 30, 30], 0.7 * lights);
      canvas.drawRect(
        Rect.fromLTWH(x - 1 * u, y + 2 * u, 2 * u, 2 * u),
        Paint()..color = _c(const [255, 70, 70], lights),
      );
    }
  }
}
