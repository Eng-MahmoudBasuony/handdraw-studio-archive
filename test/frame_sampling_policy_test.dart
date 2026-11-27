import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/project/domain/policies/project_limits.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/frame_sampling_policy.dart';

void main() {
  const policy = FrameSamplingPolicy();

  TimelineDuration duration(int microseconds) =>
      TimelineDuration.fromMicroseconds(microseconds);

  test('normalizes rational frame rates exactly', () {
    expect(FrameRate(numerator: 60000, denominator: 2002), FrameRate.ntsc2997);
    expect(FrameRate.fps24.compareTo(FrameRate.fps30), isNegative);
  });

  test('rejects invalid frame-rate numerator and denominator', () {
    expect(() => FrameRate(numerator: 0), throwsRangeError);
    expect(() => FrameRate(numerator: 30, denominator: 0), throwsRangeError);
    expect(() => FrameRate(numerator: -30, denominator: 1), throwsRangeError);
  });

  test('zero duration contains no export frames', () {
    expect(
      policy.frameCount(
        duration: TimelineDuration.zero,
        frameRate: FrameRate.fps30,
      ),
      0,
    );
    expect(
      () => policy.timeForFrame(
        index: 0,
        duration: TimelineDuration.zero,
        frameRate: FrameRate.fps30,
      ),
      throwsRangeError,
    );
  });

  test('exact one-second durations never add a sample at the end', () {
    final oneSecond = duration(1000000);

    for (final entry in {
      FrameRate.fps24: 24,
      FrameRate.fps30: 30,
      FrameRate.fps60: 60,
      FrameRate.ntsc2997: 30,
    }.entries) {
      final count = policy.frameCount(
        duration: oneSecond,
        frameRate: entry.key,
      );
      expect(count, entry.value, reason: '${entry.key}');
      expect(
        policy
            .timeForFrame(
              index: count - 1,
              duration: oneSecond,
              frameRate: entry.key,
            )
            .microseconds,
        lessThan(oneSecond.microseconds),
      );
    }
  });

  test('non-aligned duration includes every real sample before the end', () {
    final nonAligned = duration(1010000);
    final expectations = {
      FrameRate.fps24: (25, 1000000),
      FrameRate.fps30: (31, 1000000),
      FrameRate.fps60: (61, 1000000),
      FrameRate.ntsc2997: (31, 1001000),
    };

    for (final entry in expectations.entries) {
      final count = policy.frameCount(
        duration: nonAligned,
        frameRate: entry.key,
      );
      expect(count, entry.value.$1, reason: '${entry.key}');
      expect(
        policy
            .timeForFrame(
              index: count - 1,
              duration: nonAligned,
              frameRate: entry.key,
            )
            .microseconds,
        entry.value.$2,
        reason: '${entry.key}',
      );
    }
  });

  test('fractional frame timestamps use deterministic floor rounding', () {
    final tenSeconds = duration(10000000);

    expect(
      policy
          .timeForFrame(
            index: 1,
            duration: tenSeconds,
            frameRate: FrameRate.ntsc2997,
          )
          .microseconds,
      33366,
    );
    expect(
      policy
          .timeForFrame(
            index: 30,
            duration: tenSeconds,
            frameRate: FrameRate.ntsc2997,
          )
          .microseconds,
      1001000,
    );
  });

  test('invalid positive and negative frame indices are rejected', () {
    final oneSecond = duration(1000000);

    expect(
      () => policy.timeForFrame(
        index: -1,
        duration: oneSecond,
        frameRate: FrameRate.fps30,
      ),
      throwsRangeError,
    );
    expect(
      () => policy.timeForFrame(
        index: 30,
        duration: oneSecond,
        frameRate: FrameRate.fps30,
      ),
      throwsRangeError,
    );
  });

  test('24-hour maximum is exact at the largest supported frame rate', () {
    ProjectLimits.validateDuration(ProjectLimits.maximumDuration);
    final count = policy.frameCount(
      duration: ProjectLimits.maximumDuration,
      frameRate: FrameRate.fps60,
    );

    expect(count, 5184000);
    expect(
      policy
          .timeForFrame(
            index: count - 1,
            duration: ProjectLimits.maximumDuration,
            frameRate: FrameRate.fps60,
          )
          .microseconds,
      ProjectLimits.maximumDurationMicroseconds - 16667,
    );
  });

  test('large integer arithmetic does not wrap or become negative', () {
    final largeDuration = duration(1 << 50);
    final count = policy.frameCount(
      duration: largeDuration,
      frameRate: FrameRate(numerator: 120000, denominator: 1001),
    );

    expect(count, greaterThan(0));
    expect(
      policy
          .timeForFrame(
            index: count - 1,
            duration: largeDuration,
            frameRate: FrameRate(numerator: 120000, denominator: 1001),
          )
          .microseconds,
      lessThan(largeDuration.microseconds),
    );
  });

  test('large NTSC sample indices have no accumulated drift', () {
    final longDuration = duration(12 * 60 * 60 * 1000000);
    const indices = [0, 1, 29, 30, 1000, 100000, 1000000];

    for (final index in indices) {
      final actual = policy.timeForFrame(
        index: index,
        duration: longDuration,
        frameRate: FrameRate.ntsc2997,
      );
      expect(actual.microseconds, index * 1000000 * 1001 ~/ 30000);
    }
  });

  test('preview times map to the same exact samples used by export', () {
    final projectDuration = duration(1000000);

    expect(
      policy.frameIndexForTime(
        time: TimelineTime.zero,
        duration: projectDuration,
        frameRate: FrameRate.fps30,
      ),
      0,
    );
    expect(
      policy.frameIndexForTime(
        time: TimelineTime.fromMicroseconds(33332),
        duration: projectDuration,
        frameRate: FrameRate.fps30,
      ),
      0,
    );
    expect(
      policy.frameIndexForTime(
        time: TimelineTime.fromMicroseconds(33333),
        duration: projectDuration,
        frameRate: FrameRate.fps30,
      ),
      0,
    );
    expect(
      policy.frameIndexForTime(
        time: TimelineTime.fromMicroseconds(33334),
        duration: projectDuration,
        frameRate: FrameRate.fps30,
      ),
      1,
    );
    expect(
      policy.frameIndexForTime(
        time: TimelineTime.fromMicroseconds(1000000),
        duration: projectDuration,
        frameRate: FrameRate.fps30,
      ),
      29,
    );
  });

  test('60 Hz ticks resolve only 30 distinct visual samples at 30 fps', () {
    final projectDuration = duration(1000000);
    final visualSamples = <int>{};

    for (var tick = 0; tick <= 60; tick++) {
      visualSamples.add(
        policy.frameIndexForTime(
          time: TimelineTime.fromMicroseconds(tick * 1000000 ~/ 60),
          duration: projectDuration,
          frameRate: FrameRate.fps30,
        )!,
      );
    }

    expect(visualSamples, hasLength(30));
    expect(visualSamples.first, 0);
    expect(visualSamples.last, 29);
  });

  test('sampling properties hold across rates and non-aligned durations', () {
    final rates = [
      FrameRate.fps24,
      FrameRate.fps30,
      FrameRate.fps60,
      FrameRate.ntsc2997,
    ];
    final durations = [1, 33333, 33367, 999999, 1000000, 1000001, 10123456];

    for (final rate in rates) {
      for (final micros in durations) {
        final projectDuration = duration(micros);
        final count = policy.frameCount(
          duration: projectDuration,
          frameRate: rate,
        );
        TimelineTime? previous;
        for (var index = 0; index < count; index++) {
          final current = policy.timeForFrame(
            index: index,
            duration: projectDuration,
            frameRate: rate,
          );
          expect(current.microseconds, lessThan(micros));
          if (previous != null) {
            expect(current.compareTo(previous), isNonNegative);
          }
          previous = current;
        }

        // The first omitted rational sample is at or beyond the duration.
        expect(
          count * 1000000 * rate.denominator,
          greaterThanOrEqualTo(micros * rate.numerator),
        );
        if (count > 0) {
          expect(
            (count - 1) * 1000000 * rate.denominator,
            lessThan(micros * rate.numerator),
          );
        }
      }
    }
  });

  test('source guard supplements behavioral integer-arithmetic tests', () {
    final source = File(
      'lib/features/timeline/domain/services/frame_sampling_policy.dart',
    ).readAsStringSync();

    expect(RegExp(r'\bdouble\b').hasMatch(source), isFalse);
    expect(source, isNot(contains('.round(')));
    expect(source, isNot(contains('.ceil(')));
    expect(source, isNot(contains('.floor(')));
  });
}
