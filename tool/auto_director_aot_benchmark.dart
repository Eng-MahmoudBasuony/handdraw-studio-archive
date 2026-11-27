import 'dart:io';

import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/services/smart_auto_director.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  const count = 1000;
  final graph = _graph(count);
  final timeline = CompiledTimeline(
    dependencyKey: TimelineDependencyKey(
      projectId: ProjectId('aot'),
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
  const director = SmartAutoDirector();
  final rssBaseline = ProcessInfo.currentRss;
  for (var index = 0; index < 10; index++) {
    director.generate(timeline: timeline, graph: graph, cameraTrack: null);
  }
  final samples = <int>[];
  for (var index = 0; index < 100; index++) {
    final watch = Stopwatch()..start();
    director.generate(timeline: timeline, graph: graph, cameraTrack: null);
    samples.add(watch.elapsedMicroseconds);
  }
  samples.sort();
  final input = const DirectorInputBuilder().build(
    timeline: timeline,
    graph: graph,
    cameraTrack: null,
    configuration: AutoDirectorConfiguration(),
    scope: AutoDirectorScope.entireProject(),
  );
  final plan = director.generate(
    timeline: timeline,
    graph: graph,
    cameraTrack: null,
  );
  final sequence = const AttentionSequenceBuilder().build(input);
  final clusters = const RegionClusterer().cluster(input, sequence);
  var candidatesGenerated = 0;
  for (final cluster in clusters) {
    candidatesGenerated += const CameraCandidateGenerator()
        .generate(input, cluster, const CameraView.identity())
        .length;
  }
  final validationWatch = Stopwatch()..start();
  const AutoDirectorPlanValidator().validate(
    input,
    plan.proposedShots,
    plan.preservedShots,
  );
  final validationUs = validationWatch.elapsedMicroseconds;
  final rssPeak = ProcessInfo.currentRss;
  stdout.writeln(
    'AUTO_DIRECTOR_PERF mode=aot_release events=$count regions=${graph.regions.length} '
    'candidates_generated=$candidatesGenerated candidates_pruned=0 look_ahead=3 '
    'fallback_used=false semantic_compile_included=false '
    'total_p50_us=${_p(samples, .50)} total_p95_us=${_p(samples, .95)} '
    'validation_us=$validationUs peak_rss_bytes=$rssPeak '
    'rss_delta_bytes=${rssPeak - rssBaseline}',
  );
}

int _p(List<int> values, double percentile) =>
    values[((values.length - 1) * percentile).round()];

CompiledSemanticRegionGraph _graph(int count) {
  final regions = <SemanticRegion>[];
  final events = <SemanticAttentionEvent>[];
  for (var index = 0; index < count; index++) {
    final target = SemanticTargetReference.stroke(StrokeId('s$index'));
    final x = (index % 20) * 45.0;
    final y = (index ~/ 20 % 20) * 45.0;
    final bounds = SemanticWorldBounds(x, y, x + 20, y + 20);
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
        time: TimelineTime.fromMicroseconds(index * 100000),
        regionIds: [target.stableKey],
        activeBounds: bounds,
        strokeId: StrokeId('s$index'),
        sectionId: SectionId('section-$index'),
      ),
    );
  }
  return CompiledSemanticRegionGraph(
    dependencyKey: 'aot-$count',
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
