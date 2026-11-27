class SectionDrawingSpeedPolicy {
  const SectionDrawingSpeedPolicy._();

  static const double minimum = 0.25;
  static const double maximum = 4;
  static const List<double> presets = [0.25, 0.5, 1, 1.5, 2];

  static double sanitizeSpeed(double value) {
    if (!value.isFinite) return 1;
    return value.clamp(minimum, maximum);
  }

  static double baselineDuration({
    required double resolvedDurationSeconds,
    required double speedMultiplier,
  }) {
    final duration = resolvedDurationSeconds.isFinite
        ? resolvedDurationSeconds.clamp(0.05, 60)
        : 1.0;
    return duration * sanitizeSpeed(speedMultiplier);
  }

  static double durationForSpeed({
    required double baselineDurationSeconds,
    required double speedMultiplier,
  }) => (baselineDurationSeconds / sanitizeSpeed(speedMultiplier)).clamp(
    0.05,
    60,
  );

  static double speedForDuration({
    required double baselineDurationSeconds,
    required double durationSeconds,
  }) {
    final duration = durationSeconds.isFinite
        ? durationSeconds.clamp(0.05, 60)
        : baselineDurationSeconds;
    return sanitizeSpeed(baselineDurationSeconds / duration);
  }

  static bool isPreset(double value, {double tolerance = 0.001}) =>
      presets.any((preset) => (preset - value).abs() <= tolerance);
}
