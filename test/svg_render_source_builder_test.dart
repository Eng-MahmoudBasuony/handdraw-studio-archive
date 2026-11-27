import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/vector_import/infrastructure/svg_render_source_builder.dart';
import 'package:xml/xml.dart';

void main() {
  test('expands line markers and builds a text-free reveal source', () {
    const source = '''
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5"
            markerWidth="6" markerHeight="6" orient="auto">
            <path d="M0,0 L10,5 L0,10 z" fill="#999"/>
          </marker>
        </defs>
        <line x1="10" y1="50" x2="80" y2="50" stroke="#999"
          stroke-width="2" marker-end="url(#arrow)"/>
        <text x="50" y="30">Lesson</text>
      </svg>
    ''';

    final result = const SvgRenderSourceBuilder().build(source);
    final complete = XmlDocument.parse(result.complete);
    final revealBase = XmlDocument.parse(result.withoutText);
    final fills = XmlDocument.parse(result.filledArtwork);
    final strokes = XmlDocument.parse(result.strokeArtwork);
    final completeElements = complete.descendants.whereType<XmlElement>();
    final revealElements = revealBase.descendants.whereType<XmlElement>();

    expect(
      completeElements.any((element) => element.name.local == 'marker'),
      isFalse,
    );
    expect(result.complete, isNot(contains('marker-end')));
    expect(
      completeElements.any(
        (element) =>
            element.name.local == 'g' &&
            (element
                    .getAttribute('transform')
                    ?.contains('translate(80.0 50.0)') ??
                false),
      ),
      isTrue,
    );
    expect(
      completeElements.any((element) => element.name.local == 'text'),
      isTrue,
    );
    expect(
      revealElements.any((element) => element.name.local == 'text'),
      isFalse,
    );
    expect(
      fills.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'line',
      ),
      isFalse,
    );
    expect(
      strokes.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'line',
      ),
      isTrue,
    );
    expect(
      strokes.descendants.whereType<XmlElement>().any(
        (element) =>
            element.name.local == 'g' &&
            element.getAttribute('data-handdraw-reveal-layer') == 'stroke',
      ),
      isTrue,
    );
  });

  test('isolates canvas-spanning crossing lines from ordinary strokes', () {
    final source = File(
      'test/fixtures/complex-crossing-strokes.svg',
    ).readAsStringSync();
    final result = const SvgRenderSourceBuilder().build(source);
    final regular = XmlDocument.parse(result.strokeArtwork);
    final global = XmlDocument.parse(result.globalStrokeArtwork);
    Set<String> ids(XmlDocument document) => document.descendants
        .whereType<XmlElement>()
        .map((element) => element.getAttribute('id'))
        .whereType<String>()
        .toSet();

    expect(ids(regular), containsAll(['circle', 'grid']));
    expect(ids(regular), isNot(contains('global-a')));
    expect(ids(regular), isNot(contains('global-b')));
    expect(ids(global), containsAll(['global-a', 'global-b']));
    expect(ids(global), isNot(contains('circle')));
    expect(ids(global), isNot(contains('grid')));
  });
}
