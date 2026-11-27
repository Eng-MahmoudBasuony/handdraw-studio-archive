import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/scene_composer/application/scene_composer_cubit.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';
import 'package:handdraw_studio/features/scene_composer/presentation/scene_design_painter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('one explicit live account scene request', (tester) async {
    final assistant = CodexAssistantCubit.local(allowDevelopment: false);
    final cubit = SceneComposerCubit(assistant, SceneLibrary.local());
    addTearDown(assistant.close);
    addTearDown(cubit.close);
    await assistant.connect();
    expect(
      assistant.state.account?.blockedReason,
      isNull,
      reason: assistant.state.error,
    );
    await cubit.generate(
      'Create a clean scene about cloud backup. Exactly 3 separated elements: one cyan cloud vector icon, one blue database vector icon, and one text heading Cloud backup. Use at most 3 simple paths per icon. Arrange with generous spacing, no overlaps, on a 16:9 white canvas.',
    );
    expect(
      cubit.state.design,
      isNotNull,
      reason: '${cubit.state.message} ${assistant.state.error}',
    );
    final SceneDesign design = cubit.state.design!;
    expect(design.elements.length, 3);
    await cubit.save();
    await File(
      '${Directory.systemTemp.path}/scene-live.json',
    ).writeAsString(jsonEncode(design.toJson()));
    final image = await SceneDesignPainter(design).rasterize();
    await File('${Directory.systemTemp.path}/scene-live.png').writeAsBytes(
      (await image.toByteData(
        format: ui.ImageByteFormat.png,
      ))!.buffer.asUint8List(),
    );
    image.dispose();
    debugPrint(
      'Scene request tokens: input=${assistant.state.inputTokens}, output=${assistant.state.outputTokens}',
    );
  }, skip: !const bool.fromEnvironment('HANDDRAW_SCENE_LIVE'));
}
