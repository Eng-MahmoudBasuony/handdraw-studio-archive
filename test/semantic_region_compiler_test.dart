import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_duplicator.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/semantic/domain/operations/semantic_document_operations.dart';
import 'package:handdraw_studio/features/semantic/domain/services/semantic_region_compiler.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'support/fake_id_generator.dart';

void main() {
  const compiler = SemanticRegionCompiler();

  test('compiles stable typed regions, bounds, graph, index, and events', () {
    final graph = compiler.compile(_document());
    expect(
      graph.regions.map((value) => value.id),
      containsAll(['stroke:s1', 'stroke:s2', 'section:a', 'scene:scene']),
    );
    expect(graph.containment, hasLength(3));
    expect(graph.drawingOrder.single.beforeRegionId, 'stroke:s1');
    expect(graph.attentionEvents.map((value) => value.time.microseconds), [
      0,
      500000,
    ]);
    expect(graph.spatialIndex.nearest(15, 15)?.id, 'stroke:s1');
    expect(graph.spatialIndex.inScene(SceneId('scene')), hasLength(4));
    expect(
      graph.spatialIndex
          .inInterval(TimelineTime.zero, TimelineTime.fromMicroseconds(500000))
          .map((value) => value.id),
      containsAll(['stroke:s1', 'section:a', 'scene:scene']),
    );
    expect(
      graph.spatialIndex
          .inInterval(
            TimelineTime.fromMicroseconds(500000),
            TimelineTime.fromMicroseconds(500001),
          )
          .map((value) => value.id),
      contains('stroke:s2'),
    );
    final text = graph.regions.singleWhere((value) => value.id == 'stroke:s1');
    expect(text.kind, SemanticRegionKind.text);
    expect(text.direction, KnownTextDirection.rtl);
    expect(text.directionProvenance, DirectionProvenance.inferredFromKnownText);
    expect(text.geometricBounds.left, 10);
    expect(text.visualBounds.left, lessThan(text.geometricBounds.left));
  });

  test('IDs and results are deterministic across random source insertion', () {
    final forward = compiler.compile(_document());
    final reverse = compiler.compile(_document(reverseStrokes: true));
    expect(reverse.dependencyKey, forward.dependencyKey);
    expect(
      reverse.regions.map((value) => value.id),
      forward.regions.map((value) => value.id),
    );
    expect(
      reverse.attentionEvents.map((value) => value.strokeId),
      forward.attentionEvents.map((value) => value.strokeId),
    );
  });

  test('cache invalidates only semantic dependencies', () {
    final cache = SemanticRegionGraphCache();
    final document = _document();
    final first = cache.compile(document);
    expect(
      identical(
        first,
        cache.compile(document.copyWith(title: 'UI-only title')),
      ),
      isTrue,
    );
    final changed = const SemanticDocumentOperations().setImportance(
      document: document,
      target: SemanticTargetReference.stroke(StrokeId('s1')),
      value: SemanticImportance.critical,
    );
    expect(identical(first, cache.compile(changed.document)), isFalse);
    expect(cache.compilationCount, 2);
  });

  test('semantic metadata survives codec and duplicate rebinds every ID', () {
    const codec = DevelopmentProjectManifestCodec();
    final source = _document();
    final decoded = codec.decode(codec.encode(source));
    expect(
      decoded.contentMetadata.entities.single.target.stableKey,
      'stroke:s1',
    );
    expect(
      decoded.contentMetadata.entities.single.textMetadata?.originalText,
      'مرحبا',
    );

    final duplicate = const ProjectDocumentDuplicator().duplicate(
      source,
      ids: SequentialIdGenerator(),
    );
    final target = duplicate.contentMetadata.entities.single.target;
    expect(target.value, isNot('s1'));
    expect(
      duplicate.strokes.any((stroke) => stroke.id.value == target.value),
      isTrue,
    );
  });

  test('operations reject missing targets and produce semantic scope', () {
    const operations = SemanticDocumentOperations();
    final missing = operations.setCameraExcluded(
      document: _document(),
      target: SemanticTargetReference.stroke(StrokeId('missing')),
      value: true,
    );
    expect(missing.isSuccess, isFalse);
    final valid = operations.setKeepTogether(
      document: _document(),
      target: SemanticTargetReference.section(SectionId('a')),
      value: true,
    );
    expect(valid.isSuccess, isTrue);
    expect(valid.affectedScopes.single.name, 'semantic');
  });

  test(
    '40, 200, and 1000 section fixtures compile with linear region scale',
    () {
      for (final count in [40, 200, 1000]) {
        final graph = compiler.compile(_largeDocument(count));
        expect(graph.regions.length, count * 2);
        expect(graph.attentionEvents.length, count);
      }
    },
  );
}

ProjectDocument _document({bool reverseStrokes = false}) {
  final section = SectionId('a');
  final strokes = [
    ProjectStroke(
      id: StrokeId('s1'),
      sectionId: section,
      name: 'Arabic',
      points: const [DocumentPoint(.1, .1), DocumentPoint(.2, .2)],
    ),
    ProjectStroke(
      id: StrokeId('s2'),
      sectionId: section,
      name: 'Shape',
      points: const [DocumentPoint(.7, .7), DocumentPoint(.8, .8)],
    ),
  ];
  return ProjectDocument(
    id: ProjectId('p'),
    title: 'Semantic',
    canvas: const ProjectCanvas(width: 100, height: 100),
    frameRate: FrameRate(numerator: 30),
    duration: TimelineDuration.fromMicroseconds(1000000),
    assets: const [],
    strokes: reverseStrokes ? strokes.reversed.toList() : strokes,
    sections: [
      ProjectSection(
        id: section,
        name: 'A',
        strokeIds: [StrokeId('s1'), StrokeId('s2')],
        timing: DocumentSectionTiming(
          animationDuration: TimelineDuration.fromMicroseconds(1000000),
        ),
      ),
    ],
    sectionOrder: [section],
    scenes: [
      ProjectScene(id: SceneId('scene'), name: 'Scene', sectionIds: [section]),
    ],
    audioTracks: const [],
    contentMetadata: ProjectContentMetadata(
      projectLocaleHint: 'en',
      entities: [
        EntitySemanticMetadata(
          target: SemanticTargetReference.stroke(StrokeId('s1')),
          textMetadata: const ImportedTextMetadata(
            originalText: 'مرحبا',
            sourceKind: TextSourceKind.svgText,
            sourceProvenance: 'svg:text',
          ),
          provenance: SemanticMetadataProvenance.imported,
        ),
      ],
    ),
  );
}

ProjectDocument _largeDocument(int count) {
  final sections = <ProjectSection>[];
  final strokes = <ProjectStroke>[];
  for (var i = 0; i < count; i++) {
    final section = SectionId('section-$i');
    final stroke = StrokeId('stroke-$i');
    sections.add(ProjectSection(id: section, name: '$i', strokeIds: [stroke]));
    strokes.add(
      ProjectStroke(
        id: stroke,
        sectionId: section,
        name: '$i',
        points: [
          DocumentPoint(i / count, 0),
          DocumentPoint((i + 1) / count, 1),
        ],
      ),
    );
  }
  return ProjectDocument(
    id: ProjectId('large-$count'),
    title: 'Large',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate(numerator: 30),
    duration: TimelineDuration.zero,
    assets: const [],
    strokes: strokes,
    sections: sections,
    sectionOrder: sections.map((value) => value.id).toList(),
    scenes: const [],
    audioTracks: const [],
  );
}
