import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/citypop/city_style.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

class ScaffoldWrapper extends StatelessWidget {
  /// Y2K / Аэро: the full, livelier backdrop (the home screen) instead of the calm one.
  final bool y2kLoud;

  /// Lists, settings and forms stop at [readableWidth] in the middle of a
  /// wide window. On a landscape tablet the settings ran 1800 dp from the
  /// label to its arrow and the help texts were one line across the
  /// screen. Screens that use the width (the server list, statistics,
  /// logs) pass false.
  final bool readable;

  static const readableWidth = 840.0;

  const ScaffoldWrapper({
    super.key,
    required Widget child,
    this.y2kLoud = false,
    this.readable = true,
  }) : _child = child;

  final Widget _child;

  Widget get child => readable
      ? Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: readableWidth),
            child: _child,
          ),
        )
      : _child;

  @override
  Widget build(BuildContext context) => context.isY2k
      ? Y2kBackdrop(calm: !y2kLoud, child: child)
      : context.isCityPop
      // The home (y2kLoud) draws its own live scene; other pages get the calm airbrush sky.
      ? CityBackdrop(passThrough: y2kLoud, child: child)
      : context.isAero
      // The landscape fills the screen, under the floating bottom bar too;
      // the page itself stops above the bar (and the system's buttons).
      ? AeroBackdrop(
          calm: !y2kLoud,
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: MediaQuery.removePadding(context: context, removeBottom: true, child: child),
          ),
        )
      : ColoredBox(
          color: context.colors.backgroundSystem,
          child: Padding(
            padding: EdgeInsets.all(context.isMobileBreakpoint ? 0 : 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(context.isMobileBreakpoint ? 0 : 16),
              child: ColoredBox(
                color: context.colors.background,
                child: child,
              ),
            ),
          ),
        );
}
