import 'package:handdraw_studio/features/image_animation/domain/image_parts_failure.dart';
import 'flat_text_background_sampler.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_polygon_list.dart';
import 'dart:ui';

import 'package:handdraw_studio/features/image_animation/application/image_animation_analyzer.dart';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/scene_region_reveal_planner.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/region_auto_path_analyzer.dart';

/// Analyzes only authored crops, retaining original pixels and polygon masks.
/// One worker retains the source buffer; cancellation never commits a partial plan.
class ImagePartsPlanner {
  const ImagePartsPlanner();

  Future<List<DrawingStroke>?> build({
    required Image source,
    required List<SceneRegion> regions,
    required ImageAnimationAnalyzer analyzer,
    required bool Function() isCancelled,
    Set<String> revealRegionIds = const {},
    double? canvasHeight,
    Set<String> textRegionIds = const {},
    Map<String, List<Rect>> backgroundExclusions = const {},
  }) async {
    final raw = await source.toByteData(format: ImageByteFormat.rawRgba);
    if (raw == null || isCancelled()) return null;
    final session = await const IsolateRegionMaskedCropEncoder().open(
      rgba: raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
      sourceWidth: source.width,
      sourceHeight: source.height,
    );
    try {
      final result = <DrawingStroke>[];
      for (final region in regions) {
        if (isCancelled()) return null;
        if (revealRegionIds.contains(region.id)) {
          final cuts = backgroundExclusions[region.id] ?? const <Rect>[];
          final fill = cuts.isEmpty
              ? null
              : const FlatTextBackgroundSampler().sample(
                  raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
                  source.width,
                  source.height,
                  cuts,
                );
          if (cuts.isNotEmpty && fill == null) {
            throw ImagePartsFailure(
              'unsupportedBackground',
              partName: region.name,
            );
          }
          result.addAll(
            const SceneRegionRevealPlanner()
                .build(
                  regions: [region],
                  canvasHeight: canvasHeight ?? source.height.toDouble(),
                )
                .strokes
                .map(
                  (stroke) => stroke.copyWith(
                    fillColorValue: fill,
                    exclusionBounds: cuts,
                  ),
                ),
          );
          continue;
        }
        final crop = await session.encode(region);
        if (isCancelled()) return null;
        if (crop == null) {
          throw StateError(
            'The selected part ${region.name} contains no artwork.',
          );
        }
        final textOnly = textRegionIds.contains(region.id);
        final background = textOnly
            ? const FlatTextBackgroundSampler().sample(
                raw.buffer.asUint8List(raw.offsetInBytes, raw.lengthInBytes),
                source.width,
                source.height,
                [region.bounds],
              )
            : null;
        final plan = await analyzer.analyze(
          crop.encodedPng,
          textOnly: textOnly,
          backgroundColor: background,
        );
        if (plan == null || isCancelled()) return null;
        if (plan.strokes.isEmpty) {
          throw StateError(
            'The selected part ${region.name} contains no drawable artwork.',
          );
        }
        final bounds = crop.bounds;
        Offset map(Offset p) => Offset(
          bounds.left + p.dx * bounds.width,
          bounds.top + p.dy * bounds.height,
        );
        // Segmented masks already include the lasso's transparent cutout.
        // Reuse transformed masks across paths instead of copying dense polygons.
        final masks = <List<List<Offset>>, List<List<Offset>>>{};
        for (final item in plan.ordered(ImageDrawingOrder.regionFirst)) {
          final stroke = item.stroke;
          result.add(
            stroke.copyWith(
              id: '${region.id}-${stroke.id}',
              sectionId: region.id,
              points: stroke.points.map(map).toList(),
              clipPolygons: masks.putIfAbsent(
                stroke.clipPolygons,
                () => ImmutablePolygonList<Offset>.freeze([
                  for (final polygon in stroke.clipPolygons)
                    polygon.map(map).toList(),
                ]),
              ),
              clipBounds: bounds,
              isTextShape:
                  textRegionIds.contains(region.id) || stroke.isTextShape,
              isPaintStroke: item.role == ImageStrokeRole.paint,
              paintRegion: item.region,
            ),
          );
        }
      }
      return result;
    } finally {
      await session.close();
    }
  }
}
