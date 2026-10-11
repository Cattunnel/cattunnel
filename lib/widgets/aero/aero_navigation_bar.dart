import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/font_families.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/custom_icon.dart';

/// The phone's bottom bar in the «Аэро» style: a frosted glass capsule
/// floating over the landscape (the page's backdrop runs on under it, see
/// NavigationScreen); each tab's icon sits in its own glossy coloured
/// sphere, like the icons of the era, and the chosen tab gets a glossy blue
/// pill that slides over to it.
class AeroNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// Icon and label of each tab.
  final List<(IconData, String)> destinations;

  const AeroNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  /// Sphere colours by tab: servers blue, routing green, settings amber.
  static const _spheres = [
    [Color(0xFFBFE6FF), Color(0xFF2A8BF0), Color(0xFF0B4FB0)],
    [Color(0xFFE2FFB0), Color(0xFF5FC42A), Color(0xFF2A7A12)],
    [Color(0xFFFFE9B0), Color(0xFFF2A62A), Color(0xFFB0640A)],
  ];

  @override
  Widget build(BuildContext context) {
    final count = destinations.length;
    final night = context.isAeroNight;
    final duration = MediaQuery.of(context).disableAnimations ? Duration.zero : const Duration(milliseconds: 380);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: night ? const Color(0x8C8CD2FF) : const Color(0xF2FFFFFF), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: night ? const Color(0x80000814) : const Color(0x4D002814),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: night
                  ? const [Color(0xB3284A78), Color(0xCC0A2147), Color(0xE6061633)]
                  : const [Color(0xF7FFFFFF), Color(0xCCF2FAFF), Color(0xD9DDF0FF)],
              stops: const [0, 0.48, 1],
            ),
          ),
          child: SizedBox(
            height: 68,
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Stack(
                children: [
                  // The glass's own top shine.
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 0,
                    height: 22,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: night ? 0.18 : 0.9),
                              Colors.white.withValues(alpha: 0),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  AnimatedAlign(
                    duration: duration,
                    curve: Curves.easeOutBack,
                    alignment: Alignment(count == 1 ? 0 : -1 + 2 * selectedIndex / (count - 1), 0),
                    child: FractionallySizedBox(
                      widthFactor: 1 / count,
                      heightFactor: 1,
                      child: const Padding(padding: EdgeInsets.symmetric(horizontal: 3), child: _Pill()),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < count; i++)
                        Expanded(
                          child: _Item(
                            icon: destinations[i].$1,
                            label: destinations[i].$2,
                            sphere: _spheres[i % _spheres.length],
                            selected: i == selectedIndex,
                            night: night,
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
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: const Color(0xD9FFFFFF)),
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF6CC0FF), Color(0xFF2386F0), Color(0xFF0F64D6), Color(0xFF3FA0FF)],
        stops: [0, 0.5, 0.52, 1],
      ),
      boxShadow: [
        BoxShadow(color: const Color(0xFF146EE6).withValues(alpha: 0.5), blurRadius: 14, offset: const Offset(0, 4)),
      ],
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: FractionallySizedBox(
        heightFactor: 0.48,
        widthFactor: 0.92,
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24), bottom: Radius.circular(10)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white.withValues(alpha: 0.8), Colors.white.withValues(alpha: 0.12)],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A tab: its icon in a small glossy sphere, the label under it.
class _Item extends StatelessWidget {
  final IconData icon;
  final String label;
  final List<Color> sphere;
  final bool selected;
  final bool night;
  final Duration duration;
  final VoidCallback onTap;

  const _Item({
    required this.icon,
    required this.label,
    required this.sphere,
    required this.selected,
    required this.night,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final idle = night ? const Color(0xFFBFDCF5) : const Color(0xFF1F4F80);

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(26),
          splashColor: Colors.white.withValues(alpha: 0.2),
          highlightColor: Colors.transparent,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                duration: duration,
                curve: Curves.easeOutBack,
                scale: selected ? 1.08 : 1,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.45),
                      radius: 0.95,
                      colors: sphere,
                      stops: const [0, 0.55, 1],
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: sphere.last.withValues(alpha: 0.45), blurRadius: 6, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomIcon.small(icon: icon, color: Colors.white),
                      Positioned(
                        top: 2,
                        left: 6,
                        right: 6,
                        height: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.all(Radius.elliptical(20, 12)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.white.withValues(alpha: 0.85), Colors.white.withValues(alpha: 0.05)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: duration,
                style: TextStyle(
                  fontFamily: FontFamilies.nunito,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : idle,
                  height: 1.2,
                  shadows: selected
                      ? [const Shadow(color: Color(0x73002866), blurRadius: 3, offset: Offset(0, 1))]
                      : null,
                ),
                child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
