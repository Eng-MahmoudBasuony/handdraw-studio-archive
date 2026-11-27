import 'dart:async';

import 'package:handdraw_studio/features/playback/domain/audio_playback_ports.dart';
import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

final class AudioDriftPolicy {
  const AudioDriftPolicy({
    this.tolerance = const Duration(milliseconds: 20),
    this.softExitTolerance = const Duration(milliseconds: 12),
    this.hardSeekThreshold = const Duration(milliseconds: 120),
    this.softCorrectionFraction = 0.02,
    this.reentryCooldownTicks = 3,
  });

  final Duration tolerance;
  final Duration softExitTolerance;
  final Duration hardSeekThreshold;
  final double softCorrectionFraction;
  final int reentryCooldownTicks;
}

typedef AudioCoordinatorListener =
    void Function(List<AudioPlaybackFailure> failures);

/// Follows [PlaybackClock]. Backend positions never update the master clock.
final class AudioCoordinator {
  AudioCoordinator({
    required this.clock,
    required AudioAssetLeaseProvider leases,
    required AudioBackendPort backend,
    this.driftPolicy = const AudioDriftPolicy(),
    // Public dependency names are clearer than exposing private field names.
    // ignore: prefer_initializing_formals
  }) : _leases = leases,
       // ignore: prefer_initializing_formals
       _backend = backend {
    if (driftPolicy.hardSeekThreshold.inMicroseconds <
            driftPolicy.tolerance.inMicroseconds ||
        driftPolicy.softCorrectionFraction <= 0 ||
        driftPolicy.softCorrectionFraction >= 0.25 ||
        driftPolicy.softExitTolerance.inMicroseconds >=
            driftPolicy.tolerance.inMicroseconds ||
        driftPolicy.reentryCooldownTicks < 0) {
      throw ArgumentError.value(driftPolicy, 'driftPolicy');
    }
    clock.addListener(_onClock);
  }

  final PlaybackClock clock;
  final AudioAssetLeaseProvider _leases;
  final AudioBackendPort _backend;
  final AudioDriftPolicy driftPolicy;
  final Set<AudioCoordinatorListener> _listeners = {};
  final Map<AudioTrackId, _PreparedAudioTrack> _prepared = {};
  final List<AudioPlaybackFailure> _failures = [];
  CompiledTimeline? _snapshot;
  int _generation = 0;
  bool _disposed = false;
  bool _syncing = false;
  bool _syncRequested = false;
  Completer<void>? _syncCompletion;

  List<AudioPlaybackFailure> get failures => List.unmodifiable(_failures);
  int get generation => _generation;

  void addListener(AudioCoordinatorListener listener) =>
      _listeners.add(listener);
  void removeListener(AudioCoordinatorListener listener) =>
      _listeners.remove(listener);

  Future<void> replaceSnapshot(CompiledTimeline snapshot) async {
    _ensureActive();
    final pendingSync = _syncCompletion?.future;
    final generation = ++_generation;
    await pendingSync;
    await _releaseAll();
    if (!_isCurrent(generation)) return;
    _snapshot = snapshot;
    _failures.clear();
    final tracks = <_AudioTrackSpec>[
      for (final track in snapshot.audio)
        if (!track.muted)
          _AudioTrackSpec(
            id: track.audioTrackId,
            assetId: track.assetId,
            interval: track.interval,
            sourceOffset: track.sourceOffset,
          ),
      if (snapshot.voiceGuide case final voice?)
        if (!voice.muted)
          _AudioTrackSpec(
            id: voice.audioTrackId,
            assetId: voice.assetId,
            interval: voice.interval,
            sourceOffset: voice.sourceOffset,
          ),
    ];
    await Future.wait([for (final spec in tracks) _prepare(spec, generation)]);
    if (_isCurrent(generation)) await synchronize();
  }

  Future<void> synchronize() async {
    if (_disposed || _snapshot == null) return;
    if (_syncing) {
      _syncRequested = true;
      return _syncCompletion!.future;
    }
    _syncing = true;
    final completion = _syncCompletion = Completer<void>();
    try {
      do {
        _syncRequested = false;
        final generation = _generation;
        final snapshot = _snapshot;
        if (snapshot == null) break;
        final time = clock.currentTime.clampTo(snapshot.duration);
        for (final prepared in [..._prepared.values]) {
          if (!_isCurrent(generation)) break;
          try {
            await _syncTrack(prepared, time, clock.status, generation);
          } on Object catch (error) {
            if (_isCurrent(generation)) {
              _prepared.remove(prepared.spec.id);
              _recordFailure(
                AudioPlaybackFailure(
                  kind: AudioPlaybackFailureKind.backendFailed,
                  trackId: prepared.spec.id,
                  message: '$error',
                ),
              );
              await _release(prepared);
            }
          }
        }
      } while (_syncRequested && !_disposed);
    } finally {
      _syncing = false;
      _syncCompletion = null;
      completion.complete();
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    final pendingSync = _syncCompletion?.future;
    ++_generation;
    _snapshot = null;
    await pendingSync;
    await _releaseAll();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final pendingSync = _syncCompletion?.future;
    _disposed = true;
    ++_generation;
    clock.removeListener(_onClock);
    await pendingSync;
    await _releaseAll();
    _listeners.clear();
  }

  Future<void> _prepare(_AudioTrackSpec spec, int generation) async {
    AudioAssetLease? lease;
    try {
      lease = await _leases.acquire(spec.assetId);
      if (!_isCurrent(generation)) {
        await lease.release();
        return;
      }
      final handle = await _backend.prepare(
        trackId: spec.id,
        lease: lease,
        callbacks: AudioBackendCallbacks(
          onFailure: (error) => _backendFailure(spec.id, error, generation),
          onEnded: () => _backendEnded(spec.id, generation),
        ),
      );
      if (!_isCurrent(generation)) {
        await handle.dispose();
        await lease.release();
        return;
      }
      _prepared[spec.id] = _PreparedAudioTrack(
        spec: spec,
        lease: lease,
        handle: handle,
      );
    } on AudioAssetUnavailable catch (error) {
      if (_isCurrent(generation)) {
        _recordFailure(
          AudioPlaybackFailure(
            kind: AudioPlaybackFailureKind.unavailableAsset,
            trackId: spec.id,
            message: error.message,
          ),
        );
      }
      await lease?.release();
    } on Object catch (error) {
      if (_isCurrent(generation)) {
        _recordFailure(
          AudioPlaybackFailure(
            kind: AudioPlaybackFailureKind.prepareFailed,
            trackId: spec.id,
            message: '$error',
          ),
        );
      }
      await lease?.release();
    }
  }

  Future<void> _syncTrack(
    _PreparedAudioTrack prepared,
    TimelineTime projectTime,
    PlaybackStatus status,
    int generation,
  ) async {
    final active = prepared.spec.interval.contains(projectTime);
    if (!active ||
        status == PlaybackStatus.stopped ||
        status == PlaybackStatus.ended) {
      await prepared.handle.pause();
      prepared.playing = false;
      return;
    }
    final expected = TimelineTime.fromMicroseconds(
      prepared.spec.sourceOffset.microseconds +
          projectTime.difference(prepared.spec.interval.start).microseconds,
    );
    final actual = await prepared.handle.position();
    if (!_isCurrent(generation)) return;
    final driftUs = actual.microseconds - expected.microseconds;
    final magnitude = driftUs.abs();
    if (magnitude > driftPolicy.hardSeekThreshold.inMicroseconds &&
        prepared.handle.supportsAccurateSeek) {
      await prepared.handle.seek(expected);
      await prepared.handle.setRate(clock.playbackRate);
      prepared.driftMode = _DriftMode.normal;
      prepared.cooldownTicks = driftPolicy.reentryCooldownTicks;
    } else if (prepared.driftMode == _DriftMode.soft &&
        magnitude <= driftPolicy.softExitTolerance.inMicroseconds) {
      await prepared.handle.setRate(clock.playbackRate);
      prepared.driftMode = _DriftMode.normal;
      prepared.cooldownTicks = driftPolicy.reentryCooldownTicks;
    } else if ((prepared.driftMode == _DriftMode.soft ||
            (magnitude > driftPolicy.tolerance.inMicroseconds &&
                prepared.cooldownTicks == 0)) &&
        prepared.handle.supportsRateAdjustment) {
      final correction = driftUs > 0
          ? 1 - driftPolicy.softCorrectionFraction
          : 1 + driftPolicy.softCorrectionFraction;
      await prepared.handle.setRate(clock.playbackRate * correction);
      prepared.driftMode = _DriftMode.soft;
    } else {
      await prepared.handle.setRate(clock.playbackRate);
      if (prepared.cooldownTicks > 0) prepared.cooldownTicks--;
    }
    if (status == PlaybackStatus.playing && !prepared.playing) {
      await prepared.handle.play();
      prepared.playing = true;
    } else if (status != PlaybackStatus.playing && prepared.playing) {
      await prepared.handle.pause();
      prepared.playing = false;
    }
  }

  void _onClock(PlaybackClockState state) {
    unawaited(synchronize());
  }

  void _backendFailure(AudioTrackId trackId, Object error, int generation) {
    if (!_isCurrent(generation)) return;
    _recordFailure(
      AudioPlaybackFailure(
        kind: AudioPlaybackFailureKind.backendFailed,
        trackId: trackId,
        message: '$error',
      ),
    );
    final prepared = _prepared.remove(trackId);
    if (prepared != null) unawaited(_release(prepared));
  }

  void _backendEnded(AudioTrackId trackId, int generation) {
    if (!_isCurrent(generation)) return;
    final prepared = _prepared[trackId];
    if (prepared != null) prepared.playing = false;
  }

  void _recordFailure(AudioPlaybackFailure failure) {
    _failures.add(failure);
    final snapshot = List<AudioPlaybackFailure>.unmodifiable(_failures);
    for (final listener in [..._listeners]) {
      listener(snapshot);
    }
  }

  Future<void> _releaseAll() async {
    final tracks = [..._prepared.values];
    _prepared.clear();
    await Future.wait([for (final track in tracks) _release(track)]);
  }

  Future<void> _release(_PreparedAudioTrack prepared) async {
    try {
      await prepared.handle.stop();
    } on Object {
      // Release must continue after a backend shutdown failure.
    }
    try {
      await prepared.handle.dispose();
    } on Object {
      // The asset lease still must be released.
    }
    await prepared.lease.release();
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;
  void _ensureActive() {
    if (_disposed) throw StateError('AudioCoordinator is disposed.');
  }
}

final class _AudioTrackSpec {
  const _AudioTrackSpec({
    required this.id,
    required this.assetId,
    required this.interval,
    required this.sourceOffset,
  });
  final AudioTrackId id;
  final ProjectAssetId assetId;
  final TimelineInterval interval;
  final TimelineTime sourceOffset;
}

final class _PreparedAudioTrack {
  _PreparedAudioTrack({
    required this.spec,
    required this.lease,
    required this.handle,
  });
  final _AudioTrackSpec spec;
  final AudioAssetLease lease;
  final AudioBackendTrack handle;
  bool playing = false;
  _DriftMode driftMode = _DriftMode.normal;
  int cooldownTicks = 0;
}

enum _DriftMode { normal, soft }
