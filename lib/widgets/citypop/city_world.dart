import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart';

part 'city_buildings.dart';

/// The four parts of the day the street lives by (device clock).
enum CityPhase { morning, day, evening, night }

/// What the scene needs to know to draw one frame.
class CityParams {
  /// 0 day, 0.5 dusk, 1 night.
  final double tod;

  /// The part of the day: drives how busy the street is. Null keeps the old
  /// behaviour of reading it from [tod].
  final CityPhase? phase;

  /// 0 the city sleeps, 1 it lives fully (VPN: off ... on).
  final double alive;

  /// 0..1 failure: part of the city goes dark, signs stutter.
  final double fault;

  /// Strength multiplier of the film grade (1 normal, 0 off).
  final double grade;

  const CityParams({required this.tod, required this.alive, required this.fault, this.grade = 1, this.phase});
}

/// Glow of the one tube that starts like an old gas-discharge lamp: every 30
/// seconds it blinks three times in a row (short flashes that die away), then
/// burns evenly until the next time. 0 dark, 1 full.
double cityStarterGlow(double t) {
  final p = t % 30;
  if (p >= 1.4) return 1;
  const starts = [0.0, 0.42, 0.86], amps = [0.55, 0.75, 0.95];
  for (var i = 0; i < 3; i++) {
    final u = p - starts[i];
    if (u >= 0 && u < 0.22) return amps[i] * (1 - u / 0.22 * 0.6) * (u < 0.04 ? u / 0.04 : 1);
  }

  return 0;
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

//// Real street words of a Japanese shopping street. Katakana and hiragana
/// as much as kanji: ramen, coffee, karaoke, sushi, yakitori, records,
/// camera, pharmacy, snack bar, tea room, hotel, cinema, plus our own
/// «Марсик» in katakana. Owner 01.11: «везде кандзи - так не
/// бывает». No 珈琲 on the narrow vertical blades: its wide glyphs got cut.
const citySignHorizontal = ['ラーメン', 'コーヒー', 'カラオケ', 'すし', 'やきとり', 'レコード', 'カメラ', 'くすり', '喫茶', 'ホテル', 'マルシク'];
const citySignVertical = ['ラーメン', 'すし', 'くすり', 'スナック', 'カラオケ', 'そば', '喫茶', '映画', 'マルシク'];

class _CoastCar {
  double x;
  final double v;
  final List<double> col;
  _CoastCar(this.x, this.v, this.col);
}

class _Blade {
  final double s, x, z0, wid;
  final String text;
  final List<double> neon, paintCol;
  final double pos;
  final bool dk;
  _Blade(this.s, this.x, this.z0, this.wid, this.text, this.neon, this.paintCol, this.pos, this.dk);
}

enum _CarKind { car, taxi, coupe, police, ambulance, kei }

class _Car {
  String lane;
  double s, v;
  final int id;
  final bool front;
  final _CarKind kind;
  final List<double> col;
  final double x;
  double brake = 0, bt = 0;

  /// 0..1 how freely the car rolls: it eases to a stop before the zebra.
  double k = 1;
  bool get taxi => kind == _CarKind.taxi;
  bool get coupe => kind == _CarKind.coupe;
  bool get police => kind == _CarKind.police;
  bool get ambulance => kind == _CarKind.ambulance;
  bool get kei => kind == _CarKind.kei;
  _Car(this.lane, this.s, this.v, this.id, this.front, this.col, this.kind, this.x);
}

class _Ped {
  double s;
  double x;
  final double v, ph, gate;

  /// Standing at the kerb, waiting for the signal (and pressing the button).
  bool wait;

  /// Walking direction across the street while crossing: -1 to the left, 1 to the right.
  int dirX = 0;

  /// A pedestrian who crosses the street on the zebra in the walk phase.
  final bool crosser;
  final bool umb;
  final List<double> col, umbCol;

  /// Crossing pedestrian: 0 waits at the kerb, 1 crosses, 2 walks away along
  /// the pavement, 3 is gone and waits to come back.
  int cstate = 0;

  /// Seconds until this one presses the button after reaching the kerb.
  double pressIn = 0;
  bool pressed = false;

  /// seconds left before a gone pedestrian comes back.
  double respawnIn = 0;

  /// metres along the pavement left before this one disappears.
  double leaveLeft = 0;
  int leaveDir = 1;

  _Ped(
    this.s,
    this.v,
    this.x,
    this.ph,
    this.gate,
    this.umb,
    this.col,
    this.umbCol, {
    this.wait = false,
    this.crosser = false,
  });
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
  // lit rectangles of the far shore, kept per frame for the reflection
  final List<List<Rect>> _litWin = List.generate(4, (_) => []);
  final List<List<Rect>> _litSign = List.generate(5, (_) => []);
  final List<_Car> _cars = [];
  final List<_Car> _parked = [];
  final List<_Ped> _peds = [];
  final List<_Ped> _crossers = [];
  final List<_CoastCar> _coast = [];

  // The metro train on the viaduct at the far shore (city_buildings.dart).
  bool _trainActive = false;
  double _trainT0 = 0, _trainNext = 4;
  int _trainDir = -1, _trainCars = 8, _trainsRun = 0;
  final List<Rect> _litTrain = [];

  @visibleForTesting
  ({bool active, int cars, int dir, double t0}) get debugTrain =>
      (active: _trainActive, cars: _trainCars, dir: _trainDir, t0: _trainT0);

  /// The signal has no clock of its own: cars keep the green until somebody
  /// at the kerb presses the button. Then yellow, all-red, the walk (with its
  /// last two seconds blinking), all-red again and back to green. The all-red
  /// gaps empty the zebra before the other side moves.
  static const yellowTime = 2.5, allRedTime = 2.0, walkTime = 9.0, clearTime = 2.0;

  /// The zebra lies at depth 2.5..3.05 (shaders/city.frag). The stop line is
  /// set back from it by half a metre, so a stopped car does not hang over
  /// the stripes.
  static const zebraNear = 2.5, zebraFar = 3.05, stopLineA = 3.6, stopLineB = 2.0;

  /// 0 waits for a pedestrian, 1 yellow, 2 all-red before the walk, 3 walk,
  /// 4 all-red after the walk.
  int _light = 0;
  double _lightT = 0;
  bool _requested = false;

  /// Tests: without pedestrians nobody presses, so the cars stay on green.
  @visibleForTesting
  bool debugPedestrians = true;

  /// Signal state: car 0 green, 1 yellow, 2 red; ped 0 red man, 1 walk,
  /// 2 walk (blinking, do not start).
  ({int car, int ped}) get debugSignal => (car: _carSignal, ped: _pedSignal);
  int get _carSignal => switch (_light) {
    0 => 0,
    1 => 1,
    _ => 2,
  };
  int get _pedSignal => switch (_light) {
    3 => _lightT < walkTime - 2 ? 1 : 2,
    _ => 0,
  };

  @visibleForTesting
  List<({String lane, double s, int id})> get debugCars => [for (final c in _cars) (lane: c.lane, s: c.s, id: c.id)];

  /// Crossing pedestrians: x across the street (metres), whether they stand.
  @visibleForTesting
  List<({double x, bool waiting, bool crossing, bool leaving, bool gone})> get debugCrossers => [
    for (final c in _crossers)
      (x: c.x, waiting: c.cstate == 0, crossing: c.cstate == 1, leaving: c.cstate == 2, gone: c.cstate == 3),
  ];

  @visibleForTesting
  double get debugSimTime => _simT;
  final List<double> _poles = const [2.0, 3.7, 6.0, 9.4, 15.0];
  final List<double> _lamps = const [1.5, 2.6, 4.2, 6.6, 10.5, 16.0];
  double _simT = 0;

  /// Seconds since the VPN came up (alive crossed 0.9), -1 while it is off:
  /// every sign lights once with its starter flicker (item 15).
  double _connectT = -1;
  bool _wasAlive = false;
  double _planeNext = 0, _planeT0 = -1;
  int _planeDir = 1;
  bool planeForce = false;

  // cached static layer
  ui.Picture? _static, _staticFar, _staticRail;
  Size _staticSize = Size.zero;
  int _staticBucket = -1;

  // per-frame state
  double _tod = 1, _night = 1, _dayK = 0, _neonK = 1, _gs = 0.4;
  CityParams _p = const CityParams(tod: 1, alive: 0, fault: 0);
  double _time = 0;

  final Map<String, TextPainter> _text = {};

  int get carCount => _cars.length;

  /// How many buildings of each kind the street has: far shore types 0..4 as
  /// `far0`..`far4`, street facade kinds as `fac0`..`fac3`.
  @visibleForTesting
  Map<String, int> get debugBuildingKinds {
    final m = <String, int>{};
    for (final b in _far) {
      m.update('far${b.type}', (v) => v + 1, ifAbsent: () => 1);
    }
    for (final f in _fac) {
      m.update('fac${f.kind}', (v) => v + 1, ifAbsent: () => 1);
    }

    return m;
  }

  /// Far-shore buildings as rectangles (top-left origin) and the windows lit in
  /// the last painted frame.
  @visibleForTesting
  List<Rect> get debugFarBuildings => [for (final b in _far) Rect.fromLTWH(b.x, _hy - b.h, b.w, b.h)];

  @visibleForTesting
  List<Rect> get debugLitFarWindows => [for (final l in _litWin) ...l];

  /// Forces every far-shore window on (true) or off (false); null: normal.
  @visibleForTesting
  bool? debugForceFarWindows;

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
    _trainActive = false;
    _trainNext = 4;
    _trainDir = -1;
    _trainsRun = 0;
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
    _buildFar(r);
    _buildFac(r);
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
        ),
      );
    }
    _parked.clear();
    // No cars parked along the kerb: in Japan the street is no parking
    // almost everywhere (owner 01.11).
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
    _coast.clear();
    final cr = math.Random(seed + 991);
    for (var i = 0; i < 3; i++) {
      _coast.add(
        _CoastCar(
          cr.nextDouble() * _size.width,
          (6 + cr.nextDouble() * 7) * _u * (cr.nextBool() ? 1 : -1),
          _carColors[cr.nextInt(_carColors.length)],
        ),
      );
    }
    _crossers.clear();
    const gates = [0.0, 0.02, 0.05, 0.1, 0.2, 0.3];
    for (var i = 0; i < gates.length; i++) {
      final right = i.isEven;
      _crossers.add(
        _Ped(
          2.62 + 0.05 * i,
          0.12,
          right ? 0.9 + 0.1 * (i ~/ 2) : -5.6 - 0.1 * (i ~/ 2),
          pr.nextDouble() * 6,
          gates[i],
          pr.nextDouble() < 0.4,
          _paint[pr.nextInt(_paint.length)],
          [_neon[i % 5], _paint[(i + 2) % 6]][i % 2],
          wait: true,
          crosser: true,
        )..pressIn = 2.5 + gates[i] * 4.5,
      );
    }
  }

  _Car _mkCar(String lane, double s, double v, int id, bool front) {
    final r = math.Random(seed * 131 + id * 17);
    final roll = r.nextDouble();
    final kind = lane == 'P'
        ? _CarKind.car
        : roll < 0.03
        ? _CarKind.police
        : roll < 0.05
        ? _CarKind.ambulance
        : roll < 0.27
        ? _CarKind.taxi
        : roll < 0.47
        ? _CarKind.coupe
        : roll < 0.65
        ? _CarKind.kei
        : _CarKind.car;
    final col = switch (kind) {
      _CarKind.taxi => _carColors[0],
      _CarKind.police => const [26.0, 28.0, 36.0],
      _CarKind.ambulance => const [238.0, 238.0, 240.0],
      _CarKind.kei => _carColors[3 + r.nextInt(3)],
      _ => _carColors[r.nextInt(_carColors.length)],
    };

    return _Car(
      lane,
      s,
      v,
      id,
      // Japan drives on the left: A comes towards us on the right half of the
      // road (headlights), B goes away on the left half (tail lights).
      lane == 'A' ? true : (lane == 'B' ? false : front),
      col,
      kind,
      lane == 'A' ? -0.9 : (lane == 'B' ? -2.9 : -4.7),
    );
  }

  // -------------------------------------------------------------- simulation
  int _targetCars(CityParams p) {
    final t = p.tod;
    final base = switch (p.phase) {
      CityPhase.morning => 13,
      CityPhase.day => 8,
      CityPhase.evening => 13,
      CityPhase.night => 3,
      null => t < 0.5 ? _mix(6, 9, t * 2) : _mix(9, 3, (t - 0.5) * 2),
    };

    return math.max(1, (base * (0.35 + 0.65 * p.alive) * (1 - 0.45 * p.fault)).round());
  }

  /// How many of the passers-by are out. The gate of each one is fixed, so
  /// the same people stay home at night and come back in the morning.
  double _pedDensity(CityParams p) => switch (p.phase) {
    CityPhase.morning || CityPhase.evening => 1.0,
    CityPhase.day => 0.8,
    CityPhase.night => 0.35,
    null => _mix(1.0, 0.45, _night),
  };

  /// How many of the people are out now: the same gate for drawing them and
  /// for letting them press the signal button.
  double get _peopleOut => _pedDensity(_p) * (0.35 + 0.65 * _p.alive) * (1 - 0.45 * _p.fault);

  void step(double dt, CityParams p) {
    _p = p;
    _simT += dt;
    if (p.alive > 0.9 && !_wasAlive) {
      _connectT = 0;
    } else if (_connectT >= 0) {
      _connectT += dt;
    }
    if (p.alive < 0.25) _connectT = -1;
    _wasAlive = p.alive > 0.9;
    _stepLight(dt);
    final spd = 1 - 0.9 * p.fault;
    if (_cars.length < _targetCars(p) && _r.nextDouble() < dt * 0.9) {
      final lane = _r.nextDouble() < 0.55 ? 'A' : 'B';
      final s = lane == 'A' ? 24.0 : 0.78;
      if (!_cars.any((c) => c.lane == lane && (c.s - s).abs() < (lane == 'A' ? 3 : 0.5))) {
        // A city street at 30-40 km/h, not a highway.
        _cars.add(_mkCar(lane, s, (0.5 + _r.nextDouble() * 0.4) * (lane == 'A' ? -1 : 1), _r.nextInt(1000000), true));
      }
    }
    for (final c in _cars) {
      // Past its own stop line a car is committed: it clears the crossing at
      // its normal speed even in a failure. With the stop lines set back
      // from the zebra (owner 02.11) a car crawling there at the failure
      // speed met the red on the stripes.
      final committed = c.lane == 'A'
          ? c.s > zebraNear - 0.1 && c.s < stopLineA
          : c.s > stopLineB && c.s < zebraFar + 0.1;
      var v = c.v * (committed ? math.max(spd, 1.0) : spd);
      for (final o in _cars) {
        if (identical(o, c) || o.lane != c.lane) continue;
        final gap = (o.s - c.s) * (c.v < 0 ? -1 : 1);
        if (gap > 0 && gap < (c.lane == 'A' ? 2.2 * c.s * 0.25 + 0.5 : 0.4 + 0.12 * c.s)) {
          v = math.min(v.abs(), o.v.abs() * 0.6) * (c.v < 0 ? -1 : 1);
        }
      }
      // The signal: on yellow and red a car may not cross its stop line; it
      // eases to a stop before it (speed in proportion to the distance left).
      var target = 1.0;
      final sig = _carSignal;
      if (sig != 0) {
        final dist = c.lane == 'A' ? c.s - stopLineA : (c.lane == 'B' ? stopLineB - c.s : double.infinity);
        if (dist >= 0 && dist < 6) target = (dist / 0.9).clamp(0.0, 1.0);
      }
      c.k = target < c.k ? target : math.min(target, c.k + dt * 1.5);
      v *= c.k;
      c.s += v * dt * (c.lane == 'B' ? 1 + 0.18 * c.s : math.max(0.25, c.s * 0.25 + 0.4));
      c.bt -= dt;
      if (c.bt < 0 && _r.nextDouble() < dt * 0.15) c.bt = 0.6 + _r.nextDouble() * 0.8;
      c.brake = (p.fault > 0.4 || c.bt > 0 || c.k < 0.6) ? 1 : 0;
    }
    _cars.removeWhere((c) => c.s < 0.7 || c.s > 27);
    _stepCrossers(dt);
    _stepTrain();
    for (final c in _coast) {
      c.x += c.v * dt;
      if (c.x < -12 * _u) c.x = _size.width + 12 * _u;
      if (c.x > _size.width + 12 * _u) c.x = -12 * _u;
    }
    for (final pd in _peds) {
      pd.s += pd.v * dt * math.max(0.3, pd.s * 0.25);
      if (pd.s < 1.15) pd.s = 21;
      if (pd.s > 24) pd.s = 1.3;
    }
  }

  /// The signal stays green until a waiting pedestrian presses the button.
  void _stepLight(double dt) {
    _lightT += dt;
    switch (_light) {
      case 0:
        if (_requested) {
          _light = 1;
          _lightT = 0;
          _requested = false;
        }
      case 1:
        if (_lightT >= yellowTime) {
          _light = 2;
          _lightT = 0;
        }
      case 2:
        if (_lightT >= allRedTime) {
          _light = 3;
          _lightT = 0;
        }
      case 3:
        if (_lightT >= walkTime) {
          _light = 4;
          _lightT = 0;
        }
      default:
        if (_lightT >= clearTime) {
          _light = 0;
          _lightT = 0;
        }
    }
  }

  /// Pedestrians come to the kerb, press the button after a few seconds and
  /// cross at the start of the walk phase. Having crossed they walk away
  /// along the pavement and disappear; a new one comes later.
  void _stepCrossers(double dt) {
    final walk = _light == 3;
    for (final c in _crossers) {
      if (!debugPedestrians) continue;
      switch (c.cstate) {
        case 0:
          // Somebody who is not out does not press the button: with the VPN
          // off there are fewer people, but the signal still serves the ones
          // you see (owner 02.11: «без включённого VPN светофор не работает?
          // Должен»).
          if (c.gate > _peopleOut) continue;
          c.pressIn -= dt;
          if (c.pressIn <= 0) {
            c.pressed = true;
            if (_light == 0) _requested = true;
          }
          final zebraBusy = _cars.any((o) => o.s > zebraNear && o.s < zebraFar);
          if (walk && !zebraBusy && c.pressed && _lightT < 1.3 && _lightT >= c.gate * 1.3) {
            c.wait = false;
            c.pressed = false;
            c.cstate = 1;
            c.dirX = c.x > -2.5 ? -1 : 1;
          }
        case 1:
          final toLeft = c.dirX < 0;
          c.x += (toLeft ? -1 : 1) * 1.4 * dt;
          final done = toLeft ? c.x <= -5.6 : c.x >= 0.9;
          if (done) {
            c.x = toLeft ? -5.6 : 0.9;
            c.cstate = 2;
            c.leaveDir = c.gate < 0.5 ? 1 : -1;
            c.leaveLeft = 3.0 + c.gate * 8.0;
          }
        case 2:
          final step = 0.9 * dt;
          c.s += c.leaveDir * step;
          c.leaveLeft -= step;
          if (c.leaveLeft <= 0) {
            c.cstate = 3;
            c.respawnIn = 5 + c.gate * 10;
          }
        default:
          c.respawnIn -= dt;
          if (c.respawnIn <= 0) {
            final right = _ih((c.gate * 1000).round(), (_simT * 7).floor()).round().isEven;
            c.cstate = 0;
            c.wait = true;
            c.pressed = false;
            c.pressIn = 2.5 + c.gate * 4.5;
            c.s = 2.62 + (c.gate - 0.15).abs() * 0.2;
            c.x = right ? 0.9 : -5.6;
            c.dirX = right ? -1 : 1;
          }
      }
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
      // Two cached layers: the far shore, then the street's facades. The far
      // shore's lit windows are drawn between them, so they never show
      // through a facade (they did when both lived in one picture).
      final recFar = ui.PictureRecorder();
      _paintFarStatic(Canvas(recFar));
      _staticFar = recFar.endRecording();
      final recRail = ui.PictureRecorder();
      _paintRailStatic(Canvas(recRail));
      _staticRail = recRail.endRecording();
      final rec = ui.PictureRecorder();
      _paintNearStatic(Canvas(rec));
      _static = rec.endRecording();
      _staticSize = size;
      _staticBucket = bucket;
    }
    canvas.drawPicture(_staticFar!);
    _paintFarLit(canvas);
    _paintCoastStatic(canvas);
    _paintCoastCars(canvas);
    _paintRadioTower(canvas);
    canvas.drawPicture(_staticRail!);
    _paintTrain(canvas);
    _paintReflection(canvas);
    canvas.drawPicture(_static!);
    _paintNearLit(canvas);
    _paintSigns(canvas);
    _paintQuayWall(canvas);
    _paintRoadMarkings(canvas);
    final items = <(double, void Function())>[
      for (final c in _cars) (c.s, () => _paintCar(canvas, c)),
      for (final c in _parked) (c.s, () => _paintCar(canvas, c)),
      for (final pd in _peds) (pd.s, () => _paintPed(canvas, pd)),
      for (final pd in _crossers) (pd.s, () => _paintPed(canvas, pd)),
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
  List<double> get _hz => _p3([255, 205, 160], [255, 130, 100], [200, 56, 130], _tod);

  // ----------------------------------------------- tower, beacons, wires etc.
  void _paintRadioTower(Canvas canvas) {
    final hy = _hy, u = _u;
    final vis = (0.25 + 0.75 * _sm(0.25, 0.7, _tod)) * (1 - _p.fault * 0.5);
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
    // A Japanese signal: horizontal, «blue» (blue-green), yellow, red from
    // left to right. It runs on its own cycle whatever the VPN does; only a
    // failure makes the red one stutter.
    var on = [0, 0, 0];
    final sig = debugSignal;
    if (_p.fault > 0.5) {
      on = [0, 0, _ih(1, (_time * 9).floor()) < 0.7 ? 1 : 0];
    } else {
      on[sig.car] = 1;
    }
    const cols = [
      [40.0, 210.0, 190.0],
      [255.0, 200.0, 60.0],
      [255.0, 60.0, 60.0],
    ];
    for (var i = 0; i < 3; i++) {
      final c = Offset(hx + i * 0.4 * m, hy + 0.2 * m);
      canvas.drawCircle(c, 0.14 * m, Paint()..color = _c(_mixc(const [36, 36, 44], cols[i], on[i].toDouble())));
      if (on[i] == 1) _glow(canvas, c, 1.0 * m, cols[i], 0.7 * (0.35 + 0.65 * _mix(0.18, 1, _sm(0.1, 0.75, _tod))));
    }
    // The pedestrian signal on the same pole: a red standing man above, a blue
    // walking man below (blinking at the end of the walk phase).
    final bx = a.dx + 0.13 * m, by = _pt(0.1, 3.4, s).dy;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, 0.5 * m, 1.0 * m), Radius.circular(0.06 * m)),
      Paint()..color = _c(const [28, 28, 36]),
    );
    final walkOn = sig.ped == 1 || (sig.ped == 2 && ((_time * 3) % 1) < 0.5);
    final redOn = _p.fault > 0.5 ? _ih(2, (_time * 9).floor()) < 0.7 : sig.ped == 0;
    for (var i = 0; i < 2; i++) {
      final lit = i == 0 ? redOn : walkOn && _p.fault <= 0.5;
      final col = i == 0 ? cols[2] : cols[0];
      final c = Offset(bx + 0.25 * m, by + (0.27 + 0.46 * i) * m);
      final ink = Paint()..color = _c(_mixc(const [40, 40, 52], col, lit ? 1 : 0));
      canvas.drawCircle(c.translate(0, -0.14 * m), 0.055 * m, ink);
      canvas.drawRect(Rect.fromCenter(center: c.translate(0, 0.02 * m), width: 0.12 * m, height: 0.2 * m), ink);
      final leg = Paint()
        ..color = ink.color
        ..strokeWidth = math.max(0.6, 0.04 * m);
      final sw = i == 1 ? 0.07 * m : 0.0;
      canvas.drawLine(c.translate(0, 0.12 * m), c.translate(-0.05 * m - sw, 0.24 * m), leg);
      canvas.drawLine(c.translate(0, 0.12 * m), c.translate(0.05 * m + sw, 0.24 * m), leg);
      if (lit) _glow(canvas, c, 0.45 * m, col, 0.6 * (0.35 + 0.65 * _mix(0.18, 1, _sm(0.1, 0.75, _tod))));
    }
    // The push-button on the pole: a waiting pedestrian presses it, and it
    // answers with a warm blink until the walk starts.
    final pressed = _crossers.any((c) => c.cstate == 0 && c.pressed);
    final btn = Offset(bx + 0.25 * m, by + 1.22 * m);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: btn, width: 0.34 * m, height: 0.48 * m),
        Radius.circular(0.08 * m),
      ),
      Paint()..color = _c(const [40, 40, 50]),
    );
    final blink = pressed ? (0.55 + 0.45 * math.sin(_time * 7)) : 0.0;
    canvas.drawCircle(
      btn.translate(0, -0.04 * m),
      0.09 * m,
      Paint()..color = _c(_mixc(const [90, 66, 60], [255, 186, 92], blink)),
    );
    if (pressed) _glow(canvas, btn, 0.5 * m, const [255, 186, 92], 0.45 * blink);
  }

  void _paintRoadSign(Canvas canvas) {
    const s = 2.25;
    final a = _pt(0.95, 0, s), top = _pt(0.95, 4.0, s), m = _k / s;
    canvas.drawRect(
      Rect.fromLTRB(a.dx - 0.05 * m, top.dy, a.dx + 0.05 * m, a.dy),
      Paint()..color = _c(const [120, 120, 130]),
    );
    // The Japanese 407-A: a blue square, a white triangle, a black pedestrian.
    final c = Offset(top.dx, top.dy - 0.22 * m);
    final side = 0.94 * m;
    final plate = Rect.fromCenter(center: c, width: side, height: side);
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate, Radius.circular(0.1 * m)),
      Paint()..color = _c(const [34, 86, 184]),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(plate.deflate(0.05 * m), Radius.circular(0.08 * m)),
      Paint()
        ..color = _c(const [244, 244, 240])
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.04 * m,
    );
    final tri = Path()
      ..moveTo(c.dx, c.dy - 0.36 * m)
      ..lineTo(c.dx + 0.36 * m, c.dy + 0.3 * m)
      ..lineTo(c.dx - 0.36 * m, c.dy + 0.3 * m)
      ..close();
    canvas.drawPath(tri, Paint()..color = _c(const [244, 244, 240]));
    // The walker of 407-A: a head, a torso leaning forward, both arms
    // swinging and a long stride, standing on a strip of zebra bars (owner
    // 02.11: the old one was a stick «λ» without arms). The sign is about
    // 30 px on a phone, so every part is a thick round stroke.
    final ink = Paint()
      ..color = _c(const [22, 22, 26])
      ..strokeWidth = 0.05 * m
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    Offset at(double x, double y) => Offset(c.dx + x * m, c.dy + y * m);
    canvas.drawCircle(at(0.035, -0.17), 0.05 * m, Paint()..color = ink.color);
    canvas.drawLine(at(0.02, -0.1), at(-0.01, 0.05), ink); // torso
    canvas.drawPath(
      Path()
        ..moveTo(at(0.015, -0.08).dx, at(0.015, -0.08).dy)
        ..lineTo(at(0.075, -0.02).dx, at(0.075, -0.02).dy)
        ..lineTo(at(0.11, 0.03).dx, at(0.11, 0.03).dy),
      ink,
    ); // front arm
    canvas.drawPath(
      Path()
        ..moveTo(at(0.015, -0.08).dx, at(0.015, -0.08).dy)
        ..lineTo(at(-0.05, -0.02).dx, at(-0.05, -0.02).dy)
        ..lineTo(at(-0.09, 0.02).dx, at(-0.09, 0.02).dy),
      ink,
    ); // back arm
    canvas.drawPath(
      Path()
        ..moveTo(at(-0.01, 0.05).dx, at(-0.01, 0.05).dy)
        ..lineTo(at(0.06, 0.11).dx, at(0.06, 0.11).dy)
        ..lineTo(at(0.1, 0.17).dx, at(0.1, 0.17).dy),
      ink,
    ); // front leg
    canvas.drawPath(
      Path()
        ..moveTo(at(-0.01, 0.05).dx, at(-0.01, 0.05).dy)
        ..lineTo(at(-0.05, 0.12).dx, at(-0.05, 0.12).dy)
        ..lineTo(at(-0.12, 0.16).dx, at(-0.12, 0.16).dy),
      ink,
    ); // back leg
    // the zebra under the feet: four black bars
    final bar = Paint()..color = ink.color;
    for (var i = 0; i < 4; i++) {
      final x0 = -0.21 + i * 0.12;
      canvas.drawRect(Rect.fromLTRB(c.dx + x0 * m, c.dy + 0.205 * m, c.dx + (x0 + 0.07) * m, c.dy + 0.255 * m), bar);
    }
  }

  /// Japanese crossing: wide white bars along the road (the shader draws
  /// them), a stop line set back from them on each lane and the warning
  /// diamond ◇ on the approach.
  void _paintRoadMarkings(Canvas canvas) {
    final white = _c(const [244, 240, 226], _mix(0.5, 0.72, _night));
    void bar(double x0, double x1, double s0, double s1) {
      _quad(canvas, [_pt(x0, 0, s0), _pt(x1, 0, s0), _pt(x1, 0, s1), _pt(x0, 0, s1)], white);
    }

    // Lane A (towards us): stop line 0.55 m before the zebra; lane B: 0.5 m.
    bar(-1.9, 0.4, stopLineA, stopLineA + 0.12);
    bar(-5.4, -1.9, stopLineB - 0.12, stopLineB);
    void diamond(double x, double s) {
      final pts = [_pt(x, 0, s - 0.5), _pt(x + 0.38, 0, s), _pt(x, 0, s + 0.5), _pt(x - 0.38, 0, s)];
      canvas.drawPath(
        Path()..addPolygon(pts, true),
        Paint()
          ..color = white
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.6, 0.07 * _k / s),
      );
    }

    diamond(-0.9, 4.6);
    diamond(-2.9, 1.0);
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
    g *= _connectBurst(id);

    return g;
  }

  /// The starter flicker of one sign when the VPN comes up: its own delay
  /// 0..1 s, then 2-4 uneven flashes, then a steady light. After the burst
  /// (and when the scene was already alive) it is 1.
  double _connectBurst(int id) {
    if (_connectT < 0) return 1;
    final u = _connectT - _ih(id, 7);
    if (u < 0) return 0;
    final flashes = 2 + (_ih(id, 11) * 3).floor();
    final step = 0.44;
    if (u >= flashes * step) return 1;
    final amp = 0.45 + 0.55 * _ih(id, 13);
    final phase = (u / step) % 1;
    // a short strike, a long dark gap: uneven, like a gas tube
    return phase < 0.34 - 0.1 * _ih(id, 17) ? amp : 0;
  }

  /// Which letter of which blade sign has the old starter-lit tube.
  static const _starterBlade = 2, _starterLetter = 1;

  /// How lit a letter of blade sign [blade] is at [t] seconds, for a lit
  /// sign (1 = steadily on). All letters burn all the time; only the starter
  /// letter flickers (see [cityStarterGlow]).
  @visibleForTesting
  double debugLetterGlow(int blade, int letter, double t) =>
      blade == _starterBlade && letter == _starterLetter ? cityStarterGlow(t) : 1.0;

  void _paintSigns(Canvas canvas) {
    for (var bi = 0; bi < _blades.length; bi++) {
      final b = _blades[bi];
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
      // Written top to bottom, the long vowel mark stands upright.
      final runes = b.text.runes.map(String.fromCharCode).map((c) => c == 'ー' ? '｜' : c).toList();
      for (var i = 0; i < runes.length; i++) {
        final cy = y + (0.25 + (i + 0.5) * 0.95) * m;
        var on = nk;
        on *= debugLetterGlow(bi, i, _time);
        // Never wider than the blade: 映 lost its left half and read as 央.
        final size = math.max(4.0, math.min(0.82 * m, 0.78 * w));
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
    if (c.police) {
      rect(-0.92, 0.5, 0.92, 0.85, const [246, 244, 238]);
    } else if (c.ambulance) {
      rect(-0.92, 0.18, 0.92, 0.85, const [242, 240, 236]);
      rect(-0.92, 0.42, 0.92, 0.53, const [214, 40, 46]);
    }
    if (_dayK > 0.05) rect(0.55, 0.18, 0.92, 0.85, const [255, 232, 190], 0.20 * _dayK);
    final roofH = c.kei ? 1.78 : (c.coupe ? 1.38 : 1.52), cw = c.kei ? 0.7 : (c.coupe ? 0.68 : 0.62);
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
    if (c.police || c.ambulance) {
      final bp = Offset(p.dx, p.dy - (roofH + 0.22) * m);
      _glow(canvas, bp, 3.0 * m, const [255, 54, 62], 0.18 + 0.72 * n);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: bp, width: 0.46 * m, height: 0.2 * m),
          Radius.circular(0.05 * m),
        ),
        Paint()..color = _c(_mixc(const [150, 34, 40], const [255, 70, 80], 0.35 + 0.65 * n)),
      );
    }
  }

  // ------------------------------------------------------------------ people
  void _paintPed(Canvas canvas, _Ped p) {
    if (p.crosser && p.cstate == 3) return;
    final pos = _pt(p.x, 0, p.s);
    final m = _k / p.s;
    if (m < 1.2 || pos.dy > _size.height) return;
    if (p.gate > _peopleOut) return;
    final ph = p.ph + _time * 5.2 * p.v.abs() / 0.12 * 0.7;
    final sw = p.wait ? 0.0 : math.sin(ph) * 0.22, bob = p.wait ? 0.0 : math.cos(ph).abs() * 0.03;
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
  /// For screenshots: the next plane flies in [planeForceDir] (1 right = takes
  /// off, -1 left = lands), already [planeForceAge] seconds into its flight.
  int planeForceDir = -1;
  double planeForceAge = 7;

  /// The plane's flight: position of the fuselage centre, pitch of the nose
  /// (radians, up positive), the climb path as dy per px of forward travel and
  /// how far the landing gear is down (1 down, 0 retracted).
  /// To the right it takes off: nose about 9 degrees up, a gentle climb, gear
  /// up two or three seconds after the start. To the left it lands: a 3 degree
  /// glide slope, nose 2.5 degrees up, gear down.
  ({double x, double y, double pitch, double slope, double gear}) _planePose(double uu, double t) {
    final w = _size.width, h = _size.height;
    if (_planeDir > 0) {
      final x = _mix(-0.08 * w, 1.08 * w, uu);
      final y = 0.30 * h - 0.13 * w * math.pow(uu, 1.35);
      final slope = -0.13 * w * 1.35 * math.pow(math.max(uu, 0.001), 0.35) / (1.16 * w);
      final age = uu * 17;

      return (x: x, y: y, pitch: 9 * math.pi / 180, slope: slope, gear: 1 - _sm(2.2, 3.6, age));
    }
    final x = _mix(1.08 * w, -0.08 * w, uu);
    final tan3 = math.tan(3 * math.pi / 180);

    return (x: x, y: 0.27 * h + uu * 1.16 * w * tan3, pitch: 2.5 * math.pi / 180, slope: tan3, gear: 1);
  }

  void _paintPlane(Canvas canvas) {
    final u = _u, t = _time;
    if (planeForce) {
      _planeT0 = t - planeForceAge;
      _planeNext = 1e9;
      planeForce = false;
      _planeDir = planeForceDir;
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
    final pose = _planePose(uu, t);
    final dir = _planeDir.toDouble();
    // The fuselage is 23 q long; the old plane was 20.9 u: q = 1.18 u makes it 1.3 times bigger.
    final q = 1.18 * u;
    final cs = math.cos(pose.pitch), sn = math.sin(pose.pitch);
    // Fuselage coordinates (forward, down) in units of q to the screen.
    Offset at(double v, double y) => Offset(pose.x + dir * (v * cs + y * sn) * q, pose.y + (-v * sn + y * cs) * q);
    Path poly(List<List<double>> pts) {
      final path = Path();
      for (var i = 0; i < pts.length; i++) {
        final o = at(pts[i][0], pts[i][1]);
        i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
      }

      return path..close();
    }

    final lights = _sm(0.3, 0.6, _tod);
    final bodyA = 0.9 * (1 - _night * 0.85);
    final bodyColor = _c(_mixc(const [240, 238, 240], const [48, 24, 70], _tod > 0.4 ? 0.9 : 0), bodyA);
    final farColor = _c(_mixc(const [214, 212, 220], const [40, 20, 62], _tod > 0.4 ? 0.9 : 0), bodyA);
    final tail = at(-11.8, -0.4);
    if (_dayK > 0.15) {
      final p0 = tail, p1 = Offset(tail.dx - dir * 160 * u, tail.dy - pose.slope * 160 * u);
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
    final body = Paint()..color = bodyColor;
    // Side elevation: the span is foreshortened, rather than a plan-view V.
    canvas.drawPath(
      poly(const [
        [2.4, 0.0],
        [-3.8, -0.85],
        [-5.5, -0.85],
        [-1.5, 0.5],
      ]),
      Paint()..color = farColor,
    );
    final fus = Path();
    void m(Path pth, double v, double y, {bool first = false}) {
      final o = at(v, y);
      first ? pth.moveTo(o.dx, o.dy) : pth.lineTo(o.dx, o.dy);
    }

    // The fuselage outline: a rounded nose, a long barrel, an up-swept tail cone.
    // 23.1 q / 2.1 q = 11:1, matching the 54.9 m / 5 m barrel proportions.
    final nose = at(11.2, 0.2), noseTop = at(8.4, -1.05), noseCtl = at(10.1, -1.05);
    fus.moveTo(nose.dx, nose.dy);
    fus.quadraticBezierTo(noseCtl.dx, noseCtl.dy, noseTop.dx, noseTop.dy);
    m(fus, -7.1, -1.05);
    final t1 = at(-9, -1.05), t2 = at(-10.4, -0.55), t3 = at(-11.9, -0.4);
    fus.cubicTo(t1.dx, t1.dy, t2.dx, t2.dy, t3.dx, t3.dy);
    final b1 = at(-10, 0.0), b2 = at(-8, 1.05), b3 = at(-5.5, 1.05);
    fus.cubicTo(b1.dx, b1.dy, b2.dx, b2.dy, b3.dx, b3.dy);
    m(fus, 7.5, 1.05);
    final n1 = at(10.3, 1.05);
    fus.quadraticBezierTo(n1.dx, n1.dy, nose.dx, nose.dy);
    canvas.drawPath(fus, body);
    canvas.drawPath(
      poly(const [
        [-7.1, -1.05],
        [-10.1, -4.2],
        [-11.3, -4.2],
        [-10.5, -0.65],
      ]),
      body,
    );
    canvas.drawPath(
      poly(const [
        [-8.5, -0.05],
        [-11.7, -0.9],
        [-12.0, -0.9],
        [-10.6, 0.35],
      ]),
      body,
    );
    canvas.drawPath(
      poly(const [
        [3.0, 0.25],
        [-3.6, -0.7],
        [-5.7, -0.7],
        [-1.1, 0.65],
      ]),
      Paint()..color = farColor,
    );
    // engine under the near wing
    // Build the nacelle in aircraft coordinates so it follows the pitch too.
    final engine = Path();
    m(engine, 3.5, 0.65, first: true);
    m(engine, 1.1, 0.65);
    final e0 = at(0.6, 1.3), e1 = at(1.1, 1.95);
    engine.quadraticBezierTo(e0.dx, e0.dy, e1.dx, e1.dy);
    m(engine, 3.5, 1.85);
    engine.close();
    canvas.drawPath(engine, Paint()..color = farColor);
    // landing gear: a nose leg and a main leg with two wheels
    if (pose.gear > 0.02) {
      final leg = Paint()
        ..color = bodyColor
        ..strokeWidth = math.max(0.8, 0.28 * q)
        ..strokeCap = StrokeCap.round;
      final g = pose.gear;
      // Fin to main-wheel bottom: 6.65 q / 23.1 q, about 15.8 m / 54.9 m.
      final n0 = at(8.0, 1.05), n1 = at(8.0, 1.05 + 0.85 * g);
      canvas.drawLine(n0, n1, leg);
      canvas.drawCircle(n1, 0.25 * q * g, body);
      final g0 = at(-1.0, 1.05), g1 = at(-1.0, 1.05 + 1.08 * g);
      canvas.drawLine(g0, g1, leg);
      for (final dv in const [-0.32, 0.32]) {
        canvas.drawCircle(at(-1.0 + dv, 1.05 + 1.13 * g), 0.27 * q * g, body);
      }
    }
    // cabin windows: a thin row of lit dots at night, nothing by day
    if (_neonK > 0.1) {
      final win = Paint()
        ..blendMode = BlendMode.plus
        ..color = _c(const [255, 236, 190], 0.85 * _neonK);
      for (var v = 8.2; v > -8.5; v -= 0.62) {
        canvas.drawCircle(at(v, -0.35), math.max(0.35, 0.16 * q), win);
      }
    }
    if (lights < 0.02) return;
    final ph = (t * 0.83) % 1;
    final strobe = ph < 0.05 || (ph > 0.14 && ph < 0.19); // double flash like an Airbus
    final beacon = ((t * 1.1 + 0.3) % 1.5) < 0.18;
    // Lights as on an Airbus seen from the side: the navigation light on the
    // wingtip of the near wing (flying left we see the left side, red; right,
    // green), white on the tail, red beacons above and below the fuselage,
    // white strobes on the wingtip and the tail.
    final wingTip = at(-5.7, -0.7);
    final nav = _planeDir < 0 ? const [255.0, 40.0, 40.0] : const [40.0, 255.0, 90.0];
    void dot(Offset c, List<double> col, double glow, double a) {
      _glow(canvas, c, glow * u, col, 0.6 * a * lights);
      canvas.drawRect(Rect.fromCenter(center: c, width: 1.8 * u, height: 1.8 * u), Paint()..color = _c(col, lights));
    }

    dot(wingTip, nav, 8, 0.9);
    dot(tail, const [255.0, 255.0, 255.0], 6, 0.7);
    if (strobe) {
      for (final c in [wingTip, tail]) {
        dot(c, const [255.0, 255.0, 255.0], 16, 1.4);
      }
    }
    if (beacon) {
      for (final c in [at(1.0, -1.6), at(1.0, 1.6)]) {
        dot(c, const [255.0, 40.0, 40.0], 11, 1.1);
      }
    }
  }
}
