enum ExportPresetId {
  youtubeCourse4k,
  finalCutOverlay4k,
  verticalLesson,
  squareLesson,
  presentationHd,
  custom,
}

enum ExportAlphaMode { premultiplied, straight }

enum ExportRenderQuality { full, proxy }

abstract final class ExportResolutionPolicy {
  static const minDimension = 16;
  static const maxDimension = 8192;

  static bool isValidDimension(int value) =>
      value >= minDimension && value <= maxDimension;

  static bool isValid({required int width, required int height}) =>
      isValidDimension(width) && isValidDimension(height);
}

class ExportPreset {
  const ExportPreset({
    required this.id,
    required this.width,
    required this.height,
    required this.frameRate,
    required this.requiresAlpha,
  });

  final ExportPresetId id;
  final int width;
  final int height;
  final int frameRate;
  final bool requiresAlpha;

  static const all = [
    ExportPreset(
      id: ExportPresetId.youtubeCourse4k,
      width: 3840,
      height: 2160,
      frameRate: 30,
      requiresAlpha: false,
    ),
    ExportPreset(
      id: ExportPresetId.finalCutOverlay4k,
      width: 3840,
      height: 2160,
      frameRate: 30,
      requiresAlpha: true,
    ),
    ExportPreset(
      id: ExportPresetId.verticalLesson,
      width: 1080,
      height: 1920,
      frameRate: 30,
      requiresAlpha: true,
    ),
    ExportPreset(
      id: ExportPresetId.squareLesson,
      width: 1080,
      height: 1080,
      frameRate: 30,
      requiresAlpha: true,
    ),
    ExportPreset(
      id: ExportPresetId.presentationHd,
      width: 1920,
      height: 1080,
      frameRate: 30,
      requiresAlpha: true,
    ),
  ];

  static ExportPreset? byId(ExportPresetId id) {
    for (final preset in all) {
      if (preset.id == id) return preset;
    }
    return null;
  }
}
