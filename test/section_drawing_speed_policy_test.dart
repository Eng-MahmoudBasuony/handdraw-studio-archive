import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/features/drawing_engine/domain/section_drawing_speed_policy.dart';

void main() {
  test('speed presets convert duration without changing the baseline work', () {
    final baseline = SectionDrawingSpeedPolicy.baselineDuration(
      resolvedDurationSeconds: 4,
      speedMultiplier: 1,
    );

    expect(
      SectionDrawingSpeedPolicy.durationForSpeed(
        baselineDurationSeconds: baseline,
        speedMultiplier: 2,
      ),
      2,
    );
    expect(
      SectionDrawingSpeedPolicy.durationForSpeed(
        baselineDurationSeconds: baseline,
        speedMultiplier: 0.5,
      ),
      8,
    );
  });

  test('manual duration resolves back to an equivalent custom speed', () {
    expect(
      SectionDrawingSpeedPolicy.speedForDuration(
        baselineDurationSeconds: 3,
        durationSeconds: 2,
      ),
      1.5,
    );
    expect(SectionDrawingSpeedPolicy.isPreset(1.5), isTrue);
    expect(SectionDrawingSpeedPolicy.isPreset(1.35), isFalse);
  });

  test('invalid and out-of-range values stay export safe', () {
    expect(SectionDrawingSpeedPolicy.sanitizeSpeed(double.nan), 1);
    expect(SectionDrawingSpeedPolicy.sanitizeSpeed(0), 0.25);
    expect(SectionDrawingSpeedPolicy.sanitizeSpeed(9), 4);
    expect(
      SectionDrawingSpeedPolicy.durationForSpeed(
        baselineDurationSeconds: 100,
        speedMultiplier: 0.25,
      ),
      60,
    );
  });
}
