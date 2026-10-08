import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

/// The phone's bottom bar in the «Y2K» style: a dark glass strip with a
/// glowing top edge; the chosen tab gets a light bar that slides over to it,
/// a soft glow and corner brackets around the icon.
class Y2kNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Icon and label of each tab.
  final List<(IconData, String)> destinations;

  const Y2kNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    final count = destinations.length;
    final duration = MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 380);

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0A1F47), Y2kColors.ink],
        ),
        border: Border(top: BorderSide(color: Color(0x8C2F8CFF))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Stack(
            children: [
              // The sliding light bar on the top edge.
              AnimatedAlign(
                duration: duration,
                curve: Curves.easeOutCubic,
                alignment: Alignment(count == 1 ? 0 : -1 + 2 * selectedIndex / (count - 1), -1),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 2,
                      decoration: BoxDecoration(
                        color: Y2kColors.glow,
                        boxShadow: [
                          BoxShadow(color: Y2kColors.electric.withValues(alpha: 0.9), blurRadius: 10, spreadRadius: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: _Item(
                        icon: destinations[i].$1,
                        label: destinations[i].$2,
                        selected: i == selectedIndex,
                        duration: duration,
                        onTap: () => onDestinationSelected(i),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Duration duration;
  final VoidCallback onTap;

  const _Item({
    required this.icon,
    required this.label,
    required this.selected,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? Y2kColors.glow : Y2kColors.dim;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          splashColor: Y2kColors.glow.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      Y2kColors.electric.withValues(alpha: selected ? 0.35 : 0),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: CustomPaint(
                  foregroundPainter: selected ? const _BracketsPainter() : null,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: TweenAnimationBuilder<Color?>(
                      duration: duration,
                      tween: ColorTween(end: color),
                      builder: (context, value, _) => CustomIcon.medium(icon: icon, color: value),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: duration,
                style: TextStyle(
                  fontFamily: FontFamilies.exo2,
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 1.6,
                  color: selected ? Y2kColors.ice : Y2kColors.dim,
                  height: 1.2,
                  shadows: selected ? [Shadow(color: Y2kColors.electric.withValues(alpha: 0.8), blurRadius: 8)] : null,
                ),
                child: Text(label.toUpperCase(), maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Four thin corner brackets around the chosen icon.
class _BracketsPainter extends CustomPainter {
  const _BracketsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const l = 5.0;
    final paint = Paint()
      ..color = Y2kColors.glow.withValues(alpha: 0.85)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final w = size.width, h = size.height;
    canvas
      ..drawPath(
        Path()
          ..moveTo(0, l)
          ..lineTo(0, 0)
          ..lineTo(l, 0),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w - l, 0)
          ..lineTo(w, 0)
          ..lineTo(w, l),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(0, h - l)
          ..lineTo(0, h)
          ..lineTo(l, h),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w - l, h)
          ..lineTo(w, h)
          ..lineTo(w, h - l),
        paint,
      );
  }

  @override
  bool shouldRepaint(_BracketsPainter old) => false;
}
