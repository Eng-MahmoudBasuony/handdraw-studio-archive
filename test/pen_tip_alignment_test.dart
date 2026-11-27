import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/policies/hand_display_policy.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_visual_compositor.dart';
import 'package:handdraw_studio/features/camera/presentation/hand_display_transform.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';

void main() {
  const policy = HandDisplayPolicy();
  const project = Size(1920, 1080);

  for (final outputHeight in [720.0, 1080.0, 2160.0]) {
    for (final flip in [false, true]) {
      test(
        'pen tip aligns at ${outputHeight.toInt()}p flip=$flip across camera transforms',
        () {
          final output = Size(outputHeight * 16 / 9, outputHeight);
          for (final view in const [
            CameraView.identity(),
            CameraView(centerX: .25, centerY: .7, viewportWidth: .35),
            CameraView(centerX: 1.1, centerY: -.2, viewportWidth: 1.6),
          ]) {
            final camera = CameraCanvasTransform.forView(
              view: view,
              projectSize: project,
              outputSize: output,
            );
            for (final worldPoint in const [
              Offset(0, 0),
              Offset(960, 540),
              Offset(1900, 1060),
            ]) {
              final projected = camera.transformPoint(worldPoint);
              final layout = policy.resolve(
                outputWidth: output.width,
                outputHeight: output.height,
                imageWidth: 900,
                imageHeight: 1200,
                preferredHeightFraction: .24,
                penTipX: BuiltInHands.wheatTechnicalPenRight.penTip.dx,
                penTipY: BuiltInHands.wheatTechnicalPenRight.penTip.dy,
                flipX: flip,
              );
              for (final angle in [0.0, math.pi / 3, -math.pi * .8]) {
                final transform = HandDisplayTransform(
                  layout: layout,
                  projectedPathPoint: projected,
                  rotationRadians: angle,
                  flipX: flip,
                );
                expect(
                  (transform.displayedPenTip - projected).distance,
                  lessThanOrEqualTo(.01),
                );
              }
            }
          }
        },
      );
    }
  }

  test(
    'retina scale changes physical pixels but not logical pen alignment',
    () {
      const logicalPoint = Offset(321.25, 210.5);
      for (final devicePixelRatio in [1.0, 2.0, 3.0]) {
        final layout = policy.resolve(
          outputWidth: 1920 * devicePixelRatio,
          outputHeight: 1080 * devicePixelRatio,
          imageWidth: 900,
          imageHeight: 1200,
          preferredHeightFraction: .24,
          penTipX: BuiltInHands.wheatTechnicalPenRight.penTip.dx,
          penTipY: BuiltInHands.wheatTechnicalPenRight.penTip.dy,
        );
        final physicalPoint = logicalPoint * devicePixelRatio;
        final transform = HandDisplayTransform(
          layout: layout,
          projectedPathPoint: physicalPoint,
          rotationRadians: .7,
          flipX: false,
        );
        expect(
          (transform.displayedPenTip - physicalPoint).distance,
          lessThanOrEqualTo(.01),
        );
      }
    },
  );

  test('every bundled hand projects its real source anchor at every size', () {
    const contact = Offset(734.25, 418.75);
    for (final preset in BuiltInHands.all) {
      for (final scale in {.06, preset.defaultScale, .9}) {
        for (final flip in {preset.flipX, !preset.flipX}) {
          final layout = policy.resolve(
            outputWidth: 1920,
            outputHeight: 1080,
            imageWidth: 1536,
            imageHeight: 1024,
            preferredHeightFraction: scale,
            penTipX: preset.penTip.dx,
            penTipY: preset.penTip.dy,
            flipX: flip,
          );
          for (final rotation in [0.0, math.pi / 3, -math.pi * .8]) {
            final transform = HandDisplayTransform(
              layout: layout,
              projectedPathPoint: contact,
              rotationRadians: rotation,
              flipX: flip,
            );
            expect(
              transform.projectSourcePoint(transform.sourcePenAnchor),
              closeToOffset(contact, .000001),
              reason: '${preset.id} scale=$scale flip=$flip rotation=$rotation',
            );
            expect(
              transform.displayedPenTip,
              closeToOffset(contact, .000001),
              reason: '${preset.id} display contract',
            );
          }
        }
      }
    }
  });
}

Matcher closeToOffset(Offset value, double delta) => isA<Offset>()
    .having((point) => point.dx, 'dx', closeTo(value.dx, delta))
    .having((point) => point.dy, 'dy', closeTo(value.dy, delta));
