import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

class _DependencyHellTextDetector implements TextLayoutDetector {
  const _DependencyHellTextDetector();

  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) async => const [
    SmartTextRegion(
      text: 'DEPENDENCY HELL',
      bounds: Rect.fromLTWH(0.21, 0.075, 0.58, 0.08),
      confidence: 1,
    ),
    SmartTextRegion(
      text: 'When one package update breaks the whole project',
      bounds: Rect.fromLTWH(0.23, 0.205, 0.55, 0.04),
      confidence: 1,
    ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('real Dependency Hell cursor stays on visible artwork', () async {
    final drawing = await const EditorFileService().loadImage(
      'test/fixtures/00-title.png',
    );
    final hand = await const EditorFileService().loadImage(
      'assets/hands/technical-pen-wheat-right-v1.png',
    );
    addTearDown(drawing.image.dispose);
    addTearDown(hand.image.dispose);
    final bytes = await File('test/fixtures/00-title.png').readAsBytes();
    final analysis = await const SmartPathEngine(
      textDetector: _DependencyHellTextDetector(),
    ).analyze(image: drawing.image, encodedImage: bytes);
    final strokes = const AutoPathStrokePlanner()
        .build(
          sections: analysis.sections,
          project: HandDrawProject(canvasWidth: 1920, canvasHeight: 1080),
        )
        .strokes;
    final project = HandDrawProject(
      canvasWidth: 1920,
      canvasHeight: 1080,
      frameRate: 30,
      durationSeconds: 8,
      drawingDurationSeconds: 8,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      handScale: .24,
      penTip: BuiltInHands.wheatTechnicalPenRight.penTip,
      strokes: strokes,
    );
    final pixels = await drawing.image.toByteData(
      format: ImageByteFormat.rawRgba,
    );
    expect(pixels, isNotNull);
    var underlineStart = 1.0;
    for (var sample = 0; sample <= 2000; sample++) {
      final progress = sample / 2000;
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 1920, 1080),
        progress: progress,
        durationSeconds: 8,
        drawingDurationSeconds: 8,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      if (snapshot.cursor?.sectionId == 'shape-0') {
        underlineStart = progress;
        break;
      }
    }
    expect(underlineStart, lessThan(1));
    final titleFrame = await const FrameRenderer().render(
      project: project,
      drawing: drawing.image,
      hand: null,
      progress: math.max(0, underlineStart - 0.0005),
    );
    addTearDown(titleFrame.dispose);
    final titlePixels = await titleFrame.toByteData(
      format: ImageByteFormat.rawRgba,
    );
    expect(titlePixels, isNotNull);
    expect(
      _bluePixelCount(
        titlePixels!.buffer.asUint8List(),
        width: 1920,
        left: 350,
        top: 170,
        right: 1500,
        bottom: 220,
      ),
      0,
      reason:
          'The blue underline must stay completely hidden through the final '
          'title frame and its travel phase.',
    );
    var subtitleStart = 1.0;
    for (var sample = 0; sample <= 4000; sample++) {
      final progress = sample / 4000;
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 1920, 1080),
        progress: progress,
        durationSeconds: 8,
        drawingDurationSeconds: 8,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      if (snapshot.cursor?.sectionId == 'text-1') {
        subtitleStart = progress;
        break;
      }
    }
    expect(subtitleStart, lessThan(1));
    final completedUnderlineFrame = await const FrameRenderer().render(
      project: project,
      drawing: drawing.image,
      hand: null,
      progress: subtitleStart,
    );
    addTearDown(completedUnderlineFrame.dispose);
    final completedUnderlinePixels = await completedUnderlineFrame.toByteData(
      format: ImageByteFormat.rawRgba,
    );
    expect(completedUnderlinePixels, isNotNull);
    final completedProjectFrame = await const FrameRenderer().render(
      project: project,
      drawing: drawing.image,
      hand: null,
      progress: 1,
    );
    addTearDown(completedProjectFrame.dispose);
    final completedProjectPixels = await completedProjectFrame.toByteData(
      format: ImageByteFormat.rawRgba,
    );
    expect(completedProjectPixels, isNotNull);
    final sourceBluePixels = _bluePixelCount(
      completedProjectPixels!.buffer.asUint8List(),
      width: 1920,
      left: 350,
      top: 150,
      right: 1500,
      bottom: 230,
    );
    final revealedBluePixels = _bluePixelCount(
      completedUnderlinePixels!.buffer.asUint8List(),
      width: 1920,
      left: 350,
      top: 150,
      right: 1500,
      bottom: 230,
    );
    expect(
      revealedBluePixels / sourceBluePixels,
      greaterThanOrEqualTo(0.98),
      reason:
          'Both underline strokes must be fully visible before the subtitle '
          'starts, without relying on the final full-image frame.',
    );
    final distances = <double>[];
    final output = Directory('build/p0_real_pen_contact')
      ..createSync(recursive: true);
    const generate = bool.fromEnvironment('HANDDRAW_GENERATE_VISUAL_E2E');
    for (var frame = 0; frame < 240; frame++) {
      final snapshot = buildTimelineSnapshot(
        strokes: strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 1920, 1080),
        progress: frame / 240,
        durationSeconds: 8,
        drawingDurationSeconds: 8,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      if (frame % 3 == 0 && snapshot.penIsDrawing && snapshot.cursor != null) {
        distances.add(
          _distanceToInk(
            pixels!.buffer.asUint8List(),
            width: 1920,
            height: 1080,
            point: snapshot.cursor!.worldPenPoint,
            radius: 20,
          ),
        );
      }
      if (!generate && !{30, 90, 150, 210}.contains(frame)) continue;
      final time = TimelineTime.fromMicroseconds(
        (frame * 1000000 / 30).round(),
      );
      final image = await const FrameRenderer().renderResolved(
        frame: ResolvedProjectFrame(
          time: time,
          drawing: ResolvedDrawingFrame(
            localTime: time,
            duration: TimelineDuration.fromMicroseconds(8000000),
            sectionId: snapshot.cursor?.sectionId == null
                ? null
                : SectionId(snapshot.cursor!.sectionId!),
            isHeld: false,
          ),
          camera: const ResolvedSingleCameraView(CameraView.identity()),
          activeAudio: const [],
          voiceGuide: null,
          markers: const [],
          isFinalFrame: frame == 239,
        ),
        project: project,
        drawing: drawing.image,
        hand: hand.image,
        target: const RenderTarget.opaque(Color(0xFFFFFFFF)),
      );
      final png = await image.toByteData(format: ImageByteFormat.png);
      File(
        '${output.path}/frame-${frame.toString().padLeft(4, '0')}.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    }
    expect(distances, isNotEmpty);
    final maximumDistance = distances.reduce(math.max);
    // Printed as acceptance evidence alongside the generated frames/MOV.
    // ignore: avoid_print
    print(
      'real Dependency Hell pen contact: samples=${distances.length} '
      'max=${maximumDistance.toStringAsFixed(3)}px',
    );
    expect(
      maximumDistance,
      lessThanOrEqualTo(3),
      reason: 'Actual cursor must touch non-background Dependency Hell pixels.',
    );
  });
}

int _bluePixelCount(
  List<int> rgba, {
  required int width,
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  var count = 0;
  for (var y = top; y < bottom; y++) {
    for (var x = left; x < right; x++) {
      final offset = (y * width + x) * 4;
      final red = rgba[offset];
      final green = rgba[offset + 1];
      final blue = rgba[offset + 2];
      if (rgba[offset + 3] > 96 && blue > red + 80 && blue > green + 50) {
        count++;
      }
    }
  }
  return count;
}

double _distanceToInk(
  List<int> rgba, {
  required int width,
  required int height,
  required Offset point,
  required int radius,
}) {
  var nearest = double.infinity;
  for (var y = point.dy.round() - radius; y <= point.dy.round() + radius; y++) {
    if (y < 0 || y >= height) continue;
    for (
      var x = point.dx.round() - radius;
      x <= point.dx.round() + radius;
      x++
    ) {
      if (x < 0 || x >= width) continue;
      final offset = (y * width + x) * 4;
      final isInk =
          rgba[offset + 3] > 96 &&
          (rgba[offset] < 245 ||
              rgba[offset + 1] < 245 ||
              rgba[offset + 2] < 245);
      if (!isInk) continue;
      nearest = math.min(
        nearest,
        (Offset(x.toDouble(), y.toDouble()) - point).distance,
      );
    }
  }
  return nearest;
}
