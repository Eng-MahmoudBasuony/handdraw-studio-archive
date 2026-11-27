import 'dart:math' as math;
import 'dart:ui';

/// Adds restrained wrist articulation while keeping the calibrated pen tip on
/// the exact reveal path. The returned angle rotates the hand around the nib;
/// it never offsets the drawing cursor or changes revealed geometry.
final class NaturalHandMotion {
  const NaturalHandMotion();

  static const double _maximumAngle = 12 * math.pi / 180;

  double angleAt({
    required Tangent tangent,
    required double distance,
    required double pathLength,
    required double revealWidth,
  }) {
    if (pathLength <= 0) return 0;

    final progress = (distance / pathLength).clamp(0.0, 1.0);
    final endpointEnvelope = math.min(
      1.0,
      math.min(progress / 0.08, (1 - progress) / 0.08),
    );

    // Treat opposite travel directions as the same pen orientation. Without
    // this normalization an RTL stroke would turn the hand upside down.
    var direction = math.atan2(tangent.vector.dy, tangent.vector.dx);
    while (direction > math.pi / 2) {
      direction -= math.pi;
    }
    while (direction < -math.pi / 2) {
      direction += math.pi;
    }
    final directionalLean = direction.clamp(-0.7, 0.7) * 0.24;

    // Two low-amplitude, non-matching waves avoid a robotic pendulum while
    // remaining deterministic for frame-accurate Preview/MOV parity.
    final wavelength = math.max(28.0, revealWidth * 0.82);
    final primary = math.sin(distance / wavelength * math.pi * 2) * 0.075;
    final secondary =
        math.sin(distance / (wavelength * 2.7) * math.pi * 2 + 0.7) * 0.025;
    final wristRock = (primary + secondary) * endpointEnvelope;

    return (directionalLean + wristRock).clamp(-_maximumAngle, _maximumAngle);
  }
}
