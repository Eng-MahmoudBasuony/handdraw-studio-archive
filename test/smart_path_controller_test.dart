import 'support/legacy_editor_state_fixture.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_reveal_planner.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';

EditorCubit _createCubit({
  HandDrawProject? project,
  List<SmartPathSection> sections = const [],
}) {
  final cubit = EditorCubit(
    initialState: testEditorState(
      project: project ?? HandDrawProject(),
      smartSections: sections,
    ),
  );
  addTearDown(cubit.close);
  return cubit;
}

class _FixedSmartPathEngine extends SmartPathEngine {
  const _FixedSmartPathEngine(this.analysis);

  final SmartPathAnalysis analysis;

  @override
  Future<SmartPathAnalysis> analyze({
    required Image image,
    required Uint8List encodedImage,
    SmartPathProgressCallback? onProgress,
    SmartPathCancellationToken? cancellationToken,
    Rect coordinateBounds = const Rect.fromLTWH(0, 0, 1, 1),
  }) async => analysis;
}

void main() {
  test(
    'suspected frame pauses auto apply, can be restored, and records provenance',
    () async {
      final recorder = PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final drawing = await picture.toImage(100, 100);
      picture.dispose();
      const analysis = SmartPathAnalysis(
        processing: SmartPathProcessingRecord(
          suspectedFrameDetection: true,
          suspectedFrameConfidenceThreshold: 0.96,
        ),
        sections: [
          SmartPathSection(
            id: 'suspected-frame',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTRB(0.01, 0.01, 0.99, 0.99),
            label: 'Artwork 1',
            paths: [
              SmartGeneratedPath(
                points: [
                  Offset(0.01, 0.01),
                  Offset(0.99, 0.01),
                  Offset(0.99, 0.99),
                  Offset(0.01, 0.99),
                  Offset(0.01, 0.01),
                ],
              ),
            ],
            recommendedRevealWidth: 0.01,
            mode: SmartSectionMode.ignore,
            artifactHint: SmartSectionArtifactHint.suspectedFrame,
            artifactConfidence: 0.99,
          ),
        ],
      );
      final cubit = EditorCubit(
        smartPathEngine: const _FixedSmartPathEngine(analysis),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/frame.png',
            drawingImageBase64: base64Encode(const [1, 2, 3]),
          ),
          drawingImage: drawing,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        drawing.dispose();
      });

      await cubit.analyzeSmartPaths();

      expect(cubit.project.strokes, isEmpty);
      expect(cubit.smartSections.single.mode, SmartSectionMode.ignore);
      expect(cubit.autoPathResult, isNull);

      cubit.setSmartSectionMode('suspected-frame', SmartSectionMode.handDraw);
      await cubit.applySmartPathSuggestions();

      expect(cubit.project.strokes, isNotEmpty);
      expect(cubit.smartSections, isEmpty);
      final metadata = cubit.state.document.pathProcessingMetadata;
      expect(metadata, isNotNull);
      expect(metadata!.engineId, 'handdraw-smart-path');
      expect(metadata.algorithmVersion, 1);
      expect(metadata.featureSet, contains('suspected-frame-detection-v1'));
      expect(metadata.suspectedFrameConfidenceThreshold, 0.96);
      expect(
        metadata.sourceAssetHash,
        cubit.state.document.assets
            .singleWhere(
              (asset) => asset.id == cubit.state.document.artworkAssetId,
            )
            .contentHash,
      );

      cubit.undoStroke();
      expect(cubit.state.document.pathProcessingMetadata, isNull);
      cubit.redoStroke();
      expect(cubit.state.document.pathProcessingMetadata, isNotNull);
    },
  );

  test('Auto Reveal creates directional wipes and a safe fallback', () {
    const planner = AutoRevealPlanner();
    final project = HandDrawProject();
    final detected = planner.build(
      project: project,
      sections: const [
        SmartPathSection(
          id: 'message',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.2, 0.6, 0.45, 0.12),
          label: 'Version solving failed',
          paths: [],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'error-icon',
          kind: SmartSectionKind.shape,
          bounds: Rect.fromLTWH(0.72, 0.58, 0.1, 0.15),
          label: 'Error icon',
          paths: [],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
      ],
    );
    final fallback = planner.build(sections: const [], project: project);

    expect(detected.usedFallback, isFalse);
    expect(detected.strokes, hasLength(2));
    expect(detected.strokes.every((stroke) => stroke.revealOnly), isTrue);
    expect(
      detected.strokes.every(
        (stroke) => stroke.revealStyle == RevealMaskStyle.directionalWipe,
      ),
      isTrue,
    );
    expect(fallback.usedFallback, isTrue);
    expect(fallback.strokes.single.clipBounds, const Rect.fromLTWH(0, 0, 1, 1));
  });

  test('applies selected Hand, Reveal, and Ignore section modes', () async {
    final cubit = _createCubit(
      sections: const [
        SmartPathSection(
          id: 'title',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.1, 0.1, 0.5, 0.12),
          label: 'Title',
          paths: [
            SmartGeneratedPath(points: [Offset(0.1, 0.15), Offset(0.6, 0.15)]),
          ],
          recommendedRevealWidth: 0.02,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'subtitle',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.1, 0.3, 0.6, 0.08),
          label: 'Subtitle',
          paths: [],
          recommendedRevealWidth: 0.015,
          mode: SmartSectionMode.revealText,
        ),
        SmartPathSection(
          id: 'ignored',
          kind: SmartSectionKind.shape,
          bounds: Rect.fromLTWH(0.8, 0.8, 0.1, 0.1),
          label: 'Ignored',
          paths: [
            SmartGeneratedPath(points: [Offset(0.8, 0.8), Offset(0.9, 0.9)]),
          ],
          recommendedRevealWidth: 0.01,
          mode: SmartSectionMode.ignore,
        ),
      ],
    );

    await cubit.applySmartPathSuggestions();

    expect(cubit.project.strokes, hasLength(3));
    expect(cubit.project.strokes.first.revealOnly, isFalse);
    expect(cubit.project.strokes.first.sectionId, 'title');
    expect(cubit.project.strokes[1].revealOnly, isTrue);
    expect(cubit.project.strokes[1].name, contains('Complete'));
    expect(cubit.project.strokes[1].sectionId, 'title');
    expect(cubit.project.strokes.last.revealOnly, isTrue);
    expect(cubit.project.strokes.last.sectionId, 'subtitle');
    expect(
      cubit.project.strokes.every((stroke) => stroke.clipBounds != null),
      isTrue,
    );
    expect(cubit.smartSections, isEmpty);

    cubit.undoStroke();
    expect(cubit.project.strokes, isEmpty);
    cubit.redoStroke();
    expect(cubit.project.strokes, hasLength(3));
  });

  test(
    'SVG suggestions preserve native curves without raster duplication',
    () async {
      final geometry = StrokePathGeometry(
        start: const Offset(0.1, 0.5),
        segments: const [
          StrokeCubicSegment(
            control1: Offset(0.3, 0.1),
            control2: Offset(0.7, 0.9),
            end: Offset(0.9, 0.5),
          ),
        ],
      );
      final cubit = _createCubit(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'native-curve',
              name: 'Native curve',
              geometry: geometry,
              sectionId: 'svg:native-curve',
              revealWidth: 18,
            ),
            DrawingStroke(
              id: 'auto-stale-raster-copy',
              name: 'Stale raster copy',
              points: const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
              sectionId: 'raster-artwork',
            ),
          ],
        ),
        sections: const [
          SmartPathSection(
            id: 'svg-edit:native-curve',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
            label: 'Native curve',
            paths: [
              SmartGeneratedPath(points: [Offset(0.1, 0.5), Offset(0.9, 0.5)]),
            ],
            recommendedRevealWidth: 0.02,
            mode: SmartSectionMode.handDraw,
          ),
          SmartPathSection(
            id: 'ocr-label',
            kind: SmartSectionKind.text,
            bounds: Rect.fromLTWH(0.2, 0.2, 0.3, 0.08),
            label: 'Label',
            paths: [
              SmartGeneratedPath(
                points: [Offset(0.2, 0.24), Offset(0.5, 0.24)],
              ),
            ],
            recommendedRevealWidth: 0.02,
            mode: SmartSectionMode.handDraw,
          ),
        ],
      );

      await cubit.applySmartPathSuggestions();

      final native = cubit.project.strokes.where(
        (stroke) => stroke.id == 'native-curve',
      );
      expect(native, hasLength(1));
      expect(native.single.geometry, same(geometry));
      expect(
        native.single.geometry!.segments.single,
        isA<StrokeCubicSegment>(),
      );
      expect(
        cubit.project.strokes.where(
          (stroke) => stroke.sectionId == 'svg:native-curve',
        ),
        hasLength(1),
      );
      expect(
        cubit.project.strokes.where(
          (stroke) => stroke.sectionId == 'ocr-label',
        ),
        hasLength(2),
      );
      expect(
        cubit.project.strokes.any(
          (stroke) => stroke.id == 'auto-stale-raster-copy',
        ),
        isFalse,
      );

      cubit.undoStroke();
      expect(cubit.project.strokes, hasLength(2));
      expect(cubit.project.strokes.first.geometry, same(geometry));
      expect(cubit.project.strokes.last.id, 'auto-stale-raster-copy');
      cubit.redoStroke();
      expect(
        cubit.project.strokes.where((stroke) => stroke.id == 'native-curve'),
        hasLength(1),
      );
      expect(
        cubit.project.strokes.any(
          (stroke) => stroke.id == 'auto-stale-raster-copy',
        ),
        isFalse,
      );
    },
  );

  test(
    'SVG analysis keeps native geometry and discards duplicate raster shapes',
    () async {
      final recorder = PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      final drawing = await picture.toImage(100, 100);
      picture.dispose();
      final geometry = StrokePathGeometry(
        start: const Offset(0.1, 0.5),
        segments: const [StrokeLineSegment(end: Offset(0.9, 0.5))],
      );
      const analysis = SmartPathAnalysis(
        sections: [
          SmartPathSection(
            id: 'raster-artwork',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTWH(0.1, 0.4, 0.8, 0.2),
            label: 'Artwork 1',
            paths: [
              SmartGeneratedPath(points: [Offset(0.1, 0.5), Offset(0.9, 0.5)]),
            ],
            recommendedRevealWidth: 0.2,
            mode: SmartSectionMode.handDraw,
          ),
          SmartPathSection(
            id: 'ocr-label',
            kind: SmartSectionKind.text,
            bounds: Rect.fromLTWH(0.2, 0.2, 0.3, 0.08),
            label: 'Label',
            paths: [
              SmartGeneratedPath(
                points: [Offset(0.2, 0.24), Offset(0.5, 0.24)],
              ),
            ],
            recommendedRevealWidth: 0.02,
            mode: SmartSectionMode.handDraw,
          ),
        ],
      );
      final cubit = EditorCubit(
        smartPathEngine: const _FixedSmartPathEngine(analysis),
        initialState: testEditorState(
          project: HandDrawProject(
            drawingImagePath: '/tmp/diagram.svg',
            drawingImageBase64: base64Encode(const [1]),
            strokes: [
              DrawingStroke(
                id: 'native-line',
                name: 'Native line',
                geometry: geometry,
                sectionId: 'svg:native-line',
                revealWidth: 8,
              ),
              DrawingStroke(
                id: 'native-text',
                name: 'Native text',
                geometry: StrokePathGeometry(
                  start: const Offset(0.2, 0.24),
                  segments: const [StrokeLineSegment(end: Offset(0.5, 0.24))],
                ),
                isTextShape: true,
                revealStyle: RevealMaskStyle.directionalWipe,
                clipBounds: const Rect.fromLTWH(0.2, 0.2, 0.3, 0.08),
                sectionId: 'svg:native-text',
                revealWidth: 22,
              ),
            ],
          ),
          drawingImage: drawing,
        ),
      );
      addTearDown(() async {
        await cubit.close();
        drawing.dispose();
      });

      await cubit.analyzeSmartPaths(autoApply: false);

      expect(
        cubit.smartSections.map((section) => section.id),
        containsAll(['svg-edit:native-line', 'svg-edit:native-text']),
      );
      expect(
        cubit.smartSections.map((section) => section.id),
        isNot(contains(anyOf('raster-artwork', 'ocr-label'))),
      );
      expect(
        cubit.smartSections
            .firstWhere((section) => section.id == 'svg-edit:native-text')
            .kind,
        SmartSectionKind.text,
      );

      await cubit.createAutoReveal();
      expect(
        cubit.project.strokes.where((stroke) => stroke.id == 'native-line'),
        hasLength(1),
      );
      expect(cubit.project.strokes.first.geometry, same(geometry));
      expect(cubit.project.strokes.first.revealOnly, isTrue);
      expect(
        cubit.project.strokes
            .firstWhere((stroke) => stroke.id == 'native-text')
            .revealStyle,
        RevealMaskStyle.directionalWipe,
      );
      expect(
        cubit.project.strokes.any(
          (stroke) => stroke.sectionId == 'auto-reveal-all',
        ),
        isFalse,
      );
    },
  );

  test(
    'clear canvas removes drawing/paths, keeps hand/settings, and restores',
    () {
      final cubit = _createCubit(
        project: HandDrawProject(
          drawingImagePath: '/tmp/drawing.png',
          drawingImageBase64: 'drawing-bytes',
          handImagePath: '/tmp/hand.png',
          handImageBase64: 'hand-bytes',
          durationSeconds: 12,
          strokes: [
            DrawingStroke(
              id: 'one',
              name: 'One',
              points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
            ),
          ],
        ),
      );

      expect(cubit.clearCanvas(), isTrue);
      expect(cubit.project.strokes, isEmpty);
      expect(cubit.project.drawingImagePath, isNull);
      expect(cubit.project.drawingImageBase64, isNull);
      expect(cubit.project.handImagePath, '/tmp/hand.png');
      expect(cubit.project.handImageBase64, isNull);
      expect(cubit.project.durationSeconds, 12);

      cubit.restoreClearedCanvas();
      expect(cubit.project.strokes.single.id, 'one');
      expect(cubit.project.drawingImagePath, '/tmp/drawing.png');
      expect(cubit.project.handImagePath, '/tmp/hand.png');
      expect(cubit.project.durationSeconds, 12);
    },
  );

  test('new project keeps the currently selected hand', () {
    final cubit = _createCubit(
      project: HandDrawProject(
        handPresetId: 'marker-left',
        handImagePath: 'assets/hands/hand-writing-marker.png',
        handImageBase64: 'embedded-hand',
        handFlipX: true,
        penTip: const Offset(0.22, 0.68),
      ),
    );

    cubit.newProject();

    expect(cubit.project.handPresetId, 'marker-left');
    expect(cubit.project.handImagePath, 'assets/hands/hand-writing-marker.png');
    expect(cubit.project.handImageBase64, isNull);
    expect(cubit.project.handFlipX, isTrue);
    expect(cubit.project.penTip, const Offset(0.22, 0.68));
  });

  test(
    'orders mixed artwork and text spatially and protects text regions',
    () async {
      final cubit = _createCubit(
        sections: const [
          SmartPathSection(
            id: 'artwork',
            kind: SmartSectionKind.shape,
            bounds: Rect.fromLTWH(0.1, 0.1, 0.8, 0.75),
            label: 'Artwork',
            paths: [
              SmartGeneratedPath(
                points: [Offset(0.1, 0.75), Offset(0.9, 0.75)],
              ),
              SmartGeneratedPath(
                points: [Offset(0.1, 0.20), Offset(0.9, 0.20)],
              ),
            ],
            recommendedRevealWidth: 0.08,
            mode: SmartSectionMode.handDraw,
          ),
          SmartPathSection(
            id: 'top-text',
            kind: SmartSectionKind.text,
            bounds: Rect.fromLTWH(0.2, 0.16, 0.25, 0.1),
            label: 'Top text',
            paths: [
              SmartGeneratedPath(
                points: [Offset(0.2, 0.21), Offset(0.45, 0.21)],
              ),
            ],
            recommendedRevealWidth: 0.03,
            mode: SmartSectionMode.handDraw,
          ),
        ],
      );

      await cubit.applySmartPathSuggestions();

      expect(cubit.project.strokes, hasLength(4));
      expect(cubit.project.strokes.last.points.first.dy, 0.75);
      expect(
        cubit.project.strokes
            .take(3)
            .every((stroke) => stroke.points.first.dy < 0.3),
        isTrue,
      );
      final artwork = cubit.project.strokes.where(
        (stroke) => stroke.sectionId == 'artwork',
      );
      expect(
        artwork.every((stroke) => stroke.exclusionBounds.isNotEmpty),
        isTrue,
      );
    },
  );

  test('completes each diagram row before moving downward', () async {
    final cubit = _createCubit(
      sections: const [
        SmartPathSection(
          id: 'artwork',
          kind: SmartSectionKind.shape,
          bounds: Rect.fromLTWH(0.1, 0.1, 0.8, 0.8),
          label: 'Artwork',
          paths: [
            SmartGeneratedPath(points: [Offset(0.2, 0.80), Offset(0.4, 0.80)]),
            SmartGeneratedPath(points: [Offset(0.6, 0.52), Offset(0.8, 0.52)]),
            SmartGeneratedPath(
              points: [
                Offset(0.4, 0.20),
                Offset(0.6, 0.20),
                Offset(0.5, 0.26),
                Offset(0.5, 0.30),
                Offset(0.5, 0.38),
              ],
            ),
            SmartGeneratedPath(points: [Offset(0.2, 0.52), Offset(0.4, 0.52)]),
            SmartGeneratedPath(
              points: [
                Offset(0.20, 0.560),
                Offset(0.30, 0.560),
                Offset(0.30, 0.565),
                Offset(0.30, 0.590),
              ],
            ),
            SmartGeneratedPath(points: [Offset(0.5, 0.65), Offset(0.5, 0.72)]),
            SmartGeneratedPath(points: [Offset(0.6, 0.80), Offset(0.8, 0.80)]),
          ],
          recommendedRevealWidth: 0.09,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'top',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.4, 0.16, 0.2, 0.08),
          label: 'Top',
          paths: [
            SmartGeneratedPath(
              points: [Offset(0.42, 0.20), Offset(0.58, 0.20)],
            ),
          ],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'middle-left',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.2, 0.48, 0.2, 0.08),
          label: 'Middle left',
          paths: [
            SmartGeneratedPath(
              points: [Offset(0.22, 0.52), Offset(0.38, 0.52)],
            ),
          ],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'middle-right',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.6, 0.48, 0.2, 0.08),
          label: 'Middle right',
          paths: [
            SmartGeneratedPath(
              points: [Offset(0.62, 0.52), Offset(0.78, 0.52)],
            ),
          ],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'bottom-left',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.2, 0.76, 0.2, 0.08),
          label: 'Bottom left',
          paths: [
            SmartGeneratedPath(
              points: [Offset(0.22, 0.80), Offset(0.38, 0.80)],
            ),
          ],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
        SmartPathSection(
          id: 'bottom-right',
          kind: SmartSectionKind.text,
          bounds: Rect.fromLTWH(0.6, 0.76, 0.2, 0.08),
          label: 'Bottom right',
          paths: [
            SmartGeneratedPath(
              points: [Offset(0.62, 0.80), Offset(0.78, 0.80)],
            ),
          ],
          recommendedRevealWidth: 0.04,
          mode: SmartSectionMode.handDraw,
        ),
      ],
    );

    await cubit.applySmartPathSuggestions();

    int pathIndex(Offset point) => cubit.project.strokes.indexWhere(
      (stroke) => stroke.points.contains(point),
    );

    final topShape = pathIndex(const Offset(0.4, 0.20));
    final firstConnector = pathIndex(const Offset(0.5, 0.30));
    final topCompletion = cubit.project.strokes.indexWhere(
      (stroke) => stroke.sectionId == 'top' && stroke.revealOnly,
    );
    final middleLeftShape = pathIndex(const Offset(0.2, 0.52));
    final middleRightShape = pathIndex(const Offset(0.6, 0.52));
    final shortOutgoingConnector = pathIndex(const Offset(0.30, 0.590));
    final connectorBoundary = pathIndex(const Offset(0.30, 0.565));
    final middleLeftCompletion = cubit.project.strokes.indexWhere(
      (stroke) => stroke.sectionId == 'middle-left' && stroke.revealOnly,
    );
    final middleRightCompletion = cubit.project.strokes.indexWhere(
      (stroke) => stroke.sectionId == 'middle-right' && stroke.revealOnly,
    );
    final secondConnector = pathIndex(const Offset(0.5, 0.65));
    final bottomLeftShape = pathIndex(const Offset(0.2, 0.80));
    final bottomRightShape = pathIndex(const Offset(0.6, 0.80));

    expect(topShape, lessThan(firstConnector));
    expect(topCompletion, lessThan(firstConnector));
    expect(
      cubit.project.strokes[topShape].points,
      isNot(contains(const Offset(0.5, 0.30))),
    );
    expect(
      cubit.project.strokes[firstConnector].points,
      contains(const Offset(0.5, 0.30)),
    );
    expect(firstConnector, lessThan(middleLeftShape));
    expect(middleLeftCompletion, lessThan(connectorBoundary));
    expect(shortOutgoingConnector, lessThan(secondConnector));
    expect(secondConnector, lessThan(bottomLeftShape));
    expect(middleLeftCompletion, lessThan(middleRightShape));
    expect(middleRightCompletion, lessThan(secondConnector));
    expect(secondConnector, lessThan(bottomLeftShape));
    expect(bottomLeftShape, lessThan(bottomRightShape));

    final handPaths = cubit.project.strokes.where(
      (stroke) => !stroke.revealOnly,
    );
    expect(
      handPaths.every(
        (stroke) => stroke.revealWidth! <= cubit.project.revealWidth * 0.65,
      ),
      isTrue,
    );
    expect(
      cubit.project.strokes
          .where((stroke) => stroke.revealOnly)
          .every(
            (stroke) => stroke.revealWidth! > cubit.project.revealWidth * 0.65,
          ),
      isTrue,
    );
  });

  test('reset settings keeps canvas content and imported assets', () {
    final cubit = _createCubit(
      project: HandDrawProject(
        drawingImagePath: '/tmp/drawing.png',
        handImagePath: '/tmp/hand.png',
        durationSeconds: 20,
        revealWidth: 140,
        handScale: 0.5,
        handRotationDegrees: 45,
        penTip: const Offset(0.8, 0.2),
        strokes: [
          DrawingStroke(
            id: 'one',
            name: 'One',
            points: const [Offset(0.1, 0.1), Offset(0.2, 0.2)],
          ),
        ],
      ),
    );

    cubit.resetDefaultSettings();

    expect(cubit.project.durationSeconds, 6);
    expect(cubit.project.revealWidth, 54);
    expect(cubit.project.handScale, BuiltInHands.defaultPreset.defaultScale);
    expect(
      cubit.project.handRotationDegrees,
      BuiltInHands.defaultPreset.defaultRotationDegrees,
    );
    expect(cubit.project.penTip, BuiltInHands.defaultPreset.penTip);
    expect(cubit.project.strokes.single.id, 'one');
    expect(cubit.project.drawingImagePath, '/tmp/drawing.png');
    expect(cubit.project.handImagePath, '/tmp/hand.png');
  });
}
