final class TimelineFollowPolicy {
  const TimelineFollowPolicy({
    this.forwardThreshold = .75,
    this.backwardThreshold = .20,
    this.targetAlignment = .30,
  });

  final double forwardThreshold;
  final double backwardThreshold;
  final double targetAlignment;

  double? targetOffset({
    required bool enabled,
    required double playheadX,
    required double currentOffset,
    required double viewportWidth,
    required double maximumOffset,
  }) {
    if (!enabled || viewportWidth <= 0 || maximumOffset <= 0) return null;
    final left = currentOffset + viewportWidth * backwardThreshold;
    final right = currentOffset + viewportWidth * forwardThreshold;
    if (playheadX >= left && playheadX <= right) return null;
    return (playheadX - viewportWidth * targetAlignment)
        .clamp(0, maximumOffset)
        .toDouble();
  }
}
