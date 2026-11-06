import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/router/deeplink/deep_link_source.dart';
import 'package:trusttunnel/data/repository/deep_link_repository.dart';
import 'package:trusttunnel/feature/app/app_keys.dart';
import 'package:trusttunnel/feature/deep_link/deep_link_scope.dart';

class _Source extends DeepLinkSource {
  final initial = Completer<Uri?>();
  Uri? _link;
  @override
  Uri? get link => _link;
  @override
  Future<Uri?> getInitialLink() => initial.future;
  void emit(Uri uri) {
    _link = uri;
    notifyListeners();
  }
}

class _Repository implements DeepLinkRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _raw = 'cattunnel://subscription?code=secret-code&base=https%3A%2F%2Fexample.org';

Future<void> _mount(WidgetTester tester, _Source source, Future<void> Function(String, String) exchange) async {
  await tester.pumpWidget(
    DeepLinkScope(
      source: source,
      repository: _Repository(),
      exchangeCode: exchange,
      child: MaterialApp(
        scaffoldMessengerKey: appMessengerKey,
        localizationsDelegates: Localization.localizationDelegates,
        supportedLocales: Localization.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: Text('home')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('cold link is taken from initial result above MaterialApp', (tester) async {
    final source = _Source();
    var calls = 0;
    await _mount(tester, source, (code, base) async {
      calls++;
      expectSync(code, 'secret-code');
      expectSync(base, 'https://example.org');
    });
    source.initial.complete(Uri.parse(_raw));
    await tester.pumpAndSettle();
    expectSync(calls, 1);
    expectSync(find.text('Subscription added'), findsOneWidget);
    expectSync(tester.takeException(), isNull);
  });
  testWidgets('warm link error is visible and never exposes server text', (tester) async {
    final source = _Source()..initial.complete(null);
    await _mount(tester, source, (_, _) async => throw StateError('secret-code https://private.example'));
    source.emit(Uri.parse(_raw));
    await tester.pumpAndSettle();
    expectSync(find.text('The link did not work. Get a new link and try again.'), findsOneWidget);
    expectSync(find.textContaining('private.example'), findsNothing);
    expectSync(tester.takeException(), isNull);
  });
  testWidgets('initial result and stream delivery exchange the code only once', (tester) async {
    final source = _Source();
    final exchange = Completer<void>();
    var calls = 0;
    await _mount(tester, source, (_, _) {
      calls++;
      return exchange.future;
    });
    source.emit(Uri.parse(_raw));
    source.initial.complete(Uri.parse(_raw));
    await tester.pump();
    expectSync(calls, 1);
    exchange.complete();
    await tester.pumpAndSettle();
    expectSync(find.text('Subscription added'), findsOneWidget);
  });
  for (final cold in [true, false]) {
    testWidgets('signed issue file uses the exchange on ${cold ? "cold" : "warm"} start', (tester) async {
      final algorithm = Ed25519();
      final pair = await algorithm.newKeyPair();
      final public = await pair.extractPublicKey();
      final payload = utf8.encode(
        jsonEncode({
          'code': 'file-code',
          'base': ['https://example.org'],
        }),
      );
      final signature = await algorithm.sign(payload, keyPair: pair);
      final raw = jsonEncode({
        'payload': base64.encode(payload),
        'sig': base64.encode(signature.bytes),
        'key': base64.encode(public.bytes),
      });
      const channel = MethodChannel('cattunnel/issue_file');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        expectSync(call.method, 'read');
        return raw;
      });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
      );
      final source = _Source();
      var calls = 0;
      await _mount(tester, source, (code, base) async {
        calls++;
        expectSync(code, 'file-code');
      });
      final uri = Uri.parse('content://provider/file.cattunnel');
      if (cold) {
        source.initial.complete(uri);
      } else {
        source.initial.complete(null);
        source.emit(uri);
      }
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pumpAndSettle();
      expectSync(calls, 1);
      expectSync(find.text('Subscription added'), findsOneWidget);
    });
  }
  testWidgets('bad issue file displays an error and does not exchange', (tester) async {
    const channel = MethodChannel('cattunnel/issue_file');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (_) async => '{}',
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    final source = _Source()..initial.complete(null);
    var calls = 0;
    await _mount(tester, source, (_, _) async {
      calls++;
    });
    source.emit(Uri.parse('content://provider/file.cattunnel'));
    await tester.pumpAndSettle();
    expectSync(calls, 0);
    expectSync(find.text('The link did not work. Get a new link and try again.'), findsOneWidget);
  });
  testWidgets('the message is dropped when the messenger never attaches', (tester) async {
    final source = _Source()..initial.complete(null);
    // No scaffoldMessengerKey: the global messenger stays unattached.
    await tester.pumpWidget(
      DeepLinkScope(
        source: source,
        repository: _Repository(),
        exchangeCode: (_, _) async => throw StateError('x'),
        child: const MaterialApp(home: Scaffold(body: Text('home'))),
      ),
    );
    await tester.pump();
    source.emit(Uri.parse(_raw));
    for (var i = 0; i < 60; i++) {
      await tester.pump();
    }
    expectSync(find.text('The link did not work. Get a new link and try again.'), findsNothing);
    expectSync(find.text('Subscription added'), findsNothing);
    expectSync(tester.takeException(), isNull);
  });
}
