import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/default_artwork_path_facade.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_artwork_parser.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_text_layer_rasterizer.dart';

class _DependencyTreeTextDetector implements TextLayoutDetector {
  const _DependencyTreeTextDetector();

  @override
  Future<List<SmartTextRegion>> detect(Uint8List encodedImage) async => const [
    SmartTextRegion(
      text: 'MY APP',
      bounds: Rect.fromLTWH(0.390988, 0.335917, 0.106105, 0.039083),
      confidence: 1,
    ),
    SmartTextRegion(
      text: 'PACKAGE A',
      bounds: Rect.fromLTWH(0.284884, 0.55, 0.139535, 0.036563),
      confidence: 1,
    ),
    SmartTextRegion(
      text: 'PACKAGE B',
      bounds: Rect.fromLTWH(0.462209, 0.552778, 0.138081, 0.033786),
      confidence: 1,
    ),
    SmartTextRegion(
      text: 'X v1.0',
      bounds: Rect.fromLTWH(0.316833, 0.70526, 0.074183, 0.039092),
      confidence: 1,
    ),
    SmartTextRegion(
      text: 'X v2.0',
      bounds: Rect.fromLTWH(0.494186, 0.705426, 0.074128, 0.039018),
      confidence: 1,
    ),
  ];
}

void main() {
  test('explicit timeline order controls generated stroke order', () {
    final sections = [
      _simpleSection('left', 0.1),
      _simpleSection('middle', 0.4),
      _simpleSection('right', 0.7),
    ];
    final strokes = const AutoPathStrokePlanner()
        .build(
          sections: sections,
          project: HandDrawProject(),
          timelineSectionOrder: const ['right', 'left', 'middle'],
        )
        .strokes;

    expect(strokes.map((stroke) => stroke.sectionId).toList(), const [
      'right',
      'left',
      'middle',
    ]);
  });

  test('tree artwork completes each visual row before moving downward', () {
    const sections = [
      SmartPathSection(
        id: 'root',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.4, 0.08, 0.2, 0.06),
        label: 'MY APP',
        paths: [
          SmartGeneratedPath(points: [Offset(0.43, 0.11), Offset(0.57, 0.11)]),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      ),
      SmartPathSection(
        id: 'left',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.18, 0.35, 0.25, 0.06),
        label: 'PACKAGE A',
        paths: [
          SmartGeneratedPath(points: [Offset(0.2, 0.38), Offset(0.4, 0.38)]),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      ),
      SmartPathSection(
        id: 'right',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.57, 0.35, 0.25, 0.06),
        label: 'PACKAGE B',
        paths: [
          SmartGeneratedPath(points: [Offset(0.59, 0.38), Offset(0.8, 0.38)]),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      ),
      SmartPathSection(
        id: 'left-child',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.2, 0.65, 0.2, 0.06),
        label: 'X v1.0',
        paths: [
          SmartGeneratedPath(points: [Offset(0.22, 0.68), Offset(0.38, 0.68)]),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      ),
      SmartPathSection(
        id: 'right-child',
        kind: SmartSectionKind.text,
        bounds: Rect.fromLTWH(0.6, 0.65, 0.2, 0.06),
        label: 'X v2.0',
        paths: [
          SmartGeneratedPath(points: [Offset(0.62, 0.68), Offset(0.78, 0.68)]),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      ),
      SmartPathSection(
        id: 'connected-artwork',
        kind: SmartSectionKind.shape,
        bounds: Rect.fromLTWH(0.15, 0.3, 0.7, 0.48),
        label: 'Artwork',
        paths: [
          SmartGeneratedPath(
            points: [
              Offset(0.2, 0.37),
              Offset(0.4, 0.37),
              Offset(0.6, 0.37),
              Offset(0.8, 0.37),
              Offset(0.38, 0.39),
              Offset(0.3, 0.66),
              Offset(0.7, 0.66),
            ],
          ),
        ],
        recommendedRevealWidth: 0.02,
        mode: SmartSectionMode.handDraw,
      ),
    ];

    final strokes = const AutoPathStrokePlanner()
        .build(sections: sections, project: HandDrawProject())
        .strokes;
    final rootEnd = strokes.lastIndexWhere(
      (stroke) => stroke.sectionId == 'root',
    );
    final firstMiddle = strokes.indexWhere(
      (stroke) => stroke.sectionId == 'left' || stroke.sectionId == 'right',
    );
    final lastMiddle = strokes.lastIndexWhere(
      (stroke) => stroke.sectionId == 'left' || stroke.sectionId == 'right',
    );
    final firstBottom = strokes.indexWhere(
      (stroke) =>
          stroke.sectionId == 'left-child' || stroke.sectionId == 'right-child',
    );
    final leftStart = strokes.indexWhere(
      (stroke) => stroke.sectionId == 'left',
    );
    final rightStart = strokes.indexWhere(
      (stroke) => stroke.sectionId == 'right',
    );

    expect(rootEnd, lessThan(firstMiddle));
    expect(lastMiddle, lessThan(firstBottom));
    expect(leftStart, lessThan(rightStart));
  });

  test(
    'dependency tree fixture completes both parents before child labels',
    () async {
      final image = await _dependencyTreeFixtureImage();
      final analysis = await const SmartPathEngine(
        textDetector: _DependencyTreeTextDetector(),
      ).analyze(image: image, encodedImage: Uint8List(0));
      final strokes = const AutoPathStrokePlanner()
          .build(sections: analysis.sections, project: HandDrawProject())
          .strokes;
      image.dispose();

      final lastParent = strokes.lastIndexWhere(
        (stroke) =>
            stroke.sectionId == 'text-1' || stroke.sectionId == 'text-2',
      );
      final firstChild = strokes.indexWhere(
        (stroke) =>
            stroke.sectionId == 'text-3' || stroke.sectionId == 'text-4',
      );

      expect(firstChild, greaterThan(lastParent));
    },
  );

  test(
    'native dependency SVG never reaches a lower row before package B',
    () async {
      final source = File(
        'test/fixtures/dependency-graph-diagram.svg',
      ).readAsStringSync();
      final imported = const SvgArtworkParser().parse(source);
      final image = await _dependencyTreeFixtureImage();
      addTearDown(image.dispose);
      final analyzed = await const SvgArtworkPathStrategy(SmartPathEngine())
          .analyze(
            ArtworkPathRequest(
              kind: ArtworkSourceKind.svg,
              previewImage: image,
              previewBytes: Uint8List(0),
              sourceBytes: Uint8List(0),
              cachedSvgPaths: imported.paths,
            ),
          );
      final strokes = const AutoPathStrokePlanner()
          .build(
            sections: analyzed.analysis.sections,
            project: HandDrawProject(),
          )
          .strokes;
      int first(String fragment) => strokes.indexWhere(
        (stroke) => stroke.sectionId?.contains(fragment) ?? false,
      );
      int last(String fragment) => strokes.lastIndexWhere(
        (stroke) => stroke.sectionId?.contains(fragment) ?? false,
      );

      final packageBStart = first('rect-6');
      final packageBEnd = [
        last('rect-6'),
        last('text-7'),
        last('text-8'),
      ].reduce((a, b) => a > b ? a : b);
      final sharedStart = first('rect-9');
      expect(packageBStart, greaterThanOrEqualTo(0));
      expect(packageBEnd, greaterThanOrEqualTo(packageBStart));
      expect(sharedStart, greaterThan(packageBEnd));
    },
  );

  test(
    'native SVG text traces rendered glyphs instead of a synthetic baseline',
    () async {
      const fixture = 'test/fixtures/dependency-graph-diagram.svg';
      final sourceBytes = await File(fixture).readAsBytes();
      final source = await File(fixture).readAsString();
      final asset = await const EditorFileService().loadImage(fixture);
      addTearDown(asset.image.dispose);
      addTearDown(() => asset.svgRevealLayers?.dispose());
      final textLayer = await const SvgTextLayerRasterizer().rasterize(source);
      addTearDown(textLayer.dispose);
      final directTraces = await const SmartPathEngine().traceTextRegions(
        image: textLayer,
        regions: [
          asset.vectorPaths.firstWhere((path) => path.isText).clipBounds,
        ],
      );
      expect(directTraces.single.isUsable, isTrue);

      final result = await const SvgArtworkPathStrategy(SmartPathEngine())
          .analyze(
            ArtworkPathRequest(
              kind: ArtworkSourceKind.svg,
              previewImage: asset.image,
              previewBytes: Uint8List(0),
              sourceBytes: sourceBytes,
              cachedSvgPaths: asset.vectorPaths,
            ),
          );
      final text = result.analysis.sections.firstWhere(
        (section) => section.kind == SmartSectionKind.text,
      );
      final points = [for (final path in text.paths) ...path.points];
      final verticalRange =
          points.map((point) => point.dy).reduce(math.max) -
          points.map((point) => point.dy).reduce(math.min);

      expect(text.hasPreciseTrace, isTrue);
      expect(text.paths.length, greaterThan(2));
      expect(verticalRange, greaterThan(0.01));
      expect(
        text.paths.every(
          (path) => path.points.every(text.bounds.inflate(0.004).contains),
        ),
        isTrue,
      );
    },
  );

  test(
    'native SVG title draws its underline before moving to the subtitle',
    () async {
      const fixture = 'test/fixtures/00-title.svg';
      final sourceBytes = await File(fixture).readAsBytes();
      final asset = await const EditorFileService().loadImage(fixture);
      addTearDown(asset.image.dispose);
      addTearDown(() => asset.svgRevealLayers?.dispose());
      final analyzed = await const SvgArtworkPathStrategy(SmartPathEngine())
          .analyze(
            ArtworkPathRequest(
              kind: ArtworkSourceKind.svg,
              previewImage: asset.image,
              previewBytes: Uint8List(0),
              sourceBytes: sourceBytes,
              cachedSvgPaths: asset.vectorPaths,
            ),
          );
      final strokes = const AutoPathStrokePlanner()
          .build(
            sections: analyzed.analysis.sections,
            project: HandDrawProject(canvasWidth: 1920, canvasHeight: 1080),
          )
          .strokes;
      int firstNamed(String name) =>
          strokes.indexWhere((stroke) => stroke.name == name);
      int lastNamed(String name) =>
          strokes.lastIndexWhere((stroke) => stroke.name == name);

      final titleEnd = lastNamed('text-2');
      final underlineStart = [
        firstNamed('path-0'),
        firstNamed('path-1'),
      ].where((index) => index >= 0).reduce(math.min);
      final underlineEnd = [
        lastNamed('path-0'),
        lastNamed('path-1'),
      ].where((index) => index >= 0).reduce(math.max);
      final subtitleStart = firstNamed('text-3');

      expect(titleEnd, greaterThanOrEqualTo(0));
      expect(underlineStart, greaterThan(titleEnd));
      expect(subtitleStart, greaterThan(underlineEnd));
    },
  );

  test(
    'thin filled SVG artwork follows a medial path while solid cards keep wipes',
    () async {
      const source = '''
        <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
          <path id="bracket" fill="#2874ed"
            d="M10 10 H80 V24 H24 V80 H10 Z" />
          <rect id="card" x="35" y="55" width="60" height="30"
            fill="#3aaa57" />
        </svg>
      ''';
      final imported = const SvgArtworkParser().parse(source);
      final preview = await _transparentImage();
      addTearDown(preview.dispose);

      final result = await const SvgArtworkPathStrategy(SmartPathEngine())
          .analyze(
            ArtworkPathRequest(
              kind: ArtworkSourceKind.svg,
              previewImage: preview,
              previewBytes: Uint8List(0),
              sourceBytes: Uint8List.fromList(utf8.encode(source)),
              cachedSvgPaths: imported.paths,
            ),
          );

      final bracket = result.analysis.sections.firstWhere(
        (section) => section.label == 'bracket',
      );
      final card = result.analysis.sections.firstWhere(
        (section) => section.label == 'card',
      );
      final bracketPoints = [for (final path in bracket.paths) ...path.points];

      expect(bracket.hasPreciseTrace, isTrue);
      expect(card.hasPreciseTrace, isFalse);
      expect(
        bracketPoints.map((point) => point.dx).reduce(math.max) -
            bracketPoints.map((point) => point.dx).reduce(math.min),
        greaterThan(0.5),
      );
      expect(
        bracketPoints.map((point) => point.dy).reduce(math.max) -
            bracketPoints.map((point) => point.dy).reduce(math.min),
        greaterThan(0.5),
      );
    },
  );

  test('canvas-spanning decorations stay atomic and draw last', () async {
    final source = File(
      'test/fixtures/complex-crossing-strokes.svg',
    ).readAsStringSync();
    final imported = const SvgArtworkParser().parse(source);
    final image = await _dependencyTreeFixtureImage();
    addTearDown(image.dispose);
    final analyzed = await const SvgArtworkPathStrategy(SmartPathEngine())
        .analyze(
          ArtworkPathRequest(
            kind: ArtworkSourceKind.svg,
            previewImage: image,
            previewBytes: Uint8List(0),
            sourceBytes: Uint8List(0),
            cachedSvgPaths: imported.paths,
          ),
        );
    final strokes = const AutoPathStrokePlanner()
        .build(sections: analyzed.analysis.sections, project: HandDrawProject())
        .strokes;

    expect(strokes.map((stroke) => stroke.name).toSet(), {
      'circle',
      'grid',
      'global-a',
      'global-b',
    });
    expect(strokes.map((stroke) => stroke.name).skip(2), [
      'global-a',
      'global-b',
    ]);
    expect(
      strokes.skip(2).every((stroke) => stroke.orderedPoints.length >= 2),
      isTrue,
    );
    expect(
      strokes.skip(2).every((stroke) => stroke.isGlobalDecoration),
      isTrue,
    );
  });

  test('locked scene groups override spatial order and stay contiguous', () {
    SmartPathSection section(String id, double x, List<double> pathYs) =>
        SmartPathSection(
          id: id,
          kind: SmartSectionKind.shape,
          bounds: Rect.fromLTWH(x, 0.2, 0.2, 0.3),
          label: id,
          paths: [
            for (final y in pathYs)
              SmartGeneratedPath(points: [Offset(x, y), Offset(x + 0.15, y)]),
          ],
          recommendedRevealWidth: 0.01,
          mode: SmartSectionMode.handDraw,
        );

    final plan = const AutoPathStrokePlanner().build(
      sections: [
        section('left', 0.1, [0.25]),
        section('right', 0.7, [0.25, 0.4]),
      ],
      project: HandDrawProject(),
      sceneGroups: [
        DrawingSceneGroup(
          id: 'right-scene',
          name: 'Right first',
          sectionIds: ['right'],
        ),
        DrawingSceneGroup(
          id: 'left-scene',
          name: 'Left second',
          sectionIds: ['left'],
        ),
      ],
    );

    expect(plan.strokes.map((stroke) => stroke.name), [
      'right',
      'right',
      'left',
    ]);
    expect(plan.strokes.map((stroke) => stroke.sceneGroupId), [
      'right-scene',
      'right-scene',
      'left-scene',
    ]);
  });

  test(
    'native SVG completes parent connectors before dependency labels',
    () async {
      final source = File(
        'test/fixtures/dependency-graph-diagram.svg',
      ).readAsStringSync();
      final imported = const SvgArtworkParser().parse(source);
      final image = await _dependencyTreeFixtureImage();
      addTearDown(image.dispose);
      final analyzed = await const SvgArtworkPathStrategy(SmartPathEngine())
          .analyze(
            ArtworkPathRequest(
              kind: ArtworkSourceKind.svg,
              previewImage: image,
              previewBytes: Uint8List(0),
              sourceBytes: Uint8List(0),
              cachedSvgPaths: imported.paths,
            ),
          );
      final strokes = const AutoPathStrokePlanner()
          .build(
            sections: analyzed.analysis.sections,
            project: HandDrawProject(),
          )
          .strokes;
      bool isNativePath(DrawingStroke stroke, String pathId) =>
          stroke.sectionId?.endsWith(pathId) ?? false;
      int first(String pathId) =>
          strokes.indexWhere((stroke) => isNativePath(stroke, pathId));
      int last(String pathId) =>
          strokes.lastIndexWhere((stroke) => isNativePath(stroke, pathId));
      int count(String pathId) =>
          strokes.where((stroke) => isNativePath(stroke, pathId)).length;

      final rootEnd = [
        last('svg-rect-1-1'),
        last('svg-text-2-2'),
      ].reduce(math.max);
      final firstConnector = first('svg-line-12-12');
      final secondConnector = first('svg-line-13-13');
      final firstDependencyLabel = [
        first('svg-text-5-5'),
        first('svg-text-8-8'),
      ].where((index) => index >= 0).reduce(math.min);

      expect(firstConnector, greaterThan(rootEnd));
      expect(secondConnector, greaterThan(rootEnd));
      expect(firstConnector, lessThan(firstDependencyLabel));
      expect(secondConnector, lessThan(firstDependencyLabel));
      expect(count('svg-line-12-12'), 1);
      expect(count('svg-line-13-13'), 1);
    },
  );
}

SmartPathSection _simpleSection(String id, double left) => SmartPathSection(
  id: id,
  kind: SmartSectionKind.shape,
  bounds: Rect.fromLTWH(left, 0.2, 0.15, 0.1),
  label: id,
  paths: [
    SmartGeneratedPath(points: [Offset(left, 0.2), Offset(left + 0.1, 0.25)]),
  ],
  recommendedRevealWidth: 0.01,
  mode: SmartSectionMode.handDraw,
);

/// A repository-owned regression fixture for a two-branch dependency tree.
///
/// Keeping the fixture procedural makes the test deterministic, reviewable,
/// and independent from a developer's Downloads directory. The OCR detector
/// above supplies the stable text bounds while this image exercises the real
/// raster extraction and graph-ordering pipeline.
Future<ui.Image> _dependencyTreeFixtureImage() async {
  const width = 1000;
  const height = 600;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final linePaint = ui.Paint()
    ..color = const ui.Color(0xFF171717)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 9
    ..strokeCap = ui.StrokeCap.round
    ..strokeJoin = ui.StrokeJoin.round;
  final textPaint = ui.Paint()
    ..color = const ui.Color(0xFF171717)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 6
    ..strokeCap = ui.StrokeCap.round;

  Offset point(double x, double y) => Offset(x * width, y * height);

  // Connected artwork: root, left branch, then right branch. The planner must
  // keep the visual dependency order even though the raster is one component.
  final tree = ui.Path()
    ..moveTo(point(0.444, 0.375).dx, point(0.444, 0.375).dy)
    ..lineTo(point(0.444, 0.47).dx, point(0.444, 0.47).dy)
    ..lineTo(point(0.354, 0.55).dx, point(0.354, 0.55).dy)
    ..moveTo(point(0.444, 0.47).dx, point(0.444, 0.47).dy)
    ..lineTo(point(0.531, 0.553).dx, point(0.531, 0.553).dy)
    ..moveTo(point(0.354, 0.587).dx, point(0.354, 0.587).dy)
    ..lineTo(point(0.354, 0.705).dx, point(0.354, 0.705).dy)
    ..moveTo(point(0.531, 0.587).dx, point(0.531, 0.587).dy)
    ..lineTo(point(0.531, 0.705).dx, point(0.531, 0.705).dy);
  canvas.drawPath(tree, linePaint);

  // Text-like horizontal strokes give the real SmartPathEngine opaque pixels
  // to refine inside each deterministic OCR region.
  for (final segment in const [
    (0.400, 0.355, 0.486, 0.355),
    (0.296, 0.568, 0.413, 0.568),
    (0.474, 0.568, 0.589, 0.568),
    (0.324, 0.724, 0.383, 0.724),
    (0.502, 0.724, 0.560, 0.724),
  ]) {
    canvas.drawLine(
      point(segment.$1, segment.$2),
      point(segment.$3, segment.$4),
      textPaint,
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  return image;
}

Future<ui.Image> _transparentImage() async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder);
  final picture = recorder.endRecording();
  final image = await picture.toImage(100, 100);
  picture.dispose();
  return image;
}
