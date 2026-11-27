import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SVG-style reveals remain stable at 25, 50, and 100 percent', () async {
    final source = await _sourceArtwork();
    final project = HandDrawProject(
      canvasWidth: 320,
      canvasHeight: 180,
      durationSeconds: 2,
      startDelaySeconds: 0,
      endHoldSeconds: 0,
      strokes: [
        DrawingStroke(
          id: 'card',
          name: 'Rounded card',
          geometry: StrokePathGeometry(
            start: const ui.Offset(0.15, 0.25),
            segments: const [
              StrokeLineSegment(end: ui.Offset(0.85, 0.25)),
              StrokeLineSegment(end: ui.Offset(0.85, 0.75)),
              StrokeLineSegment(end: ui.Offset(0.15, 0.75)),
            ],
            closed: true,
          ),
          animationGeometry: StrokePathGeometry(
            start: const ui.Offset(0.15, 0.5),
            segments: const [StrokeLineSegment(end: ui.Offset(0.85, 0.5))],
          ),
          isFilledShape: true,
          fillColorValue: 0xFF2F6FED,
          revealStyle: RevealMaskStyle.directionalWipe,
          clipBounds: const ui.Rect.fromLTWH(0.15, 0.25, 0.7, 0.5),
          exclusionBounds: const [ui.Rect.fromLTWH(0.31, 0.42, 0.38, 0.16)],
          revealWidth: 94,
        ),
        DrawingStroke(
          id: 'label',
          name: 'Native SVG text',
          geometry: StrokePathGeometry(
            start: const ui.Offset(0.31, 0.5),
            segments: const [StrokeLineSegment(end: ui.Offset(0.69, 0.5))],
          ),
          isTextShape: true,
          revealStyle: RevealMaskStyle.directionalWipe,
          clipBounds: const ui.Rect.fromLTWH(0.31, 0.42, 0.38, 0.16),
          revealWidth: 34,
        ),
      ],
    );
    const renderer = FrameRenderer();
    for (final progress in const [0.25, 0.5, 1.0]) {
      final frame = await renderer.render(
        project: project,
        drawing: source,
        hand: null,
        progress: progress,
      );
      final suffix = (progress * 100).round();
      await expectLater(
        frame,
        matchesGoldenFile('goldens/svg_reveal_$suffix.png'),
      );
      frame.dispose();
    }
    source.dispose();
  });
}

Future<ui.Image> _sourceArtwork() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(48, 45, 224, 90),
      const ui.Radius.circular(18),
    ),
    ui.Paint()..color = const ui.Color(0xFF2F6FED),
  );
  final builder = ui.ParagraphBuilder(
    ui.ParagraphStyle(textAlign: ui.TextAlign.center),
  )..pushStyle(ui.TextStyle(color: const ui.Color(0xFFFFFFFF), fontSize: 24));
  builder.addText('Native SVG');
  final laidOut = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 160));
  canvas.drawParagraph(laidOut, const ui.Offset(80, 75));
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 180);
  picture.dispose();
  return image;
}
