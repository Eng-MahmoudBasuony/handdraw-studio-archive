import 'package:handdraw_studio/features/drawing_engine/domain/image_animation_render_policy.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:handdraw_studio/features/drawing_engine/presentation/painters/hand_image_painter.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_resolved_drawing_frame_adapter.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_visual_compositor.dart';
import 'package:handdraw_studio/features/camera/domain/policies/hand_display_policy.dart';
import 'package:handdraw_studio/features/camera/presentation/hand_display_transform.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/canvas_background/presentation/canvas_background_renderer.dart';

final class RenderTarget {
  const RenderTarget.transparent() : background = null;
  const RenderTarget.opaque(this.background);
  final Color? background;
}

class FrameRenderer {
  const FrameRenderer({
    this.revealSourceAtCompletion = true,
    this.showPenLifts = false,
    this.rasterFilterQuality = FilterQuality.high,
  });

  /// Experiments may require authored coverage even at the terminal frame.
  /// Legacy projects retain their established completion behavior by default.
  final bool revealSourceAtCompletion;
  final bool showPenLifts;
  final FilterQuality rasterFilterQuality;

  Future<Image> render({
    required HandDrawProject project,
    required Image drawing,
    Image? drawingRevealBase,
    SvgRevealLayers? svgRevealLayers,
    required Image? hand,
    required double progress,
  }) async {
    final size = Size(
      project.canvasWidth.toDouble(),
      project.canvasHeight.toDouble(),
    );
    final artworkRect = _artworkRect(project, drawing, size);
    final snapshot = buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: artworkRect,
      progress: progress,
      durationSeconds: project.durationSeconds,
      drawingDurationSeconds: project.drawingDurationSeconds,
      drawingSpeed: project.drawingSpeed,
      penTravelSpeed: project.penTravelSpeed,
      startDelaySeconds: project.startDelaySeconds,
      endHoldSeconds: project.endHoldSeconds,
      sectionTimings: project.sectionTimings,
      timingRect: Offset.zero & size,
    );

    return _renderSnapshot(
      project: project,
      drawing: drawing,
      drawingRevealBase: drawingRevealBase,
      svgRevealLayers: svgRevealLayers,
      hand: hand,
      snapshot: snapshot,
      target: const RenderTarget.transparent(),
      camera: const ResolvedSingleCameraView(CameraView.identity()),
    );
  }

  Future<Image> renderResolved({
    required ResolvedProjectFrame frame,
    required HandDrawProject project,
    required Image drawing,
    Image? drawingRevealBase,
    SvgRevealLayers? svgRevealLayers,
    required Image? hand,
    RenderTarget target = const RenderTarget.transparent(),
  }) async {
    final drawingFrame = frame.drawing;
    final size = Size(
      project.canvasWidth.toDouble(),
      project.canvasHeight.toDouble(),
    );
    final artworkRect = _artworkRect(project, drawing, size);
    final snapshot = const LegacyResolvedDrawingFrameAdapter()
        .resolveOrStaticArtwork(
          project: project,
          frame: drawingFrame,
          artworkRect: artworkRect,
          timingRect: Offset.zero & size,
        );
    return _renderSnapshot(
      project: project,
      drawing: drawing,
      drawingRevealBase: drawingRevealBase,
      svgRevealLayers: svgRevealLayers,
      hand: hand,
      snapshot: snapshot,
      target: target,
      camera: frame.camera,
    );
  }

  Future<Image> _renderSnapshot({
    required HandDrawProject project,
    required Image drawing,
    required Image? drawingRevealBase,
    required SvgRevealLayers? svgRevealLayers,
    required Image? hand,
    required TimelineSnapshot snapshot,
    required RenderTarget target,
    required ResolvedCameraState camera,
  }) async {
    final size = Size(
      project.canvasWidth.toDouble(),
      project.canvasHeight.toDouble(),
    );
    final artworkRect = _artworkRect(project, drawing, size);
    final revealAtCompletion =
        revealSourceAtCompletion &&
        !ImageAnimationRenderPolicy.authored(project);
    if (!snapshot.drawingComplete || !revealAtCompletion) {
      await prewarmRevealedArtwork(
        artworkRect: artworkRect,
        snapshot: snapshot,
        defaultRevealWidth: project.revealWidth,
        svgRevealLayers: svgRevealLayers,
        hasRevealBaseImage: drawingRevealBase != null,
      );
    }
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final background = target.background;
    if (background != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = background);
    }
    const CameraVisualCompositor().paint(
      canvas: canvas,
      outputSize: size,
      projectSize: size,
      camera: camera,
      paintScene: (sceneCanvas, transform) {
        sceneCanvas.save();
        transform.apply(sceneCanvas);
        const CanvasBackgroundRenderer().paint(
          canvas: sceneCanvas,
          rect: Offset.zero & size,
          background: project.canvasBackground,
        );
        if (snapshot.drawingComplete && revealAtCompletion) {
          _drawSourceImage(sceneCanvas, drawing, artworkRect);
        } else {
          drawRevealedArtwork(
            canvas: sceneCanvas,
            image: drawing,
            revealBaseImage: drawingRevealBase,
            svgRevealLayers: svgRevealLayers,
            artworkRect: artworkRect,
            snapshot: snapshot,
            defaultRevealWidth: project.revealWidth,
            rasterFilterQuality: ImageAnimationRenderPolicy.authored(project)
                ? FilterQuality.none
                : rasterFilterQuality,
          );
        }
        sceneCanvas.restore();
        if (hand != null &&
            ImageAnimationRenderPolicy.handVisible(
              project,
              snapshot,
              forceLift: showPenLifts,
            )) {
          _drawHand(
            canvas: sceneCanvas,
            hand: hand,
            snapshot: snapshot,
            canvasSize: size,
            project: project,
            handPosition: transform.transformPoint(
              ImageAnimationRenderPolicy.penPosition(
                project,
                snapshot,
                size.height,
                forceLift: showPenLifts,
              ),
            ),
          );
        }
      },
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      project.canvasWidth,
      project.canvasHeight,
    );
    picture.dispose();
    return image;
  }

  void _drawSourceImage(Canvas canvas, Image image, Rect artworkRect) {
    if (artworkRect.left == 0 &&
        artworkRect.top == 0 &&
        artworkRect.width == image.width &&
        artworkRect.height == image.height) {
      canvas.drawImage(image, Offset.zero, Paint());
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      artworkRect,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high,
    );
  }

  void _drawHand({
    required Canvas canvas,
    required Image hand,
    required TimelineSnapshot snapshot,
    required Size canvasSize,
    required HandDrawProject project,
    required Offset handPosition,
  }) {
    final layout = const HandDisplayPolicy().resolve(
      outputWidth: canvasSize.width,
      outputHeight: canvasSize.height,
      imageWidth: hand.width.toDouble(),
      imageHeight: hand.height.toDouble(),
      preferredHeightFraction: project.handScale,
      penTipX: project.penTip.dx,
      penTipY: project.penTip.dy,
      flipX: project.handFlipX,
    );
    final width = layout.width;
    final height = layout.height;
    final handTransform = HandDisplayTransform(
      layout: layout,
      projectedPathPoint: handPosition,
      rotationRadians:
          ImageAnimationRenderPolicy.handAngle(project, snapshot) +
          project.handRotationDegrees * math.pi / 180,
      flipX: project.handFlipX,
    );
    final source = Rect.fromLTWH(
      0,
      0,
      hand.width.toDouble(),
      hand.height.toDouble(),
    );
    final destination = Rect.fromLTWH(0, 0, width, height);
    canvas.save();
    handTransform.apply(canvas);
    drawFeatheredHandImage(
      canvas: canvas,
      image: hand,
      source: source,
      destination: destination,
      opacity: snapshot.handOpacity,
      armExit: handArmExitForProject(
        presetId: project.handPresetId,
        imagePath: project.handImagePath,
      ),
    );
    canvas.restore();
  }
}

Rect _fitRect(Image image, Size canvasSize) {
  final imageRatio = image.width / image.height;
  final canvasRatio = canvasSize.width / canvasSize.height;
  if (imageRatio > canvasRatio) {
    final height = canvasSize.width / imageRatio;
    return Rect.fromLTWH(
      0,
      (canvasSize.height - height) / 2,
      canvasSize.width,
      height,
    );
  }
  final width = canvasSize.height * imageRatio;
  return Rect.fromLTWH(
    (canvasSize.width - width) / 2,
    0,
    width,
    canvasSize.height,
  );
}

Rect _artworkRect(HandDrawProject project, Image image, Size canvasSize) {
  final destination = project.artworkDestination;
  if (destination == null) return _fitRect(image, canvasSize);
  return Rect.fromLTRB(
    destination.left / project.canvasWidth * canvasSize.width,
    destination.top / project.canvasHeight * canvasSize.height,
    destination.right / project.canvasWidth * canvasSize.width,
    destination.bottom / project.canvasHeight * canvasSize.height,
  );
}
