import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';

/// Colors of the «Y2K» style beyond the theme palette (ThemePalette.y2k).
abstract final class Y2kColors {
  static const ink = Color(0xFF02050D);
  static const navy = Color(0xFF071A3A);
  static const navyLight = Color(0xFF0B2A5C);
  static const electric = Color(0xFF2F8CFF);
  static const glow = Color(0xFF6FD3FF);
  static const ice = Color(0xFFCFE8FF);
  static const steel = Color(0xFF7FB6EA);
  static const dim = Color(0xFF4F7FB0);
  static const warn = Color(0xFFFF8A47);
}

/// Marks the «Y2K» theme (only its ThemeData carries it), so widgets can ask
/// [Y2kContext.isY2k] and rebuild when the style changes.
class Y2kStyle extends ThemeExtension<Y2kStyle> {
  const Y2kStyle();

  @override
  Y2kStyle copyWith() => this;

  @override
  Y2kStyle lerp(Y2kStyle? other, double t) => this;
}

extension Y2kContext on BuildContext {
  bool get isY2k => Theme.of(this).extension<Y2kStyle>() != null;
}

/// The Y2K panel shape: top-right and bottom-left corners cut off.
BeveledRectangleBorder y2kCut([double cut = 12, BorderSide side = BorderSide.none]) => BeveledRectangleBorder(
  side: side,
  borderRadius: BorderRadius.only(topRight: Radius.circular(cut), bottomLeft: Radius.circular(cut)),
);

/// The whole-screen background: a navy radial glow, a burst of thin "shard"
/// lines drifting slowly, a halftone dot corner, scanlines and a light sweep.
/// Drawn in code - no images. Sits behind a transparent Scaffold. [calm] is
/// the version for the other screens: dimmer rays (text sits on top), the
/// same drift and sweep. The still parts are painted once, only the rays,
/// shards and sweep repaint.
class Y2kBackdrop extends StatefulWidget {
  final Widget child;
  final bool calm;

  const Y2kBackdrop({super.key, required this.child, this.calm = false});

  @override
  State<Y2kBackdrop> createState() => _Y2kBackdropState();
}

class _Y2kBackdropState extends State<Y2kBackdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 18));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect "reduce motion": the picture stays, the drift and sweep stop.
    if (MediaQuery.of(context).disableAnimations) {
      _clock.stop();
    } else if (!_clock.isAnimating) {
      unawaited(_clock.repeat());
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, widget.calm ? -0.6 : -0.25),
            radius: widget.calm ? 1.3 : 1.15,
            colors: const [Y2kColors.navyLight, Y2kColors.navy, Y2kColors.ink],
            stops: const [0, 0.34, 0.75],
          ),
        ),
      ),
      RepaintBoundary(
        child: CustomPaint(painter: _StillPainter(calm: widget.calm)),
      ),
      RepaintBoundary(
        child: CustomPaint(painter: _ShardsPainter(_clock, calm: widget.calm)),
      ),
      widget.child,
    ],
  );
}

class _ShardsPainter extends CustomPainter {
  final Animation<double> clock;
  final bool calm;

  _ShardsPainter(this.clock, {required this.calm}) : super(repaint: clock);

  @override
  void paint(Canvas canvas, Size size) {
    final t = clock.value;
    final w = size.width, h = size.height;
    final dim = calm ? 0.45 : 1.0;
    final phase = t * 2 * math.pi;
    final drift = Offset(math.sin(phase) * 8, math.cos(phase) * 5);
    final focus = (calm ? Offset(w * 0.85, h * 0.08) : Offset(w * 0.5, h * 0.36)) + drift;

    // Burst of rays from the focus.
    final ray = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const ends = [
      (-0.1, -0.05, 1.2, .55),
      (0.2, -0.1, .7, .35),
      (1.15, 0.12, 1.4, .5),
      (1.05, -0.05, .6, .3),
      (-0.1, 0.33, .8, .35),
      (1.15, 0.6, 1.0, .4),
      (-0.05, 0.8, .7, .3),
      (0.85, 1.1, 1.2, .35),
      (0.35, 1.1, .6, .25),
    ];
    for (final (x, y, width, alpha) in ends) {
      ray
        ..strokeWidth = width
        ..color = Y2kColors.electric.withValues(alpha: alpha * 0.8 * dim);
      canvas.drawLine(focus, Offset(w * x, h * y) + drift * 2, ray);
    }

    // Floating glass shards (outlined triangles).
    final shard = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = Y2kColors.electric.withValues(alpha: 0.38 * dim);
    const tris = [
      [(0.13, 0.13), (0.45, 0.29), (0.28, 0.33)],
      [(0.78, 0.17), (0.98, 0.09), (0.9, 0.28)],
      [(0.72, 0.62), (0.98, 0.7), (0.8, 0.77)],
      [(0.08, 0.58), (0.33, 0.53), (0.26, 0.67)],
    ];
    for (var i = 0; i < tris.length; i++) {
      final d = Offset(math.sin(phase + i) * 6, math.cos(phase * 1.3 + i) * 6);
      final path = Path()..moveTo(w * tris[i][0].$1 + d.dx, h * tris[i][0].$2 + d.dy);
      for (final (x, y) in tris[i].skip(1)) {
        path.lineTo(w * x + d.dx, h * y + d.dy);
      }
      canvas.drawPath(path..close(), shard);
    }

    // A soft light band sweeping down, three times per cycle.
    final bandY = (t * 3 % 1) * (h + 240) - 120;
    final band = Rect.fromLTWH(0, bandY, w, 120);
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Y2kColors.glow.withValues(alpha: 0.08 * (calm ? 0.8 : 1)),
            Colors.transparent,
          ],
        ).createShader(band),
    );
  }

  @override
  bool shouldRepaint(_ShardsPainter old) => old.clock != clock || old.calm != calm;
}

/// Halftone corner, technical rules and scanlines - painted once.
class _StillPainter extends CustomPainter {
  final bool calm;

  const _StillPainter({required this.calm});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final dim = calm ? 0.6 : 1.0;

    final rule = Paint()
      ..strokeWidth = 1
      ..color = Y2kColors.ice.withValues(alpha: 0.18 * dim);
    canvas
      ..drawLine(Offset(w * 0.05, h * 0.22), Offset(w * 0.4, h * 0.22), rule)
      ..drawLine(Offset(w * 0.7, h * 0.33), Offset(w * 1.0, h * 0.33), rule)
      ..drawLine(Offset(0, h * 0.7), Offset(w * 0.28, h * 0.7), rule);

    // Halftone dots fading from a corner (top-left; bottom-right when calm,
    // away from the titles).
    final dot = Paint();
    const step = 7.0;
    final cornerW = math.min(w * 0.7, 280.0), cornerH = math.min(h * 0.38, 320.0);
    for (var y = step / 2; y < cornerH; y += step) {
      for (var x = step / 2; x < cornerW; x += step) {
        final fade = 1 - (x / cornerW + y / cornerH) / 1.3;
        if (fade <= 0) continue;
        final at = calm ? Offset(w - x, h - y) : Offset(x, y);
        canvas.drawCircle(at, 1.0, dot..color = Y2kColors.glow.withValues(alpha: 0.4 * fade * dim));
      }
    }

    final scan = Paint()..color = Colors.white.withValues(alpha: 0.03);
    for (var y = 0.0; y < h; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, 1), scan);
    }
  }

  @override
  bool shouldRepaint(_StillPainter old) => old.calm != calm;
}

/// "CATTUNNEL" in chrome: a white-steel-white gradient through the letters,
/// with a blue glow. Wide display font (Unbounded). Every few seconds a light
/// glint runs across the letters.
class Y2kChromeTitle extends StatefulWidget {
  final String text;
  final double size;

  const Y2kChromeTitle(this.text, {super.key, this.size = 22});

  @override
  State<Y2kChromeTitle> createState() => _Y2kChromeTitleState();
}

class _Y2kChromeTitleState extends State<Y2kChromeTitle> with SingleTickerProviderStateMixin {
  // The glint takes the first ~18% of the cycle, then the title rests.
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(seconds: 7));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _shine.stop();
    } else if (!_shine.isAnimating) {
      unawaited(_shine.repeat());
    }
  }

  @override
  void dispose() {
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final letters = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.white, Y2kColors.ice, Color(0xFF4C7FB8), Color(0xFFE6F4FF), Y2kColors.steel],
        stops: [0, 0.38, 0.52, 0.6, 1],
      ).createShader(bounds),
      child: Text(
        widget.text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: FontFamilies.unbounded,
          fontWeight: FontWeight.w700,
          fontSize: size,
          letterSpacing: size * 0.06,
          height: 1,
          shadows: [Shadow(color: Y2kColors.electric.withValues(alpha: 0.6), blurRadius: 12)],
        ),
      ),
    );

    return Semantics(
      header: true,
      label: widget.text,
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _shine,
          child: letters,
          builder: (context, child) {
            final p = _shine.value / 0.18;
            if (p >= 1 || !_shine.isAnimating) return child!;
            // A slanted white band from left to right, only on the letters.
            final x = -1.6 + p * 3.2;

            return ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment(x - 0.5, -1),
                end: Alignment(x + 0.5, 1),
                colors: [Colors.transparent, Colors.white.withValues(alpha: 0.9), Colors.transparent],
                stops: const [0.35, 0.5, 0.65],
              ).createShader(bounds),
              child: child,
            );
          },
        ),
      ),
    );
  }
}

/// The round connect button: a glowing core with Marsik, two dashed rings
/// turning in opposite directions; the glow follows the VPN state.
class Y2kConnectButton extends StatefulWidget {
  final VpnState state;
  final VoidCallback onTap;
  final String label;
  final double size;

  const Y2kConnectButton({
    super.key,
    required this.state,
    required this.onTap,
    required this.label,
    this.size = 200,
  });

  @override
  State<Y2kConnectButton> createState() => _Y2kConnectButtonState();
}

class _Y2kConnectButtonState extends State<Y2kConnectButton> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 14))
    ..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final on = state == VpnState.connected;
    final off = state == VpnState.disconnected;
    final trouble = !on && !off && state != VpnState.connecting;
    final ringColor = trouble ? Y2kColors.warn : Y2kColors.electric;
    final size = widget.size;
    final image = switch (state) {
      VpnState.connected => AssetImages.catShield,
      VpnState.connecting => AssetImages.catGear,
      VpnState.disconnected => AssetImages.catSleeping,
      _ => AssetImages.catAlert,
    };
    final still = MediaQuery.of(context).disableAnimations;

    return Semantics(
      button: true,
      label: widget.label,
      child: SizedBox(
        width: size * 1.45,
        height: size * 1.45,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Glow behind everything.
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: size * 1.45,
              height: size * 1.45,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    (on ? Y2kColors.electric : ringColor).withValues(alpha: on ? 0.38 : (off ? 0.08 : 0.22)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            AnimatedBuilder(
              animation: _spin,
              builder: (context, _) {
                // Connecting spins faster - something is happening.
                final turns = still ? 0.0 : _spin.value * (off || on ? 1 : 3);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: turns * 2 * math.pi,
                      child: CustomPaint(
                        size: Size.square(size * 1.36),
                        painter: _RingPainter(color: ringColor, dash: 2, gap: 9, width: 1.3, alpha: 0.8),
                      ),
                    ),
                    Transform.rotate(
                      angle: -turns * 2 * math.pi * 0.65,
                      child: CustomPaint(
                        size: Size.square(size * 1.18),
                        painter: const _RingPainter(color: Y2kColors.ice, dash: 64, gap: 22, width: 2, alpha: 0.45),
                      ),
                    ),
                  ],
                );
              },
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Y2kColors.ice.withValues(alpha: 0.55)),
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  colors: on
                      ? const [Y2kColors.glow, Y2kColors.electric, Color(0xFF0A2A66), Y2kColors.ink]
                      : const [Color(0xFF2A3B55), Color(0xFF0D1830), Y2kColors.ink, Y2kColors.ink],
                  stops: const [0, 0.38, 0.78, 1],
                ),
                boxShadow: [
                  if (on) ...[
                    BoxShadow(color: Y2kColors.electric.withValues(alpha: 0.75), blurRadius: 40),
                    BoxShadow(color: Y2kColors.electric.withValues(alpha: 0.3), blurRadius: 110, spreadRadius: 8),
                  ] else
                    BoxShadow(color: ringColor.withValues(alpha: 0.25), blurRadius: 18),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onTap,
                  splashColor: Y2kColors.glow.withValues(alpha: 0.25),
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.17),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: MarsikImage(image, key: ValueKey(image)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color color;
  final double dash, gap, width, alpha;

  const _RingPainter({
    required this.color,
    required this.dash,
    required this.gap,
    required this.width,
    required this.alpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2 - width;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: alpha);
    final circumference = 2 * math.pi * radius;
    final count = (circumference / (dash + gap)).floor();
    final step = 2 * math.pi / count;
    final sweep = step * dash / (dash + gap);
    for (var i = 0; i < count; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius), i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color || old.alpha != alpha;
}

/// A glassy panel with two clipped corners (top-right, bottom-left).
class Y2kGlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const Y2kGlassCard({super.key, required this.child, this.onTap});

  @override
  Widget build(BuildContext context) => ClipPath(
    clipper: const _ClippedCorners(14),
    child: Material(
      type: MaterialType.transparency,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Y2kColors.ice.withValues(alpha: 0.13),
              Y2kColors.navy.withValues(alpha: 0.45),
              Y2kColors.ink.withValues(alpha: 0.6),
            ],
          ),
          border: Border.all(color: Y2kColors.steel.withValues(alpha: 0.35)),
        ),
        child: InkWell(onTap: onTap, splashColor: Y2kColors.glow.withValues(alpha: 0.15), child: child),
      ),
    ),
  );
}

class _ClippedCorners extends CustomClipper<Path> {
  final double cut;

  const _ClippedCorners(this.cut);

  @override
  Path getClip(Size size) => Path()
    ..moveTo(0, 0)
    ..lineTo(size.width - cut, 0)
    ..lineTo(size.width, cut)
    ..lineTo(size.width, size.height)
    ..lineTo(cut, size.height)
    ..lineTo(0, size.height - cut)
    ..close();

  @override
  bool shouldReclip(_ClippedCorners old) => old.cut != cut;
}

/// Small uppercase technical caption, e.g. "SYS.REV 1.5.2".
class Y2kMicro extends StatelessWidget {
  final String text;
  final Color color;

  const Y2kMicro(this.text, {super.key, this.color = Y2kColors.steel});

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(fontFamily: FontFamilies.exo2, fontSize: 10, letterSpacing: 1.6, color: color, height: 1.3),
  );
}
