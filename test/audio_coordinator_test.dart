import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/playback/domain/audio_coordinator.dart';
import 'package:handdraw_studio/features/playback/domain/audio_playback_ports.dart';
import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test(
    'clock is master for gaps, offsets, multiple tracks, seek and rate',
    () async {
      final harness = _Harness();
      final coordinator = harness.coordinator(
        driftPolicy: const AudioDriftPolicy(
          tolerance: Duration(microseconds: 10),
          softExitTolerance: Duration(microseconds: 5),
          hardSeekThreshold: Duration(microseconds: 40),
        ),
      );
      await coordinator.replaceSnapshot(
        _timeline([
          _track('a', 100, 700, sourceOffset: 500),
          _track('b', 300, 900),
        ]),
      );

      harness.clock.seek(_time(350));
      harness.clock.setPlaybackRate(1.5);
      harness.clock.play();
      await coordinator.synchronize();

      expect(
        harness.backend.tracks[AudioTrackId('a')]!.seeks.last.microseconds,
        750,
      );
      expect(
        harness.backend.tracks[AudioTrackId('b')]!.seeks.last.microseconds,
        50,
      );
      expect(
        harness.backend.tracks.values.every((track) => track.playCount == 1),
        isTrue,
      );
      expect(
        harness.backend.tracks.values.every((track) => track.rates.last == 1.5),
        isTrue,
      );

      harness.clock.pause();
      await coordinator.synchronize();
      expect(
        harness.backend.tracks.values.every((track) => track.pauseCount > 0),
        isTrue,
      );
      harness.clock.stop();
      await coordinator.stop();
      expect(harness.leases.every((lease) => lease.released), isTrue);
      expect(
        harness.backend.tracks.values.every((track) => track.disposed),
        isTrue,
      );
    },
  );

  test(
    'drift policy ignores small, soft-corrects medium, hard-seeks large',
    () async {
      final harness = _Harness();
      final coordinator = harness.coordinator();
      await coordinator.replaceSnapshot(_timeline([_track('a', 0, 1000000)]));
      final backend = harness.backend.tracks[AudioTrackId('a')]!;
      harness.clock.seek(_time(500000));
      harness.clock.play();

      backend.positionValue = _time(490000);
      await coordinator.synchronize();
      expect(backend.seeks, isEmpty);
      expect(backend.rates.last, 1);

      backend.positionValue = _time(450000);
      await coordinator.synchronize();
      expect(backend.rates.last, closeTo(1.02, 0.0001));

      harness.clock.setPlaybackRate(1.5);
      backend.positionValue = _time(450000);
      await coordinator.synchronize();
      expect(backend.rates.last, closeTo(1.53, 0.0001));

      backend.positionValue = _time(490000);
      await coordinator.synchronize();
      expect(backend.rates.last, 1.5);
      backend.positionValue = _time(450000);
      for (var tick = 0; tick < 3; tick++) {
        await coordinator.synchronize();
        expect(backend.rates.last, 1.5);
      }
      await coordinator.synchronize();
      expect(backend.rates.last, closeTo(1.53, 0.0001));

      backend.positionValue = _time(0);
      await coordinator.synchronize();
      expect(backend.seeks.last.microseconds, 500000);
      await coordinator.dispose();
    },
  );

  test(
    'backend without smooth rate or accurate seek uses safe fallback',
    () async {
      final harness = _Harness(
        backend: _Backend(
          supportsRateAdjustment: false,
          supportsAccurateSeek: false,
        ),
      );
      final coordinator = harness.coordinator();
      await coordinator.replaceSnapshot(_timeline([_track('a', 0, 1000000)]));
      harness.clock.seek(_time(500000));
      harness.clock.setPlaybackRate(1.5);
      harness.clock.play();
      final track = harness.backend.tracks[AudioTrackId('a')]!
        ..positionValue = TimelineTime.zero;
      await coordinator.synchronize();
      expect(track.seeks, isEmpty);
      expect(track.rates.last, 1.5);
      await coordinator.dispose();
    },
  );

  test(
    'missing external asset is typed and does not drop the session',
    () async {
      final missing = {ProjectAssetId('asset-missing')};
      final harness = _Harness(missing: missing);
      final coordinator = harness.coordinator();
      await coordinator.replaceSnapshot(
        _timeline([_track('missing', 0, 1000), _track('ok', 0, 1000)]),
      );

      expect(
        coordinator.failures.single.kind,
        AudioPlaybackFailureKind.unavailableAsset,
      );
      expect(harness.backend.tracks.keys, [AudioTrackId('ok')]);
      missing.clear();
      await coordinator.replaceSnapshot(
        _timeline([_track('missing', 0, 1000)]),
      );
      expect(harness.backend.tracks, contains(AudioTrackId('missing')));
      await coordinator.dispose();
    },
  );

  test('voice guide is prepared as a normal clock follower', () async {
    final harness = _Harness();
    final coordinator = harness.coordinator();
    await coordinator.replaceSnapshot(
      _timeline(const [], voice: _voice('voice', 0, 900000)),
    );
    harness.clock.seek(_time(500000));
    harness.clock.play();
    await coordinator.synchronize();
    expect(harness.backend.tracks[AudioTrackId('voice')]!.playCount, 1);
    await coordinator.dispose();
  });

  test(
    'current backend failure releases only its track and keeps session alive',
    () async {
      final harness = _Harness();
      final coordinator = harness.coordinator();
      await coordinator.replaceSnapshot(
        _timeline([_track('bad', 0, 1000), _track('good', 0, 1000)]),
      );
      harness.backend.callbacks['bad']!.onFailure(StateError('decoder'));
      await Future<void>.value();
      await Future<void>.value();
      expect(
        coordinator.failures.single.kind,
        AudioPlaybackFailureKind.backendFailed,
      );
      expect(harness.leases.first.released, isTrue);
      expect(harness.backend.tracks[AudioTrackId('good')]!.disposed, isFalse);
      await coordinator.dispose();
    },
  );

  test(
    'replace and dispose ignore stale callbacks and release leases',
    () async {
      final harness = _Harness();
      final coordinator = harness.coordinator();
      await coordinator.replaceSnapshot(_timeline([_track('old', 0, 1000)]));
      final oldCallbacks = harness.backend.callbacks['old']!;
      await coordinator.replaceSnapshot(_timeline([_track('new', 0, 1000)]));
      oldCallbacks.onFailure(StateError('stale'));
      expect(coordinator.failures, isEmpty);
      expect(harness.leases.first.released, isTrue);

      await coordinator.dispose();
      harness.backend.callbacks['new']!.onFailure(StateError('disposed'));
      expect(coordinator.failures, isEmpty);
      expect(harness.leases.every((lease) => lease.released), isTrue);
    },
  );

  test(
    'dispose during prepare releases late lease without creating a session',
    () async {
      final harness = _Harness(deferredAcquire: true);
      final coordinator = harness.coordinator();
      final replacing = coordinator.replaceSnapshot(
        _timeline([_track('late', 0, 1000)]),
      );
      await Future<void>.value();
      await Future<void>.value();
      final disposing = coordinator.dispose();
      harness.completeAcquire();
      await Future.wait([replacing, disposing]);
      expect(harness.leases.single.released, isTrue);
      expect(harness.backend.tracks, isEmpty);
    },
  );
}

CompiledAudioTimelineTrack _track(
  String id,
  int start,
  int end, {
  int sourceOffset = 0,
}) => CompiledAudioTimelineTrack(
  audioTrackId: AudioTrackId(id),
  assetId: ProjectAssetId('asset-$id'),
  interval: TimelineInterval(start: _time(start), end: _time(end)),
  sourceOffset: _time(sourceOffset),
  affectsTimelineDuration: true,
  referenceOnly: false,
  muted: false,
);

CompiledVoiceGuideTimelineTrack _voice(String id, int start, int end) =>
    CompiledVoiceGuideTimelineTrack(
      audioTrackId: AudioTrackId(id),
      assetId: ProjectAssetId('asset-$id'),
      interval: TimelineInterval(start: _time(start), end: _time(end)),
      sourceOffset: TimelineTime.zero,
      affectsTimelineDuration: true,
      referenceOnly: true,
      muted: false,
    );

CompiledTimeline _timeline(
  List<CompiledAudioTimelineTrack> tracks, {
  CompiledVoiceGuideTimelineTrack? voice,
}) => CompiledTimeline(
  dependencyKey: TimelineDependencyKey(
    projectId: ProjectId('project'),
    documentRevision: 1,
  ),
  duration: _duration(1000000),
  contentEnd: _time(1000000),
  drawing: null,
  audio: tracks,
  voiceGuide: voice,
  sceneMarkers: const [],
);

TimelineTime _time(int us) => TimelineTime.fromMicroseconds(us);
TimelineDuration _duration(int us) => TimelineDuration.fromMicroseconds(us);

final class _Harness implements AudioAssetLeaseProvider {
  _Harness({
    this.missing = const {},
    this.deferredAcquire = false,
    _Backend? backend,
  }) : backend = backend ?? _Backend(),
       clock = PlaybackClock(
         duration: _duration(1000000),
         timeSource: _Time(),
         tickScheduler: _Scheduler(),
       );
  final Set<ProjectAssetId> missing;
  final bool deferredAcquire;
  final PlaybackClock clock;
  final _Backend backend;
  final leases = <_Lease>[];
  Completer<void>? _gate;

  AudioCoordinator coordinator({
    AudioDriftPolicy driftPolicy = const AudioDriftPolicy(),
  }) => AudioCoordinator(
    clock: clock,
    leases: this,
    backend: backend,
    driftPolicy: driftPolicy,
  );
  void completeAcquire() => (_gate ??= Completer<void>()).complete();

  @override
  Future<AudioAssetLease> acquire(ProjectAssetId assetId) async {
    if (missing.contains(assetId)) throw const AudioAssetUnavailable('missing');
    if (deferredAcquire) await (_gate ??= Completer<void>()).future;
    final lease = _Lease(assetId);
    leases.add(lease);
    return lease;
  }
}

final class _Lease implements AudioAssetLease {
  _Lease(this.assetId);
  @override
  final ProjectAssetId assetId;
  bool released = false;
  @override
  Future<void> release() async => released = true;
}

final class _Backend implements AudioBackendPort {
  _Backend({
    this.supportsRateAdjustment = true,
    this.supportsAccurateSeek = true,
  });
  final bool supportsRateAdjustment;
  final bool supportsAccurateSeek;
  final tracks = <AudioTrackId, _BackendTrack>{};
  final callbacks = <String, AudioBackendCallbacks>{};
  @override
  Future<AudioBackendTrack> prepare({
    required AudioTrackId trackId,
    required AudioAssetLease lease,
    required AudioBackendCallbacks callbacks,
  }) async {
    this.callbacks[trackId.value] = callbacks;
    return tracks[trackId] = _BackendTrack(
      supportsRateAdjustment: supportsRateAdjustment,
      supportsAccurateSeek: supportsAccurateSeek,
    );
  }
}

final class _BackendTrack implements AudioBackendTrack {
  _BackendTrack({
    required this.supportsRateAdjustment,
    required this.supportsAccurateSeek,
  });
  TimelineTime positionValue = TimelineTime.zero;
  final seeks = <TimelineTime>[];
  final rates = <double>[];
  int playCount = 0;
  int pauseCount = 0;
  bool disposed = false;
  @override
  final bool supportsRateAdjustment;
  @override
  final bool supportsAccurateSeek;
  @override
  Future<void> dispose() async => disposed = true;
  @override
  Future<void> pause() async => pauseCount++;
  @override
  Future<void> play() async => playCount++;
  @override
  Future<TimelineTime> position() async => positionValue;
  @override
  Future<void> seek(TimelineTime sourceTime) async {
    seeks.add(sourceTime);
    positionValue = sourceTime;
  }

  @override
  Future<void> setRate(double rate) async => rates.add(rate);
  @override
  Future<void> stop() async {}
}

final class _Time implements MonotonicTimeSource {
  @override
  int get elapsedMicroseconds => 0;
}

final class _Scheduler implements PlaybackTickScheduler {
  @override
  PlaybackTickHandle schedule(void Function() onTick) => _Handle();
}

final class _Handle implements PlaybackTickHandle {
  @override
  void cancel() {}
}
