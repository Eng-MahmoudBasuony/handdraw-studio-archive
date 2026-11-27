import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/path_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/scene_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/timeline_document_operations.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';
import 'support/project_document_parity_fixture.dart';

void main() {
  group('Step 5A transactions and restoration', () {
    test('simple before/after keeps undo and redo revisions monotonic', () {
      final history = EditorHistory();
      var state = EditorDocumentState(document: projectDocumentParityFixture());

      state = _commit(
        history,
        state,
        _titleOperation(state.document, 'Edited'),
        operation: HistoryOperationCode.changeSettings,
      );
      expect(state.document.title, 'Edited');
      expect(state.revision.value, 1);

      state = history.undo(state).state;
      expect(state.document.title, 'Runtime parity');
      expect(state.revision.value, 2);

      state = history.redo(state).state;
      expect(state.document.title, 'Edited');
      expect(state.revision.value, 3);
    });

    test(
      'multi-scope delete section restores strokes, pauses, and membership',
      () {
        final history = EditorHistory();
        final source = _pathDocument();
        var state = EditorDocumentState(document: source);
        final result = const SceneDocumentOperations().deleteSection(
          document: source,
          sectionId: source.sections.first.id,
        );

        state = _commit(
          history,
          state,
          result,
          operation: HistoryOperationCode.deleteSection,
        );
        expect(state.document.sections, isEmpty);
        expect(state.document.strokes, isEmpty);

        state = history.undo(state).state;
        expect(state.document.sections.single.strokeIds, hasLength(1));
        expect(
          state.document.strokes.single.pausePoints.single.id.value,
          'pause-1',
        );
        expect(state.document.scenes.single.sectionIds, hasLength(1));
      },
    );

    test('split and join paths are each one atomic history entry', () {
      final history = EditorHistory();
      var state = EditorDocumentState(document: _pathDocument());
      final split = const PathDocumentOperations().splitPath(
        document: state.document,
        strokeId: state.document.strokes.single.id,
        anchorIndex: 1,
        ids: IdAllocationContext(generator: SequentialIdGenerator()),
      );
      state = _commit(
        history,
        state,
        split,
        operation: HistoryOperationCode.splitPath,
      );
      expect(state.document.strokes, hasLength(2));
      expect(state.document.sections.single.strokeIds, hasLength(2));
      expect(history.undoEntries, hasLength(1));

      state = history.undo(state).state;
      expect(state.document.strokes, hasLength(1));
      expect(
        state.document.strokes.single.pausePoints.single.id.value,
        'pause-1',
      );
      state = history.redo(state).state;

      final first = state.document.strokes.first.id;
      final second = state.document.strokes.last.id;
      final joined = const PathDocumentOperations().joinWithNext(
        document: state.document,
        strokeId: first,
        nextStrokeId: second,
      );
      state = _commit(
        history,
        state,
        joined,
        operation: HistoryOperationCode.joinPath,
      );
      expect(state.document.strokes, hasLength(1));
      state = history.undo(state).state;
      expect(state.document.strokes, hasLength(2));
      expect(state.document.sections.single.strokeIds, [first, second]);
    });

    test('failed operation rolls back without revision or history entry', () {
      final history = EditorHistory();
      final state = EditorDocumentState(
        document: projectDocumentParityFixture(),
      );
      history.begin(
        state,
        HistoryTransactionDescriptor(
          operation: HistoryOperationCode.changePath,
        ),
      );
      final failure = DocumentOperationResult.failure(
        document: state.document,
        code: DocumentOperationFailureCode.invalidInput,
        message: 'invalid node',
      );
      expect(
        history.addFrom(expectedBase: state.document, operation: failure)?.code,
        EditorHistoryFailureCode.transactionRejected,
      );
      final committed = history.commit(state);
      expect(committed.isSuccess, isFalse);
      expect(identical(committed.state, state), isTrue);
      expect(history.undoEntries, isEmpty);
      expect(state.revision.value, 0);
    });

    test(
      'multiple operations commit once and audio cue add/clear undo atomically',
      () {
        final history = EditorHistory();
        var state = EditorDocumentState(
          document: projectDocumentParityFixture(),
        );
        final sectionId = state.document.sections.single.id;
        const timing = TimelineDocumentOperations();
        history.begin(
          state,
          HistoryTransactionDescriptor(
            operation: HistoryOperationCode.changeAudioCue,
            entityIds: {sectionId.value},
          ),
        );
        final cleared = timing.clearAudioCue(
          document: state.document,
          sectionId: sectionId,
        );
        expect(
          history.addFrom(expectedBase: state.document, operation: cleared),
          isNull,
        );
        final restored = timing.setAudioCue(
          document: cleared.document,
          sectionId: sectionId,
          anchor: AudioCueAnchor(
            audioTrackId: state.document.audioTracks.single.id,
            sourceMediaTime: TimelineTime.fromMicroseconds(1200000),
          ),
        );
        expect(
          history.addFrom(expectedBase: cleared.document, operation: restored),
          isNull,
        );
        final committed = history.commit(state);
        expect(committed.isSuccess, isTrue);
        state = committed.state;
        expect(state.revision.value, 1);
        expect(
          state
              .document
              .sections
              .single
              .timing
              .audioCueAnchor!
              .sourceMediaTime
              .microseconds,
          1200000,
        );
        expect(history.undoEntries, hasLength(1));
        state = history.undo(state).state;
        expect(
          state
              .document
              .sections
              .single
              .timing
              .audioCueAnchor!
              .sourceMediaTime
              .microseconds,
          750000,
        );
      },
    );

    test('failed undo keeps document and both stacks unchanged', () {
      final history = EditorHistory();
      var state = EditorDocumentState(document: _pathDocument());
      state = _commit(
        history,
        state,
        _strokeNameOperation(state.document, 'Changed'),
        operation: HistoryOperationCode.changeStroke,
      );
      final invalid = EditorDocumentState(
        document: state.document.copyWith(sections: const []),
        revision: state.revision,
      );
      final result = history.undo(invalid);
      expect(result.isSuccess, isFalse);
      expect(identical(result.state, invalid), isTrue);
      expect(history.undoEntries, hasLength(1));
      expect(history.redoEntries, isEmpty);
    });

    test('failed redo keeps document and both stacks unchanged', () {
      final history = EditorHistory();
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      state = _commit(
        history,
        state,
        _titleOperation(state.document, 'Changed'),
        operation: HistoryOperationCode.changeSettings,
      );
      state = history.undo(state).state;
      final stale = EditorDocumentState(
        document: state.document,
        revision: state.revision,
      );
      final result = history.redo(stale);
      expect(result.isSuccess, isFalse);
      expect(result.failure?.code, EditorHistoryFailureCode.staleEditorState);
      expect(history.undoEntries, isEmpty);
      expect(history.redoEntries, hasLength(1));
    });
  });

  group('Step 5A branches, coalescing, and limits', () {
    test('undo followed by edit clears redo', () {
      final history = EditorHistory();
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      state = _commit(
        history,
        state,
        _titleOperation(state.document, 'One'),
        operation: HistoryOperationCode.changeSettings,
      );
      state = history.undo(state).state;
      expect(history.canRedo, isTrue);
      state = _commit(
        history,
        state,
        _titleOperation(state.document, 'Branch'),
        operation: HistoryOperationCode.changeSettings,
      );
      expect(state.document.title, 'Branch');
      expect(history.canRedo, isFalse);
    });

    test('same key, entities, and scope coalesce inside fake clock window', () {
      final clock = _FakeClock();
      final history = EditorHistory(clock: clock);
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      for (final title in ['One', 'Two', 'Three']) {
        state = _commit(
          history,
          state,
          _titleOperation(state.document, title),
          operation: HistoryOperationCode.changeSettings,
          entityIds: const {'project-parity'},
          mergeKey: HistoryMergeKey('title'),
        );
        clock.advance(100);
      }
      expect(history.undoEntries, hasLength(1));
      state = history.undo(state).state;
      expect(state.document.title, 'Runtime parity');
      state = history.redo(state).state;
      expect(state.document.title, 'Three');
    });

    test(
      'add/delete, different entities, and expired windows do not coalesce',
      () {
        final clock = _FakeClock();
        final history = EditorHistory(
          clock: clock,
          limits: const EditorHistoryLimits(coalescingWindowTicks: 50),
        );
        var state = EditorDocumentState(
          document: projectDocumentParityFixture(),
        );
        state = _commit(
          history,
          state,
          _titleOperation(state.document, 'One'),
          operation: HistoryOperationCode.changeSettings,
          entityIds: const {'one'},
          mergeKey: HistoryMergeKey('field'),
        );
        clock.advance(100);
        state = _commit(
          history,
          state,
          _titleOperation(state.document, 'Two'),
          operation: HistoryOperationCode.changeSettings,
          entityIds: const {'one'},
          mergeKey: HistoryMergeKey('field'),
        );
        state = _commit(
          history,
          state,
          _titleOperation(state.document, 'Three'),
          operation: HistoryOperationCode.changeSettings,
          entityIds: const {'different'},
          mergeKey: HistoryMergeKey('field'),
        );
        expect(history.undoEntries, hasLength(3));
      },
    );

    test('entry and conservative byte limits trim oldest entries', () {
      final history = EditorHistory(
        limits: const EditorHistoryLimits(
          maxEntries: 2,
          maxEstimatedBytes: 4096,
        ),
      );
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      for (final title in ['One', 'Two', 'Three']) {
        state = _commit(
          history,
          state,
          _titleOperation(state.document, title),
          operation: HistoryOperationCode.batchEdit,
        );
      }
      expect(history.undoEntries, hasLength(2));
      expect(history.estimatedBytes, lessThanOrEqualTo(4096));
      state = history.undo(state).state;
      state = history.undo(state).state;
      expect(state.document.title, 'One');
      expect(
        history.undo(state).failure?.code,
        EditorHistoryFailureCode.nothingToUndo,
      );
    });
  });

  group('Step 5A checkpoints and asset retention', () {
    test(
      'checkpoint follows cursor and an older save cannot clean newer edit',
      () {
        final history = EditorHistory();
        var state = EditorDocumentState(
          document: projectDocumentParityFixture(),
        );
        state = _commit(
          history,
          state,
          _titleOperation(state.document, 'Saved'),
          operation: HistoryOperationCode.changeSettings,
        );
        final save = history.captureSaveSnapshot('fingerprint-saved');
        state = _commit(
          history,
          state,
          _titleOperation(state.document, 'Newer'),
          operation: HistoryOperationCode.changeSettings,
        );
        history.markSaved(save);
        expect(history.isDirty(), isTrue);
        state = history.undo(state).state;
        expect(state.document.title, 'Saved');
        expect(history.isDirty(), isFalse);
        state = history.redo(state).state;
        expect(history.isDirty(), isTrue);
      },
    );

    test('trimmed checkpoint falls back to deterministic fingerprint', () {
      final history = EditorHistory(
        limits: const EditorHistoryLimits(maxEntries: 1),
      );
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      history.markSaved(history.captureSaveSnapshot('original'));
      state = _commit(
        history,
        state,
        _titleOperation(state.document, 'One'),
        operation: HistoryOperationCode.batchEdit,
      );
      state = _commit(
        history,
        state,
        _titleOperation(state.document, 'Two'),
        operation: HistoryOperationCode.batchEdit,
      );
      expect(history.isDirty(currentFingerprint: 'original'), isFalse);
      expect(history.isDirty(currentFingerprint: 'different'), isTrue);
    });

    test('asset history retains metadata IDs and releases trimmed leases', () {
      final retention = _RecordingRetention();
      final history = EditorHistory(
        assetRetention: retention,
        limits: const EditorHistoryLimits(maxEntries: 1),
      );
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      final asset = ProjectAsset(
        id: ProjectAssetId('temporary'),
        kind: ProjectAssetKind.other,
        originalFileName: 'metadata.bin',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:temporary',
      );
      state = _commit(
        history,
        state,
        DocumentOperationResult.success(
          document: state.document.copyWith(
            assets: [...state.document.assets, asset],
          ),
          affectedScopes: const {DocumentScope.assets},
          summary: DocumentChangeSummary(action: 'add-asset'),
        ),
        operation: HistoryOperationCode.changeAssets,
      );
      expect(retention.retained.single, contains(ProjectAssetId('temporary')));
      expect(
        history.undoEntries.single.changes.single.estimatedBytes,
        greaterThan(0),
      );
      state = _commit(
        history,
        state,
        DocumentOperationResult.success(
          document: state.document.copyWith(
            assets: state.document.assets
                .where((item) => item.id != asset.id)
                .toList(),
          ),
          affectedScopes: const {DocumentScope.assets},
          summary: DocumentChangeSummary(action: 'delete-asset'),
        ),
        operation: HistoryOperationCode.changeAssets,
      );
      expect(retention.released, contains(const HistoryEntryId(1)));
      expect(state.document.assets, isNot(contains(asset)));
      state = history.undo(state).state;
      expect(state.document.assets.map((item) => item.id), contains(asset.id));
    });
  });
}

EditorDocumentState _commit(
  EditorHistory history,
  EditorDocumentState state,
  DocumentOperationResult operationResult, {
  required HistoryOperationCode operation,
  Set<String> entityIds = const {},
  HistoryMergeKey? mergeKey,
}) {
  history.begin(
    state,
    HistoryTransactionDescriptor(
      operation: operation,
      entityIds: entityIds,
      mergeKey: mergeKey,
      allowCoalescing: mergeKey != null,
    ),
  );
  final failure = history.addFrom(
    expectedBase: state.document,
    operation: operationResult,
  );
  expect(failure, isNull);
  final result = history.commit(state);
  expect(result.isSuccess, isTrue, reason: result.failure?.message);
  return result.state;
}

DocumentOperationResult _titleOperation(
  ProjectDocument document,
  String title,
) => DocumentOperationResult.success(
  document: document.copyWith(title: title),
  affectedScopes: const {DocumentScope.settings},
  summary: DocumentChangeSummary(action: 'change-title'),
);

DocumentOperationResult _strokeNameOperation(
  ProjectDocument document,
  String name,
) => DocumentOperationResult.success(
  document: document.copyWith(
    strokes: [document.strokes.single.copyWith(name: name)],
  ),
  affectedScopes: const {DocumentScope.strokes},
  summary: DocumentChangeSummary(action: 'change-stroke'),
);

ProjectDocument _pathDocument() {
  final source = projectDocumentParityFixture();
  final sectionId = source.sections.single.id;
  final stroke = source.strokes.single.copyWith(
    geometry: StrokePathGeometry(
      start: const Offset(0.1, 0.1),
      segments: const [
        StrokeLineSegment(end: Offset(0.4, 0.4)),
        StrokeLineSegment(end: Offset(0.8, 0.2)),
      ],
    ),
    pausePoints: [
      DocumentStrokePause(
        id: StrokePauseId('pause-1'),
        progress: 0.25,
        duration: TimelineDuration.fromMicroseconds(200000),
      ),
    ],
  );
  return source.copyWith(
    strokes: [stroke],
    sections: [
      source.sections.single.copyWith(strokeIds: [stroke.id]),
    ],
    scenes: [
      ProjectScene(
        id: SceneId('scene-path'),
        name: 'Path',
        sectionIds: [sectionId],
      ),
    ],
  );
}

final class _FakeClock implements MonotonicEditClock {
  int _ticks = 0;

  @override
  int get nowTicks => _ticks;

  void advance(int ticks) => _ticks += ticks;
}

final class _RecordingRetention implements HistoryAssetRetention {
  final List<Set<ProjectAssetId>> retained = [];
  final List<HistoryEntryId> released = [];

  @override
  void retain(HistoryEntryId entryId, Set<ProjectAssetId> assetIds) {
    retained.add(Set.of(assetIds));
  }

  @override
  void release(HistoryEntryId entryId) => released.add(entryId);
}
