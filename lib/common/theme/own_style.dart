import 'package:flutter/widgets.dart';
import 'package:trusttunnel/widgets/aero/aero_widgets.dart';
import 'package:trusttunnel/widgets/y2k/y2k_widgets.dart';

extension OwnStyleContext on BuildContext {
  /// A style with its own dialogs, sheets and backgrounds in the theme
  /// («Y2K», «Аэро»): widgets leave those to the theme instead of setting
  /// the plain look's colors and shapes.
  bool get hasOwnStyle => isY2k || isAero;
}
