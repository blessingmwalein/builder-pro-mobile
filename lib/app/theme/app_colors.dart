import 'package:flutter/material.dart';

/// Semantic tone used by status badges and indicators.
enum StatusTone {
  neutral,
  muted,
  success,
  warning,
  info,
  danger,
  review,
  accent,
  sky,
}

/// Background/foreground pair for a [StatusTone].
@immutable
class ToneColors {
  const ToneColors(this.background, this.foreground);
  final Color background;
  final Color foreground;
}

/// All BuilderPro colours. Light values come from `builder-pro-web/app/globals.css`;
/// the dark palette is hand-tuned (not an inversion) for contrast on graphite surfaces.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceRaised,
    required this.border,
    required this.borderSoft,
    required this.borderStrong,
    required this.text,
    required this.textMuted,
    required this.textOnPrimary,
    required this.primary,
    required this.primaryPressed,
    required this.primaryText,
    required this.primarySoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.shell,
    required this.onShell,
    required this.tones,
    required this.series,
  });

  final Color background;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceRaised;
  final Color border;

  /// The outline of a card: fainter than [border].
  final Color borderSoft;
  final Color borderStrong;
  final Color text;
  final Color textMuted;
  final Color textOnPrimary;
  final Color primary;
  final Color primaryPressed;

  /// Brand colour used for *text/links* (lighter on dark for contrast).
  final Color primaryText;
  final Color primarySoft;
  final Color success;
  final Color warning;
  final Color danger;

  /// Dark brand panel (matches the web sidebar / auth panel).
  final Color shell;
  final Color onShell;
  final Map<StatusTone, ToneColors> tones;

  /// Colours that tell items apart in a chart (a bar per task). Neighbours in
  /// the list differ most, and none is the brand red, which is kept for danger.
  /// Meaning is never carried by these alone: items are also named.
  final List<Color> series;

  ToneColors tone(StatusTone t) => tones[t]!;

  /// The [index]th series colour, starting over after the last.
  Color seriesAt(int index) => series[index % series.length];

  static const AppColors light = AppColors(
    background: Color(0xFFF6F0F0),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEDE6E6),
    surfaceRaised: Color(0xFFFFFFFF),
    border: Color(0xFFD9D1D1),
    borderSoft: Color(0xFFE7E1E1),
    borderStrong: Color(0xFFB9AFAF),
    text: Color(0xFF0F0707),
    textMuted: Color(0xFF605B5A),
    textOnPrimary: Color(0xFFFAFAFA),
    primary: Color(0xFF760F1B),
    primaryPressed: Color(0xFF5B0B15),
    primaryText: Color(0xFF760F1B),
    primarySoft: Color(0xFFF3E1E2),
    success: Color(0xFF047857),
    warning: Color(0xFFB45309),
    danger: Color(0xFFB91C1C),
    shell: Color(0xFF302827),
    onShell: Color(0xFFF4F1F1),
    tones: {
      StatusTone.neutral: ToneColors(Color(0xFFF3F4F6), Color(0xFF374151)),
      StatusTone.muted: ToneColors(Color(0xFFF3F4F6), Color(0xFF6B7280)),
      StatusTone.success: ToneColors(Color(0xFFECFDF5), Color(0xFF047857)),
      StatusTone.warning: ToneColors(Color(0xFFFFFBEB), Color(0xFFB45309)),
      StatusTone.info: ToneColors(Color(0xFFEFF6FF), Color(0xFF1D4ED8)),
      StatusTone.danger: ToneColors(Color(0xFFFEF2F2), Color(0xFFB91C1C)),
      StatusTone.review: ToneColors(Color(0xFFFAF5FF), Color(0xFF7E22CE)),
      StatusTone.accent: ToneColors(Color(0xFFEEF2FF), Color(0xFF4338CA)),
      StatusTone.sky: ToneColors(Color(0xFFF0F9FF), Color(0xFF0369A1)),
    },
    series: [
      Color(0xFF1D4ED8),
      Color(0xFFC2410C),
      Color(0xFF15803D),
      Color(0xFF6D28D9),
      Color(0xFF0E7490),
      Color(0xFFBE185D),
      Color(0xFFA16207),
      Color(0xFF475569),
    ],
  );

  static const AppColors dark = AppColors(
    background: Color(0xFF0D0505),
    surface: Color(0xFF180D0D),
    surfaceMuted: Color(0xFF251A19),
    surfaceRaised: Color(0xFF211514),
    border: Color(0xFF2E2322),
    borderSoft: Color(0xFF261C1B),
    borderStrong: Color(0xFF4A3C3A),
    text: Color(0xFFF7F0EF),
    textMuted: Color(0xFFA39B99),
    textOnPrimary: Color(0xFFFAFAFA),
    primary: Color(0xFFA94344),
    primaryPressed: Color(0xFF8E3536),
    primaryText: Color(0xFFE08A8B),
    primarySoft: Color(0xFF3A1B1C),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFFF6467),
    shell: Color(0xFF090303),
    onShell: Color(0xFFF2EDED),
    tones: {
      StatusTone.neutral: ToneColors(Color(0xFF262221), Color(0xFFD1CBC9)),
      StatusTone.muted: ToneColors(Color(0xFF1F1B1A), Color(0xFF9A9392)),
      StatusTone.success: ToneColors(Color(0xFF052E22), Color(0xFF34D399)),
      StatusTone.warning: ToneColors(Color(0xFF2E1D05), Color(0xFFFBBF24)),
      StatusTone.info: ToneColors(Color(0xFF0B1D3A), Color(0xFF60A5FA)),
      StatusTone.danger: ToneColors(Color(0xFF330D0E), Color(0xFFFF8A8C)),
      StatusTone.review: ToneColors(Color(0xFF241040), Color(0xFFC084FC)),
      StatusTone.accent: ToneColors(Color(0xFF1E1B4B), Color(0xFF818CF8)),
      StatusTone.sky: ToneColors(Color(0xFF082F49), Color(0xFF38BDF8)),
    },
    series: [
      Color(0xFF60A5FA),
      Color(0xFFFB923C),
      Color(0xFF4ADE80),
      Color(0xFFA78BFA),
      Color(0xFF22D3EE),
      Color(0xFFF472B6),
      Color(0xFFFACC15),
      Color(0xFF94A3B8),
    ],
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) =>
      t < 0.5 ? this : (other as AppColors? ?? this);
}

extension AppColorsX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
