import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';
import 'tokens.dart';

/// Builds the BuilderPro light and dark [ThemeData].
abstract final class AppTheme {
  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.textOnPrimary,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.primaryText,
      secondary: c.surfaceMuted,
      onSecondary: c.text,
      error: c.danger,
      onError: c.textOnPrimary,
      surface: c.surface,
      onSurface: c.text,
      onSurfaceVariant: c.textMuted,
      outline: c.border,
      outlineVariant: c.border,
      surfaceContainerHighest: c.surfaceMuted,
      surfaceContainerHigh: c.surfaceRaised,
    );

    final textTheme = buildTextTheme(c.text, c.textMuted);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(Corners.md),
      borderSide: BorderSide(color: c.border, width: Sizes.borderWidth),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      fontFamily: AppType.family,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      extensions: [c],
      splashFactory: InkRipple.splashFactory,
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppType.sectionTitle.copyWith(color: c.text),
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: c.primary, width: 2),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: c.danger, width: 1.5),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: c.danger, width: 2),
        ),
        labelStyle: AppType.body.copyWith(color: c.textMuted),
        floatingLabelStyle: AppType.label.copyWith(color: c.primaryText),
        hintStyle: AppType.body.copyWith(color: c.textMuted),
        errorStyle: AppType.helper.copyWith(color: c.danger),
        helperStyle: AppType.helper.copyWith(color: c.textMuted),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.shell,
        contentTextStyle: AppType.body.copyWith(color: c.onShell),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.md),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Corners.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.lg),
        ),
        titleTextStyle: AppType.sectionTitle.copyWith(color: c.text),
        contentTextStyle: AppType.body.copyWith(color: c.text),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceMuted,
        circularTrackColor: c.surfaceMuted,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected) ? c.primary : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.textOnPrimary),
        side: BorderSide(color: c.borderStrong, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corners.sm),
        ),
      ),
    );
  }
}
