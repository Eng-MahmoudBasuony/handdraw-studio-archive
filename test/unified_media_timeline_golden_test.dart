import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/voice_guide/presentation/voice_guide_bar.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  testWidgets('equal artwork and audio align on one timeline golden', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final strokes = [
      DrawingStroke(
        id: 'aligned-media',
        name: 'Aligned media',
        points: const [Offset(.1, .5), Offset(.9, .5)],
      ),
    ];
    const sectionTimings = {
      'stroke:aligned-media': SectionTiming(
        pauseBeforeEnabled: true,
        pauseBeforeSeconds: .25,
        pauseAfterEnabled: true,
        pauseAfterSeconds: .25,
      ),
    };
    final drawingOnly = HandDrawProject(
      startDelaySeconds: 0,
      strokes: strokes,
      sectionTimings: sectionTimings,
    );
    final duration = resolveProjectTimeline(drawingOnly).durationSeconds;
    final project = HandDrawProject(
      startDelaySeconds: 0,
      strokes: strokes,
      sectionTimings: sectionTimings,
      voiceGuide: VoiceGuide(
        path: '/tmp/aligned.wav',
        name: 'aligned.wav',
        durationSeconds: duration,
        waveform: List.generate(64, (index) => ((index % 8) + 1) / 8),
      ),
    );
    final cubit = EditorCubit(initialState: testEditorState(project: project));
    addTearDown(cubit.close);
    final playhead = TimelineTime.fromMicroseconds(
      (duration * .5 * Duration.microsecondsPerSecond).round(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: AppThemeFactory.dark(),
        home: Scaffold(
          body: RepaintBoundary(
            key: const ValueKey('unified-media-timeline-golden'),
            child: EditorTimelineDock(
              cubit: cubit,
              previewProgress: .5,
              isPreviewing: true,
              playheadTime: playhead,
              onSeek: (_) {},
              onPreviewStroke: (_) {},
              onTimingChangeStart: () {},
              onTimingChangeEnd: () {},
              audioLaneBuilder: (context, geometry) => VoiceGuideBar(
                guide: project.voiceGuide!,
                project: project,
                positionSeconds: duration * .5,
                isPlaying: true,
                isPaused: false,
                isMissing: false,
                selectedSectionKey: null,
                onPlayPause: () {},
                onSeek: (_) {},
                onReplace: () {},
                onRemove: () {},
                onLocate: () {},
                onSelectSection: (_) {},
                timelineMode: true,
                timelineDurationSeconds: geometry.timelineDurationSeconds,
                trackStartSeconds: geometry.trackStartSeconds,
                trackEnabled: true,
                onToggleTrackEnabled: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 80));

    final artworkNode = find.byWidgetPredicate((widget) {
      final key = widget.key;
      if (key is! ValueKey<String>) return false;
      return key.value.startsWith('timeline-node-') &&
          !key.value.startsWith('timeline-node-played:');
    });
    expect(artworkNode, findsOneWidget);
    final artworkRect = tester.getRect(artworkNode);
    final audioRect = tester.getRect(
      find.byKey(const ValueKey('timeline-audio-clip')),
    );
    expect(audioRect.left, closeTo(artworkRect.left, 1));
    expect(audioRect.right, closeTo(artworkRect.right, 1));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'timeline-node-played:',
            ),
      ),
      findsOneWidget,
    );
    await expectLater(
      find.byKey(const ValueKey('unified-media-timeline-golden')),
      matchesGoldenFile('goldens/unified_media_timeline.png'),
    );
    expect(tester.takeException(), isNull);
  });
}
