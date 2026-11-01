import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// What the system says about the network the device is on.
enum NetworkState {
  /// There is no network.
  none,

  /// The network is there, but the system could not reach the internet
  /// through it: a login page (a hotel or an airport wifi).
  captivePortal,

  /// The network is there and the system checked that it reaches the
  /// internet.
  validated,

  /// The network is there, but the system did not check it (or could not).
  unvalidated,

  /// The platform has no such signal: the desktop.
  unknown,
}

/// The state of the network, as the system sees it.
///
/// Android knows it: the system checks on its own whether the network
/// reaches the internet (`NET_CAPABILITY_VALIDATED`) and whether it is a
/// login page (`NET_CAPABILITY_CAPTIVE_PORTAL`). That is the honest answer
/// to "is there a network here", and it costs no handshake to the server's
/// name - which matters, because a burst of handshakes to one name is what
/// a filter's "freeze" keys on.
///
/// The desktop has no such signal, and says so.
abstract final class NetworkStates {
  static const _channel = MethodChannel('cattunnel/apps');

  /// The state right now; [NetworkState.unknown] when the platform has
  /// nothing to say.
  static Future<NetworkState> current() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return NetworkState.unknown;
    }

    try {
      final state = await _channel.invokeMethod<String>('networkState');

      return switch (state) {
        'none' => NetworkState.none,
        'captivePortal' => NetworkState.captivePortal,
        'validated' => NetworkState.validated,
        'unvalidated' => NetworkState.unvalidated,
        _ => NetworkState.unknown,
      };
    } on Object {
      return NetworkState.unknown;
    }
  }

  /// Whether the network is there and reaches the internet: the system's
  /// word, and only the system's word.
  static bool isUsable(NetworkState state) => state == NetworkState.validated || state == NetworkState.unvalidated;
}
