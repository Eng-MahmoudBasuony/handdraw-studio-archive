import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';

void main() {
  test(
    'Preview compositor and offline export produce identical pixels',
    () async {
      final sourceRecorder = ui.PictureRecorder();
      ui.Canvas(sourceRecorder).drawRect(
        const ui.Rect.fromLTWH(0, 0, 100, 100),
        ui.Paint()..color = const ui.Color(0xFF2474E8),
      );
      final sourcePicture = sourceRecorder.endRecording();
      final source = await sourcePicture.toImage(100, 100);
      sourcePicture.dispose();
      final project = HandDrawProject(
        canvasWidth: 100,
        canvasHeight: 100,
        durationSeconds: 4,
        drawingDurationSeconds: 4,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
        revealWidth: 24,
        strokes: [
          DrawingStroke(
            id: 'curve',
            name: 'Curve',
            geometry: StrokePathGeometry(
              start: const ui.Offset(0.1, 0.5),
              segments: const [
                StrokeCubicSegment(
                  control1: ui.Offset(0.3, 0.1),
                  control2: ui.Offset(0.7, 0.9),
                  end: ui.Offset(0.9, 0.5),
                ),
              ],
            ),
            vectorMaskStrokes: [
              VectorMaskStroke(
                geometry: StrokePathGeometry(
                  start: const ui.Offset(0.45, 0.2),
                  segments: const [
                    StrokeLineSegment(end: ui.Offset(0.45, 0.8)),
                  ],
                ),
                widthFraction: 0.08,
                featherFraction: 0.01,
                operation: VectorMaskOperation.erase,
              ),
            ],
          ),
        ],
      );

      const progress = 0.5;
      final exported = await const FrameRenderer().renderResolved(
        frame: ResolvedProjectFrame(
          time: TimelineTime.fromMicroseconds(2000000),
          drawing: ResolvedDrawingFrame(
            localTime: TimelineTime.fromMicroseconds(2000000),
            duration: TimelineDuration.fromMicroseconds(4000000),
            sectionId: null,
            isHeld: false,
          ),
          camera: const ResolvedSingleCameraView(CameraView.identity()),
          activeAudio: const [],
          voiceGuide: null,
          markers: const [],
          isFinalFrame: false,
        ),
        project: project,
        drawing: source,
        hand: null,
      );
      final previewRecorder = ui.PictureRecorder();
      final previewCanvas = ui.Canvas(previewRecorder);
      final snapshot = buildTimelineSnapshot(
        strokes: project.strokes,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        progress: progress,
        durationSeconds: project.durationSeconds,
        drawingDurationSeconds: project.drawingDurationSeconds,
        startDelaySeconds: project.startDelaySeconds,
        endHoldSeconds: project.endHoldSeconds,
        sectionTimings: project.sectionTimings,
        timingRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
      );
      drawRevealedArtwork(
        canvas: previewCanvas,
        image: source,
        artworkRect: const ui.Rect.fromLTWH(0, 0, 100, 100),
        snapshot: snapshot,
        defaultRevealWidth: project.revealWidth,
      );
      final previewPicture = previewRecorder.endRecording();
      final preview = await previewPicture.toImage(100, 100);
      previewPicture.dispose();

      final previewPixels = await _rgba(preview);
      final exportPixels = await _rgba(exported);
      expect(exportPixels, previewPixels);

      preview.dispose();
      exported.dispose();
      source.dispose();
    },
  );
}

Future<Uint8List> _rgba(ui.Image image) async => (await image.toByteData(
  format: ui.ImageByteFormat.rawRgba,
))!.buffer.asUint8List();
