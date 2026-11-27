import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

void main() {
  test('custom export resolution policy accepts production pixel bounds', () {
    expect(ExportResolutionPolicy.isValid(width: 1920, height: 1080), isTrue);
    expect(
      ExportResolutionPolicy.isValid(
        width: ExportResolutionPolicy.minDimension,
        height: ExportResolutionPolicy.maxDimension,
      ),
      isTrue,
    );
    expect(ExportResolutionPolicy.isValid(width: 15, height: 1080), isFalse);
    expect(ExportResolutionPolicy.isValid(width: 1920, height: 8193), isFalse);
  });

  test('new and legacy default projects use the visible Technical Pen nib', () {
    final fresh = HandDrawProject();
    final legacy = HandDrawProject.fromJson(const {});

    expect(fresh.handPresetId, 'marker-technical-wheat-right');
    expect(fresh.penTip, const Offset(0.114583, 0.485677));
    expect(legacy.handPresetId, isNull);
    expect(legacy.penTip, const Offset(0.114583, 0.485677));
  });

  test('legacy custom hands retain the generic fallback calibration', () {
    final restored = HandDrawProject.fromJson(const {
      'handImagePath': '/tmp/custom-hand.png',
    });

    expect(restored.penTip, const Offset(0.18, 0.72));
  });

  test('retiming changes drawing time without scaling independent holds', () {
    final project = HandDrawProject(
      durationSeconds: 6,
      startDelaySeconds: 0.4,
      endHoldSeconds: 0.9,
    );

    final shorter = project.retimed(3);
    final longer = project.retimed(12);

    expect(shorter.durationSeconds, 3);
    expect(shorter.drawingDurationSeconds, closeTo(1.7, 0.0001));
    expect(shorter.startDelaySeconds, 0.4);
    expect(shorter.endHoldSeconds, 0.9);
    expect(longer.durationSeconds, 12);
    expect(longer.drawingDurationSeconds, closeTo(10.7, 0.0001));
    expect(longer.startDelaySeconds, 0.4);
    expect(longer.endHoldSeconds, 0.9);
    expect(project.durationSeconds, 6, reason: 'Retiming must be immutable.');
  });

  test('retiming rejects invalid durations', () {
    final project = HandDrawProject();

    expect(() => project.retimed(0), throwsArgumentError);
    expect(() => project.retimed(double.nan), throwsArgumentError);
  });

  test('editable cubic geometry round-trips and reverses losslessly', () {
    final geometry = StrokePathGeometry(
      start: const Offset(0.1, 0.2),
      segments: const [
        StrokeCubicSegment(
          control1: Offset(0.2, 0.1),
          control2: Offset(0.7, 0.8),
          end: Offset(0.9, 0.7),
        ),
      ],
    );
    final project = HandDrawProject(
      strokes: [
        DrawingStroke(id: 'vector', name: 'Vector', geometry: geometry),
      ],
    );

    final restored = HandDrawProject.fromJson(project.toJson());
    final restoredGeometry = restored.strokes.single.geometry!;
    final reversed = restoredGeometry.reversed();

    expect(restoredGeometry.start, const Offset(0.1, 0.2));
    expect(restoredGeometry.end, const Offset(0.9, 0.7));
    expect(reversed.start, restoredGeometry.end);
    expect(reversed.end, restoredGeometry.start);
    final reversedSegment = reversed.segments.single as StrokeCubicSegment;
    expect(reversedSegment.control1, const Offset(0.7, 0.8));
    expect(reversedSegment.control2, const Offset(0.2, 0.1));
  });

  test(
    'quadratic geometry persists and reverses without changing its curve',
    () {
      final geometry = StrokePathGeometry(
        start: const Offset(0.1, 0.8),
        segments: const [
          StrokeQuadraticSegment(
            control: Offset(0.5, 0.1),
            end: Offset(0.9, 0.8),
          ),
        ],
      );
      final restored = StrokePathGeometry.fromJson(geometry.toJson());
      final reversed = restored.reversed();

      expect(restored.segments.single, isA<StrokeQuadraticSegment>());
      expect(reversed.start, geometry.end);
      expect(reversed.end, geometry.start);
      expect(
        (reversed.segments.single as StrokeQuadraticSegment).control,
        const Offset(0.5, 0.1),
      );
    },
  );

  test('filled SVG keeps editable and animation geometry independently', () {
    final editable = StrokePathGeometry(
      start: const Offset(0.2, 0.2),
      segments: const [
        StrokeLineSegment(end: Offset(0.8, 0.2)),
        StrokeLineSegment(end: Offset(0.8, 0.6)),
        StrokeLineSegment(end: Offset(0.2, 0.6)),
      ],
      closed: true,
    );
    final animation = StrokePathGeometry(
      start: const Offset(0.2, 0.4),
      segments: const [StrokeLineSegment(end: Offset(0.8, 0.4))],
    );
    final restored = HandDrawProject.fromJson(
      HandDrawProject(
        strokes: [
          DrawingStroke(
            id: 'filled',
            name: 'Filled',
            geometry: editable,
            animationGeometry: animation,
            isFilledShape: true,
            isTextShape: false,
            fillColorValue: 0xFF3AA757,
          ),
        ],
      ).toJson(),
    ).strokes.single;

    expect(restored.geometry!.closed, isTrue);
    expect(restored.animationGeometry!.start, const Offset(0.2, 0.4));
    expect(restored.orderedPoints, animation.sample());
    expect(restored.isFilledShape, isTrue);
    expect(restored.isTextShape, isFalse);
    expect(restored.fillColorValue, 0xFF3AA757);
  });

  test('project JSON round-trip preserves motion data', () {
    final project = HandDrawProject(
      canvasBackground: const CanvasBackground.preset(
        CanvasBackgroundPreset.kraft,
      ),
      durationSeconds: 8.5,
      drawingSpeed: 1.75,
      penTravelSpeed: 1.4,
      startDelaySeconds: 0.6,
      endHoldSeconds: 1.2,
      revealWidth: 72,
      handScale: 0.31,
      handPresetId: 'marker-left',
      handFlipX: true,
      writingSoundEnabled: true,
      writingSoundPreset: WritingSoundPreset.recordedNaturalPaper,
      writingSoundVolume: 0.72,
      exportPresetId: ExportPresetId.finalCutOverlay4k,
      exportAlphaMode: ExportAlphaMode.straight,
      exportRenderQuality: ExportRenderQuality.proxy,
      drawingImageBase64: 'embedded-drawing',
      drawingSourceKind: ArtworkSourceKind.svg,
      drawingSourceBase64: 'embedded-svg-source',
      drawingRevealBase64: 'embedded-svg-base',
      drawingRevealStrokeBase64: 'embedded-svg-strokes',
      handImageBase64: 'embedded-hand',
      penTip: const Offset(0.2, 0.7),
      strokes: [
        DrawingStroke(
          id: 'stroke-1',
          name: 'First',
          points: const [Offset(0.1, 0.2), Offset(0.8, 0.9)],
          reversed: true,
          revealOnly: true,
          isGlobalDecoration: true,
          sceneGroupId: 'scene-1',
          revealStyle: RevealMaskStyle.directionalWipe,
          exclusionBounds: const [Rect.fromLTWH(0.2, 0.3, 0.4, 0.1)],
          pausePoints: const [
            StrokePausePoint(
              id: 'pause-1',
              progress: 0.35,
              durationSeconds: 1.2,
              keepHandVisible: false,
            ),
          ],
        ),
      ],
      sceneGroups: [
        DrawingSceneGroup(
          id: 'scene-1',
          name: 'Opening',
          sectionIds: ['section-a', 'section-b'],
          collapsed: true,
        ),
      ],
      timelineSectionOrder: const ['section-b', 'section-a'],
      sectionTimings: const {
        'stroke:stroke-1': SectionTiming(
          pauseBeforeSeconds: 0.25,
          pauseAfterSeconds: 1.75,
          speedMultiplier: 1.5,
          animationDurationSeconds: 2.25,
          transitionAfterSeconds: 0.65,
          pauseHandBehavior: PauseHandBehavior.hide,
          voiceCueSeconds: 3.25,
          handEntranceAnimation: SectionHandEntranceAnimation.slingshot,
          handEntranceDurationSeconds: .45,
          handExitAnimation: SectionHandExitAnimation.fadeOut,
          handExitDurationSeconds: .55,
          keepHandVisibleAfterDrawing: true,
        ),
      },
      voiceGuide: VoiceGuide(
        path: '/tmp/voice.m4a',
        name: 'voice.m4a',
        durationSeconds: 12.4,
        waveform: const [0.1, 0.7, 0.3],
        securityBookmark: 'bookmark',
      ),
    );

    final restored = HandDrawProject.fromJson(project.toJson());

    expect(restored.durationSeconds, 8.5);
    expect(
      restored.canvasBackground,
      const CanvasBackground.preset(CanvasBackgroundPreset.kraft),
    );
    expect(restored.drawingDurationSeconds, 6.7);
    expect(restored.drawingSpeed, 1.75);
    expect(restored.penTravelSpeed, 1.4);
    expect(restored.startDelaySeconds, 0.6);
    expect(restored.endHoldSeconds, 1.2);
    expect(restored.revealWidth, 72);
    expect(restored.handScale, 0.31);
    expect(restored.handPresetId, 'marker-left');
    expect(restored.handFlipX, isTrue);
    expect(restored.writingSoundEnabled, isTrue);
    expect(
      restored.writingSoundPreset,
      WritingSoundPreset.recordedNaturalPaper,
    );
    expect(restored.writingSoundVolume, 0.72);
    expect(restored.exportPresetId, ExportPresetId.finalCutOverlay4k);
    expect(restored.exportAlphaMode, ExportAlphaMode.straight);
    expect(restored.exportRenderQuality, ExportRenderQuality.proxy);
    expect(restored.drawingImageBase64, 'embedded-drawing');
    expect(restored.drawingSourceKind, ArtworkSourceKind.svg);
    expect(restored.drawingSourceBase64, 'embedded-svg-source');
    expect(restored.drawingRevealBase64, 'embedded-svg-base');
    expect(restored.drawingRevealStrokeBase64, 'embedded-svg-strokes');
    expect(restored.handImageBase64, 'embedded-hand');
    expect(restored.penTip, const Offset(0.2, 0.7));
    expect(restored.strokes.single.reversed, isTrue);
    expect(restored.strokes.single.revealOnly, isTrue);
    expect(restored.strokes.single.isGlobalDecoration, isTrue);
    expect(restored.strokes.single.sceneGroupId, 'scene-1');
    expect(restored.sceneGroups.single.name, 'Opening');
    expect(restored.sceneGroups.single.sectionIds, ['section-a', 'section-b']);
    expect(restored.sceneGroups.single.collapsed, isTrue);
    expect(restored.timelineSectionOrder, ['section-b', 'section-a']);
    expect(
      restored.strokes.single.revealStyle,
      RevealMaskStyle.directionalWipe,
    );
    expect(restored.strokes.single.exclusionBounds, const [
      Rect.fromLTWH(0.2, 0.3, 0.4, 0.1),
    ]);
    expect(restored.strokes.single.orderedPoints.first, const Offset(0.8, 0.9));
    expect(restored.strokes.single.pausePoints.single.id, 'pause-1');
    expect(restored.strokes.single.pausePoints.single.progress, 0.35);
    expect(restored.strokes.single.pausePoints.single.durationSeconds, 1.2);
    expect(restored.strokes.single.pausePoints.single.keepHandVisible, isFalse);
    final timing = restored.sectionTimings['stroke:stroke-1']!;
    expect(timing.pauseBeforeSeconds, 0.25);
    expect(timing.pauseAfterSeconds, 1.75);
    expect(timing.speedMultiplier, 1.5);
    expect(timing.animationDurationSeconds, 2.25);
    expect(timing.transitionAfterSeconds, 0.65);
    expect(timing.pauseHandBehavior, PauseHandBehavior.hide);
    expect(timing.voiceCueSeconds, 3.25);
    expect(
      timing.handEntranceAnimation,
      SectionHandEntranceAnimation.slingshot,
    );
    expect(timing.handEntranceDurationSeconds, .45);
    expect(timing.handExitAnimation, SectionHandExitAnimation.fadeOut);
    expect(timing.handExitDurationSeconds, .55);
    expect(timing.keepHandVisibleAfterDrawing, isTrue);
    expect(restored.voiceGuide?.path, '/tmp/voice.m4a');
    expect(restored.voiceGuide?.durationSeconds, 12.4);
    expect(restored.voiceGuide?.waveform, const [0.1, 0.7, 0.3]);
    expect(restored.voiceGuide?.securityBookmark, 'bookmark');
  });

  test('old project files stay silent until the user enables sound', () {
    final restored = HandDrawProject.fromJson(const {
      'version': 6,
      'durationSeconds': 6,
      'strokes': [],
    });

    expect(restored.writingSoundEnabled, isFalse);
    expect(restored.writingSoundPreset, WritingSoundPreset.defaultPreset);
    expect(restored.writingSoundVolume, 0.65);
    expect(restored.sectionTimings, isEmpty);
    expect(restored.voiceGuide, isNull);
    expect(restored.drawingSpeed, 1);
    expect(restored.penTravelSpeed, 1);
    expect(restored.drawingDurationSeconds, closeTo(4.7, 0.0001));
  });
}
