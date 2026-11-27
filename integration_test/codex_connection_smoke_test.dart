import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/presentation/codex_assistant_dialog.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:handdraw_studio/features/codex_assistant/infrastructure/codex_rpc_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'sandboxed macOS app starts official Codex without API credentials',
    (tester) async {
      final folder = await Directory.systemTemp.createTemp(
        'handdraw-codex-smoke-',
      );
      final rpc = CodexRpcClient(home: folder);
      try {
        await rpc.connect();
        final account = await rpc.request('account/read', {
          'refreshToken': false,
        });
        expect(account['account'], isNull);
        final login = await rpc.request('account/login/start', {
          'type': 'chatgpt',
        });
        expect(Uri.parse(login['authUrl'] as String).host, 'auth.openai.com');
        await rpc.request('account/login/cancel', {
          'loginId': login['loginId'],
        });
        final assistant = CodexAssistantCubit(rpc);
        final editor = EditorCubit();
        final capture = GlobalKey();
        try {
          for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  brightness: direction == TextDirection.rtl
                      ? Brightness.dark
                      : Brightness.light,
                  extensions: [
                    direction == TextDirection.rtl
                        ? AppPalette.dark
                        : AppPalette.light,
                  ],
                ),
                home: Directionality(
                  textDirection: direction,
                  child: RepaintBoundary(
                    key: capture,
                    child: Scaffold(
                      body: CodexAssistantDialog(
                        editor: editor,
                        assistant: assistant,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('codex-prompt')), findsOneWidget);
            expect(find.byKey(const ValueKey('codex-connect')), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final screenshot = await boundary.toImage(pixelRatio: 1);
          final data = (await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          await File(
            '${Directory.systemTemp.path}/handdraw-codex-native.png',
          ).writeAsBytes(data.buffer.asUint8List());
          screenshot.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          await assistant.close();
          await editor.close();
        }
      } finally {
        await rpc.close();
        await folder.delete(recursive: true);
      }
    },
  );
}
