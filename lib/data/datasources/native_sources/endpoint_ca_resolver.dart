import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/feature/security/domain/security_platform.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';

/// Picks the CA store the VPN engine verifies an endpoint against.
///
/// The engine (TrustTunnelClient `client.cpp`) verifies against the config's
/// `certificate` when present, otherwise against Android's `AndroidCAStore` -
/// which includes *user-installed* CAs such as the Russian Ministry of Digital
/// Development root - or the Windows/Linux system store, where the Gosuslugi
/// installer puts the same root; whoever holds it could forge the endpoint
/// certificate and read the tunnel (credentials included). So:
///  1. the server's own certificate (pinned / self-signed PEM) - unchanged;
///  2. otherwise the system roots minus the Russian ones, unless the user
///     explicitly allowed user CAs in the Cyber security section;
///  3. otherwise empty - the engine's default behavior.
class EndpointCaResolver {
  final SharedPreferences _preferences;
  String? _systemBundle;

  EndpointCaResolver({required SharedPreferences preferences}) : _preferences = preferences;

  Future<String> certificateFor(ServerData server) async {
    final own = server.certificate?.data;
    if (own != null && own.trim().isNotEmpty) {
      return own;
    }

    if (SecuritySettings(_preferences).trustUserCas) {
      return '';
    }

    // Built once per process from the device's live store; Android CA
    // updates show up after the next app restart.
    return _systemBundle ??= await SecurityPlatform.systemCaBundle() ?? '';
  }
}
