import 'dart:ui';

import 'package:flutter/services.dart';

class DeviceOrientationPolicy {
  const DeviceOrientationPolicy._();

  static const double tabletShortSideDp = 600;

  static bool isWideScreen(Iterable<Size> views) => views.every((view) => view.shortestSide >= tabletShortSideDp);

  static List<DeviceOrientation> allowedOrientations(Iterable<Size> views) => [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    if (isWideScreen(views)) ...[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
  ];

  static List<DeviceOrientation>? _lastApplied;

  static Future<void> apply() async {
    final views = PlatformDispatcher.instance.views;
    final sizes = views.map((view) => view.physicalSize / view.devicePixelRatio);
    final orientations = allowedOrientations(sizes);
    if (_lastApplied != null && _same(_lastApplied!, orientations)) {
      return;
    }
    _lastApplied = List<DeviceOrientation>.of(orientations);
    await SystemChrome.setPreferredOrientations(orientations);
  }

  static bool _same(List<DeviceOrientation> a, List<DeviceOrientation> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
