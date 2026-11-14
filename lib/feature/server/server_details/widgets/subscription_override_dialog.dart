import 'dart:math';
import 'package:flutter/material.dart';
import 'package:trusttunnel/common/localization/localization.dart';

abstract final class SubscriptionChallenge {
  static const answers = ['synack', 'ack', '53', '443', '404', 'udp', 'tcp', 'clienthello'];
  static String normalize(String text) => text.toLowerCase().replaceAll(RegExp(r'[\s-]'), '');
  static bool accepts(int question, String answer) => normalize(answer) == answers[question];
  static int next(int previous, Random random) {
    final pick = random.nextInt(answers.length - 1);
    return pick >= previous ? pick + 1 : pick;
  }
}

class SubscriptionOverrideDialog extends StatefulWidget {
  const SubscriptionOverrideDialog({super.key});
  @override
  State<SubscriptionOverrideDialog> createState() => _SubscriptionOverrideDialogState();
}

class _SubscriptionOverrideDialogState extends State<SubscriptionOverrideDialog> {
  final _random = Random();
  final _answer = TextEditingController();
  late int _question = _random.nextInt(8);
  bool _wrong = false;
  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _submit() {
    if (SubscriptionChallenge.accepts(_question, _answer.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _wrong = true;
        _question = SubscriptionChallenge.next(_question, _random);
        _answer.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ln = Localization.ln;
    final questions = [
      ln.subscriptionQuestion0,
      ln.subscriptionQuestion1,
      ln.subscriptionQuestion2,
      ln.subscriptionQuestion3,
      ln.subscriptionQuestion4,
      ln.subscriptionQuestion5,
      ln.subscriptionQuestion6,
      ln.subscriptionQuestion7,
    ];
    return AlertDialog(
      title: Text(ln.subscriptionOverride),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(questions[_question]),
          TextField(
            controller: _answer,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(errorText: _wrong ? ln.subscriptionChallengeWrong : null),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(ln.cancel)),
        TextButton(onPressed: _submit, child: Text(ln.subscriptionOverride)),
      ],
    );
  }
}
