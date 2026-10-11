import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

/// Marsik's picture. In the «Y2K» style he is «кибермарсик»: a hologram of
/// himself, see [CyberMarsik]; in the other styles the plain image.
class MarsikImage extends StatelessWidget {
  final String asset;
  final double? width;
  final double? height;
  final BoxFit? fit;

  const MarsikImage(this.asset, {super.key, this.width, this.height, this.fit});

  @override
  Widget build(BuildContext context) => context.isY2k
      ? CyberMarsik(asset, width: width, height: height, fit: fit)
      : Image.asset(asset, width: width, height: height, fit: fit);
}

/// Marsik as a hologram, drawn from the ordinary picture in code: outlines
/// glow ice-blue, the white fur turns to see-through dark blue, scanlines run
/// across him, a red/cyan colour split sits at the edges. He materializes
/// (a scan from the top with a flicker) when he appears, and now and then the
/// picture glitches for a moment. With "reduce motion" he just stands there.
class CyberMarsik extends StatefulWidget {
  final String asset;
  final double? width;
  final double? height;
  final BoxFit? fit;

  const CyberMarsik(this.asset, {super.key, this.width, this.height, this.fit});

  @override
  State<CyberMarsik> createState() => _CyberMarsikState();
}

class _CyberMarsikState extends State<CyberMarsik> with SingleTickerProviderStateMixin {
  late final AnimationController _appear = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  final _random = math.Random();
  Timer? _glitchTimer;
  bool _glitch = false;
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.of(context).disableAnimations;
    if (still == _still && (_appear.isAnimating || _appear.isCompleted || _glitchTimer != null)) return;
    _still = still;
    if (still) {
      _appear.value = 1;
      _glitchTimer?.cancel();
      _glitchTimer = null;
    } else {
      unawaited(_appear.forward());
      _scheduleGlitch();
    }
  }

  void _scheduleGlitch() {
    _glitchTimer?.cancel();
    _glitchTimer = Timer(Duration(milliseconds: 3500 + _random.nextInt(5000)), () async {
      if (!mounted) return;
      setState(() => _glitch = true);
      await Future<void>.delayed(Duration(milliseconds: 70 + _random.nextInt(90)));
      if (!mounted) return;
      setState(() => _glitch = false);
      _scheduleGlitch();
    });
  }

  @override
  void dispose() {
    _glitchTimer?.cancel();
    _appear.dispose();
    super.dispose();
  }

  Widget _image({ColorFilter? filter}) {
    final image = Image.asset(widget.asset, width: widget.width, height: widget.height, fit: widget.fit);

    return filter == null ? image : ColorFiltered(colorFilter: filter, child: image);
  }

  @override
  Widget build(BuildContext context) {
    final split = _glitch ? 4.0 : 1.2;
    final picture = Stack(
      alignment: Alignment.center,
      children: [
        // Halo.
        ImageFiltered(
          imageFilter: _blur,
          child: _image(filter: _solid(Y2kColors.electric, 0.75)),
        ),
        // Colour split.
        Transform.translate(
          offset: Offset(-split, 0),
          child: _image(filter: _solid(const Color(0xFFFF3D8B), _glitch ? 0.6 : 0.35)),
        ),
        Transform.translate(
          offset: Offset(split, _glitch ? -1 : 0),
          child: _image(filter: _solid(Y2kColors.glow, _glitch ? 0.7 : 0.4)),
        ),
        // The hologram itself, with scanlines cut into it.
        ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 0.6),
              Colors.white.withValues(alpha: 0.6),
            ],
            stops: const [0, 0.5, 0.5, 1],
            tileMode: TileMode.repeated,
          ).createShader(Rect.fromLTWH(0, 0, bounds.width, 3)),
          child: _image(filter: _hologram),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: _appear,
      child: picture,
      builder: (context, child) {
        final t = _appear.value;
        if (t >= 1) return Opacity(opacity: _glitch ? 0.82 : 1, child: child);
        // Scan from the top: visible above the line, a bright edge on it,
        // with a flicker in the first half.
        final flicker = t < 0.5 && (t * 20).floor().isEven ? 0.55 : 1.0;

        return Opacity(
          opacity: flicker,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: const [Colors.white, Colors.white, Colors.transparent],
              stops: [0, t, math.min(1, t + 0.04)],
            ).createShader(bounds),
            child: child,
          ),
        );
      },
    );
  }
}

final _blur = ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7);

/// Every visible pixel in one [color], alpha scaled by [alpha].
ColorFilter _solid(Color color, double alpha) => ColorFilter.matrix(<double>[
  0, 0, 0, 0, color.r * 255, //
  0, 0, 0, 0, color.g * 255,
  0, 0, 0, 0, color.b * 255,
  0, 0, 0, alpha, 0,
]);

/// Dark outlines -> glowing ice-blue, white fur -> see-through dark blue
/// (by brightness L: colour = glow + (fill - glow) * L; the fur keeps ~92%
/// alpha so the colour split behind only shows at the edges).
final _hologram = () {
  const glow = (0.62, 0.9, 1.0), fill = (0.04, 0.12, 0.3);
  List<double> row(double g, double f) => [(f - g) * 0.3, (f - g) * 0.59, (f - g) * 0.11, 0, g * 255];

  return ColorFilter.matrix(<double>[
    ...row(glow.$1, fill.$1),
    ...row(glow.$2, fill.$2),
    ...row(glow.$3, fill.$3),
    ...[-0.024, -0.0472, -0.0088, 1, 0],
  ]);
}();
