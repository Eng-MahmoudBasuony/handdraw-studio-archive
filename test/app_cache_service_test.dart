import 'package:flutter/material.dart';
import 'package:handdraw_studio/features/cache_management/presentation/cache_cleanup_dialog.dart';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/cache_management/infrastructure/app_cache_service.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/cache_management/application/cache_cleanup_cubit.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('clear cache dialog reports completion and can close', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCacheCleanupDialog(
                context,
                service: _DialogCacheService(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('clear-cache-now')));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Removed 0 old temporary sessions.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
  test(
    'cleanup removes only old unlocked owned sessions and preserves assets and live sessions',
    () async {
      final root = await Directory.systemTemp.createTemp('cache-test-');
      addTearDown(() => root.delete(recursive: true));
      final owned = await Directory(
        '${root.path}/handdraw-studio-runtime-staging-123',
      ).create();
      final stale = await Directory('${owned.path}/session-old').create();
      await File('${stale.path}/.owner.lock').writeAsString('');
      await File('${stale.path}/copied.asset').writeAsString('cache');
      final unknown = await Directory('${owned.path}/session-unknown').create();
      final userFile = await File(
        '${root.path}/project.koni',
      ).writeAsString('project');
      final unrelated = await Directory(
        '${root.path}/handdraw-frames-test',
      ).create();
      final activeStore = FileEditorAssetStagingStore(owned);
      const id = EditorSessionId('session-live');
      await activeStore.createSession(id);
      final service = AppCacheService(
        temporaryRoot: root,
        now: () => DateTime.now().add(const Duration(days: 2)),
      );
      final result = await service.clear();
      expect(result.removedSessions, 1);
      expect(await stale.exists(), isFalse);
      expect(await Directory('${owned.path}/session-live').exists(), isTrue);
      expect(await unknown.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
      expect(await userFile.readAsString(), 'project');
      await activeStore.disposeSession(id);
      expect((await service.clear()).removedSessions, 0);
    },
  );
  test(
    'recent sessions remain and rendering can rebuild after clearing',
    () async {
      final root = await Directory.systemTemp.createTemp('cache-test-');
      addTearDown(() => root.delete(recursive: true));
      final recent = await Directory(
        '${root.path}/handdraw-studio-runtime-staging-1/session-recent',
      ).create(recursive: true);
      await File('${recent.path}/.owner.lock').writeAsString('');
      final project = HandDrawProject(
        strokes: [
          DrawingStroke(
            id: 'a',
            name: 'a',
            points: const [Offset(.1, .1), Offset(.9, .9)],
          ),
        ],
      );
      TimelineSnapshot render() => buildTimelineSnapshot(
        strokes: project.strokes,
        artworkRect: const Rect.fromLTWH(0, 0, 100, 100),
        progress: .5,
        durationSeconds: 6,
      );
      final before = render();
      final cubit = CacheCleanupCubit(AppCacheService(temporaryRoot: root));
      await cubit.clear();
      expect(cubit.state.failed, isFalse);
      expect(cubit.state.result!.removedSessions, 0);
      expect(await recent.exists(), isTrue);
      final after = render();
      expect(after.handPosition, before.handPosition);
      expect(after.handAngle, before.handAngle);
      expect(after.revealedPaths.length, before.revealedPaths.length);
      await cubit.close();
    },
  );
}

class _DialogCacheService extends AppCacheService {
  @override
  Future<CacheCleanupResult> clear() async => const CacheCleanupResult(0, 0);
}
