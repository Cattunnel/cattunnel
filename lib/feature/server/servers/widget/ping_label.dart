import 'package:flutter/widgets.dart';
import 'package:trusttunnel/common/localization/localization.dart';

/// How long ago a ping was measured: "just now", "7 min ago", "3 h ago".
String pingAgeLabel(BuildContext context, DateTime measuredAt, {DateTime? now}) {
  final age = (now ?? DateTime.now()).difference(measuredAt);
  if (age.inMinutes < 1) return context.ln.pingAgeNow;
  if (age.inHours < 1) return context.ln.pingAgeMinutes(age.inMinutes);
  if (age.inDays < 1) return context.ln.pingAgeHours(age.inHours);

  return context.ln.pingAgeDays(age.inDays);
}
