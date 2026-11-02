import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:trusttunnel/widgets/citypop/city_world.dart';

/// Time of day for the scene: 0 day, 0.5 dusk, 1 night. From the device clock
/// alone: night 21..5, day 8..16, dusk around 6 and 18. The dark theme no
/// longer decides the scene (owner 01.11: the street showed night at 14:00
/// because the phone was in the dark theme); it only styles the controls.
abstract final class CityClock {
  static double todAt(DateTime now, {bool dark = false}) {
    final h = now.hour + now.minute / 60;
    const keys = [(0.0, 1.0), (5.0, 1.0), (6.0, 0.5), (8.0, 0.0), (16.0, 0.0), (18.0, 0.5), (20.0, 1.0), (24.0, 1.0)];
    for (var i = 0; i < keys.length - 1; i++) {
      if (h >= keys[i].$1 && h <= keys[i + 1].$1) {
        final t = (h - keys[i].$1) / (keys[i + 1].$1 - keys[i].$1);

        return keys[i].$2 + (keys[i + 1].$2 - keys[i].$2) * t;
      }
    }

    return 1;
  }

  /// The four parts of the day: morning 6..10, day 10..17, evening 17..21,
  /// night 21..6. The scene changes smoothly at the borders: the sky and the
  /// lights move by [todAt], the street slowly fills and empties.
  static CityPhase phaseAt(DateTime now) {
    final h = now.hour + now.minute / 60;
    if (h >= 6 && h < 10) return CityPhase.morning;
    if (h >= 10 && h < 17) return CityPhase.day;
    if (h >= 17 && h < 21) return CityPhase.evening;

    return CityPhase.night;
  }

  /// The phase for a fixed frame ([tod] 0 day, 0.5 dusk, 1 night).
  static CityPhase phaseForTod(double tod) {
    if (tod < 0.2) return CityPhase.day;
    if (tod < 0.6) return CityPhase.evening;

    return CityPhase.night;
  }
}

/// The loaded fragment program, once for the whole app.
abstract final class _CityShader {
  static Future<ui.FragmentProgram?>? _future;

  static Future<ui.FragmentProgram?> load() => _future ??= ui.FragmentProgram.fromAsset(
    'shaders/city.frag',
  ).then<ui.FragmentProgram?>((p) => p).catchError((Object _) => null);
}

/// The «City pop» scene: shader (sky, water, wet road, film), the objects of
/// [CityWorld] on top, the film pass over everything.
///
/// - [alive] 0..1 and [fault] 0..1 (VPN state) and the time of day move by
///   springs, so the city lights up or goes dark in 1-2 s;
/// - 30 frames/s; the ticker stops by itself when the route is covered
///   (TickerMode) and here when the app is not resumed;
/// - with [MediaQuery.disableAnimations] on, one still frame is drawn;
/// - [still] draws one deterministic frame at that time (tests, screenshots).
class CityScene extends StatefulWidget {
  final double alive;
  final double fault;
  final bool dark;

  /// Overrides the clock (0 day, 0.5 dusk, 1 night).
  final double? timeOfDay;
  final double? still;
  final int seed;
  final bool planeNow;
  final double grade;

  const CityScene({
    super.key,
    required this.alive,
    this.fault = 0,
    this.dark = false,
    this.timeOfDay,
    this.still,
    this.seed = 7,
    this.planeNow = false,
    this.grade = 1,
  });

  @override
  State<CityScene> createState() => _CitySceneState();
}

class _CitySceneState extends State<CityScene> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final Ticker _ticker;
  late CityWorld _world;
  final _frame = ValueNotifier<int>(0);
  ui.FragmentShader? _scene, _film;
  Duration _last = Duration.zero;
  Duration _paintAt = Duration.zero;
  double _time = 0;
  bool _reduce = false;
  bool _resumed = true;

  // springs: position and velocity
  double _alive = 0, _aliveV = 0, _fault = 0, _faultV = 0, _tod = 1, _todV = 0;

  double get _todTarget => widget.timeOfDay ?? CityClock.todAt(DateTime.now());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _world = CityWorld(seed: widget.seed)..planeForce = widget.planeNow;
    _alive = widget.alive;
    _fault = widget.fault;
    _tod = widget.timeOfDay ?? CityClock.todAt(DateTime.now());
    _ticker = createTicker(_onTick);
    _CityShader.load().then((program) {
      if (!mounted) return;
      if (program != null) {
        _scene = program.fragmentShader();
        _film = program.fragmentShader();
      }
      _frame.value++;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(CityScene old) {
    super.didUpdateWidget(old);
    if (_reduce || widget.still != null) {
      _alive = widget.alive;
      _fault = widget.fault;
      _tod = _todTarget;
      _frame.value++;
    }
    _syncTicker();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    _syncTicker();
  }

  void _syncTicker() {
    final run = _resumed && !_reduce && widget.still == null;
    if (run && !_ticker.isActive) {
      // A restarted ticker counts from zero again. With the old _paintAt the
      // 30 fps gate below stayed shut for as long as the scene had run before
      // the pause: a screenshot (the app goes inactive for a moment) froze
      // every animation (S22, 01.11).
      _last = Duration.zero;
      _paintAt = Duration.zero;
      _ticker.start();
    } else if (!run && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _spring(double target, double x, double v, double k, double c, double dt, void Function(double, double) set) {
    final a = -k * (x - target) - c * v;
    var nv = v + a * dt;
    var nx = x + nv * dt;
    if ((nx - target).abs() < 1e-4 && nv.abs() < 1e-4) {
      nx = target;
      nv = 0;
    }
    set(nx, nv);
  }

  void _onTick(Duration elapsed) {
    if (elapsed - _paintAt < const Duration(milliseconds: 32)) return;
    final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = elapsed;
    _paintAt = elapsed;
    _time += dt;
    _spring(widget.alive, _alive, _aliveV, 5, 3.6, dt, (x, v) {
      _alive = x;
      _aliveV = v;
    });
    _spring(widget.fault, _fault, _faultV, 9, 5, dt, (x, v) {
      _fault = x;
      _faultV = v;
    });
    _spring(_todTarget, _tod, _todV, 3, 3.5, dt, (x, v) {
      _tod = x;
      _todV = v;
    });
    _world.step(dt, _params);
    _frame.value++;
  }

  CityParams get _params => CityParams(
    tod: _tod.clamp(0, 1),
    alive: _alive.clamp(0, 1.2),
    fault: _fault.clamp(0, 1),
    grade: widget.grade,
    phase: widget.timeOfDay != null ? CityClock.phaseForTod(widget.timeOfDay!) : CityClock.phaseAt(DateTime.now()),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    _scene?.dispose();
    _film?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(
      painter: _CityPainter(
        repaint: _frame,
        state: this,
      ),
      size: Size.infinite,
    ),
  );
}

class _CityPainter extends CustomPainter {
  final _CitySceneState state;

  _CityPainter({required Listenable repaint, required this.state}) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = state;
    final p = s._params;
    final still = s.widget.still;
    final time = still ?? s._time;
    if (still != null) s._world.warmUp(still, p);
    final rect = Offset.zero & size;
    final traffic = (0.4 + 0.6 * p.alive).clamp(0.0, 1.0) * 0.6;

    void shaderPass(ui.FragmentShader? sh, double pass) {
      if (sh == null) return;
      sh
        ..setFloat(0, time % 600)
        ..setFloat(1, size.width)
        ..setFloat(2, size.height)
        ..setFloat(3, p.alive.clamp(0.0, 1.0))
        ..setFloat(4, traffic)
        ..setFloat(5, p.tod)
        ..setFloat(6, p.fault)
        ..setFloat(7, 0.40)
        ..setFloat(8, pass)
        ..setFloat(9, p.grade);
      canvas.drawRect(rect, Paint()..shader = sh);
    }

    if (s._scene != null) {
      shaderPass(s._scene, 0);
    } else {
      // No shader (still loading, or not supported): a plain dusk gradient.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset.zero,
            Offset(0, size.height * 0.45),
            const [Color(0xFF241046), Color(0xFFB04D80), Color(0xFFFFC890)],
            const [0, 0.7, 1],
          )
          ..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, size.height * 0.40, size.width, size.height * 0.6),
        Paint()..color = const Color(0xFF2A1A44),
      );
    }
    s._world.paint(canvas, size, time, p);
    shaderPass(s._film, 1);
  }

  @override
  bool shouldRepaint(_CityPainter old) => false;
}

/// For tests and for a calm backdrop: whether the shader program loads.
Future<bool> cityShaderLoads() async => (await _CityShader.load()) != null;
