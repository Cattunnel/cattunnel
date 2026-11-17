import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/app_theme.dart';
import 'package:trusttunnel/common/theme/theme_palette.dart';
import 'package:trusttunnel/data/model/subscription_data.dart';
import 'package:trusttunnel/data/model/subscription_poll.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_card.dart';
import 'package:trusttunnel/feature/subscriptions/widgets/subscription_poll_dialog.dart';

const _subscription = SubscriptionData(name: 'Test', url: 'https://www.example.org/api/ct/token', id: 'sub-1');

SubscriptionPoll _poll({required bool succeeded, required List<SubscriptionPollAttempt> attempts}) => SubscriptionPoll(
  subscriptionId: 'sub-1',
  subscriptionName: 'Test',
  startedAt: DateTime(2026, 11, 17, 22, 31),
  finishedAt: DateTime(2026, 11, 17, 22, 31, 2),
  succeeded: succeeded,
  attempts: attempts,
);

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  supportedLocales: Localization.supportedLocales,
  localizationsDelegates: Localization.localizationDelegates,
  theme: AppTheme(ThemePalette.light).data,
  home: Scaffold(body: child),
);

Widget _card({required SubscriptionPoll? poll, VoidCallback? onShowPoll, bool refreshing = false}) => _app(
  SubscriptionCard(
    subscription: _subscription,
    refreshing: refreshing,
    poll: poll,
    onRefresh: () {},
    onEdit: () {},
    onShare: () {},
    onDelete: () {},
    onShowPoll: onShowPoll ?? () {},
  ),
);

void main() {
  testWidgets('a successful poll shows the mirror and the time under the subscription', (tester) async {
    await tester.pumpWidget(
      _card(
        poll: _poll(
          succeeded: true,
          attempts: const [
            SubscriptionPollAttempt(
              host: 'old.example',
              durationMs: 2100,
              outcome: SubscriptionPollOutcome.timeout,
            ),
            SubscriptionPollAttempt(
              host: 'www.example.org',
              durationMs: 420,
              outcome: SubscriptionPollOutcome.ok,
              statusCode: 200,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Обновлено 22:31 через www.example.org за 420 мс'), findsOneWidget);
  });

  testWidgets('a failed poll says how many mirrors failed and the line is tappable', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _card(
        onShowPoll: () => tapped = true,
        poll: _poll(
          succeeded: false,
          attempts: const [
            SubscriptionPollAttempt(
              host: 'old.example',
              durationMs: 2100,
              outcome: SubscriptionPollOutcome.timeout,
            ),
            SubscriptionPollAttempt(
              host: 'www.example.org',
              durationMs: 300,
              outcome: SubscriptionPollOutcome.http,
              statusCode: 404,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Не удалось: 2 зеркала'), findsOneWidget);

    await tester.tap(find.text('Не удалось: 2 зеркала'));
    await tester.pumpAndSettle();
    expect(tapped, isTrue);
  });

  testWidgets('the dialog lists every attempt with its outcome and time', (tester) async {
    await tester.pumpWidget(
      _app(
        SubscriptionPollDialog(
          poll: _poll(
            succeeded: false,
            attempts: const [
              SubscriptionPollAttempt(
                host: 'old.example',
                durationMs: 2100,
                outcome: SubscriptionPollOutcome.timeout,
              ),
              SubscriptionPollAttempt(
                host: 'www.example.org',
                durationMs: 300,
                outcome: SubscriptionPollOutcome.http,
                statusCode: 404,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Опрос подписки'), findsOneWidget);
    expect(find.text('old.example'), findsOneWidget);
    expect(find.text('Таймаут · 2,1 с'), findsOneWidget);
    expect(find.text('www.example.org'), findsOneWidget);
    expect(find.text('HTTP 404 · 300 мс'), findsOneWidget);
  });

  testWidgets('while the refresh runs the line names the mirror being asked', (tester) async {
    await tester.pumpWidget(
      _card(
        refreshing: true,
        poll: SubscriptionPoll(
          subscriptionId: 'sub-1',
          subscriptionName: 'Test',
          startedAt: DateTime(2026, 11, 17, 22, 31),
          attempts: [],
          currentHost: 'www.example.org',
        ),
      ),
    );

    expect(find.text('Спрашиваем www.example.org…'), findsOneWidget);
  });
}
