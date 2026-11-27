import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/default_artwork_path_facade.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/projected_framing_validator.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'real dependency fixture renders safe Preview/MOV source frames',
    () async {
      final drawing = await const EditorFileService().loadImage(
        'test/fixtures/dependency-graph-diagram.svg',
      );
      final hand = await const EditorFileService().loadImage(
        'assets/hands/technical-pen-wheat-right-v1.png',
      );
      final sourceBytes = await File(
        'test/fixtures/dependency-graph-diagram.svg',
      ).readAsBytes();
      addTearDown(drawing.image.dispose);
      addTearDown(() => drawing.revealBaseImage?.dispose());
      addTearDown(() => drawing.svgRevealLayers?.strokes.dispose());
      addTearDown(() => drawing.svgRevealLayers?.globalStrokes?.dispose());
      addTearDown(hand.image.dispose);

      final groups = <List<int>>[[], [], [], []];
      for (var index = 0; index < drawing.vectorPaths.length; index++) {
        final centerY = drawing.vectorPaths[index].clipBounds.center.dy;
        groups[(centerY * 4).floor().clamp(0, 3)].add(index);
      }
      final nonEmpty = groups.where((group) => group.isNotEmpty).toList();
      final regions = <SemanticRegion>[];
      final events = <SemanticAttentionEvent>[];
      for (var section = 0; section < nonEmpty.length; section++) {
        final bounds = nonEmpty[section]
            .map((index) => drawing.vectorPaths[index].clipBounds)
            .reduce((a, b) => a.expandToInclude(b));
        final visual = SemanticWorldBounds(
          bounds.left * 1800,
          bounds.top * 1000,
          bounds.right * 1800,
          bounds.bottom * 1000,
        );
        final target = SemanticTargetReference.stroke(
          StrokeId('section-union-$section'),
        );
        regions.add(
          SemanticRegion(
            id: target.stableKey,
            target: target,
            kind: SemanticRegionKind.strokeGroup,
            geometricBounds: visual,
            visualBounds: visual,
            direction: KnownTextDirection.unknown,
            directionProvenance: DirectionProvenance.unknown,
            metadata: EntitySemanticMetadata(
              target: target,
              keepTogether: true,
            ),
          ),
        );
        events.add(
          SemanticAttentionEvent(
            time: TimelineTime.fromMicroseconds(section * 2000000),
            regionIds: [target.stableKey],
            activeBounds: visual,
            sectionId: SectionId('section-$section'),
          ),
        );
      }
      final graph = CompiledSemanticRegionGraph(
        dependencyKey: 'dependency-real-e2e',
        worldWidth: 1800,
        worldHeight: 1000,
        regions: regions,
        containment: const [],
        drawingOrder: const [],
        adjacency: const [],
        attentionEvents: events,
        handFootprint: HandFootprintDescriptor(
          provenance: HandFootprintProvenance.configuredAsset,
          screenScale: .24,
          penTipX: BuiltInHands.wheatTechnicalPenRight.penTip.dx,
          penTipY: BuiltInHands.wheatTechnicalPenRight.penTip.dy,
        ),
      );
      final timeline = CompiledTimeline(
        dependencyKey: TimelineDependencyKey(
          projectId: ProjectId('dependency-real-e2e'),
          documentRevision: 1,
        ),
        duration: TimelineDuration.fromMicroseconds(8000000),
        contentEnd: TimelineTime.fromMicroseconds(8000000),
        drawing: CompiledDrawingTimelineTrack(
          interval: TimelineInterval(
            start: TimelineTime.zero,
            end: TimelineTime.fromMicroseconds(8000000),
          ),
          sections: [
            for (var section = 0; section < nonEmpty.length; section++)
              CompiledDrawingSection(
                sectionId: SectionId('section-$section'),
                interval: TimelineInterval(
                  start: TimelineTime.fromMicroseconds(section * 2000000),
                  end: TimelineTime.fromMicroseconds((section + 1) * 2000000),
                ),
              ),
          ],
        ),
        audio: const [],
        voiceGuide: null,
        sceneMarkers: const [],
      );
      final plan = const SmartAutoDirector().generate(
        timeline: timeline,
        graph: graph,
        cameraTrack: null,
      );
      expect(plan.proposedShots, hasLength(nonEmpty.length));
      expect(plan.proposedShots.last.interval.end.microseconds, 8000000);
      const framing = ProjectedFramingValidator();
      for (final shot in plan.proposedShots) {
        final targets = shot.targetRegionIds
            .map((id) => regions.singleWhere((region) => region.id == id))
            .toList();
        final union = targets
            .skip(1)
            .fold(
              targets.first.visualBounds,
              (value, region) => value.union(region.visualBounds),
            );
        expect(
          framing
              .validate(
                view: shot.keyframes.last.view,
                target: union,
                worldWidth: 1800,
                worldHeight: 1000,
                safeOutputFraction: plan.configuration.innerSafeFraction,
              )
              .projectedSafeContainmentRatio,
          closeTo(1, 1e-9),
        );
      }

      final analyzed = await DefaultArtworkPathFacade.standard().analyze(
        ArtworkPathRequest(
          kind: drawing.sourceKind,
          previewImage: drawing.image,
          previewBytes: sourceBytes,
          sourceBytes: sourceBytes,
          cachedSvgPaths: drawing.vectorPaths,
        ),
      );
      final plannedStrokes = const AutoPathStrokePlanner()
          .build(
            sections: analyzed.analysis.sections,
            project: HandDrawProject(canvasWidth: 1800, canvasHeight: 1000),
          )
          .strokes;
      final preciseTextSectionIds = analyzed.analysis.sections
          .where((section) => section.kind.name == 'text')
          .where((section) => section.hasPreciseTrace)
          .map((section) => section.id)
          .toSet();
      final approximateTextSectionIds = analyzed.analysis.sections
          .where((section) => section.kind.name == 'text')
          .where((section) => !section.hasPreciseTrace)
          .map((section) => section.id)
          .toSet();
      expect(preciseTextSectionIds, isNotEmpty);
      expect(
        plannedStrokes
            .where(
              (stroke) => approximateTextSectionIds.contains(stroke.sectionId),
            )
            .every((stroke) => stroke.revealOnly),
        isTrue,
        reason: 'Approximate SVG text paths must never display the hand.',
      );
      final project = HandDrawProject(
        canvasWidth: 1800,
        canvasHeight: 1000,
        durationSeconds: 8,
        drawingDurationSeconds: 8,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        handScale: .24,
        penTip: BuiltInHands.wheatTechnicalPenRight.penTip,
        strokes: plannedStrokes,
      );
      final sourcePixels = await drawing.image.toByteData(
        format: ImageByteFormat.rawRgba,
      );
      expect(sourcePixels, isNotNull);
      final contactDistances = <double>[];
      for (var frame = 0; frame < 8 * 30; frame += 3) {
        final snapshot = buildTimelineSnapshot(
          strokes: project.strokes,
          artworkRect: const Rect.fromLTWH(0, 0, 1800, 1000),
          progress: frame / (8 * 30),
          durationSeconds: 8,
          drawingDurationSeconds: 8,
          startDelaySeconds: 0,
          endHoldSeconds: 0,
        );
        final cursor = snapshot.cursor;
        if (!snapshot.penIsDrawing || cursor == null) continue;
        contactDistances.add(
          _distanceToVisiblePixel(
            sourcePixels!.buffer.asUint8List(),
            width: drawing.image.width,
            height: drawing.image.height,
            point: Offset(
              cursor.worldPenPoint.dx * drawing.image.width / 1800,
              cursor.worldPenPoint.dy * drawing.image.height / 1000,
            ),
            searchRadius: 24,
          ),
        );
      }
      expect(contactDistances, isNotEmpty);
      final maximumContactDistance = contactDistances.reduce(math.max);
      expect(
        maximumContactDistance,
        lessThanOrEqualTo(12),
        reason:
            'The resolved cursor must stay on visible dependency artwork; '
            'measured distances=$contactDistances',
      );
      final output = Directory('build/visual_e2e_step7c4')
        ..createSync(recursive: true);
      const generateMovieFrames = bool.fromEnvironment(
        'HANDDRAW_GENERATE_VISUAL_E2E',
      );
      final framesPerSecond = project.frameRate;
      final expectedFrameCount = (project.durationSeconds * framesPerSecond)
          .round();
      final sampleTimes = generateMovieFrames
          ? [
              for (var frame = 0; frame < expectedFrameCount; frame++)
                frame / framesPerSecond,
            ]
          : [0.0, 3.0, 6.0, 7.9];
      for (var frameIndex = 0; frameIndex < sampleTimes.length; frameIndex++) {
        final seconds = sampleTimes[frameIndex];
        final us = (seconds * 1000000).round();
        final shot = plan.proposedShots.lastWhere(
          (value) => value.interval.start.microseconds <= us,
          orElse: () => plan.proposedShots.first,
        );
        final image = await const FrameRenderer().renderResolved(
          frame: ResolvedProjectFrame(
            time: TimelineTime.fromMicroseconds(us),
            drawing: ResolvedDrawingFrame(
              localTime: TimelineTime.fromMicroseconds(us),
              duration: TimelineDuration.fromMicroseconds(8000000),
              sectionId: null,
              isHeld: false,
            ),
            camera: ResolvedSingleCameraView(shot.keyframes.last.view),
            activeAudio: const [],
            voiceGuide: null,
            markers: const [],
            isFinalFrame: seconds == 7.9,
          ),
          project: project,
          drawing: drawing.image,
          drawingRevealBase: drawing.revealBaseImage,
          svgRevealLayers: drawing.svgRevealLayers,
          hand: hand.image,
          target: const RenderTarget.opaque(Color(0xFFFFFFFF)),
        );
        final png = await image.toByteData(format: ImageByteFormat.png);
        final bytes = png!.buffer.asUint8List();
        if (generateMovieFrames) {
          File(
            '${output.path}/movie-${frameIndex.toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(bytes);
        }
        if (!generateMovieFrames ||
            {
              0,
              3 * framesPerSecond,
              6 * framesPerSecond,
              expectedFrameCount - 1,
            }.contains(frameIndex)) {
          File(
            '${output.path}/after-${seconds.toStringAsFixed(1)}s.png',
          ).writeAsBytesSync(bytes);
        }
        image.dispose();
      }
    },
  );
}

double _distanceToVisiblePixel(
  List<int> rgba, {
  required int width,
  required int height,
  required Offset point,
  required int searchRadius,
}) {
  var nearest = double.infinity;
  final centerX = point.dx.round();
  final centerY = point.dy.round();
  for (var y = centerY - searchRadius; y <= centerY + searchRadius; y++) {
    if (y < 0 || y >= height) continue;
    for (var x = centerX - searchRadius; x <= centerX + searchRadius; x++) {
      if (x < 0 || x >= width) continue;
      final alpha = rgba[(y * width + x) * 4 + 3];
      if (alpha < 96) continue;
      nearest = math.min(
        nearest,
        (Offset(x.toDouble(), y.toDouble()) - point).distance,
      );
    }
  }
  return nearest;
}
