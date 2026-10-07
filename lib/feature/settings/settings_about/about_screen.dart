import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/feature/onboarding/widgets/intro_film.dart';
import 'package:trusttunnel/feature/updates/domain/update_service.dart';
import 'package:trusttunnel/feature/updates/widgets/update_dialogs.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/default_page.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';
import 'package:url_launcher/url_launcher.dart';

/// Release flow: the plain build (version "1.3.5") is scanned on VirusTotal
/// first; the build people install is then made from the same code as
/// "1.3.5/S-Signed" ("signed after the VirusTotal check") with the report of
/// its plain twin passed in at build time:
///   `--dart-define=VT_REPORT_URL=https://www.virustotal.com/gui/file/SHA256`
///   `--dart-define=VT_DETECTIONS=N`
/// A link can't point at the very file containing it (the link changes the
/// hash), hence the twin. Without these defines (the scanned build) the
/// badge is hidden.
const _virusTotalReportUrl = String.fromEnvironment('VT_REPORT_URL');
const _virusTotalDetections = String.fromEnvironment('VT_DETECTIONS', defaultValue: '?');

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(
        title: context.ln.about,
      ),
      body: FutureBuilder<String>(
        future: _getPackageVersion(),
        builder: (context, snapshot) => Column(
          children: [
            Expanded(
              child: DefaultPage.responsive(
                title: 'CatTunnel',
                descriptionText: [
                  if (snapshot.data != null) snapshot.data!,
                  context.ln.aboutAttribution,
                ].join('\n'),
                imagePath: AssetImages.catShield,
                buttonText: context.ln.viewLicenses,
                onButtonPressed: () => _showLicenses(context),
              ),
            ),
            if (IntroFilm.supported)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.movie_outlined),
                  label: Text(context.ln.introFilmWatch),
                  onPressed: () => IntroFilm.show(context),
                ),
              ),
            if (UpdateService.enabled)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextButton.icon(
                  icon: const Icon(Icons.system_update),
                  label: Text(context.ln.updateCheck),
                  onPressed: () => checkForUpdatesManually(context),
                ),
              ),
            if (_virusTotalReportUrl.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _VirusTotalBadge(),
              ),
          ],
        ),
      ),
    ),
  );

  Future<String> _getPackageVersion() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    // Not lowercased: "1.3.5/S-Signed" should read as written.
    return 'v${packageInfo.version}';
  }

  void _showLicenses(BuildContext context) => showLicensePage(
    context: context,
    applicationName: 'CatTunnel',
  );
}

class _VirusTotalBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: () => launchUrl(Uri.parse(_virusTotalReportUrl), mode: LaunchMode.externalApplication),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_user, size: 18, color: context.colors.accent),
              const SizedBox(width: 8),
              Text(
                context.ln.virusTotalBadge(_virusTotalDetections),
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colors.accent,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            context.ln.virusTotalBadgeCaveat,
            textAlign: TextAlign.center,
            style: context.textTheme.bodySmall?.copyWith(color: context.colors.neutralDark),
          ),
        ],
      ),
    ),
  );
}
