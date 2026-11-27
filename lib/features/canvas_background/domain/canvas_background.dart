enum CanvasBackgroundMode { transparent, solid, preset }

enum CanvasBackgroundPreset {
  notebook,
  graph,
  cream,
  chalkboard,
  softGradient,
  warmWhite,
  blueprint,
  kraft,
  dark,
  linen,
}

/// Persistent, renderer-independent canvas background configuration.
///
/// Colors are stored as 32-bit ARGB values so project documents stay free of
/// Flutter painting objects. Procedural presets are identified by stable enum
/// names and therefore add no external asset or file-system dependency.
final class CanvasBackground {
  const CanvasBackground._({
    required this.mode,
    required this.colorValue,
    required this.preset,
  });

  const CanvasBackground.transparent()
    : this._(
        mode: CanvasBackgroundMode.transparent,
        colorValue: 0x00000000,
        preset: null,
      );

  const CanvasBackground.solid(int colorValue)
    : this._(
        mode: CanvasBackgroundMode.solid,
        colorValue: colorValue,
        preset: null,
      );

  const CanvasBackground.preset(CanvasBackgroundPreset preset)
    : this._(
        mode: CanvasBackgroundMode.preset,
        colorValue: 0x00000000,
        preset: preset,
      );

  final CanvasBackgroundMode mode;
  final int colorValue;
  final CanvasBackgroundPreset? preset;

  bool get isTransparent => mode == CanvasBackgroundMode.transparent;

  bool get isOpaque => switch (mode) {
    CanvasBackgroundMode.transparent => false,
    CanvasBackgroundMode.solid => (colorValue >>> 24) == 0xFF,
    CanvasBackgroundMode.preset => true,
  };

  CanvasBackground normalized() => switch (mode) {
    CanvasBackgroundMode.transparent => const CanvasBackground.transparent(),
    CanvasBackgroundMode.solid => CanvasBackground.solid(
      colorValue | 0xFF000000,
    ),
    CanvasBackgroundMode.preset when preset != null => CanvasBackground.preset(
      preset!,
    ),
    CanvasBackgroundMode.preset => const CanvasBackground.transparent(),
  };

  @override
  bool operator ==(Object other) =>
      other is CanvasBackground &&
      mode == other.mode &&
      colorValue == other.colorValue &&
      preset == other.preset;

  @override
  int get hashCode => Object.hash(mode, colorValue, preset);
}
