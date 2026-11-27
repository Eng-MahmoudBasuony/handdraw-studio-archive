import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/timeline_section_properties_dialog.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('section timing editor ${locale.languageCode} golden', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1100, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cubit = EditorCubit(
        initialState: testEditorState(
          project: HandDrawProject(
            strokes: [
              DrawingStroke(
                id: 'artwork-1',
                name: 'Artwork 1',
                sectionId: 'artwork-1',
                points: const [Offset(.15, .4), Offset(.85, .4)],
              ),
            ],
          ),
        ),
      );
      addTearDown(cubit.close);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppThemeFactory.dark(),
          home: Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => TimelineSectionPropertiesDialog(
                      cubit: cubit,
                      sectionId: 'artwork-1',
                      label: 'Artwork 1',
                      preview: const ColoredBox(color: Color(0xff111a2b)),
                      animationSeconds: .99,
                      speedMultiplier: 1,
                      pauseSeconds: 0,
                      transitionSeconds: 0,
                      pauseBeforeSeconds: 0,
                      pauseBeforeEnabled: false,
                      pauseAfterEnabled: false,
                      handEntranceAnimation: SectionHandEntranceAnimation.none,
                      handEntranceDurationSeconds: .35,
                      handExitAnimation: SectionHandExitAnimation.none,
                      handExitDurationSeconds: 0,
                      keepHandVisibleAfterDrawing: false,
                      allowTransition: false,
                      strokeIndex: 0,
                      onTimingChangeStart: () {},
                      onTimingChangeEnd: () {},
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(const ValueKey('timeline-section-properties-dialog')),
        matchesGoldenFile(
          'goldens/section_timing_editor_${locale.languageCode}.png',
        ),
      );
      await tester.tap(find.byKey(const ValueKey('section-start-stage')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('section-end-stage')),
      );
      await tester.tap(find.byKey(const ValueKey('section-end-stage')));
      await tester.pumpAndSettle();
      final timingScroll = find
          .descendant(
            of: find.byKey(
              const ValueKey('timeline-section-properties-dialog'),
            ),
            matching: find.byType(SingleChildScrollView),
          )
          .first;
      await tester.drag(timingScroll, const Offset(0, -620));
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const ValueKey('timeline-section-properties-dialog')),
        matchesGoldenFile(
          'goldens/section_timing_editor_${locale.languageCode}_end.png',
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
