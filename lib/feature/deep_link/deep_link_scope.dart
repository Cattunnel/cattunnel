import 'dart:async';

import 'package:adguard_logger/adguard_logger.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/router/deeplink/deep_link_source.dart';
import 'package:trusttunnel/common/utils/device_issue_file.dart';
import 'package:trusttunnel/common/utils/subscription_share_link.dart';
import 'package:trusttunnel/data/model/server_data.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/feature/app/app_keys.dart';
import 'package:trusttunnel/feature/deep_link/controller/deep_link_controller.dart';

/// {@template deep_link_scope}
/// DeepLinkScope widget.
/// {@endtemplate}
class DeepLinkScope extends StatefulWidget {
  const DeepLinkScope({
    required this.child,
    super.key,
    this.source,
    this.repository,
    this.exchangeCode,
  });

  /// The widget below this widget in the tree.
  final Widget child;
  final DeepLinkSource? source;
  final DeepLinkRepository? repository;
  final Future<void> Function(String code, String base)? exchangeCode;

  @override
  State<DeepLinkScope> createState() => _DeepLinkScopeState();

  static _InheritedDeepLinkScope? maybeOf(BuildContext context, {bool listen = true}) => listen
      ? context.dependOnInheritedWidgetOfExactType<_InheritedDeepLinkScope>()
      : context.getElementForInheritedWidgetOfExactType<_InheritedDeepLinkScope>()?.widget as _InheritedDeepLinkScope?;

  static _InheritedDeepLinkScope of(BuildContext context, {bool listen = true}) =>
      maybeOf(context, listen: listen) ?? _notFoundInheritedWidgetOfExactType();

  static Never _notFoundInheritedWidgetOfExactType() => throw ArgumentError(
    'Out of scope, not found inherited widget '
        'a _InheritedDeepLinkScope of the exact type',
    'out_of_scope',
  );
}

/// State for widget DeepLinkScope.
class _DeepLinkScopeState extends State<DeepLinkScope> {
  static const int _maxMessageFrames = 50;

  late final DeepLinkSource _deepLinkSource;
  late final DeepLinkController _controller;
  Uri? _lastStreamLink;
  Uri? _initialLink;
  final Set<String> _exchanging = {};
  final ValueNotifier<ServerData?> _serverData = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    _deepLinkSource = widget.source ?? AppLinksSource(AppLinks());
    _controller = DeepLinkController(
      repository: widget.repository ?? context.repositoryFactory.deepLinkRepository,
    );
    _deepLinkSource.addListener(_onDeepLinkReceived);
    unawaited(_readInitialLink());
    _controller.addListener(_updateServerData);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _serverData,
    builder: (_, updatedData, child) => _InheritedDeepLinkScope(
      deepLinkData: updatedData,
      child: child!,
    ),
    child: widget.child,
  );

  void _updateServerData() {
    if (_serverData.value != _controller.state.parsedData) {
      _serverData.value = _controller.state.parsedData;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _serverData.value = null;
      });
    }
  }

  Future<void> _readInitialLink() async {
    try {
      final link = await _deepLinkSource.getInitialLink();
      _initialLink = link;
      if (mounted && link != null && link != _lastStreamLink) await _handleLink(link);
    } on Object catch (e, st) {
      _linkError(e, st);
    }
  }

  void _onDeepLinkReceived() {
    final link = _deepLinkSource.link;
    _lastStreamLink = link;
    if (link == _initialLink) return;
    if (link != null) unawaited(_handleLink(link));
  }

  Future<void> _handleLink(Uri link) async {
    try {
      if (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS &&
          widget.source == null) {
        await context.dependencyFactory.appWindowController.showMainWindow();
      }
      if (!mounted) return;
      if (link.scheme == 'content' || link.scheme == 'file') {
        final raw = await const MethodChannel('cattunnel/issue_file').invokeMethod<String>(
          'read',
          link.toString(),
        );
        final issue = raw == null ? null : await DeviceIssueFile.tryParse(raw);
        if (issue == null) throw const FormatException('Invalid issue file');
        final bases = issue.base
            .where(
              (base) =>
                  SubscriptionShareLink.tryDecodeCode(
                    Uri(
                      scheme: 'cattunnel',
                      host: 'subscription',
                      queryParameters: {
                        'code': issue.code,
                        'base': base,
                      },
                    ).toString(),
                  ) !=
                  null,
            )
            .toList();
        if (bases.isEmpty) throw const FormatException('Missing HTTPS base');
        await _exchangeSubscriptionCode(issue.code, bases.first);
        return;
      }
      final codeLink = SubscriptionShareLink.tryDecodeCode(link.toString());
      if (codeLink != null) {
        await _exchangeSubscriptionCode(codeLink.code, codeLink.base);
      } else if (link.scheme == 'cattunnel' && link.queryParameters.containsKey('code')) {
        throw const FormatException('Invalid subscription code link');
      } else {
        _controller.onDeepLinkReceived(link);
      }
    } on Object catch (e, st) {
      _linkError(e, st);
    }
  }

  Future<void> _exchangeSubscriptionCode(String code, String base) async {
    final token = '$base\n$code';
    if (!_exchanging.add(token)) return;
    try {
      if (widget.exchangeCode case final exchange?) {
        await exchange(code, base);
      } else {
        final syncService = context.dependencyFactory.subscriptionSyncService;
        final repository = context.repositoryFactory.subscriptionRepository;
        final subscription = await syncService.exchangeCode(code, base);
        await repository.addSubscription(request: subscription);
      }
      _message(true);
    } on Object catch (e, st) {
      _linkError(e, st);
    } finally {
      _exchanging.remove(token);
    }
  }

  void _linkError(Object error, StackTrace stack) {
    // Codes, subscription URLs and server error bodies never enter the log/UI.
    logger.logError('Subscription link failed (${error.runtimeType})', additionalTags: ['deep_link']);
    _message(false);
  }

  void _message(bool success, {int attempts = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = appMessengerKey.currentState;
      if (messenger == null) {
        // The messenger never showed up: give it a few frames, then discard,
        // so the retry loop cannot run forever.
        if (attempts >= _maxMessageFrames) {
          logger.logInfo(
            'Subscription link message dropped after $attempts frames (passed: $success)',
            additionalTags: ['deep_link'],
          );
          return;
        }
        _message(success, attempts: attempts + 1);
        return;
      }
      final ln = Localization.of(messenger.context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            success ? ln.subscriptionLinkAdded : ln.subscriptionLinkFailed,
          ),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _serverData.dispose();
    _controller.dispose();
    _deepLinkSource.dispose();
    super.dispose();
  }
}

class _InheritedDeepLinkScope extends InheritedWidget {
  const _InheritedDeepLinkScope({
    required this.deepLinkData,
    required super.child,
  });

  final ServerData? deepLinkData;

  @override
  bool updateShouldNotify(covariant _InheritedDeepLinkScope oldWidget) => deepLinkData != oldWidget.deepLinkData;
}
