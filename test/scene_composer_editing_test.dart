import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/infrastructure/codex_rpc_client.dart';
import 'package:handdraw_studio/features/scene_composer/application/scene_composer_cubit.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';
import 'package:handdraw_studio/features/scene_composer/presentation/scene_composer_dialog.dart';

void main() {
  test(
    'text kind and editing identity survive clearing and content changes',
    () {
      final element = SceneDesign.example().elements[1];
      final empty = element.copyWith(text: '');
      expect(empty.isText, isTrue);
      expect(empty.instanceId, same(element.instanceId));
      expect(empty.copyWith(text: 'replacement').isText, isTrue);
      expect(() => SceneElement.parse(empty.toJson()), throwsFormatException);
      expect(
        element.copyWith(newInstance: true).instanceId,
        isNot(same(element.instanceId)),
      );
      expect(
        () => SceneDesign.parse({
          'title': 'test',
          'elements': [3],
        }),
        throwsFormatException,
      );
    },
  );
  for (final locale in ['en', 'ar']) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('editing and template replacement $locale at $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(800, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final directory = Directory.systemTemp.createTempSync('scene-edit-');
        final assistant = CodexAssistantCubit(_Offline());
        final cubit = SceneComposerCubit(assistant, SceneLibrary(directory));
        addTearDown(cubit.close);
        addTearDown(assistant.close);
        addTearDown(() => directory.deleteSync(recursive: true));
        final text = SceneDesign.example().elements[1];
        cubit.show(SceneDesign(title: 'A', elements: [text]));
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SceneComposerDialog(controller: cubit, connect: false),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        Finder field(String prefix) => find.byWidgetPredicate(
          (w) => w is TextFormField && w.key.toString().contains(prefix),
        );
        await tester.enterText(field('scene-text'), '');
        await tester.pump();
        expect(field('scene-text'), findsOneWidget);
        await tester.enterText(field('scene-text'), 'Replacement');
        await tester.pump();
        expect(cubit.state.design!.elements.single.text, 'Replacement');
        cubit.show(
          SceneDesign(
            title: 'B',
            elements: [
              text.copyWith(text: 'Second', category: 'Other', seconds: 7),
            ],
          ),
        );
        await tester.pump();
        String value(String prefix) => tester
            .widget<EditableText>(
              find.descendant(
                of: field(prefix),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text;
        expect(value('scene-text'), 'Second');
        expect(value('category'), 'Other');
        expect(value('seconds'), '7.0');
        cubit.add(text.copyWith(text: 'Added'));
        await tester.pump();
        expect(value('scene-text'), 'Added');
        cubit.move(-1);
        await tester.pump();
        expect(value('scene-text'), 'Added');
        cubit.remove();
        await tester.pump();
        expect(value('scene-text'), 'Second');
        await tester.ensureVisible(find.byKey(const ValueKey('scene-apply')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('scene-apply')).hitTestable(),
          findsOneWidget,
        );

        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
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
  ) async => throw StateError('Offline test');
}
