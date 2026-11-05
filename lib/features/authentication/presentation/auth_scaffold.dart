import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_typography.dart';
import '../../../app/theme/tokens.dart';
import '../../../shared/components/brand_mark.dart';

/// Shared frame for the signed-out screens: dark brand panel, then content.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.showBack = false,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                color: c.shell,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(Corners.xl + 4),
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.lg,
                    Space.xxl,
                    Space.x3,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showBack)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            tooltip: 'Back',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: Icon(
                              Icons.arrow_back_rounded,
                              color: c.onShell,
                            ),
                          ),
                        )
                      else
                        const SizedBox(height: Space.sm),
                      const BrandMark(height: 64, forceLight: true),
                      const SizedBox(height: Space.xl),
                      Text(
                        'Construction project management, simplified.',
                        style: AppType.body.copyWith(
                          color: c.onShell.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.xxl,
                    Space.xxl,
                    Space.xxl,
                    Space.x4,
                  ),
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
                        const SizedBox(height: Space.sm),
                        Text(
                          subtitle!,
                          style: AppType.body.copyWith(color: c.textMuted),
                        ),
                      ],
                      const SizedBox(height: Space.xxl),
                      ...children,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
