import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_typography.dart';
import '../../app/theme/tokens.dart';

/// Softly bordered, rounded surface (flat, no shadow). The default container for grouped content.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Space.lg),
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Corners.card),
      side: BorderSide(color: c.borderSoft, width: Sizes.cardBorderWidth),
    );
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) {
      body = InkWell(onTap: onTap, child: body);
    }
    final card = Material(
      color: color ?? c.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: body,
    );
    return semanticLabel == null
        ? card
        : Semantics(
            container: true,
            button: onTap != null,
            label: semanticLabel,
            child: card,
          );
  }
}

/// Section title row with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(0, Space.xl, 0, Space.sm),
  });
  final String title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: AppType.overline.copyWith(color: c.textMuted),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Standard page body: safe-area aware, centred and width-limited on tablets,
/// with the app gutter. Use for every scrolling screen.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.onRefresh,
    this.padding,
    this.controller,
    this.bottomInset = Space.x4,
  });

  final List<Widget> children;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry? padding;
  final ScrollController? controller;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding:
          padding ??
          EdgeInsets.fromLTRB(
            Space.gutter,
            Space.sm,
            Space.gutter,
            bottomInset,
          ),
      children: children,
    );
    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Sizes.maxContentWidth),
        child: list,
      ),
    );
    return onRefresh == null
        ? body
        : RefreshIndicator(
            onRefresh: onRefresh!,
            color: context.colors.primary,
            child: body,
          );
  }
}

/// Large screen title used at the top of tab roots.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.subtitle, this.trailing});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, Space.sm, 0, Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: AppType.pageTitle.copyWith(color: c.text),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    subtitle!,
                    style: AppType.bodySmall.copyWith(color: c.textMuted),
                  ),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Icon in a tinted square, used in list rows and menus.
class IconTile extends StatelessWidget {
  const IconTile(this.icon, {super.key, this.tone});
  final IconData icon;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bg = tone == null ? c.primarySoft : c.tone(tone!).background;
    final fg = tone == null ? c.primaryText : c.tone(tone!).foreground;
    return Container(
      width: Sizes.iconContainer,
      height: Sizes.iconContainer,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Corners.md),
      ),
      child: Icon(icon, size: Sizes.iconMd, color: fg),
    );
  }
}
