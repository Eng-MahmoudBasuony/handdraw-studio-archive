import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';

void main() {
  testWidgets('reference reveal keeps a fast nib sweep and a clean exit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1800, 338));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: ValueKey('reference-reveal-motion-strip'),
          child: CustomPaint(
            size: Size(1800, 338),
            painter: _ReferenceMotionStripPainter(),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('reference-reveal-motion-strip')),
      matchesGoldenFile('goldens/reference_reveal_motion.png'),
    );
  });
}

final class _ReferenceMotionStripPainter extends CustomPainter {
  const _ReferenceMotionStripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const panel = ui.Size(300, 169);
    const artwork = ui.Rect.fromLTWH(0, 0, 300, 169);
    const duration = 5.41;
    const sampleSeconds = [0.0, .33, .66, .99, 1.21, 1.42];
    const timings = {
      'section:reference': SectionTiming(
        animationDurationSeconds: 1,
        handExitAnimation: SectionHandExitAnimation.moveOut,
        handExitDurationSeconds: .42,
      ),
    };

    for (final direction in [false, true].indexed) {
      final rightToLeft = direction.$2;
      final stroke = DrawingStroke(
        id: 'reference-reveal-${rightToLeft ? 'rtl' : 'ltr'}',
        name: 'Reference reveal',
        sectionId: 'reference',
        points: rightToLeft
            ? const [ui.Offset(.67381, .52), ui.Offset(.1, .52)]
            : const [ui.Offset(.1, .52), ui.Offset(.67381, .52)],
        revealOnly: true,
        revealStyle: RevealMaskStyle.directionalWipe,
        clipBounds: const ui.Rect.fromLTWH(.1, .31, .57381, .42),
        revealWidth: 72,
      );
      for (final sample in sampleSeconds.indexed) {
        final snapshot = buildTimelineSnapshot(
          strokes: [stroke],
          artworkRect: artwork,
          timingRect: artwork,
          progress: sample.$2 / duration,
          durationSeconds: duration,
          drawingDurationSeconds: 1,
          startDelaySeconds: 0,
          endHoldSeconds: 3.99,
          sectionTimings: timings,
        );
        canvas.save();
        canvas.translate(sample.$1 * panel.width, direction.$1 * panel.height);
        canvas.drawRect(
          ui.Offset.zero & panel,
          Paint()..color = const Color(0xFFFDFDFC),
        );
        canvas.save();
        final frontier = snapshot.phase == TimelinePhase.drawing
            ? snapshot.handPosition.dx
            : rightToLeft
            ? 30.0
            : 202.143;
        canvas.clipRect(
          rightToLeft
              ? ui.Rect.fromLTRB(frontier, 0, 202.143, panel.height)
              : ui.Rect.fromLTRB(30, 0, frontier, panel.height),
        );
        _drawContent(canvas);
        canvas.restore();
        if (snapshot.handVisible) _drawHand(canvas, snapshot);
        _drawTime(canvas, sample.$2, rightToLeft: rightToLeft);
        canvas.drawRect(
          ui.Rect.fromLTWH(panel.width - 1, 0, 1, panel.height),
          Paint()..color = const Color(0x22304A68),
        );
        canvas.restore();
      }
    }
  }

  void _drawContent(Canvas canvas) {
    final ink = Paint()..color = const Color(0xFF26344A);
    for (var index = 0; index < 8; index++) {
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(34 + index * 20, 72, 13, 29 + index % 2 * 8),
          const ui.Radius.circular(3),
        ),
        ink,
      );
    }
    canvas.drawLine(
      const ui.Offset(36, 116),
      const ui.Offset(198, 116),
      Paint()
        ..color = const Color(0xFFF3A919)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawHand(Canvas canvas, TimelineSnapshot snapshot) {
    canvas.save();
    canvas.translate(snapshot.handPosition.dx, snapshot.handPosition.dy);
    canvas.drawLine(
      ui.Offset.zero,
      const ui.Offset(86, 22),
      Paint()
        ..color = const Color(0xFF1D2633)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(54, -27, 124, 66),
        const ui.Radius.circular(29),
      ),
      Paint()..color = const Color(0xFFD69A6B),
    );
    canvas.drawCircle(
      ui.Offset.zero,
      4,
      Paint()..color = const Color(0xFF111820),
    );
    canvas.restore();
  }

  void _drawTime(Canvas canvas, double seconds, {required bool rightToLeft}) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${rightToLeft ? 'RTL' : 'LTR'} ${seconds.toStringAsFixed(2)}s',
        style: const TextStyle(
          color: Color(0xFF627083),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, const ui.Offset(8, 8));
  }

  @override
  bool shouldRepaint(covariant _ReferenceMotionStripPainter oldDelegate) =>
      false;
}
