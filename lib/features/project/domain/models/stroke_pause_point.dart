/// A timed hold anchored to normalized arc-length progress on one stroke.
///
/// Progress is independent from the stroke's sampled point count, so path
/// smoothing and point reduction do not move an authored pause unexpectedly.
class StrokePausePoint {
  const StrokePausePoint({
    required this.id,
    required this.progress,
    required this.durationSeconds,
    this.keepHandVisible = true,
  });

  final String id;
  final double progress;
  final double durationSeconds;
  final bool keepHandVisible;

  StrokePausePoint copyWith({
    String? id,
    double? progress,
    double? durationSeconds,
    bool? keepHandVisible,
  }) => StrokePausePoint(
    id: id ?? this.id,
    progress: progress ?? this.progress,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    keepHandVisible: keepHandVisible ?? this.keepHandVisible,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'progress': progress,
    'durationSeconds': durationSeconds,
    'keepHandVisible': keepHandVisible,
  };

  factory StrokePausePoint.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress'];
    final rawDuration = json['durationSeconds'];
    final progress = rawProgress is num && rawProgress.toDouble().isFinite
        ? rawProgress.toDouble().clamp(0.01, 0.99)
        : 0.5;
    final duration = rawDuration is num && rawDuration.toDouble().isFinite
        ? rawDuration.toDouble().clamp(0.05, 60.0)
        : 0.5;
    return StrokePausePoint(
      id:
          json['id'] as String? ??
          'pause-${DateTime.now().microsecondsSinceEpoch}',
      progress: progress,
      durationSeconds: duration,
      keepHandVisible: json['keepHandVisible'] as bool? ?? true,
    );
  }
}
