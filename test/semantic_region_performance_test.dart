import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/services/semantic_region_compiler.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('records semantic cold, cached, spatial p50/p95 and RSS', () {
    const compiler = SemanticRegionCompiler();
    final document = _fixture(1000);
    final compileUs = <int>[];
    CompiledSemanticRegionGraph? graph;
    for (var i = 0; i < 25; i++) {
      final watch = Stopwatch()..start();
      graph = compiler.compile(document);
      compileUs.add(watch.elapsedMicroseconds);
    }
    final cache = SemanticRegionGraphCache();
    final dependencyWatch = Stopwatch()..start();
    final dependencyKey = compiler.dependencyKey(document);
    final dependencyKeyUs = dependencyWatch.elapsedMicroseconds;
    cache.compileWithDependencyKey(document, dependencyKey);
    final cachedUs = <int>[];
    for (var i = 0; i < 1000; i++) {
      final watch = Stopwatch()..start();
      cache.lookup(dependencyKey);
      cachedUs.add(watch.elapsedMicroseconds);
    }
    final queryUs = <int>[];
    for (var i = 0; i < 5000; i++) {
      final x = (i * 37 % 1920).toDouble();
      final y = (i * 53 % 1080).toDouble();
      final watch = Stopwatch()..start();
      graph!.spatialIndex.nearest(x, y);
      queryUs.add(watch.elapsedMicroseconds);
    }
    compileUs.sort();
    cachedUs.sort();
    queryUs.sort();
    // ignore: avoid_print
    print(
      'SEMANTIC_PERF mode=debug_jit sections=1000 dependency_key_us=$dependencyKeyUs compile_p50_us=${_p(compileUs, .50)} compile_p95_us=${_p(compileUs, .95)} cached_p50_us=${_p(cachedUs, .50)} cached_p95_us=${_p(cachedUs, .95)} spatial_p50_us=${_p(queryUs, .50)} spatial_p95_us=${_p(queryUs, .95)} rss_bytes=${ProcessInfo.currentRss}',
    );
    expect(_p(compileUs, .95), lessThan(1000000));
    expect(_p(queryUs, .95), lessThan(10000));
  });
}

int _p(List<int> sorted, double percentile) =>
    sorted[((sorted.length - 1) * percentile).round()];

ProjectDocument _fixture(int count) {
  final sections = <ProjectSection>[];
  final strokes = <ProjectStroke>[];
  for (var i = 0; i < count; i++) {
    final sectionId = SectionId('section-$i');
    final strokeId = StrokeId('stroke-$i');
    sections.add(
      ProjectSection(id: sectionId, name: '$i', strokeIds: [strokeId]),
    );
    strokes.add(
      ProjectStroke(
        id: strokeId,
        sectionId: sectionId,
        name: '$i',
        points: [
          DocumentPoint(i / count, 0),
          DocumentPoint((i + 1) / count, 1),
        ],
      ),
    );
  }
  return ProjectDocument(
    id: ProjectId('perf'),
    title: 'Performance',
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
