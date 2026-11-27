import 'package:flutter/material.dart';

/// Typography tokens shared by every HandDraw Studio surface.
///
/// Playpen Sans Arabic supports both Arabic and Latin, keeping the product's
/// hand-drawn character without sacrificing readability in dense controls.
abstract final class AppTypography {
  static const fontFamily = 'PlaypenSansArabic';

  static TextTheme applyTo(TextTheme base, Color foreground) {
    final themed = base.apply(
      fontFamily: fontFamily,
      bodyColor: foreground,
      displayColor: foreground,
    );
    return themed.copyWith(
      titleLarge: themed.titleLarge?.copyWith(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.15,
      ),
      titleMedium: themed.titleMedium?.copyWith(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w600,
      ),
      labelLarge: themed.labelLarge?.copyWith(
        fontFamily: fontFamily,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
      ),
    );
  }
}
