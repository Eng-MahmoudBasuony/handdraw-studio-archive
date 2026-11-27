import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/infrastructure/codex_rpc_client.dart';
import 'package:handdraw_studio/features/scene_composer/application/scene_composer_cubit.dart';
import 'package:handdraw_studio/features/scene_composer/application/scene_project_builder.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';
import 'package:handdraw_studio/features/scene_composer/presentation/scene_composer_dialog.dart';
import 'package:handdraw_studio/features/export/infrastructure/frame_renderer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('compose, save independent assets and build real timeline', (
    tester,
  ) async {
    final folder = await Directory.systemTemp.createTemp('scene-native-');
    final assistant = CodexAssistantCubit(_Offline());
    final cubit = SceneComposerCubit(assistant, SceneLibrary(folder));
    addTearDown(cubit.close);
    addTearDown(assistant.close);
    addTearDown(() => folder.delete(recursive: true));
    final capture = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeFactory.dark(),
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RepaintBoundary(
          key: capture,
          child: Scaffold(
            body: SceneComposerDialog(controller: cubit, connect: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('مثال Flutter بدون استهلاك'));
    await tester.pumpAndSettle();
    expect(cubit.state.design!.elements.length, 6);
    await tester.tap(find.text('حفظ القالب والعناصر'));
    await tester.pumpAndSettle();
    expect(cubit.state.assets.length, 6);
    expect(tester.takeException(), isNull);
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final shot = await boundary.toImage();
    await File(
      '${Directory.systemTemp.path}/scene-composer-preview.png',
    ).writeAsBytes(
      (await shot.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    shot.dispose();
    final editor = await const SceneProjectBuilder().build(
      SceneDesign.example(),
    );
    addTearDown(editor.close);
    expect(editor.state.document.sections.length, 6);
    expect(editor.state.handImage, isNotNull);
    expect(editor.project.strokes.any((s) => s.isTextShape), isTrue);
    final frame = await const FrameRenderer().render(
      project: editor.project,
      drawing: editor.drawingImage!,
      hand: editor.state.handImage,
      progress: .3,
    );
    await File(
      '${Directory.systemTemp.path}/scene-composer-frame.png',
    ).writeAsBytes(
      (await frame.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    frame.dispose();
  });
}

class _Offline implements CodexRpc {
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
  ) async => throw StateError('No network in preview test');
}
