import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:trusttunnel/common/extensions/model_extensions.dart';
import 'package:trusttunnel/common/logging/extensions/vpn_logger_extension.dart';
import 'package:trusttunnel/common/utils/upstream_protocol_encoder.dart';
import 'package:trusttunnel/common/utils/validation_utils.dart';
import 'package:trusttunnel/common/utils/vpn_mode_encoder.dart';
import 'package:trusttunnel/data/datasources/app_split_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/kill_switch_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/mtu_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/native_sources/endpoint_ca_resolver.dart';
import 'package:trusttunnel/data/datasources/ru_services_settings_datasource.dart';
import 'package:trusttunnel/data/datasources/vpn_datasource.dart';
import 'package:trusttunnel/data/model/routing_mode.dart';
import 'package:trusttunnel/data/model/routing_profile_data.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_log.dart';
import 'package:trusttunnel/data/model/vpn_logging_payload.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/data/ru_lists/ru_lists_service.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/auto_bypass_apps.dart';
import 'package:trusttunnel/feature/settings/app_split/domain/installed_apps_platform.dart';
import 'package:trusttunnel/feature/vpn/domain/services/vpn_log_converter.dart';
import 'package:trusttunnel/feature/vpn/domain/tls_profile_auto.dart';
import 'package:vpn_plugin/models/configuration.dart';
import 'package:vpn_plugin/models/configuration_log_level.dart';
import 'package:vpn_plugin/models/connect_failure.dart';
import 'package:vpn_plugin/models/endpoint.dart';
import 'package:vpn_plugin/models/query_log_row.dart';
import 'package:vpn_plugin/models/socks.dart';
import 'package:vpn_plugin/models/tun.dart';
import 'package:vpn_plugin/platform_api.g.dart' as p;
import 'package:vpn_plugin/vpn_plugin.dart';

/// {@template vpn_data_source_impl}
/// Platform-backed implementation of [VpnDataSource].
///
/// This implementation adapts the generated plugin API ([VpnPlugin]) to the
/// domain-level abstractions used by the app. Its responsibilities include:
/// - converting platform enums and models into domain equivalents,
/// - constructing a platform [Configuration] from domain models,
/// - exposing platform streams as domain streams.
///
/// This class does not cache state or retry operations; it is a thin translation
/// layer between Dart domain code and the platform channel.
/// {@endtemplate}
class VpnDataSourceImpl implements VpnDataSource {
  final VpnPlugin _platformApi;
  final KillSwitchSettingsDataSource _killSwitchSettingsDataSource;
  final MtuSettingsDataSource _mtuSettingsDataSource;
  final RuServicesSettingsDataSource _ruServicesSettingsDataSource;
  final AppSplitSettingsDataSource _appSplitSettingsDataSource;
  final RuListsService _ruListsService;
  final EndpointCaResolver _endpointCaResolver;

  /// {@macro vpn_data_source_impl}
  VpnDataSourceImpl({
    required VpnPlugin vpnPlugin,
    required KillSwitchSettingsDataSource killSwitchSettingsDataSource,
    required MtuSettingsDataSource mtuSettingsDataSource,
    required RuServicesSettingsDataSource ruServicesSettingsDataSource,
    required AppSplitSettingsDataSource appSplitSettingsDataSource,
    required RuListsService ruListsService,
    required EndpointCaResolver endpointCaResolver,
  }) : _platformApi = vpnPlugin,
       _killSwitchSettingsDataSource = killSwitchSettingsDataSource,
       _mtuSettingsDataSource = mtuSettingsDataSource,
       _ruServicesSettingsDataSource = ruServicesSettingsDataSource,
       _appSplitSettingsDataSource = appSplitSettingsDataSource,
       _ruListsService = ruListsService,
       _endpointCaResolver = endpointCaResolver {
    final platformStates = _platformApi.states;
    final platformQueryLog = _platformApi.queryLog;

    _loggingVpnObserver = logger.extension<VpnLoggerExtension>();

    final vpnState = platformStates.transform(
      StreamTransformer<p.VpnManagerState, VpnState>.fromHandlers(
        handleData: (data, sink) => sink.add(VpnStateFromApi.parse(data)),
        handleDone: (sink) async {
          await _platformApi.stop();
          sink
            ..add(VpnState.disconnected)
            ..close();
        },
      ),
    );
    final vpnLogs = platformQueryLog.transform(
      StreamTransformer<QueryLogRow, VpnLog>.fromHandlers(
        handleData: (data, sink) => sink.add(VpnLogConverter().convert(data)),
        handleDone: (sink) => sink.close(),
      ),
    );

    _vpnState = _loggingVpnObserver?.observeStateStream(vpnState) ?? vpnState;
    _vpnLogs = _loggingVpnObserver?.observeQueryLogStream(vpnLogs) ?? vpnLogs;
  }

  late final VpnLoggerExtension? _loggingVpnObserver;
  late final Stream<VpnState> _vpnState;
  late final Stream<VpnLog> _vpnLogs;

  /// {@macro vpn_data_source_state_stream}
  ///
  /// Platform states are converted to [VpnState]. When the underlying platform
  /// state stream completes, the VPN is explicitly stopped and a final
  /// [VpnState.disconnected] value is emitted before closing the stream.
  @override
  Stream<VpnState> get vpnState => _vpnState;

  /// {@macro vpn_data_source_logs_stream}
  ///
  /// Platform log rows are converted into domain [VpnLog] entries.
  @override
  Stream<VpnLog> get vpnLogs => _vpnLogs;

  @override
  Stream<ConnectFailure> get connectFailures => _platformApi.connectFailures;

  /// {@macro vpn_data_source_start}
  ///
  /// This implementation:
  /// 1) derives exclusions based on the routing profile,
  /// 2) constructs a platform [Endpoint] and [Configuration],
  /// 3) invokes the platform `start` command.
  @override
  Future<void> start({
    required ServerData server,
    required RoutingProfileData routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) async {
    final prep = await _prepare(server, routingProfile, excludedRoutes);
    final exclusions = prep.exclusions;
    final allExcludedRoutes = prep.excludedRoutes;
    final appSplit = prep.appSplit;
    final killSwitchEnabled = await _killSwitchSettingsDataSource.isEnabled();
    final mtuSize = await _mtuSettingsDataSource.getValue();
    final certificate = await _endpointCaResolver.certificateFor(server);

    final endPoint = Endpoint(
      name: server.name,
      hostName: server.domain,
      hasIpv6: server.ipv6,
      antiDpi: server.antiDpi,
      antiDpiMode: server.engineAntiDpiMode,
      tlsProfile: await TlsProfileAuto.resolve(server.tlsProfile),
      antiDpiDesync: server.engineAntiDpiDesync,
      h2PaddingFrames: server.h2PaddingFrames,
      blockQuic: server.blockQuic,
      certificate: certificate,
      clientRandom: server.tlsPrefix ?? '',
      customSni: server.customSni ?? '',
      username: server.username,
      password: server.password,
      addresses: [
        server.ipAddress,
      ],
      exclusions: exclusions,
      dnsUpStreams: server.dnsServers,
      upStreamProtocol: UpStreamProtocolEncoder().convert(
        server.vpnProtocol,
      ),
    );

    Future<void> command() => _platformApi.start(
      configuration: Configuration(
        logLevel: _convertLogLevel(logLevel),
        vpnMode: VpnModeEncoder().convert(prep.mode),
        endpoint: endPoint,
        tun: Tun(
          excludedRoutes: allExcludedRoutes,
          mtuSize: mtuSize,
          excludedApps: appSplit.excluded,
          includedApps: appSplit.included,
        ),
        socks: const Socks(),
        killSwitchEnabled: killSwitchEnabled,
      ),
    );

    if (_loggingVpnObserver != null) {
      await _loggingVpnObserver.runCommand(
        'start',
        command,
        payloadBuilder: () => VpnLoggingPayload.fromModels(
          server: server,
          routingProfile: routingProfile,
          excludedRoutes: excludedRoutes,
        ).toJson(),
      );

      return;
    }

    await command();
  }

  /// {@macro vpn_data_source_stop}
  @override
  Future<void> stop() => _loggingVpnObserver?.runCommand('stop', _platformApi.stop) ?? _platformApi.stop();

  /// {@macro vpn_data_source_request_state}
  ///
  /// The platform state is converted into a domain [VpnState].
  @override
  Future<VpnState> requestState() async {
    Future<VpnState> command() async {
      final state = await _platformApi.getCurrentState();

      return VpnStateFromApi.parse(state);
    }

    return _loggingVpnObserver?.runCommandWithResult('requestState', command) ?? command();
  }

  @override
  Future<void> updateConfiguration({
    required ServerData server,
    required RoutingProfileData routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) async {
    final prep = await _prepare(server, routingProfile, excludedRoutes);
    final exclusions = prep.exclusions;
    final allExcludedRoutes = prep.excludedRoutes;
    final appSplit = prep.appSplit;
    final killSwitchEnabled = await _killSwitchSettingsDataSource.isEnabled();
    final mtuSize = await _mtuSettingsDataSource.getValue();
    final certificate = await _endpointCaResolver.certificateFor(server);

    final endPoint = Endpoint(
      name: server.name,
      hostName: server.domain,
      hasIpv6: server.ipv6,
      antiDpi: server.antiDpi,
      antiDpiMode: server.engineAntiDpiMode,
      tlsProfile: await TlsProfileAuto.resolve(server.tlsProfile),
      antiDpiDesync: server.engineAntiDpiDesync,
      h2PaddingFrames: server.h2PaddingFrames,
      blockQuic: server.blockQuic,
      username: server.username,
      password: server.password,
      addresses: [
        server.ipAddress,
      ],
      exclusions: exclusions,
      dnsUpStreams: server.dnsServers,
      upStreamProtocol: UpStreamProtocolEncoder().convert(
        server.vpnProtocol,
      ),
      customSni: server.customSni ?? '',
      certificate: certificate,
      clientRandom: server.tlsPrefix ?? '',
    );

    Future<void> command() => _platformApi.updateConfiguration(
      configuration: Configuration(
        logLevel: _convertLogLevel(logLevel),
        vpnMode: VpnModeEncoder().convert(prep.mode),
        endpoint: endPoint,
        tun: Tun(
          excludedRoutes: allExcludedRoutes,
          mtuSize: mtuSize,
          excludedApps: appSplit.excluded,
          includedApps: appSplit.included,
        ),
        socks: const Socks(),
        killSwitchEnabled: killSwitchEnabled,
      ),
    );

    if (_loggingVpnObserver != null) {
      await _loggingVpnObserver.runCommand(
        'updateConfiguration',
        command,
        payloadBuilder: () => VpnLoggingPayload.fromModels(
          server: server,
          routingProfile: routingProfile,
          excludedRoutes: excludedRoutes,
        ).toJson(),
      );

      return;
    }

    await command();
  }

  @override
  Future<void> deleteConfiguration() =>
      _loggingVpnObserver?.runCommand(
        'deleteConfiguration',
        () => _platformApi.updateConfiguration(configuration: null),
      ) ??
      _platformApi.updateConfiguration(configuration: null);

  /// Everything [start] / [updateConfiguration] hand the engine besides the
  /// server itself.
  ///
  /// Usual key: Russian apps and networks bypass the VPN (per-app split,
  /// OS routes, engine exclusions), everything else goes through it.
  ///
  /// Russian-exit key ([ServerData.ruExit], for people abroad): the reverse -
  /// the engine goes direct by default and sends Russian domains/networks
  /// (the same lists) through the VPN, from any app, browsers included.
  /// Per-app split and the Russian OS routes don't apply then: every app
  /// has to enter the tunnel for its Russian traffic to reach the server.
  Future<
    ({
      RoutingMode mode,
      List<String> exclusions,
      List<String> excludedRoutes,
      ({List<String> excluded, List<String> included}) appSplit,
    })
  >
  _prepare(ServerData server, RoutingProfileData routingProfile, List<String> excludedRoutes) async {
    final watch = Stopwatch()..start();
    if (server.ruExit) {
      final ru = await _getRuRules(server);
      final exclusions = {...ru.rules, ...ru.prepared}.toList();
      logger.logInfo(
        'Connect prepared in ${watch.elapsedMilliseconds} ms (Russian exit): '
        '${exclusions.length} rules through the VPN, the rest direct',
      );

      return (
        mode: RoutingMode.bypass,
        exclusions: exclusions,
        excludedRoutes: excludedRoutes,
        appSplit: (excluded: <String>[], included: <String>[]),
      );
    }

    // The two slow parts (lists, installed apps) side by side.
    final appSplitFuture = _getAppSplit();
    final ruBypass = await _getRuServicesBypass(server);
    final appSplit = await appSplitFuture;
    final exclusions = _getExclusionsByMode(
      routingProfile,
      extraBypassRules: ruBypass.rules,
      preparedBypassRules: ruBypass.prepared,
    );
    final allExcludedRoutes = [...excludedRoutes, ...ruBypass.routes];
    logger.logInfo(
      'Connect prepared in ${watch.elapsedMilliseconds} ms: ${exclusions.length} exclusions, '
      '${allExcludedRoutes.length} excluded routes, ${appSplit.excluded.length} bypassing apps',
    );

    return (
      mode: routingProfile.defaultMode,
      exclusions: exclusions,
      excludedRoutes: allExcludedRoutes,
      appSplit: appSplit,
    );
  }

  /// The Russian rules for a Russian-exit key: the built-in list (whatever
  /// the "Russian services" toggle says - here it's the point of the key)
  /// plus the downloaded domains and networks, domains with their `*.`
  /// variants.
  Future<({List<String> rules, List<String> prepared})> _getRuRules(ServerData server) async {
    final builtIn = await _ruServicesSettingsDataSource.getRules();
    final lists = await _ruListsService.load(keepInVpn: _serverAddresses(server));
    final rules = <String>{};
    for (final rule in builtIn) {
      final domain = ValidationUtils.tryParseDomain(rule, allowFirstLevel: true);
      if (domain == null) {
        rules.add(rule);
        continue;
      }
      rules.add(domain);
      if (!domain.startsWith('*.')) rules.add('*.$domain');
    }

    return (rules: rules.toList(), prepared: [...lists.domains, ...lists.cidrs]);
  }

  /// Per-app split tunneling - Android only (CatTunnel's engine patch).
  /// Russian apps never go through the VPN: they bypass it in every mode and
  /// are dropped from an "only these through the VPN" list. The other
  /// automatic apps (Chinese/vendor, Uzbek, local tools) bypass it while
  /// "Auto" is on, except the ones the person put back into the VPN.
  Future<({List<String> excluded, List<String> included})> _getAppSplit() async {
    const none = (excluded: <String>[], included: <String>[]);
    if (defaultTargetPlatform != TargetPlatform.android) return none;
    final mode = await _appSplitSettingsDataSource.getMode();
    final picked = await _appSplitSettingsDataSource.getApps(mode);

    var auto = AutoBypassApps.empty;
    try {
      auto = await autoBypassApps(_ruListsService);
    } on Object {
      // No app list (platform error) - the picked apps still apply.
    }

    if (mode == AppSplitMode.include) {
      final included = picked.where((package) => !auto.ru.contains(package)).toList();
      // Only Russian apps were picked: an empty allow-list would mean "the
      // VPN covers everything", Russian apps included - bypass them instead.
      if (included.isEmpty && picked.isNotEmpty) {
        return (excluded: (auto.ru.toList()..sort()), included: <String>[]);
      }

      return (excluded: <String>[], included: included);
    }

    final bypassing = auto.bypassing(
      otherOn: await _appSplitSettingsDataSource.getAutoRuCn(),
      forcedVpn: await _appSplitSettingsDataSource.getForcedVpn(),
    );

    return (excluded: ({...picked, ...bypassing}.toList()..sort()), included: <String>[]);
  }

  /// "Russian services bypass the VPN": the editable built-in list plus the
  /// downloaded Russian networks/domains (RuListsService). On Android the
  /// large v4 networks of the built-in list become OS routes (the traffic
  /// never enters the tunnel); everything else - and everything on other
  /// platforms - engine exclusions. [prepared] are already normalized rules
  /// (the downloaded lists) that skip the per-rule parsing. The VPN server's
  /// own address is never bypassed. Refreshes the lists in the background a
  /// bit later, so the downloads don't compete with the connection (applied
  /// on the next connect).
  Future<({List<String> rules, List<String> prepared, List<String> routes})> _getRuServicesBypass(
    ServerData server,
  ) async {
    final enabled = await _ruServicesSettingsDataSource.isEnabled();
    if (!enabled) {
      return (rules: const <String>[], prepared: const <String>[], routes: const <String>[]);
    }

    unawaited(Future<void>.delayed(const Duration(seconds: 30), _ruListsService.refreshIfDue));
    final keepInVpn = _serverAddresses(server);
    final builtIn = await _ruServicesSettingsDataSource.getRules();
    final lists = await _ruListsService.load(keepInVpn: keepInVpn);
    final android = defaultTargetPlatform == TargetPlatform.android;

    return (
      rules: builtIn,
      prepared: [...lists.domains, ...lists.cidrs],
      routes: android
          ? RuListsService.routesFromRules(
              builtIn,
              keepInVpn: keepInVpn,
              everyNetwork: await _nativeExcludedRoutes(),
            )
          : const <String>[],
    );
  }

  /// Android 13+: the engine hands excluded routes to the OS as they are
  /// (Builder.excludeRoute, engine patch 0004) instead of their complement.
  static Future<bool> _nativeExcludedRoutes() async {
    try {
      return await InstalledAppsPlatform.sdkInt() >= 33;
    } on Object {
      return false;
    }
  }

  /// The server's IP (without a port) as a CIDR to keep in the VPN.
  static List<String> _serverAddresses(ServerData server) {
    var host = server.ipAddress.trim();
    if (host.startsWith('[')) {
      final end = host.indexOf(']');
      host = host.substring(1, end < 0 ? host.length : end);
    } else if (host.split(':').length == 2) {
      host = host.split(':').first;
    }

    return [host];
  }

  /// Computes the effective exclusion list based on routing mode.
  ///
  /// Domains are normalized to include wildcard variants when appropriate.
  ///
  /// [extraBypassRules] are rules that should always go direct (bypass the
  /// VPN), regardless of the profile. They are only merged in when the
  /// profile's default mode is [RoutingMode.vpn] - under [RoutingMode.bypass]
  /// everything not explicitly sent through the VPN already goes direct, so
  /// adding them to `exclusions` there would incorrectly force them through
  /// the tunnel instead (see [RoutingMode] semantics below).
  ///
  /// [preparedBypassRules] are like [extraBypassRules] but already
  /// normalized (domains with their `*.` variants, CIDRs): tens of thousands
  /// of them, added as they are.
  List<String> _getExclusionsByMode(
    RoutingProfileData profile, {
    List<String> extraBypassRules = const [],
    List<String> preparedBypassRules = const [],
  }) {
    final List<String> exclusions;

    switch (profile.defaultMode) {
      case RoutingMode.bypass:
        exclusions = profile.vpnRules;
      case RoutingMode.vpn:
        exclusions = [...profile.bypassRules, ...extraBypassRules];
    }

    const wildCard = '*.';
    final Set<String> parsedDomains = {};
    final Set<String> parsedAddresses = {};

    for (final exclusion in exclusions) {
      final domainValue = ValidationUtils.tryParseDomain(exclusion, allowFirstLevel: true);

      if (domainValue == null) {
        parsedAddresses.add(exclusion);

        continue;
      }

      parsedDomains.add(domainValue);
      if (!domainValue.startsWith(wildCard)) {
        parsedDomains.add('$wildCard$domainValue');
      }
    }

    return {
      ...parsedAddresses,
      ...parsedDomains,
      if (profile.defaultMode == RoutingMode.vpn) ...preparedBypassRules,
    }.toList();
  }

  ConfigurationLogLevel _convertLogLevel(VpnConfigurationLogLevel logLevel) => switch (logLevel) {
    VpnConfigurationLogLevel.error => ConfigurationLogLevel.error,
    VpnConfigurationLogLevel.info => ConfigurationLogLevel.info,
    VpnConfigurationLogLevel.debug => ConfigurationLogLevel.debug,
  };
}
