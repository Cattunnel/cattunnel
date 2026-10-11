import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

class ScaffoldWrapper extends StatelessWidget {
  final Widget child;

  /// Y2K / Аэро: the full, livelier backdrop (the home screen) instead of the calm one.
  final bool y2kLoud;

  const ScaffoldWrapper({
    super.key,
    required this.child,
    this.y2kLoud = false,
  });

  @override
  Widget build(BuildContext context) => context.isY2k
      ? Y2kBackdrop(calm: !y2kLoud, child: child)
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
