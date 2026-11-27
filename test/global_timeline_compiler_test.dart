import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/ports/drawing_timeline_compiler_adapter.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';
import 'package:handdraw_studio/features/timeline/domain/services/timeline_compiler.dart';

void main() {
  const resolver = GlobalTimelineResolver();

  test('zero duration compiles and resolves deterministically', () {
    final compiled = _compile(_document(), drawingUs: 0);
    final frame = resolver.resolveAt(compiled, TimelineTime.zero);

    expect(compiled.duration, TimelineDuration.zero);
    expect(frame.time, TimelineTime.zero);
    expect(frame.isFinalFrame, isTrue);
    expect(frame.drawing?.isHeld, isTrue);
  });

  test('audio and voice use [start, end) and independent export policy', () {
    final included = _audio('included', startUs: 100, durationUs: 200);
    final ignored = _audio(
      'ignored',
      startUs: 600,
      durationUs: 500,
      affectsDuration: false,
      exportPolicy: AudioExportPolicy.embedInOutput,
    );
    final document = _document(audio: [included, ignored], voice: included);
    final compiled = _compile(document, drawingUs: 50);

    expect(compiled.duration.microseconds, 300);
    expect(compiled.voiceGuide?.referenceOnly, isTrue);
    expect(resolver.resolveAt(compiled, _time(100)).voiceGuide, isNotNull);
    expect(resolver.resolveAt(compiled, _time(299)).voiceGuide, isNotNull);
    expect(resolver.resolveAt(compiled, _time(300)).voiceGuide, isNull);
    expect(compiled.audio.single.audioTrackId, ignored.id);
  });

  test('drawing or voice can independently define project duration', () {
    final voice = _audio('voice', durationUs: 900);
    expect(
      _compile(
        _document(audio: [voice], voice: voice),
        drawingUs: 400,
      ).duration.microseconds,
      900,
    );
    expect(
      _compile(
        _document(audio: [voice], voice: voice),
        drawingUs: 1200,
      ).duration.microseconds,
      1200,
    );
  });

  test(
    'section pauses, gaps, explicit holds, markers, and final hold survive',
    () {
      final sectionA = SectionId('a');
      final sectionB = SectionId('b');
      final scene = SceneId('scene');
      final document = _document(
        sections: [sectionA, sectionB],
        scenes: [scene],
        timeline: PersistentTimeline(
          leadingHold: _duration(100),
          trailingHold: _duration(300),
          sceneMarkers: [
            PersistentSceneMarker(sceneId: scene, time: _time(250)),
          ],
        ),
      );
      final compiled = TimelineCompiler(
        drawingAdapter: _FakeDrawingAdapter(
          duration: _duration(800),
          sections: [
            _section(sectionA, 0, 200),
            // [200, 500) is the authored pause/gap.
            _section(sectionB, 500, 800),
          ],
        ),
      ).compile(document: document, documentRevision: 11);

      expect(compiled.duration.microseconds, 1200);
      expect(compiled.dependencyKey.documentRevision, 11);
      expect(
        resolver.resolveAt(compiled, _time(350)).drawing?.sectionId,
        isNull,
      );
      expect(resolver.resolveAt(compiled, _time(350)).markers, [scene]);
      final finalFrame = resolver.resolveAt(compiled, _time(1200));
      expect(finalFrame.drawing?.localTime.microseconds, 800);
      expect(finalFrame.drawing?.sectionId, sectionB);
      expect(finalFrame.drawing?.isHeld, isTrue);
    },
  );

  test('sequential and random seeks return identical frames', () {
    final audio = _audio('music', startUs: 150, durationUs: 500);
    final compiled = _compile(_document(audio: [audio]), drawingUs: 1000);
    final times = [for (var us = 0; us <= 1000; us += 10) _time(us)];
    final sequential = {
      for (final time in times)
        time: _signature(resolver.resolveAt(compiled, time)),
    };
    final random = [...times]..shuffle(Random(47));

    for (final time in random) {
      expect(_signature(resolver.resolveAt(compiled, time)), sequential[time]);
    }
  });
}

CompiledTimeline _compile(ProjectDocument document, {required int drawingUs}) =>
    TimelineCompiler(
      drawingAdapter: _FakeDrawingAdapter(duration: _duration(drawingUs)),
    ).compile(document: document, documentRevision: 3);

ProjectDocument _document({
  List<ProjectAudioTrack> audio = const [],
  ProjectAudioTrack? voice,
  List<SectionId> sections = const [],
  List<SceneId> scenes = const [],
  PersistentTimeline? timeline,
}) {
  final effectiveTimeline =
      timeline ??
      PersistentTimeline(
        audio: [
          for (final track in audio)
            PersistentAudioTimelineTrack(audioTrackId: track.id),
        ],
        voiceGuide: voice == null
            ? null
            : PersistentVoiceGuideTimelineTrack(audioTrackId: voice.id),
      );
  return ProjectDocument(
    id: ProjectId('project'),
    title: 'Timeline fixture',
    canvas: const ProjectCanvas(width: 1920, height: 1080),
    frameRate: FrameRate.fps30,
    duration: TimelineDuration.zero,
    assets: [
      for (final track in audio)
        ProjectAsset(
          id: track.assetId,
          kind: ProjectAssetKind.audio,
          originalFileName: '${track.id.value}.wav',
          storagePolicy: ProjectAssetStoragePolicy.embedded,
          contentHash: 'hash-${track.id.value}',
        ),
    ],
    strokes: const [],
    sections: [
      for (final id in sections)
        ProjectSection(id: id, name: id.value, strokeIds: const []),
    ],
    sectionOrder: sections,
    scenes: [
      for (final id in scenes)
        ProjectScene(id: id, name: id.value, sectionIds: sections),
    ],
    audioTracks: audio,
    voiceGuide: voice == null
        ? null
        : ProjectVoiceGuide(
            audioTrackId: voice.id,
            displayName: 'Voice',
            originalFileName: 'voice.wav',
          ),
    timeline: effectiveTimeline,
  );
}

ProjectAudioTrack _audio(
  String id, {
  int startUs = 0,
  required int durationUs,
  bool affectsDuration = true,
  AudioExportPolicy exportPolicy = AudioExportPolicy.referenceOnly,
}) => ProjectAudioTrack(
  id: AudioTrackId(id),
  assetId: ProjectAssetId('asset-$id'),
  start: _time(startUs),
  duration: _duration(durationUs),
  exportPolicy: exportPolicy,
  affectsTimelineDuration: affectsDuration,
);

CompiledDrawingSection _section(SectionId id, int start, int end) =>
    CompiledDrawingSection(
      sectionId: id,
      interval: TimelineInterval(start: _time(start), end: _time(end)),
    );
TimelineTime _time(int value) => TimelineTime.fromMicroseconds(value);
TimelineDuration _duration(int value) =>
    TimelineDuration.fromMicroseconds(value);

String _signature(dynamic frame) =>
    '${frame.time.microseconds}:${frame.drawing?.localTime.microseconds}:'
    '${frame.drawing?.sectionId}:${frame.drawing?.isHeld}:'
    '${frame.activeAudio.map((dynamic item) => item.audioTrackId).join(',')}:'
    '${frame.voiceGuide?.audioTrackId}:${frame.isFinalFrame}';

final class _FakeDrawingAdapter implements DrawingTimelineCompilerAdapter {
  _FakeDrawingAdapter({required this.duration, this.sections = const []});
  final TimelineDuration duration;
  final List<CompiledDrawingSection> sections;

  @override
  AdaptedDrawingTimeline compile(ProjectDocument document) =>
      AdaptedDrawingTimeline(duration: duration, sections: sections);
}
