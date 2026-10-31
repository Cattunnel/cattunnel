import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trusttunnel/common/utils/physical_net.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connect_failures.dart';
import 'package:trusttunnel/feature/vpn/domain/net_diagnostics.dart';
import 'package:trusttunnel/feature/vpn/domain/network_fingerprint.dart';
import 'package:trusttunnel/feature/vpn/domain/network_state.dart';
import 'package:trusttunnel/feature/vpn/domain/server_tls.dart';
import 'package:vpn_plugin/models/net_diagnostic.dart';

enum DiagnosisStep { internet, server, tls, access }

enum DiagnosisStepStatus { pending, running, ok, failed, skipped }

enum DiagnosisVerdict {
  /// The system says there is no network.
  noInternet,

  /// The network is there, but it needs a login before it lets anything
  /// through (a hotel or an airport wifi).
  captivePortal,

  /// The network is there and reaches the internet, but the path to the
  /// server is cut: the engine's own verdict (a frozen address, a cut
  /// after a fixed number of bytes, a session that went silent).
  networkCuts,

  /// The app already knows the plain connection is cut in this network
  /// (anti-DPI "auto" remembered it): the bypass is the answer, not "no
  /// internet", even when the reference host is unreachable too.
  bypassNeeded,

  /// TCP connect to the server timed out - IP blocked, or the host is down.
  serverTimeout,

  /// The server host actively refused TCP - it's up, but nothing listens.
  serverRefused,

  /// TCP to the server connects, but the TLS handshake dies or goes silent:
  /// a filter cuts the secure connection to it (by name or by address -
  /// telling these apart would take a handshake with our name to someone
  /// else's host, which is itself a probe through the filter).
  tlsBlocked,

  /// The server accepted our credentials, yet the tunnel doesn't come up -
  /// traffic is being choked after the handshake (TSPU-style throttling).
  trafficBlocked,

  /// The subscription replies 404 - the account was disabled/expired, or
  /// the link was revoked (the server deliberately doesn't tell these apart).
  accessEnded,

  /// The subscription handed out different credentials - they've been
  /// updated locally, reconnecting should work.
  keysUpdated,

  /// The server rejected our credentials, and they're the latest ones the
  /// subscription has (or there's no subscription to ask).
  keysRejected,

  /// The network path looks fine, but neither the server nor the
  /// subscription gave a clear answer about the credentials.
  inconclusive,

  /// The device clock is outside the validity of our own server's
  /// certificate: certificate checks fail on that alone ("not yet valid" /
  /// "expired"). Turning on automatic date and time fixes it.
  clockWrong,

  /// The engine's ClientHello to this server got no answer a moment ago
  /// (ConnectFailures): a filter froze the address for a couple of minutes.
  /// Not probed - each handshake would keep it frozen.
  addressFrozen,
}

class ConnectionDiagnosis {
  final DiagnosisVerdict verdict;

  /// The same server with refreshed credentials ([DiagnosisVerdict.keysUpdated]).
  final Server? updatedServer;

  /// Another server of the same subscription that accepted a TCP connection
  /// right now, offered when the current one looks blocked.
  final Server? alternative;

  /// What the engine said about the last session to this server, when it
  /// said something about the path rather than about the credentials.
  final NetDiagnostic? engine;

  /// What the anti-DPI "auto" ended with while the dialog was waiting, if
  /// that round was for this server.
  final AntiDpiRound? auto;

  const ConnectionDiagnosis({
    required this.verdict,
    this.updatedServer,
    this.alternative,
    this.engine,
    this.auto,
  });
}

enum _ProbeOutcome { ok, timeout, refused, failed }

enum _AuthOutcome { accepted, rejected, unknown }

enum _SubscriptionOutcome { notFound, updated, unchanged, failed }

/// What one handshake with our server showed.
class _ServerProbe {
  /// The server answered the handshake (a TLS alert or an untrusted
  /// certificate count too).
  final bool reached;

  /// Whether the server accepted our credentials, when it got that far.
  final _AuthOutcome auth;

  /// The device clock is outside the validity of the certificate it showed.
  final bool clockWrong;

  const _ServerProbe({required this.reached, this.auth = _AuthOutcome.unknown, this.clockWrong = false});
}

/// {@template connection_diagnostics}
/// Works out *why* a VPN connection is stuck, one layer at a time: internet
/// at all (the system's word) -> TCP to the server -> TLS with its SNI ->
/// credentials (asked from the server itself, then from the subscription).
///
/// Packets go only where the app connects anyway: the server itself, other
/// servers of the same subscription, the subscription host. No reference
/// hosts: a probe to someone else's host carrying our server's name is a
/// probe through the filter and tells it our name.
///
/// Runs over the plain network even while the tunnel is still trying: the
/// vendor VPN service excludes CatTunnel's own package from the tunnel
/// (`addDisallowedApplication(packageName)`), so these sockets never loop
/// through the half-up VPN. On Windows [PhysicalNet] pins them to the
/// physical adapter instead.
///
/// Server-side behavior this relies on (TrustTunnel endpoint, see its
/// `core.rs`/`tls_demultiplexer.rs`): connections with an unknown SNI or an
/// unacceptable ALPN are dropped without a TLS alert, `client_random_prefix`
/// rules default to allow, and a CONNECT with bad credentials gets
/// `auth_failure_status_code` (one of 403/404/405/407).
/// {@endtemplate}
class ConnectionDiagnostics {
  static const _tcpTimeout = Duration(seconds: 5);
  static const _tlsTimeout = Duration(seconds: 6);

  /// Offer both, so the server picks whichever tunnel protocol it has on -
  /// an ALPN it can't use makes it drop the connection like DPI would.
  static const _tunnelAlpn = ['h2', 'http/1.1'];

  static const _authProbeTarget = 'ya.ru:443';
  static const _authRejectedCodes = {403, 404, 405, 407};

  /// Subscription 404s count toward the main host's fail2ban `nginx-sub`
  /// jail (10 per 10 minutes bans the whole IP - often a family's shared
  /// one), so a repeatedly stuck connection must not refetch on every run.
  static const _subscriptionCheckCooldown = Duration(minutes: 5);
  static final _recentSubscriptionChecks = <String, (DateTime, _SubscriptionOutcome)>{};

  /// A network verdict for a server is reused this long instead of probing
  /// it again. Every probe is a TLS handshake to the server's SNI on top of
  /// the engine's own retries, and a burst of handshakes to one name is
  /// reportedly what TSPU's behavioural "freeze" (June 2026, ~120 s
  /// blackhole) keys on - retrying inside it only extends it. See
  /// the public reports on TSPU behaviour.
  static const _probeCooldown = Duration(minutes: 2);
  static final _recentVerdicts = <String, (DateTime, ConnectionDiagnosis)>{};

  static const _networkVerdicts = {
    DiagnosisVerdict.serverTimeout,
    DiagnosisVerdict.serverRefused,
    DiagnosisVerdict.tlsBlocked,
    DiagnosisVerdict.trafficBlocked,
  };

  final SubscriptionRepository _subscriptionRepository;
  final ServerRepository _serverRepository;
  final bool _trustUserCas;

  /// The app's memory of the networks. Without it the diagnosis still
  /// works, it just cannot say that this network is already known to cut
  /// the plain connection.
  final SharedPreferences? _preferences;

  const ConnectionDiagnostics({
    required SubscriptionRepository subscriptionRepository,
    required ServerRepository serverRepository,
    bool trustUserCas = false,
    SharedPreferences? preferences,
  }) : _subscriptionRepository = subscriptionRepository,
       _serverRepository = serverRepository,
       _trustUserCas = trustUserCas,
       _preferences = preferences;

  /// {@macro connection_diagnostics}
  ///
  /// [onStep] reports progress for the UI; [otherServers] are candidates for
  /// [ConnectionDiagnosis.alternative].
  Future<ConnectionDiagnosis> run(
    Server server, {
    required List<Server> otherServers,
    required void Function(DiagnosisStep step, DiagnosisStepStatus status) onStep,
  }) async {
    final fingerprint = await NetworkFingerprints.current(kind: await AntiDpiAuto.networkKind());
    final kind = fingerprint.kind;
    final network = fingerprint.key;
    // The address and the network too: a verdict for the old one says
    // nothing once the user or the subscription has changed it, and the
    // same server may be cut in one network and fine in another.
    final cacheKey = '${server.id}|${server.serverData.ipAddress}|$network';
    if (ConnectFailures.isFrozen(server.id)) {
      for (final step in DiagnosisStep.values) {
        onStep(step, DiagnosisStepStatus.skipped);
      }

      // Other servers are other addresses: one handshake each is fine.
      return ConnectionDiagnosis(
        verdict: DiagnosisVerdict.addressFrozen,
        alternative: await _findWorkingServer(otherServers),
      );
    }
    final recent = _recentVerdicts[cacheKey];
    if (recent != null && DateTime.now().difference(recent.$1) < _probeCooldown) {
      for (final step in DiagnosisStep.values) {
        onStep(step, DiagnosisStepStatus.skipped);
      }

      return recent.$2;
    }

    // The anti-DPI "auto" is switching techniques right now. Its
    // handshakes and ours would go to one name at the same time, and three
    // of them close to each other are what a filter's "freeze" keys on. So
    // we wait for the round to end (it is bounded itself) instead of
    // adding to it, and then say what it ended with.
    final waitedForRound = AntiDpiAuto.running.value;
    final round = await AntiDpiAuto.waitForRound(serverId: server.id);
    if (AntiDpiAuto.running.value) {
      for (final step in DiagnosisStep.values) {
        onStep(step, DiagnosisStepStatus.skipped);
      }

      return const ConnectionDiagnosis(verdict: DiagnosisVerdict.inconclusive);
    }
    if (round != null && (round.failed || waitedForRound)) {
      for (final step in DiagnosisStep.values) {
        onStep(step, DiagnosisStepStatus.skipped);
      }

      return round.failed
          ? ConnectionDiagnosis(verdict: DiagnosisVerdict.networkCuts, auto: round)
          : ConnectionDiagnosis(verdict: DiagnosisVerdict.inconclusive, auto: round);
    }

    // The app already knows this network cuts the plain connection. Saying
    // "no internet" here would be wrong even when the reference host does
    // not answer either: the bypass is on, and that is the way through. The
    // probes would also be more handshakes into the filter.
    final preferences = _preferences;
    if (preferences != null &&
        AntiDpiAuto(preferences).directFails(serverId: server.id, network: network, kind: kind)) {
      for (final step in DiagnosisStep.values) {
        onStep(step, DiagnosisStepStatus.skipped);
      }

      return const ConnectionDiagnosis(verdict: DiagnosisVerdict.bypassNeeded);
    }

    final diagnosis = await _run(server, otherServers: otherServers, onStep: onStep);
    if (_networkVerdicts.contains(diagnosis.verdict)) {
      _recentVerdicts[cacheKey] = (DateTime.now(), diagnosis);
    }

    return diagnosis;
  }

  /// Whether the engine's verdict says the path to the server was cut: a
  /// frozen address, a cut after a fixed number of bytes, a session that
  /// went silent. An error from the server is not the network's doing.
  @visibleForTesting
  static bool isCutVerdict(NetDiagnostic verdict) => verdict.isHandshakeFreeze || verdict.isCut || verdict.isStall;

  Future<ConnectionDiagnosis> _run(
    Server server, {
    required List<Server> otherServers,
    required void Function(DiagnosisStep step, DiagnosisStepStatus status) onStep,
  }) async {
    void skipFrom(DiagnosisStep step) {
      for (final later in DiagnosisStep.values.where((s) => s.index > step.index)) {
        onStep(later, DiagnosisStepStatus.skipped);
      }
    }

    Future<ConnectionDiagnosis> networkFailure(DiagnosisStep step, DiagnosisVerdict verdict) async {
      onStep(step, DiagnosisStepStatus.failed);
      skipFrom(step);

      return ConnectionDiagnosis(verdict: verdict, alternative: await _findWorkingServer(otherServers));
    }

    // 0. What the engine saw in the last session to this server: a frozen
    // address, a cut after a fixed number of bytes, a session that went
    // silent. That is the network's verdict, and no probe of ours can say
    // more - every probe is another handshake to the same name, and a burst
    // of them is what a filter's "freeze" keys on.
    final engine = NetDiagnostics.recent(server.id, within: NetDiagnostics.freshWindow);
    if (engine != null && isCutVerdict(engine)) {
      onStep(DiagnosisStep.internet, DiagnosisStepStatus.ok);
      skipFrom(DiagnosisStep.internet);

      return ConnectionDiagnosis(
        verdict: DiagnosisVerdict.networkCuts,
        engine: engine,
        alternative: await _findWorkingServer(otherServers),
      );
    }

    // 1. Internet at all: the system's word, and only the system's.
    //
    // Android checks the network itself (whether it reaches the internet,
    // whether it is a login page) and that costs no packet of ours. Where
    // the system has not checked, or there is no such signal (the desktop),
    // the step says "not checked" and the server itself is asked next: a
    // probe to a reference host would be a packet to someone else's host.
    onStep(DiagnosisStep.internet, DiagnosisStepStatus.running);
    final network = await NetworkStates.current();
    switch (network) {
      case NetworkState.none || NetworkState.captivePortal:
        onStep(DiagnosisStep.internet, DiagnosisStepStatus.failed);
        skipFrom(DiagnosisStep.internet);

        // No network: another server would not help either.
        return ConnectionDiagnosis(
          verdict: network == NetworkState.captivePortal ? DiagnosisVerdict.captivePortal : DiagnosisVerdict.noInternet,
        );
      case NetworkState.validated:
        onStep(DiagnosisStep.internet, DiagnosisStepStatus.ok);
      case NetworkState.unvalidated || NetworkState.unknown:
        onStep(DiagnosisStep.internet, DiagnosisStepStatus.skipped);
    }

    // 2. TCP to the server itself.
    onStep(DiagnosisStep.server, DiagnosisStepStatus.running);
    final (host, port) = ServerLatencyTester.parseAddress(server.serverData.ipAddress);
    final tcp = await _tcp(host, port);
    if (tcp != _ProbeOutcome.ok) {
      return networkFailure(
        DiagnosisStep.server,
        tcp == _ProbeOutcome.refused ? DiagnosisVerdict.serverRefused : DiagnosisVerdict.serverTimeout,
      );
    }
    onStep(DiagnosisStep.server, DiagnosisStepStatus.ok);

    // 3. TLS with our SNI, to our server only. Whether the filter keys on
    // the name or on the address is not asked: that would take our name to
    // someone else's host. The certificate it shows also tells whether the
    // device clock is off (the clock has no other honest source here).
    onStep(DiagnosisStep.tls, DiagnosisStepStatus.running);
    final sni = ServerTls.sniOf(server);
    final probe = await _probeServer(server, host, port, sni: sni);
    if (probe.clockWrong) {
      onStep(DiagnosisStep.tls, DiagnosisStepStatus.failed);
      skipFrom(DiagnosisStep.tls);

      return const ConnectionDiagnosis(verdict: DiagnosisVerdict.clockWrong);
    }
    if (!probe.reached) {
      return networkFailure(DiagnosisStep.tls, DiagnosisVerdict.tlsBlocked);
    }
    onStep(DiagnosisStep.tls, DiagnosisStepStatus.ok);
    final auth = probe.auth;

    // 4. The path is clear - ask the server whether it takes our keys.
    onStep(DiagnosisStep.access, DiagnosisStepStatus.running);
    if (auth == _AuthOutcome.accepted) {
      onStep(DiagnosisStep.access, DiagnosisStepStatus.ok);

      return ConnectionDiagnosis(
        verdict: DiagnosisVerdict.trafficBlocked,
        alternative: await _findWorkingServer(otherServers),
      );
    }

    final diagnosis = await _checkSubscription(server, authRejected: auth == _AuthOutcome.rejected);
    onStep(
      DiagnosisStep.access,
      diagnosis.verdict == DiagnosisVerdict.keysUpdated ? DiagnosisStepStatus.ok : DiagnosisStepStatus.failed,
    );

    return diagnosis;
  }

  Future<ConnectionDiagnosis> _checkSubscription(Server server, {required bool authRejected}) async {
    final fallback = ConnectionDiagnosis(
      verdict: authRejected ? DiagnosisVerdict.keysRejected : DiagnosisVerdict.inconclusive,
    );

    final subscriptionName = server.serverData.subscriptionName;
    if (subscriptionName == null) {
      return fallback;
    }

    final subscriptions = await _subscriptionRepository.getAllSubscriptions();
    final subscription = subscriptions.firstWhereOrNull((s) => s.name == subscriptionName);
    if (subscription == null) {
      return fallback;
    }

    final cacheKey = subscription.id ?? subscription.name;
    final recent = _recentSubscriptionChecks[cacheKey];
    final useRecent = recent != null && DateTime.now().difference(recent.$1) < _subscriptionCheckCooldown;
    final outcome = useRecent ? recent.$2 : await _refreshSubscription(subscription);

    if (!useRecent && outcome != _SubscriptionOutcome.updated) {
      _recentSubscriptionChecks[cacheKey] = (DateTime.now(), outcome);
    }

    switch (outcome) {
      case _SubscriptionOutcome.notFound:
        return const ConnectionDiagnosis(verdict: DiagnosisVerdict.accessEnded);
      case _SubscriptionOutcome.unchanged:
      case _SubscriptionOutcome.failed:
        return fallback;
      case _SubscriptionOutcome.updated:
        break;
    }

    final refreshed = await _serverRepository.getServerById(id: server.id);
    if (refreshed == null) {
      return fallback;
    }

    final before = server.serverData;
    final after = refreshed.serverData;
    final changed =
        before.username != after.username ||
        before.password != after.password ||
        before.ipAddress != after.ipAddress ||
        before.domain != after.domain ||
        before.customSni != after.customSni;

    return changed ? ConnectionDiagnosis(verdict: DiagnosisVerdict.keysUpdated, updatedServer: refreshed) : fallback;
  }

  /// Refreshes the subscription. [_SubscriptionOutcome.updated] only means
  /// the fetch worked - whether *this* server's credentials changed is
  /// decided by the caller.
  Future<_SubscriptionOutcome> _refreshSubscription(SubscriptionData subscription) async {
    try {
      await _subscriptionRepository.refresh(subscription: subscription);

      return _SubscriptionOutcome.updated;
    } on SubscriptionFetchException catch (e) {
      return e.statusCode == 404 ? _SubscriptionOutcome.notFound : _SubscriptionOutcome.failed;
    } catch (_) {
      return _SubscriptionOutcome.failed;
    }
  }

  /// First of [candidates] that accepts a TCP connection right now (probed
  /// in parallel, one connect each), in their original order. No TLS: a
  /// handshake carries the name, and these servers are not the ones the
  /// person is connecting to.
  Future<Server?> _findWorkingServer(List<Server> candidates) async {
    final results = await Future.wait(
      candidates.map((candidate) async {
        final (host, port) = ServerLatencyTester.parseAddress(candidate.serverData.ipAddress);

        return await _tcp(host, port) == _ProbeOutcome.ok;
      }),
    );

    return candidates.whereIndexed((index, _) => results[index]).firstOrNull;
  }

  /// Whether the device clock explains a certificate our own server showed:
  /// [now] is before the certificate's start or after its end. Our
  /// certificates are renewed well before they end, so outside the window
  /// it is the clock, not the certificate.
  @visibleForTesting
  static bool clockOutside({required DateTime notBefore, required DateTime notAfter, required DateTime now}) =>
      now.isBefore(notBefore) || now.isAfter(notAfter);

  static bool _clockWrongFor(X509Certificate certificate) => clockOutside(
    notBefore: certificate.startValidity,
    notAfter: certificate.endValidity,
    now: DateTime.now(),
  );

  Future<_ProbeOutcome> _tcp(String host, int port) async {
    final pinned = await PhysicalNet.probeTcp(host, port, timeout: _tcpTimeout);
    if (pinned != null) {
      return switch (pinned) {
        'ok' => _ProbeOutcome.ok,
        'timeout' => _ProbeOutcome.timeout,
        'refused' => _ProbeOutcome.refused,
        _ => _ProbeOutcome.failed,
      };
    }

    try {
      final socket = await Socket.connect(host, port, timeout: _tcpTimeout);
      socket.destroy();

      return _ProbeOutcome.ok;
    } on SocketException catch (e) {
      final code = e.osError?.errorCode;
      final message = '${e.message} ${e.osError?.message ?? ''}'.toLowerCase();

      // ECONNREFUSED: 111 on Linux/Android.
      if (code == 111 || message.contains('refused')) {
        return _ProbeOutcome.refused;
      }
      if (message.contains('timed out')) {
        return _ProbeOutcome.timeout;
      }

      return _ProbeOutcome.failed;
    } catch (_) {
      return _ProbeOutcome.failed;
    }
  }

  /// Whether a TLS handshake with [sni] got an answer from the server.
  ///
  /// Certificates aren't judged here (nothing secret is sent), and a TLS
  /// alert still counts as "reached it". What DPI does is reset/close the
  /// connection mid-handshake ("Connection terminated during handshake" -
  /// also a [HandshakeException], so only alerts count) or silently drop it
  /// (timeout).
  Future<_ServerProbe> _tls(String host, int port, {required String sni}) async {
    Socket? socket;
    var clockWrong = false;
    try {
      socket = await PhysicalNet.connect(host, port, timeout: _tcpTimeout);
      final secure = await SecureSocket.secure(
        socket,
        host: sni,
        onBadCertificate: (certificate) {
          clockWrong = _clockWrongFor(certificate);

          return true;
        },
        supportedProtocols: _tunnelAlpn,
      ).timeout(_tlsTimeout);
      final certificate = secure.peerCertificate;
      if (certificate != null && _clockWrongFor(certificate)) {
        clockWrong = true;
      }
      secure.destroy();

      return _ServerProbe(reached: true, clockWrong: clockWrong);
    } on HandshakeException catch (e) {
      final alert = '${e.message} ${e.osError?.message ?? ''}'.toUpperCase().contains('ALERT');

      return _ServerProbe(reached: alert, clockWrong: clockWrong);
    } catch (_) {
      return _ServerProbe(reached: false, clockWrong: clockWrong);
    } finally {
      socket?.destroy();
    }
  }

  /// TLS to the server and, on the same connection, whether it accepts our
  /// credentials - one handshake to its SNI where there used to be two
  /// (see [_probeCooldown] for why that matters).
  ///
  /// The credential check is an HTTP/1.1 CONNECT with Basic proxy auth, the
  /// same way the VPN client authenticates; any status outside
  /// [_authRejectedCodes] means the auth itself passed. Credentials only
  /// ever go to a *verified* peer (see [ServerTls] - the same trust the VPN
  /// engine uses), so a TLS-intercepting middlebox, e.g. one holding the
  /// Russian Ministry root, can't harvest them.
  ///
  /// "Reached" = the server answered the handshake (a TLS alert or a
  /// certificate we don't trust count too). A silent timeout - DPI dropping
  /// or freezing the flow - is final. Only a connection closed mid-handshake
  /// is ambiguous (the server also drops an ALPN it doesn't serve, and we
  /// offered just http/1.1 here), so only then one more unverified
  /// handshake offering both tunnel ALPNs decides.
  Future<_ServerProbe> _probeServer(Server server, String host, int port, {required String sni}) async {
    final context = await ServerTls.contextFor(server, trustUserCas: _trustUserCas);
    if (context == null) {
      return _tls(host, port, sni: sni);
    }

    Socket? socket;
    SecureSocket? secure;
    var clockWrong = false;
    try {
      socket = await PhysicalNet.connect(host, port, timeout: _tcpTimeout);
      secure = await SecureSocket.secure(
        socket,
        host: sni,
        context: context,
        // Called only when verification failed; the answer stays "no".
        onBadCertificate: (certificate) {
          clockWrong = _clockWrongFor(certificate);

          return false;
        },
        supportedProtocols: const ['http/1.1'],
      ).timeout(_tlsTimeout);
    } on HandshakeException catch (e) {
      socket?.destroy();
      final message = '${e.message} ${e.osError?.message ?? ''}'.toUpperCase();
      if (clockWrong || message.contains('ALERT') || message.contains('CERTIFICATE')) {
        return _ServerProbe(reached: true, clockWrong: clockWrong);
      }

      return _tls(host, port, sni: sni);
    } on TimeoutException {
      socket?.destroy();

      return const _ServerProbe(reached: false);
    } catch (_) {
      socket?.destroy();

      return const _ServerProbe(reached: false);
    }

    try {
      final credentials = base64.encode(utf8.encode('${server.serverData.username}:${server.serverData.password}'));
      secure.write(
        'CONNECT $_authProbeTarget HTTP/1.1\r\n'
        'Host: $_authProbeTarget\r\n'
        'Proxy-Authorization: Basic $credentials\r\n'
        '\r\n',
      );
      await secure.flush();

      final statusLine = await utf8.decoder.bind(secure).transform(const LineSplitter()).first.timeout(_tlsTimeout);
      final status = int.tryParse(statusLine.split(' ').elementAtOrNull(1) ?? '');
      if (status == null) {
        return const _ServerProbe(reached: true);
      }

      return _ServerProbe(
        reached: true,
        auth: _authRejectedCodes.contains(status) ? _AuthOutcome.rejected : _AuthOutcome.accepted,
      );
    } catch (_) {
      return const _ServerProbe(reached: true);
    } finally {
      secure.destroy();
      socket.destroy();
    }
  }
}
