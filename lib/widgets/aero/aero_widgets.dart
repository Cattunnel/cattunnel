import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/widgets/aero/aero_scene.dart';

export 'package:trusttunnel/widgets/aero/aero_scene.dart' show AeroPhase, AeroScene;

/// Colors of the «Аэро» style beyond the theme palettes.
abstract final class AeroColors {
  static const lime = Color(0xFFA6EC2C);
  static const limeNight = Color(0xFFC4FF3D);
  static const sky = Color(0xFF1A7BE6);
  static const ink = Color(0xFF08305E);
}

/// The time of day the «Аэро» style shows: morning 5-10, day 10-17,
/// evening 17-21, night 21-5 by the phone's clock, checked every minute
/// while the style is on (App starts and stops it).
abstract final class AeroClock {
  static final phase = ValueNotifier<AeroPhase>(phaseAt(DateTime.now()));
  static Timer? _timer;

  static AeroPhase phaseAt(DateTime time) => switch (time.hour) {
    >= 5 && < 10 => AeroPhase.morning,
    >= 10 && < 17 => AeroPhase.day,
    >= 17 && < 21 => AeroPhase.evening,
    _ => AeroPhase.night,
  };

  static void start() {
    phase.value = phaseAt(DateTime.now());
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) => phase.value = phaseAt(DateTime.now()));
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Marks the «Аэро» theme (only its ThemeData carries it): widgets ask
/// [AeroContext.isAero]; [night] says which of its two themes it is.
class AeroStyle extends ThemeExtension<AeroStyle> {
  final bool night;

  const AeroStyle({required this.night});

  @override
  AeroStyle copyWith({bool? night}) => AeroStyle(night: night ?? this.night);

  @override
  AeroStyle lerp(AeroStyle? other, double t) => t < 0.5 || other == null ? this : other;
}

extension AeroContext on BuildContext {
  bool get isAero => Theme.of(this).extension<AeroStyle>() != null;

  bool get isAeroNight => Theme.of(this).extension<AeroStyle>()?.night ?? false;
}

/// Phone tilt for the parallax, from the accelerometer, -1..1 on both axes.
/// It drifts back to the middle when the phone is held still, so only
/// movement shows. Only on Android/iOS; one sensor stream for all backdrops.
abstract final class _Tilt {
  static final value = ValueNotifier<Offset>(Offset.zero);
  static StreamSubscription<AccelerometerEvent>? _sub;
  static int _users = 0;
  static Offset? _base;

  static bool get _supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static void attach() {
    _users++;
    if (_sub != null || !_supported) return;
    try {
      _sub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
        (e) {
          final now = Offset(e.x, e.y);
          final base = _base = _base == null ? now : Offset.lerp(_base, now, 0.02);
          final d = now - base!;
          value.value = Offset((d.dx / 2.5).clamp(-1.0, 1.0), (-d.dy / 2.5).clamp(-1.0, 1.0));
        },
        onError: (_) {},
        cancelOnError: true,
      );
    } catch (_) {}
  }

  static void detach() {
    _users--;
    if (_users > 0) return;
    unawaited(_sub?.cancel());
    _sub = null;
    _base = null;
    value.value = Offset.zero;
  }
}

/// The whole-screen «Аэро» landscape for the current [AeroClock] phase,
/// alive (clouds, water, bubbles or fireflies, sun rays) and shifting by
/// depth with the phone's tilt. [calm]: the version for the other screens -
/// horizon lower, a light veil, no flare or bubbles. Reduce motion: still.
class AeroBackdrop extends StatefulWidget {
  final Widget child;
  final bool calm;

  const AeroBackdrop({super.key, required this.child, this.calm = false});

  @override
  State<AeroBackdrop> createState() => _AeroBackdropState();
}

class _AeroBackdropState extends State<AeroBackdrop> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  Offset _tilt = Offset.zero;
  bool _still = false;

  @override
  void initState() {
    super.initState();
    _Tilt.attach();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.of(context).disableAnimations;
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      unawaited(_ticker.start());
    }
  }

  void _tick(Duration elapsed) {
    // Ease towards the tilt so the layers glide instead of jumping.
    _tilt = Offset.lerp(_tilt, _Tilt.value.value, 0.08)!;
    _time.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _Tilt.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<AeroPhase>(
    valueListenable: AeroClock.phase,
    builder: (context, phase, child) => Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: _time,
            builder: (context, time, _) => CustomPaint(
              painter: AeroScenePainter(
                scene: AeroScene.of(phase),
                phase: phase,
                calm: widget.calm,
                pixelRatio: MediaQuery.devicePixelRatioOf(context),
                time: time,
                tilt: _still ? Offset.zero : _tilt,
              ),
            ),
          ),
        ),
        child!,
      ],
    ),
    child: widget.child,
  );
}

/// A glossy title: white letters with a Vista-style split shine (the lower
/// half slightly tinted), a soft drop shadow and a glow.
class AeroTitle extends StatelessWidget {
  final String text;
  final double size;

  const AeroTitle(this.text, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    final night = context.isAeroNight;
    final style = TextStyle(
      fontFamily: FontFamilies.nunito,
      fontWeight: FontWeight.w900,
      fontSize: size,
      height: 1.1,
      letterSpacing: -0.3,
    );

    return Stack(
      children: [
        Transform.translate(
          offset: const Offset(0, 2),
          child: Text(
            text,
            style: style.copyWith(
              color: night ? const Color(0xCC00143C) : const Color(0x8C0046A0),
              shadows: [Shadow(color: Colors.white.withValues(alpha: night ? 0.15 : 0.5), blurRadius: 14)],
            ),
          ),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              night ? const Color(0xFFA9D8FF) : const Color(0xFFD7EFFF),
              Colors.white,
            ],
            stops: const [0, 0.48, 0.52, 1],
          ).createShader(bounds),
          child: Text(text, style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}

/// Frosted glass with a wet highlight on its top half, a white edge and a
/// soft shadow - cards, pills, the status panel.
class AeroGlass extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool highlighted;

  /// A few dew drops on the glass (the bigger cards).
  final bool drops;

  const AeroGlass({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 24,
    this.padding = EdgeInsets.zero,
    this.highlighted = false,
    this.drops = false,
  });

  @override
  Widget build(BuildContext context) {
    final night = context.isAeroNight;
    final shape = BorderRadius.circular(radius);
    final lime = night ? AeroColors.limeNight : AeroColors.lime;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: night ? const Color(0x66000814) : const Color(0x33003C28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (highlighted) BoxShadow(color: lime.withValues(alpha: 0.35), blurRadius: 18),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: CustomPaint(
          foregroundPainter: drops ? const _DropsPainter() : null,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: shape,
                  color: highlighted
                      ? (night ? const Color(0x73285A3C) : const Color(0xBFEBFFD2))
                      : (night ? const Color(0xB30E2C5A) : const Color(0xB8FFFFFF)),
                  border: Border.all(
                    color: highlighted ? lime : (night ? const Color(0x738CD2FF) : const Color(0xF2FFFFFF)),
                    width: highlighted ? 2 : 1,
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 34,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: night ? 0.16 : 0.75),
                                Colors.white.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(padding: padding, child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The connect button: a glass bubble with Marsik inside. Off: the bubble
/// is pale and Marsik sleeps; connecting: a turning ring; on: the bubble
/// fills with light from below and a lime ring circles it.
class AeroConnectButton extends StatefulWidget {
  final VpnState state;
  final String label;
  final double size;
  final VoidCallback onTap;

  const AeroConnectButton({super.key, required this.state, required this.label, required this.onTap, this.size = 224});

  @override
  State<AeroConnectButton> createState() => _AeroConnectButtonState();
}

class _AeroConnectButtonState extends State<AeroConnectButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      unawaited(_spin.repeat());
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  bool get _trouble => switch (widget.state) {
    VpnState.waitingForRecovery || VpnState.recovering || VpnState.waitingForNetwork => true,
    _ => false,
  };

  @override
  Widget build(BuildContext context) {
    final night = context.isAeroNight;
    final on = widget.state == VpnState.connected;
    final busy = widget.state == VpnState.connecting || _trouble;
    final size = widget.size;
    final lime = night ? AeroColors.limeNight : AeroColors.lime;
    final ring = _trouble ? const Color(0xFFFFB04A) : (busy ? const Color(0xFF5FB6FF) : lime);
    final image = switch (widget.state) {
      VpnState.connected => AssetImages.catShield,
      VpnState.connecting => AssetImages.catGear,
      VpnState.disconnected => AssetImages.catSleeping,
      _ => AssetImages.catAlert,
    };

    final body = on
        ? (night
              ? const [Color(0x4D8CC8FF), Color(0x8C1E5AAA), Color(0xEB061E50)]
              : const [Color(0xA6FFFFFF), Color(0x8082C8FF), Color(0xD91469E1)])
        : (night
              ? const [Color(0x408CC8FF), Color(0x8C19468C), Color(0xEB05163C)]
              : const [Color(0x99FFFFFF), Color(0x8096CDFA), Color(0xBF3C78C8)]);

    return Semantics(
      button: true,
      label: widget.label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size + 48,
            height: size + 48,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (context, child) {
                final t = _spin.value;
                final wobble = 1 + 0.012 * math.sin(t * 2 * math.pi);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // A soft shadow on the grass under the bubble.
                    Positioned(
                      bottom: 6,
                      child: Container(
                        width: size * 0.7,
                        height: 22,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.all(Radius.elliptical(200, 22)),
                          gradient: RadialGradient(
                            colors: [
                              (night ? lime : const Color(0xFF00461E)).withValues(alpha: night ? 0.22 : 0.3),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (on || busy)
                      Transform.rotate(
                        angle: t * 2 * math.pi * (busy ? 3 : 1),
                        child: Container(
                          width: size + 36,
                          height: size + 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: ring.withValues(alpha: 0.45), blurRadius: 18)],
                          ),
                          foregroundDecoration: _RingDecoration(ring),
                        ),
                      ),
                    Transform.scale(scale: wobble, child: child),
                  ],
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: night ? const Color(0xA6A0DCFF) : const Color(0xE6FFFFFF), width: 2),
                  gradient: RadialGradient(center: const Alignment(0, -0.24), colors: body, stops: const [0, 0.55, 1]),
                  boxShadow: [
                    if (on) BoxShadow(color: lime.withValues(alpha: night ? 0.45 : 0.55), blurRadius: 40),
                    BoxShadow(
                      color: night ? const Color(0x80000814) : const Color(0x59003278),
                      blurRadius: 36,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Material(
                  type: MaterialType.transparency,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onTap,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Light rising from below when connected.
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 450),
                          opacity: on ? 1 : 0,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: RadialGradient(
                                center: const Alignment(0, 1.36),
                                radius: 0.96,
                                colors: [lime.withValues(alpha: 0.7), lime.withValues(alpha: 0)],
                              ),
                            ),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.all(size * 0.2),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Opacity(
                              key: ValueKey(image),
                              opacity: on || busy ? 1 : 0.88,
                              child: Image.asset(image),
                            ),
                          ),
                        ),
                        // The wet highlight on top and the soft one at the bottom.
                        Positioned(
                          top: size * 0.035,
                          left: size * 0.14,
                          right: size * 0.14,
                          height: size * 0.42,
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.42)),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.white.withValues(alpha: night ? 0.45 : 0.9),
                                    Colors.white.withValues(alpha: night ? 0.04 : 0.12),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                  stops: const [0, 0.85, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: size * 0.05,
                          child: IgnorePointer(
                            child: Container(
                              width: size * 0.48,
                              height: size * 0.1,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.elliptical(size, size * 0.1)),
                                gradient: RadialGradient(
                                  colors: [Colors.white.withValues(alpha: 0.55), Colors.white.withValues(alpha: 0)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // «Reflective»: the bubble mirrored on the glossy ground, fading out.
          IgnorePointer(
            child: ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 0.26,
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: night ? 0.22 : 0.32),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.26],
                  ).createShader(bounds),
                  child: Transform.flip(
                    flipY: true,
                    child: Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.24),
                          colors: body,
                          stops: const [0, 0.55, 1],
                        ),
                      ),
                      padding: EdgeInsets.all(size * 0.2),
                      child: Image.asset(image),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ring that fades round its length (a comet chasing its tail).
class _RingDecoration extends Decoration {
  final Color color;

  const _RingDecoration(this.color);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _RingPainter(color);
}

class _RingPainter extends BoxPainter {
  final Color color;

  _RingPainter(this.color);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size!;
    final rect = (offset & size).deflate(3);
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [color.withValues(alpha: 0), color, color.withValues(alpha: 0), color],
          stops: const [0, 0.45, 0.5, 1],
        ).createShader(rect),
    );
  }
}

/// Dew on glass: a few drops with a bright spot and a soft shadow.
class _DropsPainter extends CustomPainter {
  const _DropsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    for (final (fx, fy, r) in const [(.86, .22, 4.5), (.9, .62, 2.6), (.07, .78, 3.4), (.62, .14, 2.2)]) {
      final c = Offset(size.width * fx, size.height * fy);
      canvas.drawCircle(c + Offset(r * .25, r * .45), r, Paint()..color = const Color(0x2600284A));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            c + Offset(-r * .3, -r * .35),
            r * 1.3,
            const [
              Color(0xF2FFFFFF),
              Color(0x33FFFFFF),
              Color(0x99FFFFFF),
            ],
            const [0, .5, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_DropsPainter old) => false;
}
