import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:trusttunnel/common/utils/physical_net.dart';
import 'package:trusttunnel/data/domain/subscription_sync_service.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/repository/server_repository.dart';
import 'package:trusttunnel/data/repository/subscription_repository.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';
import 'package:trusttunnel/feature/vpn/domain/connect_failures.dart';
import 'package:trusttunnel/feature/vpn/domain/server_tls.dart';

enum DiagnosisStep { internet, server, tls, access }

enum DiagnosisStepStatus { pending, running, ok, failed, skipped }

enum DiagnosisVerdict {
  /// Even a well-known domestic host is unreachable.
  noInternet,

  /// TCP connect to the server timed out - IP blocked, or the host is down.
  serverTimeout,

  /// The server host actively refused TCP - it's up, but nothing listens.
  serverRefused,

  /// TLS to the server dies, and so does a handshake carrying the server's
  /// SNI sent to an unrelated, reachable host - the name itself is filtered
  /// (DPI).
  sniBlocked,

  /// TLS to the server dies, but its SNI passes fine elsewhere - encrypted
  /// traffic to this particular IP is cut (e.g. mobile "whitelist" mode).
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

  /// The engine's ClientHello to this server got no answer a moment ago
  /// (ConnectFailures): a filter froze the address for a couple of minutes.
  /// Not probed - each handshake would keep it frozen.
  addressFrozen,
}

class ConnectionDiagnosis {
  final DiagnosisVerdict verdict;

  /// The same server with refreshed credentials ([DiagnosisVerdict.keysUpdated]).
  final Server? updatedServer;

  /// Another saved server that passed TCP + TLS right now, offered when the
  /// current one looks blocked.
  final Server? alternative;

  const ConnectionDiagnosis({
    required this.verdict,
    this.updatedServer,
    this.alternative,
  });
}

enum _ProbeOutcome { ok, timeout, refused, failed }

enum _AuthOutcome { accepted, rejected, unknown }

enum _SubscriptionOutcome { notFound, updated, unchanged, failed }

/// {@template connection_diagnostics}
/// Works out *why* a VPN connection is stuck, one layer at a time: internet
/// at all -> TCP to the server -> TLS with its SNI -> credentials (asked
/// from the server itself, then from the subscription).
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
  static const _referenceDnsIp = '77.88.8.8';

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
  /// ~/dpi_reading_notes.md in the project notes.
  static const _probeCooldown = Duration(minutes: 2);
  static final _recentVerdicts = <String, (DateTime, ConnectionDiagnosis)>{};

  static const _networkVerdicts = {
    DiagnosisVerdict.serverTimeout,
    DiagnosisVerdict.serverRefused,
    DiagnosisVerdict.sniBlocked,
    DiagnosisVerdict.tlsBlocked,
    DiagnosisVerdict.trafficBlocked,
  };

  final SubscriptionRepository _subscriptionRepository;
  final ServerRepository _serverRepository;
  final bool _trustUserCas;

  /// Reachable from any Russian network, including mobile whitelist modes.
  /// Used as the "is there internet" probe, and as the unrelated host that
  /// the server's SNI is sent to when checking for SNI filtering - ya.ru
  /// completes a handshake for any SNI. Overridable for tests only.
  final String _referenceHost;
  final int _referencePort;

  const ConnectionDiagnostics({
    required SubscriptionRepository subscriptionRepository,
    required ServerRepository serverRepository,
    bool trustUserCas = false,
    @visibleForTesting String referenceHost = 'ya.ru',
    @visibleForTesting int referencePort = 443,
  }) : _subscriptionRepository = subscriptionRepository,
       _serverRepository = serverRepository,
       _trustUserCas = trustUserCas,
       _referenceHost = referenceHost,
       _referencePort = referencePort;

  /// {@macro connection_diagnostics}
  ///
  /// [onStep] reports progress for the UI; [otherServers] are candidates for
  /// [ConnectionDiagnosis.alternative].
  Future<ConnectionDiagnosis> run(
    Server server, {
    required List<Server> otherServers,
    required void Function(DiagnosisStep step, DiagnosisStepStatus status) onStep,
  }) async {
    // The address too: a verdict for the old one says nothing once the user or
    // the subscription has changed it.
    final cacheKey = '${server.id}|${server.serverData.ipAddress}';
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

    final diagnosis = await _run(server, otherServers: otherServers, onStep: onStep);
    if (_networkVerdicts.contains(diagnosis.verdict)) {
      _recentVerdicts[cacheKey] = (DateTime.now(), diagnosis);
    }

    return diagnosis;
  }

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

    // 1. Internet at all.
    onStep(DiagnosisStep.internet, DiagnosisStepStatus.running);
    final internet =
        await _tcp(_referenceHost, _referencePort) == _ProbeOutcome.ok ||
        await _tcp(_referenceDnsIp, 53) == _ProbeOutcome.ok;
    if (!internet) {
      onStep(DiagnosisStep.internet, DiagnosisStepStatus.failed);
      skipFrom(DiagnosisStep.internet);

      return const ConnectionDiagnosis(verdict: DiagnosisVerdict.noInternet);
    }
    onStep(DiagnosisStep.internet, DiagnosisStepStatus.ok);

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

    // 3. TLS with our SNI. If it dies, send the same SNI to an unrelated
    // host: dying there too means the name itself is filtered - but only if
    // that host still takes its *own* SNI (control), otherwise the reference
    // is just unreachable and says nothing about our name.
    onStep(DiagnosisStep.tls, DiagnosisStepStatus.running);
    final sni = ServerTls.sniOf(server);
    final (reached, auth) = await _probeServer(server, host, port, sni: sni);
    if (!reached) {
      final sniFiltered =
          !await _tls(_referenceHost, _referencePort, sni: sni) &&
          await _tls(_referenceHost, _referencePort, sni: _referenceHost);

      return networkFailure(
        DiagnosisStep.tls,
        sniFiltered ? DiagnosisVerdict.sniBlocked : DiagnosisVerdict.tlsBlocked,
      );
    }
    onStep(DiagnosisStep.tls, DiagnosisStepStatus.ok);

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

  /// First of [candidates] that passes TCP + TLS right now (probed in
  /// parallel), in their original order.
  Future<Server?> _findWorkingServer(List<Server> candidates) async {
    final results = await Future.wait(
      candidates.map((candidate) async {
        final (host, port) = ServerLatencyTester.parseAddress(candidate.serverData.ipAddress);
        if (await _tcp(host, port) != _ProbeOutcome.ok) {
          return false;
        }

        return _tls(host, port, sni: ServerTls.sniOf(candidate));
      }),
    );

    return candidates.whereIndexed((index, _) => results[index]).firstOrNull;
  }

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
  Future<bool> _tls(String host, int port, {required String sni}) async {
    Socket? socket;
    try {
      socket = await PhysicalNet.connect(host, port, timeout: _tcpTimeout);
      final secure = await SecureSocket.secure(
        socket,
        host: sni,
        onBadCertificate: (_) => true,
        supportedProtocols: _tunnelAlpn,
      ).timeout(_tlsTimeout);
      secure.destroy();

      return true;
    } on HandshakeException catch (e) {
      return '${e.message} ${e.osError?.message ?? ''}'.toUpperCase().contains('ALERT');
    } catch (_) {
      return false;
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
  Future<(bool, _AuthOutcome)> _probeServer(Server server, String host, int port, {required String sni}) async {
    final context = await ServerTls.contextFor(server, trustUserCas: _trustUserCas);
    if (context == null) {
      return (await _tls(host, port, sni: sni), _AuthOutcome.unknown);
    }

    Socket? socket;
    SecureSocket? secure;
    try {
      socket = await PhysicalNet.connect(host, port, timeout: _tcpTimeout);
      secure = await SecureSocket.secure(
        socket,
        host: sni,
        context: context,
        supportedProtocols: const ['http/1.1'],
      ).timeout(_tlsTimeout);
    } on HandshakeException catch (e) {
      socket?.destroy();
      final message = '${e.message} ${e.osError?.message ?? ''}'.toUpperCase();
      if (message.contains('ALERT') || message.contains('CERTIFICATE')) {
        return (true, _AuthOutcome.unknown);
      }

      return (await _tls(host, port, sni: sni), _AuthOutcome.unknown);
    } on TimeoutException {
      socket?.destroy();

      return (false, _AuthOutcome.unknown);
    } catch (_) {
      socket?.destroy();

      return (false, _AuthOutcome.unknown);
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
        return (true, _AuthOutcome.unknown);
      }

      return (true, _authRejectedCodes.contains(status) ? _AuthOutcome.rejected : _AuthOutcome.accepted);
    } catch (_) {
      return (true, _AuthOutcome.unknown);
    } finally {
      secure.destroy();
      socket.destroy();
    }
  }
}
