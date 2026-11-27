import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_artwork_parser.dart';

void main() {
  const parser = SvgArtworkParser();

  test('imports SVG path commands as normalized editable geometry', () {
    final result = parser.parse('''
      <svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">
        <path id="curve" fill="none" stroke="#111" stroke-width="4"
          d="M 20 20 C 40 0 160 100 180 80" />
      </svg>
    ''');

    expect(result.warnings, isEmpty);
    expect(result.paths, hasLength(1));
    final imported = result.paths.single;
    expect(imported.id, 'curve');
    expect(imported.geometry.start, const Offset(0.1, 0.2));
    final segment = imported.geometry.segments.single as StrokeCubicSegment;
    expect(segment.control1, const Offset(0.2, 0));
    expect(segment.control2, const Offset(0.8, 1));
    expect(segment.end, const Offset(0.9, 0.8));
    expect(imported.recommendedRevealWidth, closeTo(0.04, 0.0001));
    expect(result.document.paths.single.geometry, same(imported.geometry));
  });

  test(
    'imports primitives, groups, and transforms without flattening curves',
    () {
      final result = parser.parse('''
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <g transform="translate(10 5)">
          <rect id="card" x="10" y="15" width="20" height="10" />
          <circle id="node" cx="50" cy="50" r="10" />
        </g>
      </svg>
    ''');

      expect(result.paths, hasLength(2));
      final card = result.paths.first;
      final node = result.paths.last;
      expect(card.geometry.start, const Offset(0.2, 0.2));
      expect(card.geometry.closed, isTrue);
      expect(card.geometry.segments, hasLength(3));
      expect(node.geometry.start, const Offset(0.7, 0.55));
      expect(node.geometry.segments, hasLength(4));
      expect(
        node.geometry.segments.every(
          (segment) => segment is StrokeCubicSegment,
        ),
        isTrue,
      );
    },
  );

  test('splits multiple SVG contours into independently editable paths', () {
    final result = parser.parse('''
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <path d="M0 0 L20 0 M80 100 L100 100" fill="none" stroke="black" />
      </svg>
    ''');

    expect(result.paths, hasLength(2));
    expect(result.paths.first.geometry.start, Offset.zero);
    expect(result.paths.last.geometry.start, const Offset(0.8, 1));
  });

  test('matches SVG preserveAspectRatio viewport positioning', () {
    final centered = parser.parse('''
      <svg width="200" height="100" viewBox="0 0 100 100">
        <line x1="0" y1="50" x2="100" y2="50" stroke="black" />
      </svg>
    ''');
    expect(centered.paths.single.geometry.start, const Offset(0.25, 0.5));
    expect(
      centered.paths.single.geometry.segments.single.end,
      const Offset(0.75, 0.5),
    );

    final stretched = parser.parse('''
      <svg width="200" height="100" viewBox="0 0 100 100"
        preserveAspectRatio="none">
        <line x1="0" y1="50" x2="100" y2="50" stroke="black" />
      </svg>
    ''');
    expect(stretched.paths.single.geometry.start, const Offset(0, 0.5));
    expect(
      stretched.paths.single.geometry.segments.single.end,
      const Offset(1, 0.5),
    );
  });

  test('ignores definitions and preserves rounded filled-shape semantics', () {
    final result = parser.parse('''
      <svg width="900" height="500" viewBox="0 0 900 500">
        <defs>
          <marker id="arrow"><path d="M0 0 L10 5 L0 10 z" /></marker>
        </defs>
        <rect id="card" x="380" y="70" width="140" height="50" rx="10"
          fill="#2f6fed" />
        <line id="edge" x1="410" y1="120" x2="255" y2="200"
          stroke="#9aa5b1" stroke-width="2" marker-end="url(#arrow)" />
        <rect id="hidden" x="0" y="0" width="900" height="500"
          display="none" />
      </svg>
    ''');

    expect(result.paths.map((path) => path.id), ['card', 'edge']);
    final card = result.paths.first;
    expect(card.geometry.segments, hasLength(8));
    expect(
      card.geometry.segments.whereType<StrokeCubicSegment>(),
      hasLength(4),
    );
    expect(card.isFilled, isTrue);
    expect(card.animationGeometry, isNotNull);
    expect(card.animationGeometry!.start.dy, closeTo(0.19, 0.0001));
    expect(card.clipBounds.left, closeTo(0.421222, 0.000001));
    expect(card.clipBounds.top, closeTo(0.139, 0.000001));
    expect(card.clipBounds.right, closeTo(0.578778, 0.000001));
    expect(card.clipBounds.bottom, closeTo(0.241, 0.000001));

    final edge = result.paths.last;
    expect(edge.isFilled, isFalse);
    expect(edge.isConnector, isTrue);
    expect(edge.animationGeometry, isNull);
    expect(edge.recommendedRevealWidth, greaterThan(0.02));
  });

  test('imports dependency graph shapes and text as native reveal paths', () {
    final result = parser.parse(
      File('test/fixtures/dependency-graph-diagram.svg').readAsStringSync(),
    );

    expect(result.paths, hasLength(21));
    expect(result.paths.map((path) => path.id), isNot(contains('path-0')));
    expect(result.paths.where((path) => path.isFilled), hasLength(5));
    expect(result.paths.where((path) => path.isText), hasLength(12));
    expect(result.paths.where((path) => path.isConnector), hasLength(4));
    expect(result.report.importedPathCount, 21);
    expect(result.report.filledShapeCount, 5);
    expect(result.report.textPathCount, 12);
    expect(
      result.paths.firstWhere((path) => path.id == 'rect-1').fillColorValue,
      0xFF2F6FED,
    );
    expect(
      result.paths
          .where((path) => path.isFilled)
          .every((path) => path.animationGeometry != null),
      isTrue,
    );
    expect(
      result.paths
          .where((path) => !path.isFilled && !path.isText)
          .every((path) => path.recommendedRevealWidth >= 0.024),
      isTrue,
    );
    final title = result.paths.firstWhere((path) => path.isText);
    expect(
      title.geometry.start.dy,
      closeTo(title.clipBounds.center.dy, 0.0001),
    );
    expect(title.clipBounds.center.dx, closeTo(0.5, 0.01));
  });

  test('classifies only canvas-spanning diagonal lines as decorations', () {
    final result = parser.parse(
      File('test/fixtures/complex-crossing-strokes.svg').readAsStringSync(),
    );

    expect(
      result.paths
          .where((path) => path.isGlobalDecoration)
          .map((path) => path.id),
      ['global-a', 'global-b'],
    );
    expect(
      result.paths
          .where((path) => !path.isGlobalDecoration)
          .map((path) => path.id),
      containsAll(['circle', 'grid']),
    );
  });

  test('rejects scripts and external resources', () {
    expect(
      () => parser.parse('<svg><script>alert(1)</script></svg>'),
      throwsFormatException,
    );
    expect(
      () => parser.parse(
        '<svg><image href="https://example.com/image.png" /></svg>',
      ),
      throwsFormatException,
    );
  });

  test('preserves trusted SVG text metadata through isolate transfer', () {
    final result = parser.parse('''
      <svg viewBox="0 0 200 100"><text id="greeting" x="10" y="30"
        font-size="18">مرحبا Hello</text></svg>
    ''');
    final text = result.paths.single;
    expect(text.originalText, 'مرحبا Hello');
    expect(text.fontSize, 18);
    expect(text.lineCount, 1);
    expect(text.rightToLeft, isTrue);
    final restored = result.toTransferJson();
    expect(
      (restored['paths']! as List).single,
      containsPair('originalText', 'مرحبا Hello'),
    );
  });

  test('rejects excessive text and exposes typed cancellation', () {
    final excessive = 'a' * (SvgArtworkParser.maximumTextCharacters + 1);
    expect(
      () => parser.parse('<svg><text>$excessive</text></svg>'),
      throwsFormatException,
    );
    expect(
      () => parser.parse('<svg/>', isCancelled: () => true),
      throwsA(isA<SvgImportCancelledException>()),
    );
  });

  test(
    'rejects excessive group depth and reports complex raster fallbacks',
    () {
      final nested =
          '${List.filled(129, '<g>').join()}'
          '<path d="M0 0 L10 10" stroke="black" />'
          '${List.filled(129, '</g>').join()}';
      expect(
        () => parser.parse('<svg viewBox="0 0 10 10">$nested</svg>'),
        throwsFormatException,
      );

      final fallback = parser.parse('''
      <svg viewBox="0 0 100 100">
        <style>.accent { fill: red; }</style>
        <filter id="blur"><feGaussianBlur stdDeviation="2" /></filter>
        <rect class="accent" x="10" y="10" width="40" height="40"
          mask="url(#complex)" />
      </svg>
    ''');
      expect(fallback.paths, hasLength(1));
      expect(fallback.warnings, hasLength(greaterThanOrEqualTo(3)));
    },
  );

  test(
    'reports unsupported editable content instead of silently dropping it',
    () {
      final result = parser.parse('''
      <svg viewBox="0 0 100 100">
        <foreignObject x="10" y="20" width="40" height="20" />
      </svg>
    ''');

      expect(result.paths, isEmpty);
      expect(result.warnings, isNotEmpty);
    },
  );
}
