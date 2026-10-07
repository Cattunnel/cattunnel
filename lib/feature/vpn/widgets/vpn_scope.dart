import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/utils/physical_net.dart';
import 'package:trusttunnel/data/model/routing_profile.dart';
import 'package:trusttunnel/data/model/server.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/model/vpn_configuration_log_level.dart';
import 'package:trusttunnel/data/model/vpn_log.dart';
import 'package:trusttunnel/data/model/vpn_state.dart';
import 'package:trusttunnel/data/repository/connection_notifications_settings_repository.dart';
import 'package:trusttunnel/data/repository/vpn_repository.dart';
import 'package:trusttunnel/feature/app/controller/app_window_controller.dart';
import 'package:trusttunnel/feature/menu_bar/tray_manager/macos/macos_exit_dialog.dart';
import 'package:trusttunnel/feature/security/domain/security_settings.dart';
import 'package:trusttunnel/feature/server/servers/domain/server_latency_tester.dart';
import 'package:trusttunnel/feature/vpn/domain/anti_dpi_auto.dart';
import 'package:trusttunnel/feature/vpn/domain/connect_failures.dart';
import 'package:trusttunnel/feature/vpn/domain/services/vpn_connection_notifier.dart';
import 'package:trusttunnel/feature/vpn/models/log_controller.dart';
import 'package:trusttunnel/feature/vpn/models/vpn_aspect.dart';
import 'package:trusttunnel/feature/vpn/models/vpn_controller.dart';
import 'package:vpn_plugin/models/connect_failure.dart';

/// {@template vpn_scope_on_start_callback}
/// Signature of the "start VPN" operation used by [VpnScope].
///
/// The callback starts a VPN session for the given [server] and [routingProfile]
/// and applies [excludedRoutes] (typically CIDR ranges) and [logLevel] as part of the configuration.
///
/// The concrete behavior depends on the platform/backend implementation behind
/// the repository, but the callback is expected to complete only after the
/// start request has been handed off to the backend (not necessarily after a
/// successful connection).
/// {@endtemplate}
typedef UpdateVpnCallback =
    Future<void> Function({
      required Server server,
      required RoutingProfile routingProfile,
      required List<String> excludedRoutes,
      required VpnConfigurationLogLevel logLevel,
    });

/// {@template vpn_scope}
/// Provides access to VPN state, logs, and control operations to a widget subtree.
///
/// `VpnScope` is an app-level scope built on top of [InheritedModel] that exposes
/// two "controllers" to descendants:
/// - a [VpnController] (VPN lifecycle + current [VpnState])
/// - a [LogController] (collected [VpnLog] entries)
///
/// Descendants obtain these controllers using:
/// - [VpnScope.vpnControllerOf] / [VpnScope.vpnControllerMaybeOf]
/// - [VpnScope.logsControllerOf] / [VpnScope.logsControllerMaybeOf]
///
/// ## How updates and rebuilds work
/// Internally, this scope uses [InheritedModel] with [VpnAspect] to support
/// aspect-based subscriptions:
/// - Consumers that subscribe to [VpnAspect.vpn] rebuild only when [VpnState]
///   changes.
/// - Consumers that subscribe to [VpnAspect.logs] rebuild only when the log list
///   changes.
/// - If a consumer requests both aspects, it may rebuild on either change.
///
/// To control whether your widget rebuilds:
/// - Pass `listen: true` (default) to subscribe and rebuild on updates.
/// - Pass `listen: false` to read the controller without subscribing.
///
/// ## VPN lifecycle and state
/// `VpnScope` maintains a current [VpnState] value and updates it by subscribing
/// to a state stream produced by [VpnRepository.listenToStates].
///
/// Calling [VpnController.start] will:
/// 1) stop any existing session (by calling [VpnController.stop]),
/// 2) start a new VPN session.
///
/// State observation starts with the scope itself and remains active for the
/// scope's entire lifetime, including when VPN changes are initiated outside
/// the app.
///
/// Calling [VpnController.stop] will:
/// - call [VpnRepository.stop] when the VPN is not already disconnected,
/// - reset [VpnController.state] to [VpnState.disconnected].
///
/// ## Logs collection
/// Logs are collected by subscribing to [VpnRepository.listenToLogs].
/// The scope stores logs in memory and keeps only the most recent entries
/// (see the internal log limit) to avoid unbounded growth.
///
/// ## Usage
/// Place the scope above any widgets that need VPN state/control:
///
/// ```dart
/// VpnScope(
///   vpnRepository: repository,
///   child: MyApp(),
/// )
/// ```
///
/// Then, inside the subtree:
///
/// ```dart
/// final vpn = VpnScope.vpnControllerOf(context); // subscribes by default
/// final logs = VpnScope.logsControllerOf(context, listen: false); // read only
/// ```
///
/// ## Errors
/// The `*Of` methods throw if called outside of a `VpnScope` subtree. Use the
/// `*MaybeOf` variants if you want a nullable result instead.
/// {@endtemplate}
class VpnScope extends StatefulWidget {
  /// Raised when a start never left "disconnected" - the VPN didn't even
  /// begin connecting (e.g. the system refused the VPN interface);
  /// ConnectionWatchdog shows Marsik's alert and resets it.
  static final startDidNotBegin = ValueNotifier<bool>(false);

  /// Raised when anti-DPI "auto" went through every technique and none
  /// connected; ConnectionWatchdog shows Marsik's alert and resets it.
  static final antiDpiAutoFailed = ValueNotifier<bool>(false);

  final AppWindowController? appWindowController;

  /// Repository used to start/stop the VPN and to listen for state/log updates.
  final VpnRepository vpnRepository;

  /// Initial state exposed before the repository provides real state updates.
  ///
  /// Defaults to [VpnState.disconnected].
  final VpnState initialState;

  /// Widget subtree that receives access to the scope.
  final Widget child;

  /// {@macro vpn_scope}
  const VpnScope({
    required this.appWindowController,
    required this.child,
    required this.vpnRepository,
    this.initialState = VpnState.disconnected,
    super.key,
  });

  @override
  State<VpnScope> createState() => _VpnScopeState();

  /// {@template vpn_scope_vpn_controller_maybe_of}
  /// Returns the nearest [VpnController] from the widget tree, or `null`.
  ///
  /// If [listen] is `true` (default), the caller subscribes to [VpnAspect.vpn]
  /// and will rebuild when the VPN state changes.
  ///
  /// If [listen] is `false`, the controller is read without establishing an
  /// inherited dependency, so the caller will not rebuild automatically.
  /// {@endtemplate}
  static VpnController? vpnControllerMaybeOf(BuildContext context, {bool listen = true}) =>
      _accessScope(context, listen: listen, aspect: VpnAspect.vpn);

  /// {@template vpn_scope_vpn_controller_of}
  /// Returns the nearest [VpnController] from the widget tree.
  ///
  /// If [listen] is `true` (default), the caller subscribes to [VpnAspect.vpn]
  /// and will rebuild when the VPN state changes.
  ///
  /// Throws an [ArgumentError] if called outside of a [VpnScope] subtree.
  /// Use [vpnControllerMaybeOf] when a nullable result is acceptable.
  /// {@endtemplate}
  static VpnController vpnControllerOf(BuildContext context, {bool listen = true}) =>
      _accessScope(context, listen: listen, aspect: VpnAspect.vpn) ?? _notFoundInheritedWidgetOfExactType();

  /// {@template vpn_scope_logs_controller_maybe_of}
  /// Returns the nearest [LogController] from the widget tree, or `null`.
  ///
  /// If [listen] is `true` (default), the caller subscribes to [VpnAspect.logs]
  /// and will rebuild when the logs list changes.
  ///
  /// If [listen] is `false`, the controller is read without establishing an
  /// inherited dependency.
  /// {@endtemplate}
  static LogController? logsControllerMaybeOf(BuildContext context, {bool listen = true}) =>
      _accessScope(context, listen: listen, aspect: VpnAspect.logs);

  /// {@template vpn_scope_logs_controller_of}
  /// Returns the nearest [LogController] from the widget tree.
  ///
  /// If [listen] is `true` (default), the caller subscribes to [VpnAspect.logs]
  /// and will rebuild when the logs list changes.
  ///
  /// Throws an [ArgumentError] if called outside of a [VpnScope] subtree.
  /// Use [logsControllerMaybeOf] when a nullable result is acceptable.
  /// {@endtemplate}
  static LogController logsControllerOf(BuildContext context, {bool listen = true}) =>
      _accessScope(context, listen: listen, aspect: VpnAspect.logs) ?? _notFoundInheritedWidgetOfExactType();

  static _InheritedVpnScope? _accessScope(BuildContext context, {bool listen = true, VpnAspect? aspect}) => (listen
      ? InheritedModel.inheritFrom<_InheritedVpnScope>(
          context,
          aspect: aspect,
        )
      : context.getElementForInheritedWidgetOfExactType<_InheritedVpnScope>()?.widget as _InheritedVpnScope?);

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
    'Out of scope, not found inherited widget '
        'a _InheritedVpnScope of the exact type',
    'out_of_scope',
  );
}

class _VpnScopeState extends State<VpnScope> {
  static const _logLimit = 500;

  late final ValueNotifier<VpnState> _stateNotifier;
  late final ValueNotifier<List<VpnLog>> _logsNotifier;

  /// Listens to app lifecycle events (resume and exit requested).
  /// Handles macOS exit requests by showing a dialog if the VPN is connected or connecting.
  late final AppLifecycleListener _appLifecycleListener;

  StreamSubscription<VpnLog>? _logStreamSub;
  StreamSubscription<VpnState>? _vpnStreamSub;
  StreamSubscription<ConnectFailure>? _failureSub;

  /// The engine's failures for the server being started, for anti-DPI
  /// "auto" (they are also kept in ConnectFailures).
  final _failures = StreamController<ConnectFailure>.broadcast();

  /// The server the last start was for.
  String? _currentServerId;

  // Tracks state updates so a delayed request cannot overwrite a newer VPN state.
  int _vpnStateRevision = 0;

  late final ConnectionNotificationsSettingsRepository _connectionNotificationsSettingsRepository;
  final VpnConnectionNotifier _connectionNotifier = VpnConnectionNotifier();
  String? _lastServerName;

  static const _startGrace = Duration(seconds: 6);
  int _startAttempt = 0;
  bool _leftDisconnectedSinceStart = true;

  /// The technique anti-DPI "auto" is running now, for configuration
  /// updates while connected; `null` when not in auto.
  int? _autoAntiDpiMode;

  /// Anti-DPI "auto" is between two techniques: no "disconnected" notice.
  bool _autoSwitching = false;

  /// The last start's settings and when it was asked for. A server switch
  /// reaches here twice - from the connect button and from VpnUpdateManager
  /// seeing the new selection - and the second start would be another
  /// handshake milliseconds after the first, a freeze trigger.
  int? _lastStartKey;
  DateTime _lastStartAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _sameStartWindow = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    _stateNotifier = ValueNotifier(widget.initialState);
    _logsNotifier = ValueNotifier(<VpnLog>[]);
    _connectionNotificationsSettingsRepository = context.repositoryFactory.connectionNotificationsSettingsRepository;
    _appLifecycleListener = AppLifecycleListener(
      onResume: _onAppResumed,
      onExitRequested: _onExitRequested,
    );
    unawaited(_listenToVpnStates());
    unawaited(_listenToLogs());
    _failureSub = widget.vpnRepository.connectFailures.listen(_onConnectFailure);
  }

  void _onConnectFailure(ConnectFailure failure) {
    final serverId = _currentServerId;
    if (serverId == null) {
      return;
    }
    ConnectFailures.record(serverId, failure);
    _failures.add(failure);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(
      [
        _stateNotifier,
        _logsNotifier,
      ],
    ),
    builder: (_, child) => _InheritedVpnScope(
      logs: _logsNotifier.value,
      state: _stateNotifier.value,
      onStart: _start,
      onStop: _stop,
      onUpdate: _updateConfiguration,
      onDeleteConfiguration: _deleteConfiguration,
      child: child!,
    ),
    child: widget.child,
  );

  Future<void> _deleteConfiguration() async {
    await _stop();

    return widget.vpnRepository.deleteConfiguration();
  }

  Future<void> _start({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) async {
    final key = Object.hash(server, routingProfile, Object.hashAll(excludedRoutes), logLevel);
    final now = DateTime.now();
    if (key == _lastStartKey && now.difference(_lastStartAt) < _sameStartWindow) {
      return;
    }

    await _stop();
    _lastStartKey = key;
    _lastStartAt = now;

    final attempt = ++_startAttempt;
    _leftDisconnectedSinceStart = false;
    _lastServerName = server.serverData.name;
    _currentServerId = server.id;
    _autoAntiDpiMode = null;
    // Windows: diagnostics must reach these while the tunnel owns DNS.
    await PhysicalNet.prime([ServerLatencyTester.parseAddress(server.serverData.ipAddress).$1, 'ya.ru']);

    final data = server.serverData;
    if (data.antiDpi && data.antiDpiMode == ServerData.antiDpiAuto) {
      await _startAntiDpiAuto(
        attempt: attempt,
        server: server,
        routingProfile: routingProfile,
        excludedRoutes: excludedRoutes,
        logLevel: logLevel,
      );

      return;
    }

    await widget.vpnRepository.start(
      server: server,
      routingProfile: routingProfile,
      excludedRoutes: excludedRoutes,
      logLevel: logLevel,
    );

    _watchStartBegins(attempt);
  }

  /// Anti-DPI "auto": the techniques in AntiDpiAuto's order, one round,
  /// each until it connects or AntiDpiAuto.attemptTimeout; the one that
  /// connects is remembered for this server and network. None - the VPN is
  /// stopped and Marsik says so. A stop or another start in between ends
  /// the round.
  ///
  /// The engine's failure (our build; without it the round just times out)
  /// decides what happens after a technique fails:
  /// - hello_reset - the filter cut this technique: the next one;
  /// - hello_no_answer - the address looks frozen: no more switching, the
  ///   engine keeps the technique and waits a minute itself (another
  ///   technique is another handshake into the freeze). A start while the
  ///   address is still frozen (ConnectFailures) tries only the first one;
  /// - connect - no TCP at all, no technique helps: the engine keeps
  ///   retrying, Marsik's diagnosis explains.
  Future<void> _startAntiDpiAuto({
    required int attempt,
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) async {
    final auto = AntiDpiAuto(context.dependencyFactory.sharedPreferences);
    final network = await AntiDpiAuto.networkKind();
    final fullOrder = auto.order(serverId: server.id, network: network);
    final order = ConnectFailures.isFrozen(server.id) ? fullOrder.take(1).toList() : fullOrder;

    for (final (index, mode) in order.indexed) {
      if (!mounted || attempt != _startAttempt) {
        return;
      }
      if (index > 0) {
        _autoSwitching = true;
        try {
          await widget.vpnRepository.stop();
          await _waitForState(VpnState.disconnected, attempt, const Duration(seconds: 3));
          // Not right after the previous ClientHello: handshakes milliseconds
          // apart are one of the freeze triggers.
          await Future<void>.delayed(AntiDpiAuto.switchPause);
        } finally {
          _autoSwitching = false;
        }
        if (!mounted || attempt != _startAttempt) {
          return;
        }
      }

      _autoAntiDpiMode = mode;
      final failure = _failures.stream.first.then<ConnectFailure?>((f) => f, onError: (_) => null);
      await widget.vpnRepository.start(
        server: server.copyWith(serverData: server.serverData.copyWith(antiDpiMode: mode)),
        routingProfile: routingProfile,
        excludedRoutes: excludedRoutes,
        logLevel: logLevel,
      );
      if (index == 0) {
        _watchStartBegins(attempt);
      }

      final outcome = await Future.any<Object?>([
        _waitForState(VpnState.connected, attempt, AntiDpiAuto.attemptTimeout),
        failure,
      ]);
      if (outcome == true) {
        await auto.remember(serverId: server.id, network: network, mode: mode);

        return;
      }
      if (outcome == ConnectFailure.helloNoAnswer || outcome == ConnectFailure.connect) {
        return; // the engine goes on with this technique
      }
    }

    if (!mounted || attempt != _startAttempt || order.length < fullOrder.length) {
      return;
    }
    await _stop();
    VpnScope.antiDpiAutoFailed.value = true;
  }

  /// Whether the VPN reaches [target] within [timeout], while [attempt] is
  /// still the current start.
  Future<bool> _waitForState(VpnState target, int attempt, Duration timeout) async {
    if (_stateNotifier.value == target) {
      return true;
    }

    final reached = Completer<bool>();
    void listener() {
      if (_stateNotifier.value == target && !reached.isCompleted) {
        reached.complete(true);
      }
    }

    _stateNotifier.addListener(listener);
    final timer = Timer(timeout, () {
      if (!reached.isCompleted) {
        reached.complete(false);
      }
    });
    try {
      return await reached.future && attempt == _startAttempt;
    } finally {
      timer.cancel();
      _stateNotifier.removeListener(listener);
    }
  }

  /// If the tunnel never even starts, the state just stays "disconnected":
  /// the system refused the VPN interface (another VPN or a root module
  /// holding one, seen on the S22 as "Cannot set address"), or the config
  /// was rejected - the engine reports that as DISCONNECTED (patch 0006).
  /// Flag it for Marsik (shown by ConnectionWatchdog), unless the user
  /// stopped/restarted meanwhile or the app isn't in front (e.g. the system
  /// VPN consent dialog is up).
  void _watchStartBegins(int attempt) {
    unawaited(
      Future<void>.delayed(_startGrace, () {
        final stillThisAttempt = attempt == _startAttempt;
        final appInFront = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
        if (mounted && stillThisAttempt && appInFront && !_leftDisconnectedSinceStart) {
          VpnScope.startDidNotBegin.value = true;
        }
      }),
    );
  }

  Future<void> _updateConfiguration({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) => widget.vpnRepository.updateConfiguration(
    // Anti-DPI "auto" keeps the technique that connected.
    server: switch (_autoAntiDpiMode) {
      final mode? when server.serverData.antiDpiMode == ServerData.antiDpiAuto => server.copyWith(
        serverData: server.serverData.copyWith(antiDpiMode: mode),
      ),
      _ => server,
    },
    routingProfile: routingProfile,
    excludedRoutes: excludedRoutes,
    logLevel: logLevel,
  );

  /// Stops the VPN and immediately changes the state to disconnected.
  Future<void> _stop() async {
    _startAttempt++;
    _lastStartKey = null;
    // On Android the stop always reaches the engine: the app can believe
    // the VPN is down while a stuck attempt is still running (Marsik's
    // "Disconnect"), and skipping the stop left that service in the
    // foreground, ignoring every later start. The engine does nothing when
    // no service is running (patch 0005).
    if (_stateNotifier.value == VpnState.disconnected && defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    await widget.vpnRepository.stop();
    _setVpnState(VpnState.disconnected);
  }

  /// Stops the VPN and waits for the native side to report disconnection.
  Future<void> _stopAndWaitUntilDisconnected() async {
    if (_stateNotifier.value == VpnState.disconnected) {
      return;
    }

    final disconnectedCompleter = Completer<void>();
    void disconnectedStateListener() {
      if (_stateNotifier.value == VpnState.disconnected && !disconnectedCompleter.isCompleted) {
        disconnectedCompleter.complete();
      }
    }

    _stateNotifier.addListener(disconnectedStateListener);
    try {
      await widget.vpnRepository.stop();
      await disconnectedCompleter.future;
    } finally {
      _stateNotifier.removeListener(disconnectedStateListener);
    }
  }

  void _setVpnState(VpnState state) {
    if (state != VpnState.disconnected) {
      _leftDisconnectedSinceStart = true;
    }
    if (state == VpnState.connected && _currentServerId != null) {
      ConnectFailures.clear(_currentServerId!);
    }
    final previousState = _stateNotifier.value;
    _vpnStateRevision++;
    _stateNotifier.value = state;

    if (previousState != state) {
      unawaited(_maybeNotifyStateChange(previousState: previousState, state: state));
    }
  }

  Future<void> _maybeNotifyStateChange({
    required VpnState previousState,
    required VpnState state,
  }) async {
    final isConnectedTransition = state == VpnState.connected && previousState != VpnState.connected;
    final isDisconnectedTransition = state == VpnState.disconnected && previousState != VpnState.disconnected;

    if (!isConnectedTransition && !isDisconnectedTransition) {
      return;
    }

    // Always: this only rebrands the vendor's mandatory foreground-service
    // notification, it never adds a second one.
    if (isConnectedTransition) {
      await _connectionNotifier.notifyConnected(
        serverName: _lastServerName ?? await _selectedServerName() ?? 'CatTunnel',
        disguised: _disguised,
      );

      return;
    }

    if (!_autoSwitching && await _connectionNotificationsSettingsRepository.isEnabled()) {
      await _connectionNotifier.notifyDisconnected(disguised: _disguised);
    }
  }

  bool get _disguised => SecuritySettings(context.dependencyFactory.sharedPreferences).disguise;

  /// For connections this scope didn't start itself (QS tile reconnect,
  /// VPN already up when the app launched) - the selected server is the one
  /// the vendor service persisted and is running.
  Future<String?> _selectedServerName() async {
    final servers = await context.repositoryFactory.serverRepository.getAllServers();

    return servers.firstWhereOrNull((server) => server.serverData.selected)?.serverData.name;
  }

  Future<void> _listenToVpnStates() async {
    final stream = await widget.vpnRepository.listenToStates();
    if (!mounted) {
      return;
    }

    _vpnStreamSub = stream.listen(_setVpnState);
  }

  void _onLogCollected(VpnLog log) {
    final limit = _logLimit;
    var trimmedList = _logsNotifier.value;
    if (_logsNotifier.value.length >= limit) {
      trimmedList = trimmedList.sublist(_logsNotifier.value.length - limit);
    }

    _logsNotifier.value = [...trimmedList, log];
  }

  Future<void> _listenToLogs() async {
    final stream = await widget.vpnRepository.listenToLogs();
    if (!mounted) {
      return;
    }

    _logStreamSub = stream.listen(_onLogCollected);
  }

  Future<void> _refreshState() async {
    final revisionBeforeRequest = _vpnStateRevision;
    final state = await widget.vpnRepository.requestState();
    if (!mounted || revisionBeforeRequest != _vpnStateRevision) {
      return;
    }

    _setVpnState(state);
  }

  void _onAppResumed() => unawaited(_refreshState());

  Future<AppExitResponse> _onExitRequested() async {
    if (defaultTargetPlatform != TargetPlatform.macOS) {
      return AppExitResponse.exit;
    }
    final appWindowController = widget.appWindowController;
    if (appWindowController == null) {
      throw StateError('AppWindowController must be provided on macOS');
    }

    final shouldShowExitDialog = switch (_stateNotifier.value) {
      VpnState.connected || VpnState.connecting => true,
      VpnState.disconnected ||
      VpnState.waitingForRecovery ||
      VpnState.recovering ||
      VpnState.waitingForNetwork => false,
    };

    if (shouldShowExitDialog) {
      final localization = Localization.ln;
      final result = await MacosExitDialog.show(
        title: localization.exitDialogTitle,
        message: localization.exitDialogDescription,
        quitButtonText: localization.quit,
        dontQuitButtonText: localization.dontQuit,
      );
      if (!mounted || result != MacosExitDialogResult.quit) {
        return AppExitResponse.cancel;
      }
    }

    await _stopAndWaitUntilDisconnected();
    await appWindowController.setPreventClose(false);

    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    _appLifecycleListener.dispose();
    _logStreamSub?.cancel().ignore();
    _vpnStreamSub?.cancel().ignore();
    _failureSub?.cancel().ignore();
    _failures.close().ignore();
    _stateNotifier.dispose();
    _logsNotifier.dispose();
    super.dispose();
  }
}

class _InheritedVpnScope extends InheritedModel<VpnAspect> implements VpnController, LogController {
  final AsyncCallback _onStop;
  final AsyncCallback _onDeleteConfiguration;
  final UpdateVpnCallback _onStart;
  final UpdateVpnCallback _updateConfiguration;

  @override
  final List<VpnLog> logs;

  @override
  final VpnState state;

  const _InheritedVpnScope({
    required UpdateVpnCallback onStart,
    required UpdateVpnCallback onUpdate,
    required AsyncCallback onStop,
    required AsyncCallback onDeleteConfiguration,
    required this.state,
    required this.logs,
    required super.child,
  }) : _onStart = onStart,
       _onStop = onStop,
       _onDeleteConfiguration = onDeleteConfiguration,
       _updateConfiguration = onUpdate;

  @override
  Future<void> start({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) => _onStart(
    server: server,
    routingProfile: routingProfile,
    excludedRoutes: excludedRoutes,
    logLevel: logLevel,
  );

  @override
  Future<void> updateConfiguration({
    required Server server,
    required RoutingProfile routingProfile,
    required List<String> excludedRoutes,
    required VpnConfigurationLogLevel logLevel,
  }) => _updateConfiguration(
    server: server,
    routingProfile: routingProfile,
    excludedRoutes: excludedRoutes,
    logLevel: logLevel,
  );

  @override
  Future<void> stop() => _onStop();

  @override
  bool updateShouldNotify(covariant _InheritedVpnScope oldWidget) =>
      _shouldNotifyLogController(oldWidget) || _shouldNotifyVpnController(oldWidget);

  @override
  bool updateShouldNotifyDependent(covariant _InheritedVpnScope oldWidget, Set<VpnAspect> dependencies) {
    if (dependencies.contains(VpnAspect.vpn) && _shouldNotifyVpnController(oldWidget)) {
      return true;
    }
    if (dependencies.contains(VpnAspect.logs) && _shouldNotifyLogController(oldWidget)) {
      return true;
    }

    return false;
  }

  @override
  Future<void> deleteConfiguration() => _onDeleteConfiguration();

  bool _shouldNotifyVpnController(_InheritedVpnScope oldWidget) => oldWidget.state != state;

  bool _shouldNotifyLogController(_InheritedVpnScope oldWidget) => !listEquals(oldWidget.logs, logs);
}
