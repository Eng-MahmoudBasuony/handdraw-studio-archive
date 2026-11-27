import 'dart:convert';
import 'dart:typed_data';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_image_context.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_account.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_drawing_plan.dart';
import 'package:handdraw_studio/features/codex_assistant/infrastructure/codex_rpc_client.dart';
import 'package:handdraw_studio/features/codex_assistant/presentation/codex_assistant_dialog.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';
import '../test/support/legacy_editor_state_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Apply creates native parts with complete lines and no early ink',
    (tester) async {
      // Engine rasterization must complete outside the test async scope.
      final bytes = (await tester.runAsync(_createDrawingFixture))!;
      final codec = await ui.instantiateImageCodec(bytes);
      final source = (await codec.getNextFrame()).image;
      codec.dispose();
      final context = await CodexImageContext.prepare(source);
      final textIds = [
        for (var i = 0; i < context.texts.length; i++)
          if (context.texts[i].bounds.left > .3 &&
              context.texts[i].bounds.top > .28 &&
              context.texts[i].bounds.bottom < .76)
            i,
      ];
      expect(textIds.length, 4);
      expect(
        context.texts[textIds.first].text.toLowerCase(),
        'flutter pub get',
      );
      expect(context.texts[textIds.first].bounds.bottom, lessThan(.43));
      final plan = CodexDrawingPlan.parse({
        'summary': 'رسم النافذة ثم سطور الأوامر من الصورة الأصلية.',
        'confidence': .95,
        'showHand': true,
        'parts': [
          {
            'name': 'النافذة البيضاء',
            'bounds': [.288, .17, .968, .805],
            'mode': 'reveal',
            'seconds': 1.2,
            'excludeText': true,
            'textId': '',
          },
          for (final i in textIds)
            {
              'name': context.texts[i].text,
              'bounds': [0, 0, 1, 1],
              'mode': 'write',
              'seconds': 1.5,
              'excludeText': false,
              'textId': 'text-$i',
            },
        ],
      }, context.texts);
      final editor = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            canvasWidth: source.width,
            canvasHeight: source.height,
            drawingImageBase64: base64Encode(bytes),
          ),
          drawingImage: source,
        ),
      );
      final assistant = _OfflinePlan(plan);
      addTearDown(editor.close);
      addTearDown(assistant.close);
      addTearDown(source.dispose);
      final capture = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeFactory.dark(),
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RepaintBoundary(
            key: capture,
            child: EditorScreen(cubit: editor),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final route = showDialog<void>(
        context: tester.element(find.byType(EditorScreen)),
        builder: (_) =>
            CodexAssistantDialog(editor: editor, assistant: assistant),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('codex-prompt')),
        'ارسم النافذة ثم اكتب الأوامر.',
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.ensureVisible(find.byKey(const ValueKey('codex-generate')));
      await tester.tap(find.byKey(const ValueKey('codex-generate')));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      final apply = find.byKey(const ValueKey('codex-apply'));
      await tester.ensureVisible(apply);
      await tester.tap(apply);
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(minutes: 3),
      );
      expect(
        find.byKey(const ValueKey('codex-assistant-dialog')),
        findsNothing,
        reason: editor.state.statusMessage,
      );
      await route;
      expect(editor.state.document.sections, hasLength(plan.parts.length));
      for (final id in editor.timelineSectionOrder) {
        expect(find.byKey(ValueKey('timeline-thumbnail-$id')), findsOneWidget);
      }
      final sourcePixels = (await source.toByteData())!.buffer.asUint8List();
      final textPaths = editor.project.strokes.where((s) => s.isTextShape);
      expect(textPaths, isNotEmpty);
      for (final stroke in textPaths) {
        expect(stroke.isPaintStroke, isFalse);
        for (final point in stroke.points) {
          final x = (point.dx * source.width).round();
          final y = (point.dy * source.height).round();
          var touchesInk = false;
          for (var dy = -2; dy <= 2; dy++) {
            for (var dx = -2; dx <= 2; dx++) {
              final px = (x + dx).clamp(0, source.width - 1);
              final py = (y + dy).clamp(0, source.height - 1);
              if (sourcePixels[(py * source.width + px) * 4] < 180) {
                touchesInk = true;
              }
            }
          }
          expect(
            touchesInk,
            isTrue,
            reason: 'Writing path in whitespace at $point',
          );
        }
      }
      final project = editor.project;
      final spans = projectTimelineSectionSpans(project);
      final total = timelineDurationSeconds(
        strokes: project.strokes,
        timingRect: ui.Rect.fromLTWH(
          0,
          0,
          source.width.toDouble(),
          source.height.toDouble(),
        ),
        durationSeconds: project.durationSeconds,
        drawingDurationSeconds: project.drawingDurationSeconds,
        drawingSpeed: project.drawingSpeed,
        penTravelSpeed: project.penTravelSpeed,
        startDelaySeconds: project.startDelaySeconds,
        endHoldSeconds: project.endHoldSeconds,
        sectionTimings: project.sectionTimings,
      );
      final firstLine = await const FrameRenderer().render(
        project: editor.project,
        drawing: source,
        hand: null,
        progress: (spans[1].endSeconds - .001) / total,
      );
      final firstPixels = (await firstLine.toByteData())!.buffer.asUint8List();
      // The next line's ink must remain fully covered, including its top edge.
      for (var y = 450; y < 520; y++) {
        for (var x = 530; x < 1330; x++) {
          final p = (y * source.width + x) * 4;
          expect(
            firstPixels[p],
            greaterThan(220),
            reason: 'Early ink at $x,$y',
          );
        }
      }
      var getInk = 0;
      for (var y = 350; y < 420; y++) {
        for (var x = 1045; x < 1170; x++) {
          if (firstPixels[(y * source.width + x) * 4] < 80) getInk++;
        }
      }
      expect(
        getInk,
        greaterThan(500),
        reason: 'The word get is part of line one',
      );
      await File(
        '${Directory.systemTemp.path}/codex-first-complete-line.png',
      ).writeAsBytes(
        (await firstLine.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List(),
      );
      firstLine.dispose();
      final output = await const FrameRenderer().render(
        project: editor.project,
        drawing: source,
        hand: null,
        progress: 1,
      );
      final rgba = (await output.toByteData())!.buffer.asUint8List();
      final original = (await source.toByteData())!.buffer.asUint8List();
      for (final x in [1250, 1321, 1389]) {
        final index = (229 * source.width + x + 18) * 4;
        expect(
          rgba.sublist(index, index + 4),
          original.sublist(index, index + 4),
          reason: 'Unscheduled OCR must not erase a window control',
        );
      }
      final encoded = await output.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${Directory.systemTemp.path}/codex-applied-frame.png',
      ).writeAsBytes(encoded!.buffer.asUint8List());
      output.dispose();
      final boundary =
          capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final shot = await boundary.toImage();
      final data = await shot.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${Directory.systemTemp.path}/codex-applied-timeline.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      shot.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

// Generated entirely in the test: no external user artwork or downloaded assets.
Future<Uint8List> _createDrawingFixture() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final window = RRect.fromRectAndRadius(
    const Rect.fromLTRB(450, 180, 1480, 815),
    const Radius.circular(35),
  );
  canvas.drawRRect(window, Paint()..color = Colors.white);
  canvas.drawRRect(
    window,
    Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12,
  );
  canvas.drawLine(
    const Offset(452, 290),
    const Offset(1478, 290),
    Paint()
      ..color = Colors.black
      ..strokeWidth = 10,
  );
  for (final x in [1250.0, 1321.0, 1389.0]) {
    canvas.drawCircle(
      Offset(x, 229),
      18,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9,
    );
  }
  for (final (index, line) in const [
    'flutter pub get',
    'flutter pub upgrade',
    'flutter pub outdated',
    'flutter pub deps',
  ].indexed) {
    final painter = TextPainter(
      text: TextSpan(
        text: line,
        style: const TextStyle(
          fontFamily: 'Courier',
          fontSize: 72,
          color: Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, Offset(530, 335 + index * 100));
    painter.dispose();
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(1536, 1024);
  picture.dispose();
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  image.dispose();
  return bytes;
}

class _OfflinePlan extends CodexAssistantCubit {
  _OfflinePlan(this.result) : super(_NoNetwork());
  final CodexDrawingPlan result;
  @override
  Future<void> connect() async => emit(
    state.copyWith(
      phase: CodexPhase.ready,
      account: CodexAccount.fromResponses(
        {
          'account': {'type': 'chatgpt', 'planType': 'pro'},
        },
        {
          'rateLimits': {
            'credits': {'hasCredits': false, 'unlimited': false},
            'primary': {'usedPercent': 5},
          },
        },
      ),
    ),
  );
  @override
  Future<CodexDrawingPlan?> plan(String prompt, CodexImageContext image) async {
    emit(state.copyWith(plan: result));
    return result;
  }
}

class _NoNetwork implements CodexRpc {
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  Future<void> connect() async {}
  @override
  Future<void> close() async {}
  @override
  Future<Map<String, dynamic>> request(
    String method,
    Map<String, dynamic> params,
  ) async => throw StateError('Network forbidden in this regression test');
}
