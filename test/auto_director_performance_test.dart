import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test('40/200/1000 events stay bounded and report stage timings/RSS', () {
    for (final count in [40, 200, 1000]) {
      final rssBaseline = ProcessInfo.currentRss;
      final graph = _graph(count);
      final timeline = _timeline(count);
      final inputWatch = Stopwatch()..start();
      final input = const DirectorInputBuilder().build(
        timeline: timeline,
        graph: graph,
        cameraTrack: null,
        configuration: AutoDirectorConfiguration(),
        scope: AutoDirectorScope.entireProject(),
      );
      final keyUs = inputWatch.elapsedMicroseconds;
      final sequenceWatch = Stopwatch()..start();
      final sequence = const AttentionSequenceBuilder().build(input);
      final sequenceUs = sequenceWatch.elapsedMicroseconds;
      final clusterWatch = Stopwatch()..start();
      final clusters = const RegionClusterer().cluster(input, sequence);
      final clusterUs = clusterWatch.elapsedMicroseconds;
      final candidateWatch = Stopwatch()..start();
      var maximumCandidates = 0;
      var candidatesGenerated = 0;
      for (final cluster in clusters) {
        final candidates = const CameraCandidateGenerator().generate(
          input,
          cluster,
          const CameraView.identity(),
        );
        if (candidates.length > maximumCandidates) {
          maximumCandidates = candidates.length;
        }
        candidatesGenerated += candidates.length;
      }
      final candidateUs = candidateWatch.elapsedMicroseconds;
      final totalWatch = Stopwatch()..start();
      final plan = const SmartAutoDirector().generate(
        timeline: timeline,
        graph: graph,
        cameraTrack: null,
      );
      final totalUs = totalWatch.elapsedMicroseconds;
      final validationWatch = Stopwatch()..start();
      final validation = const AutoDirectorPlanValidator().validate(
        input,
        plan.proposedShots,
        plan.preservedShots,
      );
      final validationUs = validationWatch.elapsedMicroseconds;
      final rssPeak = ProcessInfo.currentRss;
      final fallbackUsed = plan.diagnostics.any(
        (value) => value.code == 'budget_fallback',
      );
      // ignore: avoid_print
      print(
        'AUTO_DIRECTOR_PERF mode=debug_jit events=$count regions=${graph.regions.length} candidates_generated=$candidatesGenerated candidates_pruned=0 look_ahead=${input.configuration.lookAheadEvents} fallback_used=$fallbackUsed semantic_compile_included=false dependency_key_us=$keyUs attention_us=$sequenceUs clustering_us=$clusterUs candidates_us=$candidateUs planning_us=$totalUs validation_us=$validationUs peak_rss_bytes=$rssPeak rss_delta_bytes=${rssPeak - rssBaseline}',
      );
      expect(plan.proposedShots.length, lessThanOrEqualTo(count));
      expect(
        maximumCandidates,
        lessThanOrEqualTo(
          AutoDirectorConfiguration().maximumCandidatesPerEvent,
        ),
      );
      expect(totalUs, lessThan(3000000));
      expect(validation, isEmpty);
    }
  });

  test('worst candidate cap and cancellation latency stay bounded', () {
    final graph = _graph(1000);
    final timeline = _timeline(1000);
    final cancellation = _ReadCountCancellation(12);
    final watch = Stopwatch()..start();
    expect(
      () => const SmartAutoDirector().generate(
        timeline: timeline,
        graph: graph,
        cameraTrack: null,
        configuration: AutoDirectorConfiguration(maximumCandidatesPerEvent: 1),
        cancellation: cancellation,
      ),
      throwsA(isA<AutoDirectorCancelledException>()),
    );
    // ignore: avoid_print
    print(
      'AUTO_DIRECTOR_CANCEL mode=debug_jit reads=${cancellation.reads} latency_us=${watch.elapsedMicroseconds}',
    );
    expect(watch.elapsed, lessThan(const Duration(milliseconds: 100)));
  });
}

final class _ReadCountCancellation implements AutoDirectorCancellation {
  _ReadCountCancellation(this.cancelAfterReads);
  final int cancelAfterReads;
  int reads = 0;
  @override
  bool get isCancelled => ++reads >= cancelAfterReads;
}

CompiledTimeline _timeline(int count) => CompiledTimeline(
  dependencyKey: TimelineDependencyKey(
    projectId: ProjectId('perf'),
    documentRevision: 1,
  ),
  duration: TimelineDuration.fromMicroseconds(count * 100000),
  contentEnd: TimelineTime.fromMicroseconds(count * 100000),
  drawing: null,
  camera: null,
  audio: const [],
  voiceGuide: null,
  sceneMarkers: const [],
);

CompiledSemanticRegionGraph _graph(int count) {
  final regions = <SemanticRegion>[];
  final events = <SemanticAttentionEvent>[];
  for (var i = 0; i < count; i++) {
    final target = SemanticTargetReference.stroke(StrokeId('s$i'));
    final x = (i % 20) / 20;
    final y = (i ~/ 20 % 20) / 20;
    final bounds = SemanticWorldBounds(
      x * 1000,
      y * 1000,
      x * 1000 + 20,
      y * 1000 + 20,
    );
    regions.add(
      SemanticRegion(
        id: target.stableKey,
        target: target,
        kind: SemanticRegionKind.vector,
        geometricBounds: bounds,
        visualBounds: bounds,
        direction: KnownTextDirection.unknown,
        directionProvenance: DirectionProvenance.unknown,
        metadata: null,
      ),
    );
    events.add(
      SemanticAttentionEvent(
        time: TimelineTime.fromMicroseconds(i * 100000),
        regionIds: [target.stableKey],
        activeBounds: bounds,
        strokeId: StrokeId('s$i'),
        sectionId: SectionId('section-$i'),
      ),
    );
  }
  return CompiledSemanticRegionGraph(
    dependencyKey: 'perf-$count',
    worldWidth: 1000,
    worldHeight: 1000,
    regions: regions,
    containment: const [],
    drawingOrder: const [],
    adjacency: const [],
    attentionEvents: events,
    handFootprint: const HandFootprintDescriptor(
      provenance: HandFootprintProvenance.unknown,
    ),
  );
}
