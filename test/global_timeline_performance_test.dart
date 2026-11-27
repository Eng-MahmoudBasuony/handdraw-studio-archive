import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_drawing_timeline_compiler_adapter.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';
import 'package:handdraw_studio/features/timeline/domain/services/timeline_compiler.dart';

import 'support/project_document_parity_fixture.dart';

const _run = bool.fromEnvironment('HANDDRAW_RUN_GLOBAL_TIMELINE_BENCHMARK');
final _clockFrequency = Stopwatch().frequency;

void main() {
  test(
    'records separated compiler and resolver baseline',
    () {
      const compiler = TimelineCompiler(
        drawingAdapter: LegacyDrawingTimelineCompilerAdapter(),
      );
      const resolver = GlobalTimelineResolver();
      final random = Random(4);
      var checksum = 0;
      final clockResolutionTicks = _clockResolutionTicks();

      for (final count in [40, 200, 1000]) {
        final document = _scaledDocument(count);
        final compile = <int>[];
        final cold = <int>[];
        late var compiled = compiler.compile(
          document: document,
          documentRevision: 1,
        );
        for (var iteration = 0; iteration < 100; iteration++) {
          var watch = Stopwatch()..start();
          compiled = compiler.compile(
            document: document,
            documentRevision: iteration + 2,
          );
          compile.add(watch.elapsedTicks);
          watch = Stopwatch()..start();
          final frame = resolver.resolveAt(
            compiled,
            TimelineTime.fromMicroseconds(compiled.duration.microseconds ~/ 2),
          );
          cold.add(watch.elapsedTicks);
          checksum = _consume(
            checksum,
            frame.time.microseconds,
            frame.drawing?.sectionId?.hashCode ?? 0,
          );
        }
        for (var iteration = 0; iteration < 1000; iteration++) {
          final frame = resolver.resolveAt(
            compiled,
            TimelineTime.fromMicroseconds(
              iteration % (compiled.duration.microseconds + 1),
            ),
          );
          checksum = _consume(
            checksum,
            frame.time.microseconds,
            frame.activeAudio.length,
          );
        }

        final sequential = <int>[];
        final randomSamples = <int>[];
        for (var iteration = 0; iteration < 10000; iteration++) {
          final sequentialUs =
              (compiled.duration.microseconds * iteration) ~/ 9999;
          var watch = Stopwatch()..start();
          final sequentialFrame = resolver.resolveAt(
            compiled,
            TimelineTime.fromMicroseconds(sequentialUs),
          );
          sequential.add(watch.elapsedTicks);
          checksum = _consume(
            checksum,
            sequentialFrame.time.microseconds,
            sequentialFrame.drawing?.localTime.microseconds ?? 0,
          );

          final randomUs = compiled.duration.microseconds == 0
              ? 0
              : random.nextInt(compiled.duration.microseconds + 1);
          watch = Stopwatch()..start();
          final randomFrame = resolver.resolveAt(
            compiled,
            TimelineTime.fromMicroseconds(randomUs),
          );
          randomSamples.add(watch.elapsedTicks);
          checksum = _consume(
            checksum,
            randomFrame.time.microseconds,
            randomFrame.drawing?.sectionId?.hashCode ?? 0,
          );
        }
        // ignore: avoid_print
        print(
          'GLOBAL_TIMELINE mode=debug_jit sections=$count clock_hz=$_clockFrequency clock_resolution_ticks=$clockResolutionTicks compile_n=100 ${_stats(compile)} cold_resolve_n=100 ${_stats(cold)} warm_sequential_n=10000 ${_stats(sequential)} random_resolve_n=10000 ${_stats(randomSamples)} rss_bytes=${ProcessInfo.currentRss} checksum=$checksum',
        );
      }
      expect(checksum, isNot(0));
    },
    skip: _run
        ? false
        : 'Opt-in with --dart-define=HANDDRAW_RUN_GLOBAL_TIMELINE_BENCHMARK=true',
  );
}

String _stats(List<int> ticks) {
  ticks.sort();
  final mean = ticks.reduce((a, b) => a + b) / ticks.length;
  double us(num value) => value * 1000000 / _clockFrequency;
  return 'mean_us=${us(mean).toStringAsFixed(3)} median_us=${us(_percentile(ticks, 0.50)).toStringAsFixed(3)} p95_us=${us(_percentile(ticks, 0.95)).toStringAsFixed(3)} p99_us=${us(_percentile(ticks, 0.99)).toStringAsFixed(3)}';
}

int _percentile(List<int> values, double percentile) =>
    values[((values.length - 1) * percentile).round()];

int _clockResolutionTicks() {
  var minimum = 1 << 62;
  for (var iteration = 0; iteration < 1000; iteration++) {
    final watch = Stopwatch()..start();
    while (watch.elapsedTicks == 0) {}
    minimum = min(minimum, watch.elapsedTicks);
  }
  return minimum;
}

int _consume(int checksum, int a, int b) =>
    ((checksum * 31) ^ a ^ b) & 0x7fffffff;

ProjectDocument _scaledDocument(int count) {
  final base = projectDocumentParityFixture();
  final sections = [
    for (var index = 0; index < count; index++)
      ProjectSection(
        id: SectionId('section-$index'),
        name: 'Section $index',
        strokeIds: const [],
      ),
  ];
  return base.copyWith(
    strokes: const [],
    sections: sections,
    sectionOrder: [for (final section in sections) section.id],
    scenes: const [],
  );
}
