import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/application/session/staging_history_asset_retention.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

void main() {
  test(
    'delete, undo, redo, and trimming preserve then release staged bytes',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'history-retention-',
      );
      addTearDown(() async {
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });
      final staging = FileEditorAssetStagingStore(temporary);
      const sessionId = EditorSessionId('history-session');
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final asset = ProjectAsset(
        id: ProjectAssetId('asset'),
        kind: ProjectAssetKind.other,
        originalFileName: 'asset.bin',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:${sha256.convert(bytes)}',
      );
      await staging.createSession(sessionId);
      await staging.stageEmbedded(
        StageEmbeddedAssetRequest(
          sessionId: sessionId,
          asset: asset,
          source: _Source(bytes),
        ),
      );
      staging.retain(
        sessionId: sessionId,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.activeDocument,
      );
      final history = EditorHistory(
        limits: const EditorHistoryLimits(maxEntries: 1),
        assetRetention: StagingHistoryAssetRetention(
          sessionId: sessionId,
          staging: staging,
        ),
      );
      var state = EditorDocumentState(document: _document(asset));

      state = _commit(
        history,
        state,
        state.document.copyWith(assets: const []),
        const {DocumentScope.assets},
        HistoryOperationCode.changeAssets,
      );
      staging.releaseReference(
        sessionId: sessionId,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.activeDocument,
      );
      var lease = await staging.acquire(
        sessionId: sessionId,
        assetId: asset.id,
        kind: StagedAssetReferenceKind.preview,
      );
      expect(
        await lease.openRead().fold<int>(0, (sum, chunk) => sum + chunk.length),
        5,
      );
      await lease.release();

      state = history.undo(state).state;
      expect(state.document.assets.single.id, asset.id);
      state = history.redo(state).state;
      expect(state.document.assets, isEmpty);

      state = _commit(
        history,
        state,
        state.document.copyWith(title: 'Trim deletion'),
        const {DocumentScope.settings},
        HistoryOperationCode.batchEdit,
      );
      await expectLater(
        staging.acquire(
          sessionId: sessionId,
          assetId: asset.id,
          kind: StagedAssetReferenceKind.preview,
        ),
        throwsA(isA<AssetStagingException>()),
      );
      history.clear();
      await staging.disposeSession(sessionId);
    },
  );
}

EditorDocumentState _commit(
  EditorHistory history,
  EditorDocumentState state,
  ProjectDocument candidate,
  Set<DocumentScope> scopes,
  HistoryOperationCode code,
) {
  history.begin(state, HistoryTransactionDescriptor(operation: code));
  final operation = DocumentOperationResult.success(
    document: candidate,
    affectedScopes: scopes,
    summary: DocumentChangeSummary(action: 'asset-retention-test'),
  );
  history.addFrom(expectedBase: state.document, operation: operation);
  return history.commit(state).state;
}

ProjectDocument _document(ProjectAsset asset) => ProjectDocument(
  id: ProjectId('project'),
  title: 'Retention',
  canvas: const ProjectCanvas(width: 1920, height: 1080),
  frameRate: FrameRate.fps30,
  duration: TimelineDuration.zero,
  assets: [asset],
  strokes: const [],
  sections: const [],
  sectionOrder: const [],
  scenes: const [],
  audioTracks: const [],
);

final class _Source implements EditorAssetStreamSource {
  const _Source(this.bytes);

  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Stream<Uint8List> openRead() async* {
    yield bytes;
  }
}
