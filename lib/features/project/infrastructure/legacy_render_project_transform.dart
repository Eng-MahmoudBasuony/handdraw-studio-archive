import 'dart:math' as math;

import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';

/// Read-model-only transformations for rendering compatibility snapshots.
///
/// The returned legacy project is never published to EditorState, persisted,
/// or converted back to ProjectDocument.
final class LegacyRenderProjectTransform {
  const LegacyRenderProjectTransform();

  HandDrawProject forExport(HandDrawProject project) {
    if (project.exportRenderQuality == ExportRenderQuality.full) return project;
    const scale = 0.5;
    return project.copyWith(
      canvasWidth: math.max(2, (project.canvasWidth * scale).round()),
      canvasHeight: math.max(2, (project.canvasHeight * scale).round()),
      revealWidth: project.revealWidth * scale,
      strokes: [
        for (final stroke in project.strokes)
          stroke.copyWith(
            revealWidth: stroke.revealWidth == null
                ? null
                : stroke.revealWidth! * scale,
          ),
      ],
    );
  }
}
