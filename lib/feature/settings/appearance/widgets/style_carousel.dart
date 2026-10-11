import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trusttunnel/common/assets/assets_images.dart';
import 'package:trusttunnel/common/extensions/context_extensions.dart';
import 'package:trusttunnel/common/localization/localization.dart';
import 'package:trusttunnel/common/theme/appearance_preferences.dart';
import 'package:trusttunnel/widgets/y2k/marsik_image.dart';

/// The styles side by side in a horizontal carousel: swipe (or tap a
/// neighbour peeking at the edge); the one in the middle is the pick. Dots
/// under it show where you are.
class StyleCarousel extends StatefulWidget {
  final AppStyle initial;
  final ValueChanged<AppStyle> onChanged;

  const StyleCarousel({super.key, required this.initial, required this.onChanged});

  @override
  State<StyleCarousel> createState() => _StyleCarouselState();
}

class _StyleCarouselState extends State<StyleCarousel> {
  static const _order = [AppStyle.aero, AppStyle.y2k, AppStyle.cozy, AppStyle.minimal];

  late int _page = math.max(0, _order.indexOf(widget.initial));
  late final PageController _controller = PageController(viewportFraction: 0.78, initialPage: _page);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) => _controller.animateToPage(
    page,
    duration: const Duration(milliseconds: 320),
    curve: Curves.easeOutCubic,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final names = {
      AppStyle.aero: (context.ln.appearanceStyleAero, context.ln.appearanceStyleAeroDescription, const _AeroPreview()),
      AppStyle.y2k: (context.ln.appearanceStyleY2k, context.ln.appearanceStyleY2kDescription, const _Y2kPreview()),
      AppStyle.cozy: (context.ln.appearanceStyleCozy, context.ln.appearanceStyleCozyDescription, const _CozyPreview()),
      AppStyle.minimal: (
        context.ln.appearanceStyleMinimal,
        context.ln.appearanceStyleMinimalDescription,
        const _MinimalPreview(),
      ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 300 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.4),
          child: PageView.builder(
            controller: _controller,
            itemCount: _order.length,
            onPageChanged: (page) {
              setState(() => _page = page);
              widget.onChanged(_order[page]);
            },
            itemBuilder: (context, i) {
              final (title, description, preview) = names[_order[i]]!;

              return AnimatedScale(
                duration: const Duration(milliseconds: 220),
                scale: i == _page ? 1 : 0.9,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _StyleCard(
                    title: title,
                    description: description,
                    selected: i == _page,
                    preview: preview,
                    onTap: () => _go(i),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Semantics(
          label: '${_page + 1} / ${_order.length}',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _order.length; i++)
                GestureDetector(
                  onTap: () => _go(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? colors.accent : colors.neutralLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StyleCard extends StatelessWidget {
  final String title;
  final String description;
  final bool selected;
  final Widget preview;
  final VoidCallback onTap;

  const _StyleCard({
    required this.title,
    required this.description,
    required this.selected,
    required this.preview,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Semantics(
      selected: selected,
      button: true,
      label: title,
      child: Material(
        color: selected ? colors.blend : colors.backgroundAdditional,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: selected ? colors.accent : colors.backgroundSystem, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: 150, child: preview),
                const SizedBox(height: 10),
                Text(title, style: context.textTheme.titleMedium, textAlign: TextAlign.center, maxLines: 1),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.fade,
                    style: context.textTheme.bodySmall?.copyWith(color: colors.neutralDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tiny sketch of the «Уютный» main screen: the round button with Marsik
/// and a server card under it.
class _CozyPreview extends StatelessWidget {
  const _CozyPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 66,
          height: 66,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.background,
            border: Border.all(color: colors.accent, width: 2),
          ),
          child: const MarsikImage(AssetImages.catSleeping),
        ),
        const SizedBox(height: 10),
        Container(
          height: 18,
          decoration: BoxDecoration(color: colors.background, borderRadius: BorderRadius.circular(8)),
        ),
      ],
    );
  }
}

/// Tiny sketch of the «Минимализм» main screen: a list of servers with
/// round power buttons.
class _MinimalPreview extends StatelessWidget {
  const _MinimalPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(color: colors.neutralLight, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colors.neutralLight),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tiny sketch of «Аэро»: sky over a green hill, a glass bubble with Marsik.
class _AeroPreview extends StatelessWidget {
  const _AeroPreview();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1F7FF0), Color(0xFFA9DCFF), Color(0xFF84D634), Color(0xFF2E8C1C)],
          stops: [0, 0.55, 0.62, 1],
        ),
      ),
      child: Center(
        child: Container(
          width: 66,
          height: 66,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
            gradient: const RadialGradient(
              center: Alignment(0, -0.3),
              colors: [Color(0xCCFFFFFF), Color(0x8096CDFA), Color(0xBF3C78C8)],
            ),
            boxShadow: const [BoxShadow(color: Color(0x80A6EC2C), blurRadius: 12)],
          ),
          child: Image.asset(AssetImages.catShield),
        ),
      ),
    ),
  );
}

/// Tiny sketch of «Y2K»: deep navy, a glowing ring around Marsik.
class _Y2kPreview extends StatelessWidget {
  const _Y2kPreview();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(colors: [Color(0xFF0B2A5C), Color(0xFF02050D)]),
      ),
      child: Center(
        child: Container(
          width: 66,
          height: 66,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF6FD3FF), width: 2),
            boxShadow: const [BoxShadow(color: Color(0xAA2F8CFF), blurRadius: 14)],
          ),
          child: Image.asset(AssetImages.catShield),
        ),
      ),
    ),
  );
}
