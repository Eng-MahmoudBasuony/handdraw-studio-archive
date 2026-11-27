import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/export/application/export_status_cubit.dart';
import 'package:handdraw_studio/features/export/application/export_status_state.dart';
import 'package:handdraw_studio/features/export/domain/video_export_cancellation.dart';
import 'package:handdraw_studio/features/export/presentation/export_status_overlay.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

void main() {
  test(
    'export status preserves rendering, success, failure, and dismiss states',
    () {
      final cubit = ExportStatusCubit();
      addTearDown(cubit.close);

      cubit.start('Preparing');
      cubit.update(progress: 0.42, stage: 'Rendering frame 42');
      expect(cubit.state.phase, ExportStatusPhase.rendering);
      expect(cubit.state.progress, 0.42);
      expect(cubit.state.canCancel, isTrue);

      cubit.succeed(
        path: '/tmp/movie.mov',
        fileSizeBytes: 2048,
        durationSeconds: 6,
      );
      expect(cubit.state.phase, ExportStatusPhase.success);
      expect(cubit.state.outputPath, '/tmp/movie.mov');

      cubit.fail('Encoder failed');
      expect(cubit.state.phase, ExportStatusPhase.failure);
      expect(cubit.state.errorMessage, 'Encoder failed');

      cubit.dismiss();
      expect(cubit.state.phase, ExportStatusPhase.idle);
    },
  );

  test('video export cancellation is explicit and idempotent', () {
    final token = VideoExportCancellationToken();
    expect(token.isCancelled, isFalse);
    token.throwIfCancelled();
    token.cancel();
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(
      token.throwIfCancelled,
      throwsA(isA<VideoExportCancelledException>()),
    );
  });

  testWidgets('completion popover exposes professional result actions', (
    tester,
  ) async {
    final cubit = ExportStatusCubit(
      autoDismissDelay: const Duration(minutes: 1),
    );
    addTearDown(cubit.close);
    String? action;

    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [AppPalette.dark],
          ),
          home: Scaffold(
            body: Stack(
              children: [
                ExportStatusOverlay(
                  compact: false,
                  topInset: 60,
                  onCancel: () => action = 'cancel',
                  onReveal: (_) => action = 'reveal',
                  onOpen: (_) => action = 'open',
                  onCopyPath: (_) => action = 'copy',
                  onRetry: () => action = 'retry',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    cubit.start('Preparing');
    cubit.update(progress: 0.35, stage: 'Rendering');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-status-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-progress')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-cancel')));
    expect(action, 'cancel');

    cubit.succeed(
      path: '/tmp/handdraw-animation.mov',
      fileSizeBytes: 12 * 1024 * 1024,
      durationSeconds: 6,
    );
    await tester.pumpAndSettle();
    expect(find.text('handdraw-animation.mov'), findsOneWidget);
    expect(find.byKey(const ValueKey('export-reveal-finder')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-open')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-copy-path')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('export-copy-path')));
    expect(action, 'copy');
    await tester.tap(find.byKey(const ValueKey('export-open')));
    expect(action, 'open');
    await tester.tap(find.byKey(const ValueKey('export-reveal-finder')));
    expect(action, 'reveal');
    cubit.dismiss();
    await tester.pumpAndSettle();
  });

  testWidgets('failure popover remains actionable until dismissed', (
    tester,
  ) async {
    final cubit = ExportStatusCubit();
    addTearDown(cubit.close);
    var retried = false;
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(extensions: const [AppPalette.light]),
          home: Scaffold(
            body: Stack(
              children: [
                ExportStatusOverlay(
                  compact: true,
                  topInset: 60,
                  onCancel: () {},
                  onReveal: (_) {},
                  onOpen: (_) {},
                  onCopyPath: (_) {},
                  onRetry: () => retried = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    cubit.fail('Disk is full');
    await tester.pumpAndSettle();
    expect(find.text('Disk is full'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-retry')));
    expect(retried, isTrue);
  });
}
