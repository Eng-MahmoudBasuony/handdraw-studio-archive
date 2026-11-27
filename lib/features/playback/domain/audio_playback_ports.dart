import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum AudioPlaybackFailureKind { unavailableAsset, prepareFailed, backendFailed }

final class AudioPlaybackFailure {
  const AudioPlaybackFailure({
    required this.kind,
    required this.trackId,
    required this.message,
  });
  final AudioPlaybackFailureKind kind;
  final AudioTrackId trackId;
  final String message;
}

final class AudioAssetUnavailable implements Exception {
  const AudioAssetUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AudioAssetLease {
  ProjectAssetId get assetId;
  Future<void> release();
}

abstract interface class AudioAssetLeaseProvider {
  Future<AudioAssetLease> acquire(ProjectAssetId assetId);
}

final class AudioBackendCallbacks {
  const AudioBackendCallbacks({required this.onFailure, required this.onEnded});
  final void Function(Object error) onFailure;
  final void Function() onEnded;
}

abstract interface class AudioBackendPort {
  Future<AudioBackendTrack> prepare({
    required AudioTrackId trackId,
    required AudioAssetLease lease,
    required AudioBackendCallbacks callbacks,
  });
}

abstract interface class AudioBackendTrack {
  bool get supportsRateAdjustment;
  bool get supportsAccurateSeek;
  Future<TimelineTime> position();
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(TimelineTime sourceTime);
  Future<void> setRate(double rate);
  Future<void> dispose();
}
