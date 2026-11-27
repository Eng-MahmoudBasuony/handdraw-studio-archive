import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_image_context.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('HANDDRAW_CODEX_LIVE');
  testWidgets('installed host has full user access and one live image plan', (
    tester,
  ) async {
    final assistant = CodexAssistantCubit.local();
    try {
      expect(assistant.developmentEnabled, isTrue);
      await assistant.connect();
      expect(assistant.state.error, isNull);
      expect(assistant.state.account!.blockedReason, isNull);
      final command = await assistant.rpc.request('command/exec', {
        'command': [
          '/usr/bin/python3',
          '-c',
          'from pathlib import Path; import tempfile; d=Path.home()/"Library/Application Support/HandDraw Studio Developer"; f=tempfile.NamedTemporaryFile(dir=d,delete=False); p=Path(f.name); f.write(b"full-access-probe"); f.close(); print(p.read_text()); p.unlink()',
        ],
        'sandboxPolicy': {'type': 'dangerFullAccess'},
        'timeoutMs': 10000,
      });
      expect(command['exitCode'], 0);
      expect(command['stdout'], contains('full-access-probe'));
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(
        const ui.Rect.fromLTWH(30, 30, 68, 68),
        ui.Paint()..color = const ui.Color(0xff168cff),
      );
      final picture = recorder.endRecording();
      final source = await picture.toImage(128, 128);
      picture.dispose();
      try {
        final context = await CodexImageContext.prepare(source);
        final plan = await assistant.plan(
          'ارسم المربع الأزرق الموجود فقط كجزء واحد لمدة ثانيتين مع ظهور اليد. هذه مهمة رسم عادية مدعومة بالفعل؛ لا تحتاج تعديل كود أو فحص المستودع.',
          context,
        );
        expect(plan, isNotNull, reason: assistant.state.error);
        expect(plan!.parts, hasLength(1));
        expect(plan.showHand, isTrue);
        expect(
          plan.parts.single.bounds.contains(const ui.Offset(.5, .5)),
          isTrue,
        );
        expect(assistant.state.developmentStatus, 'unchanged');
        final report = File(
          '${Directory.systemTemp.path}/handdraw-codex-live-result.txt',
        );
        await report.writeAsString(
          'One authenticated image request passed. Full user access probe passed. No code changes. Input tokens: ${assistant.state.inputTokens}; output tokens: ${assistant.state.outputTokens}.',
        );
      } finally {
        source.dispose();
      }
    } finally {
      await assistant.close();
    }
  }, skip: !enabled);
}
