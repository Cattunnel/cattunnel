import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/widgets/custom_app_bar.dart';
import 'package:trusttunnel/widgets/scaffold_wrapper.dart';

/// Settings -> Help: a bundled page (`assets/readme/<name>.<ru|en>.md`) in the
/// UI language - the README, or how the connection works ("CONNECTION").
///
/// Rendered by a deliberately tiny Markdown subset - `#`/`##`/`###`
/// headings, `-` bullets, `1.` numbered items, `**bold**` and `` `code` ``
/// - to avoid a dependency for one static page. Keep the README within it.
class ReadmeScreen extends StatelessWidget {
  /// The file name without the language suffix.
  final String name;

  /// The app bar title; the README's by default.
  final String? title;

  const ReadmeScreen({super.key, this.name = 'README', this.title});

  String _assetFor(Locale locale) => 'assets/readme/$name.${locale.languageCode == 'ru' ? 'ru' : 'en'}.md';

  @override
  Widget build(BuildContext context) => ScaffoldWrapper(
    child: Scaffold(
      appBar: CustomAppBar(
        title: title ?? context.ln.readme,
        leadingIconType: AppBarLeadingIconType.back,
        onBackPressed: () => Navigator.of(context).maybePop(),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(_assetFor(Localizations.localeOf(context))),
        builder: (context, snapshot) {
          final text = snapshot.data;
          if (text == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SelectionArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: _MarkdownLite.render(context, text),
            ),
          );
        },
      ),
    ),
  );
}

abstract final class _MarkdownLite {
  static final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)-\s+(.*)$');
  static final _numbered = RegExp(r'^(\d+)\.\s+(.*)$');
  static final _inline = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`');

  static List<Widget> render(BuildContext context, String markdown) {
    final theme = context.textTheme;
    final widgets = <Widget>[];

    for (final line in markdown.split('\n')) {
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final style = switch (level) {
          1 => theme.headlineSmall,
          2 => theme.titleLarge,
          _ => theme.titleMedium,
        };
        widgets.add(
          Padding(
            padding: EdgeInsets.only(top: level == 1 ? 8 : 16, bottom: 4),
            child: Text.rich(_spans(context, heading.group(2)!, style)),
          ),
        );
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      final numbered = bullet == null ? _numbered.firstMatch(line) : null;
      if (bullet != null || numbered != null) {
        final indent = bullet != null ? bullet.group(1)!.length * 8.0 : 0.0;
        final marker = bullet != null ? '•' : '${numbered!.group(1)}.';
        final content = bullet != null ? bullet.group(2)! : numbered!.group(2)!;
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 22, child: Text(marker, style: theme.bodyMedium)),
                Expanded(child: Text.rich(_spans(context, content, theme.bodyMedium))),
              ],
            ),
          ),
        );
        continue;
      }

      widgets.add(Text.rich(_spans(context, line, theme.bodyMedium)));
    }

    return widgets;
  }

  static TextSpan _spans(BuildContext context, String text, TextStyle? base) {
    final spans = <InlineSpan>[];
    var offset = 0;

    for (final match in _inline.allMatches(text)) {
      if (match.start > offset) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
      }

      final bold = match.group(1);
      spans.add(
        bold != null
            ? TextSpan(
                text: bold,
                style: const TextStyle(fontWeight: FontWeight.w700),
              )
            : TextSpan(
                text: match.group(2),
                style: TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor: context.colors.accent.withValues(alpha: 0.08),
                ),
              ),
      );
      offset = match.end;
    }

    if (offset < text.length) {
      spans.add(TextSpan(text: text.substring(offset)));
    }

    return TextSpan(style: base, children: spans);
  }
}
