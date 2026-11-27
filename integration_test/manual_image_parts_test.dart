import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as raster;
import 'package:integration_test/integration_test.dart';
import 'package:handdraw_studio/core/platform/native_launch_service.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

import '../test/support/legacy_editor_state_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('four circled image parts become four native timeline blocks', (
    tester,
  ) async {
    final pixels = raster.Image(width: 480, height: 240, numChannels: 4);
    for (var i = 0; i < 4; i++) {
      raster.fillCircle(
        pixels,
        x: 60 + i * 120,
        y: 120,
        radius: 34,
        color: raster.ColorRgba8(20, 20, 20, 255),
      );
      raster.fillCircle(
        pixels,
        x: 60 + i * 120,
        y: 120,
        radius: 28,
        color: raster.ColorRgba8(50 + i * 50, 180 - i * 30, 220, 255),
      );
    }
    final encoded = raster.encodePng(pixels);
    final codec = await ui.instantiateImageCodec(encoded);
    final source = (await codec.getNextFrame()).image;
    codec.dispose();
    final editor = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          canvasWidth: 480,
          canvasHeight: 240,
          drawingImageBase64: base64Encode(encoded),
          drawingSourceBase64: base64Encode(encoded),
        ),
        drawingImage: source,
      ),
    );
    addTearDown(editor.close);
    addTearDown(source.dispose);
    editor.openImageAnimationControls();
    editor.setImageAnimationEffect('drawPaint');
    editor.setTool(EditorTool.drawPath);
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: capture,
          child: EditorScreen(cubit: editor),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await NativeLaunchService.notifyFirstFrameRendered();
    await tester.tap(find.byKey(const ValueKey('animate-image')));
    await tester.pumpAndSettle();
    final choose = find.byKey(const ValueKey('animation-select-parts'));
    await tester.ensureVisible(choose);
    await tester.tap(choose);
    await tester.pumpAndSettle();
    final area = tester.getRect(
      find.byKey(const ValueKey('smart-scene-split-canvas')),
    );
    for (var i = 0; i < 4; i++) {
      ui.Offset point(int step) {
        final angle = step * 2 * math.pi / 32;
        return ui.Offset(
          area.left +
              area.width * ((60 + i * 120 + 45 * math.cos(angle)) / 480),
          area.top + area.height * ((120 + 45 * math.sin(angle)) / 240),
        );
      }

      final gesture = await tester.startGesture(point(0));
      for (var step = 1; step <= 32; step++) {
        await gesture.moveTo(point(step));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
    }
    expect(find.text('Create 4 scenes'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-smart-scene-split')));
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(minutes: 2),
    );
    final deadline = DateTime.now().add(const Duration(minutes: 2));
    while (editor.state.isAnalyzingSmartPaths &&
        DateTime.now().isBefore(deadline)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(editor.state.isAnalyzingSmartPaths, isFalse);
    expect(
      editor.state.document.sections,
      hasLength(4),
      reason: editor.state.statusMessage,
    );
    for (final id in editor.timelineSectionOrder) {
      expect(find.byKey(ValueKey('timeline-thumbnail-$id')), findsOneWidget);
    }
    await tester.pumpAndSettle();
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final screenshot = await boundary.toImage();
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '${Directory.systemTemp.path}/handdraw-manual-parts-native.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    debugPrint(
      'Native parts screenshot: ${Directory.systemTemp.path}/handdraw-manual-parts-native.png',
    );
    screenshot.dispose();
    expect(tester.takeException(), isNull);
  });
}
