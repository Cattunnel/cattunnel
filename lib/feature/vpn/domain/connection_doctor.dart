import 'package:flutter/foundation.dart';
import 'package:trusttunnel/feature/vpn/domain/connection_diagnostics.dart';

/// What Marsik offers to do about a verdict, besides switching servers.
enum DoctorAction {
  /// Start the same server again.
  retry,

  /// The system Wi-Fi screen: a network behind a login page signs in there.
  wifiSettings,

  /// The system date and time screen: the clock is off.
  dateSettings,

  /// The problem report, addressed to whoever runs the server.
  messageAdmin,

  /// Nothing to press: waiting is the answer (a frozen address).
  none,
}

/// One voice for "what is happening with the connection".
///
/// The line under the connect button and Marsik's window used to decide
/// on their own, and could say opposite things at the same moment (task 38,
/// problems 5 and 16). Whatever both of them show is decided here.
abstract final class ConnectionDoctor {
  /// Marsik's window is open: it speaks, the line under the button is quiet.
  static final marsikOpen = ValueNotifier<bool>(false);

  /// Verdicts where another server can help: the trouble is on the way to
  /// this one. No internet, a login page, a clock that is off, a key the
  /// server refuses or an ended subscription follow to any other server.
  static bool alternativeHelps(DiagnosisVerdict verdict) => switch (verdict) {
    DiagnosisVerdict.networkCuts ||
    DiagnosisVerdict.serverTimeout ||
    DiagnosisVerdict.serverRefused ||
    DiagnosisVerdict.tlsBlocked ||
    DiagnosisVerdict.trafficBlocked ||
    DiagnosisVerdict.addressFrozen => true,
    DiagnosisVerdict.noInternet ||
    DiagnosisVerdict.captivePortal ||
    DiagnosisVerdict.clockWrong ||
    DiagnosisVerdict.accessEnded ||
    DiagnosisVerdict.keysUpdated ||
    DiagnosisVerdict.keysRejected ||
    DiagnosisVerdict.bypassNeeded ||
    DiagnosisVerdict.inconclusive => false,
  };

  /// The one button under the verdict. [systemSettings]: the platform can
  /// open the system Wi-Fi and date screens (Android).
  static DoctorAction actionFor(DiagnosisVerdict verdict, {required bool systemSettings}) => switch (verdict) {
    DiagnosisVerdict.captivePortal when systemSettings => DoctorAction.wifiSettings,
    DiagnosisVerdict.clockWrong when systemSettings => DoctorAction.dateSettings,
    // The desktop has no screen to send to; the text says what to change.
    DiagnosisVerdict.clockWrong => DoctorAction.retry,
    DiagnosisVerdict.accessEnded || DiagnosisVerdict.keysRejected => DoctorAction.messageAdmin,
    // Every new attempt extends the freeze.
    DiagnosisVerdict.addressFrozen => DoctorAction.none,
    // Reconnects by itself with the new keys.
    DiagnosisVerdict.keysUpdated => DoctorAction.none,
    _ => DoctorAction.retry,
  };
}
