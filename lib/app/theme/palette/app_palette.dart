import 'package:flutter/material.dart';

/// The only source of raw UI colors in the application.
///
/// Widgets consume [StudioThemeColors] semantically through ThemeData instead
/// of depending on palette values directly.
abstract final class AppPalette {
  static const brand = Color(0xFF22D3EE);

  static const dark = StudioThemeColors(
    appBackground: Color(0xFF070B17),
    surface: Color(0xFF0D1426),
    surfaceAlt: Color(0xFF101A31),
    surfaceElevated: Color(0xFF15213B),
    toolbar: Color(0xFF091123),
    workspace: Color(0xFF080E1D),
    inputFill: Color(0xFF111D35),
    border: Color(0xFF253B65),
    textPrimary: Color(0xFFEDF5FF),
    textSecondary: Color(0xFFB9C9E6),
    textMuted: Color(0xFF7588AC),
    accent: brand,
    accentSoft: Color(0xFF7DEBFF),
    success: Color(0xFF43D9A3),
    warning: Color(0xFFFFB020),
    danger: Color(0xFFFF5C7A),
    dangerSoft: Color(0xFFFFA4B6),
    dangerContainer: Color(0xFF3A1829),
    selectedSurface: Color(0xFF132A4B),
    selectedSurfaceStrong: Color(0xFF173B68),
    accentContainer: Color(0xFF0C2B4B),
    checkerBase: Color(0xFF111A2B),
    checkerCell: Color(0xFF18243A),
    canvasGuide: Color(0xFF3B5279),
    path: Color(0xFF139BFF),
    pathMarkerGlow: Color(0xFFFF7A00),
    pathMarkerRing: Color(0xFFFF9800),
    pathMarkerCore: Color(0xFFFFD84D),
    pathMarkerText: Color(0xFF251500),
    reveal: Color(0xFFA855F7),
    ignored: Color(0xFF7181A0),
    waveformBackground: Color(0xFF060A14),
    waveformIdle: Color(0xFF53698D),
    waveformPlayed: Color(0xFF22D3EE),
    mediaProgress: Color(0xFFFF0033),
    scrim: Color(0xD9050912),
  );

  static const light = StudioThemeColors(
    appBackground: Color(0xFFF3F7FF),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF8FAFF),
    surfaceElevated: Color(0xFFEDF3FF),
    toolbar: Color(0xFFFBFDFF),
    workspace: Color(0xFFE8EFFA),
    inputFill: Color(0xFFEDF3FC),
    border: Color(0xFFC8D6EC),
    textPrimary: Color(0xFF0A1730),
    textSecondary: Color(0xFF405273),
    textMuted: Color(0xFF6A7C9B),
    accent: Color(0xFF007FBD),
    accentSoft: Color(0xFF006EA5),
    success: Color(0xFF238257),
    warning: Color(0xFFA66000),
    danger: Color(0xFFC33F52),
    dangerSoft: Color(0xFF9F2F40),
    dangerContainer: Color(0xFFFBE7EA),
    selectedSurface: Color(0xFFE2F3FF),
    selectedSurfaceStrong: Color(0xFFCDE9FF),
    accentContainer: Color(0xFFD8F3FF),
    checkerBase: Color(0xFFD6DFEC),
    checkerCell: Color(0xFFE8EEF7),
    canvasGuide: Color(0xFF657898),
    path: Color(0xFF007FD1),
    pathMarkerGlow: Color(0xFFFFA000),
    pathMarkerRing: Color(0xFFE66A00),
    pathMarkerCore: Color(0xFFFFC928),
    pathMarkerText: Color(0xFF321C00),
    reveal: Color(0xFF7C3AED),
    ignored: Color(0xFF74829A),
    waveformBackground: Color(0xFFE8EFFA),
    waveformIdle: Color(0xFF8091AB),
    waveformPlayed: Color(0xFF007FBD),
    mediaProgress: Color(0xFFD90429),
    scrim: Color(0xCCFFFFFF),
  );
}

@immutable
class StudioThemeColors extends ThemeExtension<StudioThemeColors> {
  const StudioThemeColors({
    required this.appBackground,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceElevated,
    required this.toolbar,
    required this.workspace,
    required this.inputFill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerSoft,
    required this.dangerContainer,
    required this.selectedSurface,
    required this.selectedSurfaceStrong,
    required this.accentContainer,
    required this.checkerBase,
    required this.checkerCell,
    required this.canvasGuide,
    required this.path,
    required this.pathMarkerGlow,
    required this.pathMarkerRing,
    required this.pathMarkerCore,
    required this.pathMarkerText,
    required this.reveal,
    required this.ignored,
    required this.waveformBackground,
    required this.waveformIdle,
    required this.waveformPlayed,
    required this.mediaProgress,
    required this.scrim,
  });

  final Color appBackground;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceElevated;
  final Color toolbar;
  final Color workspace;
  final Color inputFill;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerSoft;
  final Color dangerContainer;
  final Color selectedSurface;
  final Color selectedSurfaceStrong;
  final Color accentContainer;
  final Color checkerBase;
  final Color checkerCell;
  final Color canvasGuide;
  final Color path;
  final Color pathMarkerGlow;
  final Color pathMarkerRing;
  final Color pathMarkerCore;
  final Color pathMarkerText;
  final Color reveal;
  final Color ignored;
  final Color waveformBackground;
  final Color waveformIdle;
  final Color waveformPlayed;
  final Color mediaProgress;
  final Color scrim;

  @override
  StudioThemeColors copyWith({
    Color? appBackground,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceElevated,
    Color? toolbar,
    Color? workspace,
    Color? inputFill,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? dangerSoft,
    Color? dangerContainer,
    Color? selectedSurface,
    Color? selectedSurfaceStrong,
    Color? accentContainer,
    Color? checkerBase,
    Color? checkerCell,
    Color? canvasGuide,
    Color? path,
    Color? pathMarkerGlow,
    Color? pathMarkerRing,
    Color? pathMarkerCore,
    Color? pathMarkerText,
    Color? reveal,
    Color? ignored,
    Color? waveformBackground,
    Color? waveformIdle,
    Color? waveformPlayed,
    Color? mediaProgress,
    Color? scrim,
  }) => StudioThemeColors(
    appBackground: appBackground ?? this.appBackground,
    surface: surface ?? this.surface,
    surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    surfaceElevated: surfaceElevated ?? this.surfaceElevated,
    toolbar: toolbar ?? this.toolbar,
    workspace: workspace ?? this.workspace,
    inputFill: inputFill ?? this.inputFill,
    border: border ?? this.border,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    accentSoft: accentSoft ?? this.accentSoft,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    dangerSoft: dangerSoft ?? this.dangerSoft,
    dangerContainer: dangerContainer ?? this.dangerContainer,
    selectedSurface: selectedSurface ?? this.selectedSurface,
    selectedSurfaceStrong: selectedSurfaceStrong ?? this.selectedSurfaceStrong,
    accentContainer: accentContainer ?? this.accentContainer,
    checkerBase: checkerBase ?? this.checkerBase,
    checkerCell: checkerCell ?? this.checkerCell,
    canvasGuide: canvasGuide ?? this.canvasGuide,
    path: path ?? this.path,
    pathMarkerGlow: pathMarkerGlow ?? this.pathMarkerGlow,
    pathMarkerRing: pathMarkerRing ?? this.pathMarkerRing,
    pathMarkerCore: pathMarkerCore ?? this.pathMarkerCore,
    pathMarkerText: pathMarkerText ?? this.pathMarkerText,
    reveal: reveal ?? this.reveal,
    ignored: ignored ?? this.ignored,
    waveformBackground: waveformBackground ?? this.waveformBackground,
    waveformIdle: waveformIdle ?? this.waveformIdle,
    waveformPlayed: waveformPlayed ?? this.waveformPlayed,
    mediaProgress: mediaProgress ?? this.mediaProgress,
    scrim: scrim ?? this.scrim,
  );

  @override
  StudioThemeColors lerp(StudioThemeColors? other, double t) {
    if (other == null) return this;
    return StudioThemeColors(
      appBackground: Color.lerp(appBackground, other.appBackground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      toolbar: Color.lerp(toolbar, other.toolbar, t)!,
      workspace: Color.lerp(workspace, other.workspace, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      selectedSurface: Color.lerp(selectedSurface, other.selectedSurface, t)!,
      selectedSurfaceStrong: Color.lerp(
        selectedSurfaceStrong,
        other.selectedSurfaceStrong,
        t,
      )!,
      accentContainer: Color.lerp(accentContainer, other.accentContainer, t)!,
      checkerBase: Color.lerp(checkerBase, other.checkerBase, t)!,
      checkerCell: Color.lerp(checkerCell, other.checkerCell, t)!,
      canvasGuide: Color.lerp(canvasGuide, other.canvasGuide, t)!,
      path: Color.lerp(path, other.path, t)!,
      pathMarkerGlow: Color.lerp(pathMarkerGlow, other.pathMarkerGlow, t)!,
      pathMarkerRing: Color.lerp(pathMarkerRing, other.pathMarkerRing, t)!,
      pathMarkerCore: Color.lerp(pathMarkerCore, other.pathMarkerCore, t)!,
      pathMarkerText: Color.lerp(pathMarkerText, other.pathMarkerText, t)!,
      reveal: Color.lerp(reveal, other.reveal, t)!,
      ignored: Color.lerp(ignored, other.ignored, t)!,
      waveformBackground: Color.lerp(
        waveformBackground,
        other.waveformBackground,
        t,
      )!,
      waveformIdle: Color.lerp(waveformIdle, other.waveformIdle, t)!,
      waveformPlayed: Color.lerp(waveformPlayed, other.waveformPlayed, t)!,
      mediaProgress: Color.lerp(mediaProgress, other.mediaProgress, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

extension StudioThemeContext on BuildContext {
  StudioThemeColors get studioColors =>
      Theme.of(this).extension<StudioThemeColors>() ?? AppPalette.dark;
}
