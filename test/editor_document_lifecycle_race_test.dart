import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_session_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/hand_library/infrastructure/hand_image_loader.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/koni_project_container_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('handdraw-race-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  EditorCubit editor(
    _Files files,
    ProjectContainerStore store, {
    HandImageLoader? hands,
  }) => EditorCubit(
    fileService: files,
    projectContainerStore: store,
    handImageLoader: hands,
    sessionCoordinator: EditorSessionCoordinator(
      staging: FileEditorAssetStagingStore(
        Directory('${directory.path}/staging-${files.hashCode}'),
      ),
      containerStore: store,
      fingerprints: const CanonicalDocumentFingerprintCalculator(),
      projectIds: SecureRandomIdGenerator(),
    ),
  );

  test(
    'late save cannot give the next document its previous destination',
    () async {
      final store = _DelayedStore();
      final files = _Files([
        '${directory.path}/a.koni',
        '${directory.path}/b.koni',
      ]);
      final cubit = editor(files, store);
      addTearDown(cubit.close);
      final firstId = cubit.state.document.id;
      final saving = cubit.saveProject();
      await store.started.future;
      cubit.newProject();
      final secondId = cubit.state.document.id;
      store.release.complete();
      await saving;
      expect(await cubit.saveProject(), files.paths[1]);
      expect(files.savePicks, 2);
      final a = await store.open(ProjectContainerLocation(files.paths[0]));
      final b = await store.open(ProjectContainerLocation(files.paths[1]));
      expect(a.document.id, firstId);
      expect(b.document.id, secondId);
      await a.close();
      await b.close();
    },
  );

  test(
    'save picker completing after new project cannot save the new document',
    () async {
      final files = _Files(['${directory.path}/a.koni'])
        ..saveGate = Completer<String?>();
      final cubit = editor(files, const KoniProjectContainerStore());
      addTearDown(cubit.close);
      final saving = cubit.saveProject();
      cubit.newProject();
      files.saveGate!.complete(files.paths.first);
      expect(await saving, isNull);
      expect(File(files.paths.first).existsSync(), isFalse);
    },
  );

  for (final closeInstead in [false, true]) {
    test(
      'delayed hand load cannot publish after ${closeInstead ? 'close' : 'a newer open'}',
      () async {
        final files = _Files([
          '${directory.path}/a.koni',
          '${directory.path}/b.koni',
        ]);
        final author = editor(files, const KoniProjectContainerStore());
        await author.saveProject();
        author.newProject();
        final secondId = author.state.document.id;
        await author.saveProject();
        await author.close();
        final hands = _DelayedHands();
        final opened = editor(
          files,
          const KoniProjectContainerStore(),
          hands: hands,
        );
        final first = opened.openProject();
        await hands.started.future;
        if (closeInstead) {
          await opened.close();
        } else {
          await opened.openProject();
          expect(opened.state.document.id, secondId);
        }
        hands.release.complete(await _hand());
        await first;
        if (!closeInstead) {
          expect(opened.state.document.id, secondId);
          await opened.close();
        }
      },
    );
  }
}

Future<LoadedHandImage> _hand() async {
  final recorder = PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 2, 2), Paint());
  final picture = recorder.endRecording();
  final image = await picture.toImage(2, 2);
  picture.dispose();
  return LoadedHandImage(bytes: Uint8List(0), image: image);
}

class _DelayedHands implements HandImageLoader {
  final started = Completer<void>();
  final release = Completer<LoadedHandImage>();
  int calls = 0;
  @override
  Future<LoadedHandImage> load(HandPreset preset) async {
    if (calls++ == 0) {
      started.complete();
      return release.future;
    }
    return _hand();
  }
}

class _Files extends EditorFileService {
  _Files(this.paths);
  final List<String> paths;
  int savePicks = 0;
  int openPicks = 0;
  Completer<String?>? saveGate;
  @override
  Future<String?> pickProjectSavePath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => saveGate?.future ?? paths[savePicks++];
  @override
  Future<String?> pickProjectOpenPath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => paths[openPicks++];
}

class _DelayedStore implements ProjectContainerStore {
  final delegate = const KoniProjectContainerStore();
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> save({
    required ProjectContainerLocation destination,
    required ProjectDocument document,
    required ProjectAssetSourceCatalog assetSources,
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await delegate.save(
      destination: destination,
      document: document,
      assetSources: assetSources,
      cancellation: cancellation,
      onProgress: onProgress,
    );
  }

  @override
  Future<ProjectContainerSession> open(
    ProjectContainerLocation source, {
    ProjectContainerCancellation cancellation =
        const NeverCancelProjectContainer(),
    ProjectContainerProgressCallback? onProgress,
  }) =>
      delegate.open(source, cancellation: cancellation, onProgress: onProgress);
  @override
  Future<int> cleanupStaleTemporaryFiles(
    ProjectContainerLocation destination,
  ) => delegate.cleanupStaleTemporaryFiles(destination);
}
