import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/app/theme/app_theme_factory.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/canvas_playback_overlay.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('player keeps unavailable preview visible and disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        child: CanvasPlaybackOverlay(
          canPreview: false,
          isPreviewing: false,
          isPreviewPaused: false,
          positionSeconds: 0,
          durationSeconds: 0,
          hasAudio: false,
          volume: 1,
          qualityLabel: '1080p',
          onPlay: () {},
          onPause: () {},
          onResume: () {},
          onStop: () {},
          onSeek: (_) {},
          onToggleMute: () {},
          onVolumeChanged: (_) {},
        ),
      ),
    );

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('canvas-preview-toggle')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('canvas-preview-mute')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const ValueKey('canvas-preview-stop')), findsNothing);
  });

  testWidgets('audio controls expose mute volume and current quality', (
    tester,
  ) async {
    var muted = false;
    double? changedVolume;
    await tester.pumpWidget(
      _harness(
        child: CanvasPlaybackOverlay(
          canPreview: true,
          isPreviewing: true,
          isPreviewPaused: false,
          positionSeconds: 8,
          durationSeconds: 42,
          hasAudio: true,
          volume: .65,
          qualityLabel: '1080p',
          onPlay: () {},
          onPause: () {},
          onResume: () {},
          onStop: () {},
          onSeek: (_) {},
          onToggleMute: () => muted = true,
          onVolumeChanged: (value) => changedVolume = value,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('canvas-preview-mute')));
    expect(muted, isTrue);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('canvas-preview-volume')),
    );
    slider.onChanged!(.25);
    expect(changedVolume, .25);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Full HD'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('canvas-player-brand-logo')),
      findsOneWidget,
    );
  });

  testWidgets('a selected timeline frame stays paused and seekable', (
    tester,
  ) async {
    var played = false;
    double? soughtSeconds;
    await tester.pumpWidget(
      _harness(
        child: CanvasPlaybackOverlay(
          canPreview: true,
          isPreviewing: false,
          isPreviewPaused: false,
          positionSeconds: 6,
          durationSeconds: 6,
          hasAudio: false,
          volume: 1,
          qualityLabel: '1080p',
          onPlay: () => played = true,
          onPause: () => fail('A static timeline frame is not playback.'),
          onResume: () =>
              fail('A static timeline frame is not paused playback.'),
          onStop: () {},
          onSeek: (seconds) => soughtSeconds = seconds,
          onToggleMute: () {},
          onVolumeChanged: (_) {},
        ),
      ),
    );

    final toggle = tester.widget<IconButton>(
      find.byKey(const ValueKey('canvas-preview-toggle')),
    );
    expect((toggle.icon as Icon).icon, Icons.play_arrow);
    expect(find.byKey(const ValueKey('canvas-preview-stop')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('canvas-preview-toggle')));
    expect(played, isTrue);

    final progress = tester.widget<Slider>(
      find.byKey(const ValueKey('canvas-preview-progress')),
    );
    expect(progress.onChanged, isNotNull);
    progress.onChanged!(.5);
    expect(soughtSeconds, 3);
  });

  test('quality tiers explain common video resolutions', () {
    expect(videoQualityTier('720p'), 'HD');
    expect(videoQualityTier('1080p'), 'Full HD');
    expect(videoQualityTier('1440p'), 'QHD');
    expect(videoQualityTier('2160p'), '4K UHD');
    expect(videoQualityTier('4320p'), '8K UHD');
  });

  testWidgets(
    'player remains usable without overflow at narrow canvas widths',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(245, 300));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          child: CanvasPlaybackOverlay(
            canPreview: true,
            isPreviewing: true,
            isPreviewPaused: false,
            positionSeconds: 8,
            durationSeconds: 42,
            hasAudio: true,
            volume: .65,
            qualityLabel: '1080p',
            onPlay: () {},
            onPause: () {},
            onResume: () {},
            onStop: () {},
            onSeek: (_) {},
            onToggleMute: () {},
            onVolumeChanged: (_) {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('canvas-preview-toggle')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('canvas-preview-mute')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('canvas-preview-progress')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('canvas-preview-stop')), findsNothing);
    },
  );

  for (final locale in const [Locale('en'), Locale('ar')]) {
    testWidgets('canvas player ${locale.languageCode} golden', (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 560));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _harness(
          locale: locale,
          child: RepaintBoundary(
            key: const ValueKey('canvas-player-golden'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xff111a2b)),
                Center(
                  child: Icon(
                    Icons.gesture_rounded,
                    size: 96,
                    color: const Color(0xff22d3ee).withValues(alpha: .24),
                  ),
                ),
                CanvasPlaybackOverlay(
                  canPreview: true,
                  isPreviewing: true,
                  isPreviewPaused: true,
                  positionSeconds: 8,
                  durationSeconds: 42,
                  hasAudio: true,
                  volume: .65,
                  qualityLabel: '1080p',
                  onPlay: () {},
                  onPause: () {},
                  onResume: () {},
                  onStop: () {},
                  onSeek: (_) {},
                  onToggleMute: () {},
                  onVolumeChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byKey(const ValueKey('canvas-player-golden')),
        matchesGoldenFile('goldens/canvas_player_${locale.languageCode}.png'),
      );
    });
  }
}

Widget _harness({required Widget child, Locale locale = const Locale('en')}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppThemeFactory.dark(),
      home: Scaffold(body: SizedBox.expand(child: child)),
    );
