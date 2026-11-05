import 'package:flutter/material.dart';

/// Typography scale on Inter (variable font bundled in assets).
abstract final class AppType {
  static const String family = 'Inter';

  static TextStyle _s(
    double size,
    double height,
    double weight, {
    double? letterSpacing,
    bool tabular = false,
  }) {
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      height: height / size,
      fontWeight: _bucket(weight),
      fontVariations: [FontVariation('wght', weight)],
      letterSpacing: letterSpacing,
      fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
    );
  }

  static FontWeight _bucket(double w) {
    if (w >= 700) return FontWeight.w700;
    if (w >= 600) return FontWeight.w600;
    if (w >= 500) return FontWeight.w500;
    return FontWeight.w400;
  }

  static final TextStyle pageTitle = _s(26, 32, 700, letterSpacing: -0.4);
  static final TextStyle sectionTitle = _s(17, 24, 650);
  static final TextStyle body = _s(15, 22, 400);
  static final TextStyle bodyStrong = _s(15, 22, 600);
  static final TextStyle bodySmall = _s(13, 18, 400);
  static final TextStyle label = _s(13, 16, 600, letterSpacing: 0.1);
  static final TextStyle helper = _s(12, 16, 400);
  static final TextStyle button = _s(16, 20, 600);
  static final TextStyle badge = _s(11, 14, 650, letterSpacing: 0.2);
  static final TextStyle overline = _s(11, 14, 650, letterSpacing: 0.8);
  static final TextStyle kpi = _s(
    30,
    36,
    700,
    letterSpacing: -0.5,
    tabular: true,
  );
  static final TextStyle amount = _s(15, 20, 600, tabular: true);
  static final TextStyle timer = _s(
    44,
    48,
    700,
    letterSpacing: -1,
    tabular: true,
  );
}

TextTheme buildTextTheme(Color text, Color muted) {
  return TextTheme(
    displaySmall: AppType.pageTitle.copyWith(color: text),
    headlineSmall: AppType.pageTitle.copyWith(color: text),
    titleLarge: AppType.sectionTitle.copyWith(color: text),
    titleMedium: AppType.bodyStrong.copyWith(color: text),
    titleSmall: AppType.label.copyWith(color: text),
    bodyLarge: AppType.body.copyWith(color: text),
    bodyMedium: AppType.body.copyWith(color: text),
    bodySmall: AppType.bodySmall.copyWith(color: muted),
    labelLarge: AppType.button.copyWith(color: text),
    labelMedium: AppType.label.copyWith(color: text),
    labelSmall: AppType.helper.copyWith(color: muted),
  );
}
