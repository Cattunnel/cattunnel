import 'package:flutter/material.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/settings/app_logging/widgets/app_logging_screen.dart';
import 'package:trusttunnel/feature/settings/query_log/widgets/query_log_screen.dart';
import 'package:trusttunnel/feature/settings/settings/widgets/download_app_logs_tile.dart';
import 'package:trusttunnel/feature/support/problem_report.dart';
import 'package:trusttunnel/widgets/common/custom_arrow_list_tile.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// Groups every log-related settings entry (connection log, app logging,
/// export) behind a single "Logs" item instead of listing them separately.
class LogsScreen extends StatelessWidget {
  const LogsScreen({super.key});

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: ScaffoldMessenger(
      child: Scaffold(
        appBar: CustomAppBar(
          title: context.ln.logs,
          centerTitle: true,
          leadingIconType: AppBarLeadingIconType.back,
        ),
        body: ListView(
          children: [
            CustomArrowListTile(
              title: context.ln.connectionLog,
              onTap: () => _pushQueryLogScreen(context),
            ),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.appLogging,
              onTap: () => _pushAppLoggingScreen(context),
            ),
            const Divider(),
            const DownloadAppLogsTile(),
            const Divider(),
            CustomArrowListTile(
              title: context.ln.reportProblem,
              onTap: () => ProblemReport.share(context),
            ),
          ],
        ),
      ),
    ),
  );

  void _pushQueryLogScreen(BuildContext context) => context.push(
    const QueryLogScreen(),
  );

  void _pushAppLoggingScreen(BuildContext context) => context.push(
    const AppLoggingScreen(),
  );
}
