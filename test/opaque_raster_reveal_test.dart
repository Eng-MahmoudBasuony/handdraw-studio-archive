import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/opaque_raster_reveal_planner.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';

import 'support/legacy_editor_state_fixture.dart';

class _RecordingArtworkPathFacade implements ArtworkPathFacade {
  int calls = 0;

  @override
  Future<ArtworkPathResult> analyze(ArtworkPathRequest request) async {
    calls++;
    return ArtworkPathResult(analysis: const SmartPathAnalysis(sections: []));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('opaque raster planner creates one clipped diagonal reveal sweep', () {
    final strokes = const OpaqueRasterRevealPlanner().build(
      project: HandDrawProject(canvasWidth: 1920, canvasHeight: 1080),
    );

    expect(strokes, hasLength(1));
    expect(strokes.single.name, 'Opaque Artwork • Diagonal Reveal');
    expect(strokes.single.points.length, inInclusiveRange(10, 16));
    expect(strokes.every((stroke) => stroke.revealOnly), isTrue);
    expect(
      strokes.every((stroke) => stroke.revealStyle == RevealMaskStyle.brush),
      isTrue,
    );
    expect(
      strokes.every(
        (stroke) => stroke.clipBounds == const ui.Rect.fromLTWH(0, 0, 1, 1),
      ),
      isTrue,
    );
    expect(strokes.single.points.first.dx, 0);
    expect(strokes.single.points.first.dy, greaterThan(0));
    expect(strokes.single.points.first.dy, lessThan(0.1));
    expect(strokes.single.points[1].dx, 1);
    expect(
      strokes.single.points[1].dy - strokes.single.points.first.dy,
      greaterThanOrEqualTo(0.15),
      reason: 'Diagonal reveal uses clearly diagonal strokes.',
    );
    expect(strokes.single.points[2].dx, 1);
    expect(strokes.single.points[3].dx, 0);
    expect(
      strokes.single.points[2].dy - strokes.single.points[3].dy,
      greaterThanOrEqualTo(0.15),
    );
    expect(
      strokes.first.points.last.dy,
      greaterThan(strokes.first.points.first.dy),
    );
    final snapshot = buildTimelineSnapshot(
      strokes: strokes,
      artworkRect: const ui.Rect.fromLTWH(0, 0, 1920, 1080),
      progress: 0.5,
    );
    expect(snapshot.handVisible, isTrue);
    for (var step = 1; step < 20; step++) {
      final sampled = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 1920, 1080),
        progress: step / 20,
      );
      if (!sampled.handVisible) continue;
      expect(sampled.handPosition.dy, inInclusiveRange(0, 1080));
    }
  });

  test('opaque raster skips OCR and selects smart region reveal', () async {
    final asset = await _rasterAsset(opaque: true);
    final facade = _RecordingArtworkPathFacade();
    final cubit = EditorCubit(
      artworkPathFacade: facade,
      initialState: testEditorState(
        project: HandDrawProject(
          drawingImagePath: '/tmp/opaque.png',
          drawingImageBase64: asset.encoded,
          drawingSourceBase64: asset.encoded,
          drawingSourceKind: ArtworkSourceKind.raster,
        ),
        drawingImage: asset.image,
      ),
    );
    addTearDown(() async {
      await cubit.close();
      asset.image.dispose();
    });

    await cubit.createAutoReveal();

    expect(facade.calls, 0);
    expect(cubit.project.strokes.length, greaterThan(1));
    expect(
      cubit.project.strokes,
      everyElement(
        isA<DrawingStroke>().having(
          (stroke) => stroke.id,
          'smart region id',
          startsWith('auto-smart-region-'),
        ),
      ),
    );
    expect(cubit.project.strokes.map((stroke) => stroke.sectionId).toSet(), {
      'auto-smart-region-reveal',
    }, reason: 'The timeline presents one coherent reveal clip.');
    expect(cubit.project.startDelaySeconds, 0);
    expect(cubit.project.endHoldSeconds, closeTo(3.99, .0001));
    final timing =
        cubit.project.sectionTimings['section:auto-smart-region-reveal'];
    expect(timing?.animationDurationSeconds, isNotNull);
    expect(timing?.handExitAnimation, SectionHandExitAnimation.moveOut);
    expect(timing?.handExitDurationSeconds, closeTo(.42, .0001));
  });

  test(
    'alpha-bearing raster preserves the existing Auto Reveal route',
    () async {
      final asset = await _rasterAsset(opaque: false);
      final facade = _RecordingArtworkPathFacade();
      final cubit = EditorCubit(
        artworkPathFacade: facade,
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/transparent.png',
            drawingImageBase64: asset.encoded,
            drawingSourceBase64: asset.encoded,
            drawingSourceKind: ArtworkSourceKind.raster,
          ),
          drawingImage: asset.image,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        asset.image.dispose();
      });

      await cubit.createAutoReveal();

      expect(facade.calls, 1);
      expect(
        cubit.project.strokes.any(
          (stroke) => stroke.id.startsWith('auto-opaque-reveal-'),
        ),
        isFalse,
      );
      expect(
        cubit.project.strokes.single.revealStyle,
        RevealMaskStyle.directionalWipe,
      );
    },
  );

  test('diagonal sweep progresses and fully restores opaque pixels', () async {
    final asset = await _rasterAsset(opaque: true, size: 160);
    final baseProject = HandDrawProject(
      canvasWidth: 160,
      canvasHeight: 160,
      durationSeconds: 2,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );
    final strokes = const OpaqueRasterRevealPlanner().build(
      project: baseProject,
    );
    final project = baseProject.copyWith(strokes: strokes);
    const renderer = FrameRenderer();
    final start = await renderer.render(
      project: project,
      drawing: asset.image,
      hand: null,
      progress: 0,
    );
    final middle = await renderer.render(
      project: project,
      drawing: asset.image,
      hand: null,
      progress: 0.5,
    );
    final end = await renderer.render(
      project: project,
      drawing: asset.image,
      hand: null,
      progress: 1,
    );

    final startVisible = await _visiblePixelCount(start);
    final middleVisible = await _visiblePixelCount(middle);
    final endVisible = await _visiblePixelCount(end);
    expect(startVisible, 0);
    expect(middleVisible, greaterThan(0));
    expect(middleVisible, lessThan(endVisible));
    expect(endVisible, 160 * 160);

    start.dispose();
    middle.dispose();
    end.dispose();
    asset.image.dispose();
  });

  test('opaque raster reveal has a clear diagonal boundary golden', () async {
    final asset = await _rasterAsset(opaque: true, size: 320);
    final baseProject = HandDrawProject(
      canvasWidth: 320,
      canvasHeight: 320,
      durationSeconds: 2,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
    );
    final project = baseProject.copyWith(
      strokes: const OpaqueRasterRevealPlanner().build(project: baseProject),
    );
    final frame = await const FrameRenderer().render(
      project: project,
      drawing: asset.image,
      hand: null,
      progress: 0.18,
    );

    await expectLater(
      frame,
      matchesGoldenFile('goldens/opaque_raster_diagonal_reveal_18.png'),
    );

    frame.dispose();
    asset.image.dispose();
  });
}

Future<({ui.Image image, String encoded})> _rasterAsset({
  required bool opaque,
  int size = 64,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  if (opaque) {
    canvas.drawColor(const ui.Color(0xFF2D67C7), ui.BlendMode.src);
    canvas.drawCircle(
      ui.Offset(size * 0.28, size * 0.3),
      size * 0.16,
      ui.Paint()..color = const ui.Color(0xFFFFC043),
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(size * 0.5, size * 0.18, size * 0.32, size * 0.56),
        ui.Radius.circular(size * 0.05),
      ),
      ui.Paint()..color = const ui.Color(0xFFE94F64),
    );
  } else {
    canvas.drawRect(
      ui.Rect.fromLTWH(size * 0.25, size * 0.25, size * 0.5, size * 0.5),
      ui.Paint()..color = const ui.Color(0xFF2D67C7),
    );
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(size, size);
  picture.dispose();
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return (image: image, encoded: base64Encode(data!.buffer.asUint8List()));
}

Future<int> _visiblePixelCount(ui.Image image) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = data!.buffer.asUint8List();
  var count = 0;
  for (var index = 3; index < bytes.length; index += 4) {
    if (bytes[index] > 0) count++;
  }
  return count;
}
