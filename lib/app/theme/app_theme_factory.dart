import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/theme/app_typography.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

abstract final class AppThemeFactory {
  static ThemeData light() =>
      _build(brightness: Brightness.light, colors: AppPalette.light);

  static ThemeData dark() =>
      _build(brightness: Brightness.dark, colors: AppPalette.dark);

  static ThemeData _build({
    required Brightness brightness,
    required StudioThemeColors colors,
  }) {
    final isDark = brightness == Brightness.dark;
    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: brightness,
        ).copyWith(
          primary: colors.accent,
          onPrimary: isDark ? const Color(0xFF001B26) : Colors.white,
          primaryContainer: colors.accentContainer,
          secondary: colors.reveal,
          secondaryContainer: colors.selectedSurfaceStrong,
          tertiary: colors.warning,
          surface: colors.surface,
          surfaceContainer: colors.surfaceAlt,
          surfaceContainerHigh: colors.surfaceElevated,
          error: colors.danger,
          outline: colors.border,
          outlineVariant: colors.border.withValues(alpha: 0.62),
        );
    final base = ThemeData.from(colorScheme: colorScheme, useMaterial3: true);
    final roundedRectangle = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    final textTheme = AppTypography.applyTo(base.textTheme, colors.textPrimary);
    return base.copyWith(
      scaffoldBackgroundColor: colors.appBackground,
      dividerColor: colors.border,
      textTheme: textTheme.copyWith(
        titleLarge: textTheme.titleLarge,
        titleMedium: textTheme.titleMedium,
        labelLarge: textTheme.labelLarge,
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceAlt,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: roundedRectangle.copyWith(
          side: BorderSide(color: colors.border.withValues(alpha: 0.72)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.inputFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: colors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: colors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: colors.accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 38)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          shape: WidgetStatePropertyAll(roundedRectangle),
          elevation: const WidgetStatePropertyAll(0),
          overlayColor: WidgetStatePropertyAll(
            colors.accentSoft.withValues(alpha: 0.16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(44, 38)),
          shape: WidgetStatePropertyAll(roundedRectangle),
          side: WidgetStateProperty.resolveWith((states) {
            final color = states.contains(WidgetState.hovered)
                ? colors.accent
                : colors.border;
            return BorderSide(color: color);
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(roundedRectangle),
          foregroundColor: WidgetStatePropertyAll(colors.textSecondary),
          overlayColor: WidgetStatePropertyAll(
            colors.accent.withValues(alpha: 0.1),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.square(38)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return colors.textMuted.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colors.accentSoft;
            }
            return colors.textSecondary;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)) {
              return colors.selectedSurface;
            }
            return Colors.transparent;
          }),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: colors.border)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.selectedSurfaceStrong;
            }
            return colors.surfaceAlt.withValues(alpha: 0.78);
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colors.accentSoft;
            return colors.textSecondary;
          }),
        ),
      ),
      sliderTheme: base.sliderTheme.copyWith(
        activeTrackColor: colors.accent,
        inactiveTrackColor: colors.border,
        thumbColor: colors.accentSoft,
        overlayColor: colors.accent.withValues(alpha: 0.14),
        trackHeight: 3,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.textPrimary
              : colors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? colors.accent
              : colors.inputFill;
        }),
        trackOutlineColor: WidgetStatePropertyAll(colors.border),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceElevated,
        elevation: 12,
        shadowColor: colors.scrim,
        surfaceTintColor: Colors.transparent,
        shape: roundedRectangle.copyWith(
          side: BorderSide(color: colors.border),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: colors.scrim,
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        textStyle: TextStyle(color: colors.textPrimary, fontSize: 12),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: colors.surface),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceElevated,
        contentTextStyle: TextStyle(color: colors.textPrimary),
        actionTextColor: colors.accentSoft,
        behavior: SnackBarBehavior.floating,
        shape: roundedRectangle,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.border,
      ),
      extensions: [colors],
    );
  }
}
