import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  testWidgets('manual reveal hand has natural writing articulation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 225));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: ValueKey('manual-hand-motion-strip'),
          child: CustomPaint(
            size: Size(1600, 225),
            painter: _MotionStripPainter(),
          ),
        ),
      ),
    );

    await expectLater(
      find.byKey(const ValueKey('manual-hand-motion-strip')),
      matchesGoldenFile('goldens/manual_hand_motion.png'),
    );
  });
}

final class _MotionStripPainter extends CustomPainter {
  const _MotionStripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const panelSize = ui.Size(400, 225);
    const pathRect = ui.Rect.fromLTWH(0, 0, 400, 225);
    final stroke = DrawingStroke(
      id: 'manual-writing-sweep',
      name: 'Manual writing sweep',
      revealWidth: 88,
      points: const [ui.Offset(0.08, 0.5), ui.Offset(0.92, 0.5)],
    );

    for (final entry in [0.18, 0.38, 0.58, 0.78].indexed) {
      final snapshot = buildTimelineSnapshot(
        strokes: [stroke],
        artworkRect: pathRect,
        timingRect: pathRect,
        progress: entry.$2,
        durationSeconds: 4,
        drawingDurationSeconds: 4,
        startDelaySeconds: 0,
        endHoldSeconds: 0,
      );
      canvas.save();
      canvas.translate(entry.$1 * panelSize.width, 0);
      canvas.drawRect(
        ui.Offset.zero & panelSize,
        Paint()..color = const Color(0xFFF7F3E8),
      );
      canvas.save();
      canvas.clipRect(
        ui.Rect.fromLTRB(
          0,
          snapshot.handPosition.dy - 48,
          snapshot.handPosition.dx + 44,
          snapshot.handPosition.dy + 48,
        ),
      );
      _drawTitle(canvas);
      canvas.restore();
      _drawHand(canvas, snapshot);
      canvas.drawRect(
        ui.Rect.fromLTWH(panelSize.width - 1, 0, 1, panelSize.height),
        Paint()..color = const Color(0x22304A68),
      );
      canvas.restore();
    }
  }

  void _drawTitle(Canvas canvas) {
    final ink = Paint()..color = const Color(0xFF15243C);
    for (var index = 0; index < 11; index++) {
      final left = 34.0 + index * 30;
      final height = 38.0 + (index % 3) * 11;
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(left, 112 - height / 2, 20, height),
          const ui.Radius.circular(6),
        ),
        ink,
      );
    }
    canvas.drawLine(
      const ui.Offset(45, 154),
      const ui.Offset(354, 154),
      Paint()
        ..color = const Color(0xFFF3A919)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawHand(Canvas canvas, TimelineSnapshot snapshot) {
    canvas.save();
    canvas.translate(snapshot.handPosition.dx, snapshot.handPosition.dy);
    canvas.rotate(snapshot.handAngle);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(62, -28, 190, 76),
        const ui.Radius.circular(34),
      ),
      Paint()..color = const Color(0xFFD7A071),
    );
    canvas.drawLine(
      ui.Offset.zero,
      const ui.Offset(128, 5),
      Paint()
        ..color = const Color(0xFF203957)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      ui.Offset.zero,
      4,
      Paint()..color = const Color(0xFFFFB000),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MotionStripPainter oldDelegate) => false;
}
