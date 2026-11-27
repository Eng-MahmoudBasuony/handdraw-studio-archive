import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';

/// Keeps authored scenes sequential without disturbing the natural Auto Path
/// order inside each scene.
///
/// Auto Path first establishes semantic reading order (text, shapes and pen
/// travel) over the analyzed artwork. Scene Split then performs one stable
/// grouping pass: every stroke belonging to Scene 1 is emitted before Scene 2,
/// while the relative order chosen by Auto Path inside either scene remains
/// unchanged. Preview and MOV consume this same persisted stroke list.
class SceneSplitStrokeOrderer {
  const SceneSplitStrokeOrderer();

  List<DrawingStroke> order({
    required List<DrawingStroke> strokes,
    required List<SceneRegion> regions,
    required Map<String, SceneRegion> sectionRegions,
  }) {
    if (strokes.length < 2 || regions.isEmpty || sectionRegions.isEmpty) {
      return List.unmodifiable(strokes);
    }
    final buckets = <String, List<DrawingStroke>>{
      for (final region in regions) region.id: <DrawingStroke>[],
    };
    final unassigned = <DrawingStroke>[];
    for (final stroke in strokes) {
      final region = sectionRegions[stroke.sectionId];
      final bucket = region == null ? null : buckets[region.id];
      if (bucket == null) {
        unassigned.add(stroke);
      } else {
        bucket.add(stroke);
      }
    }
    return List.unmodifiable([
      for (final region in regions) ...buckets[region.id]!,
      ...unassigned,
    ]);
  }
}
