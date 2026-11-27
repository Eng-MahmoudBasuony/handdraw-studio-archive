import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  testWidgets('Arabic draw and reveal workspace golden', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final image = await _sampleArtwork();
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          canvasWidth: 800,
          canvasHeight: 450,
          drawingImagePath: '/tmp/manual-reveal-golden.png',
          revealWidth: 72,
        ),
        drawingImage: image,
        tool: EditorTool.drawPath,
        activeStroke: const [
          Offset(0.15, 0.42),
          Offset(0.32, 0.28),
          Offset(0.52, 0.46),
          Offset(0.72, 0.3),
          Offset(0.86, 0.44),
        ],
      ),
    );
    addTearDown(() async {
      await cubit.close();
      image.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeFactory.dark(),
        home: EditorScreen(cubit: cubit),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(const ValueKey('editor-layout-wide')),
      matchesGoldenFile('goldens/manual_draw_reveal_ar.png'),
    );
    expect(tester.takeException(), isNull);
  });
}

Future<ui.Image> _sampleArtwork() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 800, 450),
    ui.Paint()..color = const ui.Color(0xFFF7F9FC),
  );
  final line = ui.Paint()
    ..color = const ui.Color(0xFF10243F)
    ..style = ui.PaintingStyle.stroke
    ..strokeWidth = 24
    ..strokeCap = ui.StrokeCap.round;
  final path = ui.Path()
    ..moveTo(120, 190)
    ..cubicTo(250, 80, 390, 270, 520, 160)
    ..cubicTo(600, 100, 650, 210, 700, 190);
  canvas.drawPath(path, line);
  canvas.drawCircle(
    const ui.Offset(170, 320),
    42,
    ui.Paint()..color = const ui.Color(0xFF35B7D5),
  );
  canvas.drawRRect(
    ui.RRect.fromRectAndRadius(
      const ui.Rect.fromLTWH(570, 285, 120, 72),
      const ui.Radius.circular(18),
    ),
    ui.Paint()..color = const ui.Color(0xFFF5B93C),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 450);
  picture.dispose();
  return image;
}
