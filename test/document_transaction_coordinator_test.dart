import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_transaction_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_scoped_document_change_detector.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/mask_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/path_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/project_settings_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/scene_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/stroke_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/timeline_document_operations.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';
import 'support/project_document_parity_fixture.dart';

void main() {
  const coordinator = DocumentTransactionCoordinator(
    changeDetector: CanonicalScopedDocumentChangeDetector(),
  );

  test(
    'all 61 operation families have one policy and session boundaries are explicit',
    () {
      const policies = DocumentOperationPolicyRegistry();
      expect(DocumentOperationKind.values, hasLength(61));
      final classified = {
        for (final kind in DocumentOperationKind.values)
          kind: policies.policyFor(kind),
      };
      expect(classified, hasLength(61));
      expect(
        classified.values.where((policy) => policy.sessionBoundary),
        hasLength(2),
      );
      expect(
        classified[DocumentOperationKind.settingsCreateNew]!.sessionBoundary,
        isTrue,
      );
      expect(
        classified[DocumentOperationKind.settingsDuplicateProject]!
            .sessionBoundary,
        isTrue,
      );
    },
  );

  test(
    'stroke commit, undo, and redo preserve generated IDs and revisions',
    () {
      final source = _documentWithGeometry();
      var state = EditorDocumentState(document: source);
      final history = EditorHistory();
      final result = coordinator.execute(
        current: state,
        history: history,
        expectedProjectId: source.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.pathSplit,
        operation: (document) => const PathDocumentOperations().splitPath(
          document: document,
          strokeId: document.strokes.first.id,
          anchorIndex: 1,
          ids: _ids(document),
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.state.revision.value, 1);
      expect(
        history.undoEntries.single.operation,
        HistoryOperationCode.splitPath,
      );
      final createdId = result.state.document.strokes.last.id;
      state = coordinator.undo(current: result.state, history: history).state;
      expect(state.revision.value, 2);
      expect(
        state.document.strokes.any((stroke) => stroke.id == createdId),
        isFalse,
      );
      state = coordinator.redo(current: state, history: history).state;
      expect(state.revision.value, 3);
      expect(state.document.strokes.last.id, createdId);
    },
  );

  test('no-op changes nothing and does not clear redo', () {
    final source = projectDocumentParityFixture();
    var state = EditorDocumentState(document: source);
    final history = EditorHistory();
    final changed = coordinator.execute(
      current: state,
      history: history,
      expectedProjectId: source.id,
      expectedRevision: state.revision,
      kind: DocumentOperationKind.strokeSetHidden,
      operation: (document) => const StrokeDocumentOperations().setHidden(
        document: document,
        strokeId: document.strokes.single.id,
        hidden: true,
      ),
    );
    state = coordinator.undo(current: changed.state, history: history).state;
    expect(history.canRedo, isTrue);
    final noOp = coordinator.execute(
      current: state,
      history: history,
      expectedProjectId: source.id,
      expectedRevision: state.revision,
      kind: DocumentOperationKind.strokeSetHidden,
      operation: (document) => const StrokeDocumentOperations().setHidden(
        document: document,
        strokeId: document.strokes.single.id,
        hidden: false,
      ),
    );
    expect(noOp.noOp, isTrue);
    expect(identical(noOp.state, state), isTrue);
    expect(history.canRedo, isTrue);
  });

  test('timing changes coalesce only for the same property and entity', () {
    final source = projectDocumentParityFixture();
    var state = EditorDocumentState(document: source);
    final history = EditorHistory(
      limits: const EditorHistoryLimits(coalescingWindowTicks: 1000000),
    );
    for (final micros in [100000, 200000]) {
      final result = coordinator.execute(
        current: state,
        history: history,
        expectedProjectId: source.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.timingSetPauseBefore,
        mergeProperty: 'pauseBefore',
        operation: (document) =>
            const TimelineDocumentOperations().setPauseBefore(
              document: document,
              sectionId: document.sections.single.id,
              duration: TimelineDuration.fromMicroseconds(micros),
            ),
      );
      state = result.state;
    }
    expect(history.undoEntries, hasLength(1));
    state = coordinator.undo(current: state, history: history).state;
    expect(
      state.document.sections.single.timing.pauseBefore,
      TimelineDuration.zero,
    );
  });

  test(
    'scene, mask, settings, and timing families publish correct metadata',
    () {
      final cases =
          <({DocumentOperationKind kind, PureDocumentOperation operation})>[
            (
              kind: DocumentOperationKind.sceneCreate,
              operation: (document) =>
                  const SceneDocumentOperations().createScene(
                    document: document,
                    name: 'Scene',
                    sectionIds: [document.sections.single.id],
                    ids: _ids(document),
                  ),
            ),
            (
              kind: DocumentOperationKind.maskAdd,
              operation: (document) => MaskDocumentOperations().add(
                document: document,
                strokeId: document.strokes.single.id,
                mask: DocumentVectorMaskStroke(
                  geometry: document.strokes.single.geometry!,
                  width: 0.02,
                  erase: false,
                ),
              ),
            ),
            (
              kind: DocumentOperationKind.settingsSetCanvas,
              operation: (document) =>
                  const ProjectSettingsOperations().setCanvas(
                    document: document,
                    canvas: const ProjectCanvas(width: 1280, height: 720),
                  ),
            ),
            (
              kind: DocumentOperationKind.timingSetSpeedMultiplier,
              operation: (document) =>
                  const TimelineDocumentOperations().setSpeedMultiplier(
                    document: document,
                    sectionId: document.sections.single.id,
                    multiplier: 1.5,
                  ),
            ),
          ];
      for (final item in cases) {
        final source = _documentWithGeometry();
        final state = EditorDocumentState(document: source);
        final history = EditorHistory();
        final result = coordinator.execute(
          current: state,
          history: history,
          expectedProjectId: source.id,
          expectedRevision: state.revision,
          kind: item.kind,
          operation: item.operation,
        );
        expect(result.isSuccess, isTrue, reason: item.kind.name);
        expect(result.state.revision.value, 1, reason: item.kind.name);
        expect(history.undoEntries.single.affectedScopes, isNotEmpty);
        expect(history.undoEntries.single.entityIds, isNotNull);
        expect(
          coordinator
              .redo(
                current: coordinator
                    .undo(current: result.state, history: history)
                    .state,
                history: history,
              )
              .isSuccess,
          isTrue,
        );
      }
    },
  );

  test(
    'typed stale, wrong-session, operation, validation, and session failures are atomic',
    () {
      final source = projectDocumentParityFixture();
      final state = EditorDocumentState(document: source);
      for (final invocation
          in <DocumentTransactionResult Function(EditorHistory)>[
            (history) => coordinator.execute(
              current: state,
              history: history,
              expectedProjectId: ProjectId('wrong'),
              expectedRevision: state.revision,
              kind: DocumentOperationKind.strokeSetHidden,
              operation: (_) => throw StateError('must not run'),
            ),
            (history) => coordinator.execute(
              current: state,
              history: history,
              expectedProjectId: source.id,
              expectedRevision: state.revision.next,
              kind: DocumentOperationKind.strokeSetHidden,
              operation: (_) => throw StateError('must not run'),
            ),
            (history) => coordinator.execute(
              current: state,
              history: history,
              expectedProjectId: source.id,
              expectedRevision: state.revision,
              kind: DocumentOperationKind.strokeSetHidden,
              operation: (_) => throw StateError('operation'),
            ),
            (history) => coordinator.execute(
              current: state,
              history: history,
              expectedProjectId: source.id,
              expectedRevision: state.revision,
              kind: DocumentOperationKind.strokeSetHidden,
              operation: (document) => DocumentOperationResult.success(
                document: document.copyWith(strokes: const []),
                affectedScopes: const {DocumentScope.strokes},
                summary: DocumentChangeSummary(action: 'invalid'),
              ),
            ),
            (history) => coordinator.execute(
              current: state,
              history: history,
              expectedProjectId: source.id,
              expectedRevision: state.revision,
              kind: DocumentOperationKind.settingsCreateNew,
              operation: (_) => throw StateError('must not run'),
            ),
          ]) {
        final history = EditorHistory();
        final result = invocation(history);
        expect(result.isSuccess, isFalse);
        expect(identical(result.state, state), isTrue);
        expect(history.undoEntries, isEmpty);
        expect(history.redoEntries, isEmpty);
      }
    },
  );

  test(
    'retention failure leaves revision, cursor, history, and redo unchanged',
    () {
      final source = projectDocumentParityFixture();
      final state = EditorDocumentState(document: source);
      final retention = _FailingRetention()..fail = true;
      final history = EditorHistory(assetRetention: retention);
      final asset = source.assets.first.copyWith(
        id: ProjectAssetId('new-asset'),
      );
      final result = coordinator.execute(
        current: state,
        history: history,
        expectedProjectId: source.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.settingsAddAsset,
        operation: (document) => const ProjectSettingsOperations().addAsset(
          document: document,
          asset: asset,
        ),
      );
      expect(
        result.failure?.code,
        DocumentTransactionFailureCode.assetRetentionFailed,
      );
      expect(identical(result.state, state), isTrue);
      expect(history.currentStateToken, 0);
      expect(history.undoEntries, isEmpty);
      expect(history.redoEntries, isEmpty);
      expect(retention.live, isEmpty);
    },
  );

  test('all injected transaction stages fail without changing owners', () {
    for (final point in DocumentTransactionFailurePoint.values.take(4)) {
      final source = projectDocumentParityFixture();
      final state = EditorDocumentState(document: source);
      final history = EditorHistory();
      final injected = DocumentTransactionCoordinator(
        changeDetector: const CanonicalScopedDocumentChangeDetector(),
        failureInjector: _FailureInjector(point),
      );
      final result = injected.execute(
        current: state,
        history: history,
        expectedProjectId: source.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.strokeSetHidden,
        operation: (document) => const StrokeDocumentOperations().setHidden(
          document: document,
          strokeId: document.strokes.single.id,
          hidden: true,
        ),
      );
      expect(result.isSuccess, isFalse, reason: point.name);
      expect(identical(result.state, state), isTrue, reason: point.name);
      expect(history.undoEntries, isEmpty, reason: point.name);
      expect(history.redoEntries, isEmpty, reason: point.name);
      expect(history.hasActiveTransaction, isFalse, reason: point.name);
    }

    final source = projectDocumentParityFixture();
    final initial = EditorDocumentState(document: source);
    final history = EditorHistory();
    final committed = coordinator.execute(
      current: initial,
      history: history,
      expectedProjectId: source.id,
      expectedRevision: initial.revision,
      kind: DocumentOperationKind.strokeSetHidden,
      operation: (document) => const StrokeDocumentOperations().setHidden(
        document: document,
        strokeId: document.strokes.single.id,
        hidden: true,
      ),
    );
    final failedUndo = DocumentTransactionCoordinator(
      changeDetector: const CanonicalScopedDocumentChangeDetector(),
      failureInjector: const _FailureInjector(
        DocumentTransactionFailurePoint.undoRestore,
      ),
    ).undo(current: committed.state, history: history);
    expect(failedUndo.isSuccess, isFalse);
    expect(history.undoEntries, hasLength(1));
    expect(history.redoEntries, isEmpty);

    final undone = coordinator.undo(current: committed.state, history: history);
    final failedRedo = DocumentTransactionCoordinator(
      changeDetector: const CanonicalScopedDocumentChangeDetector(),
      failureInjector: const _FailureInjector(
        DocumentTransactionFailurePoint.redoRestore,
      ),
    ).redo(current: undone.state, history: history);
    expect(failedRedo.isSuccess, isFalse);
    expect(history.undoEntries, isEmpty);
    expect(history.redoEntries, hasLength(1));
  });

  test('asset relink is persistence-dirty and undo returns saved state', () {
    const fingerprints = CanonicalDocumentFingerprintCalculator();
    final fixture = projectDocumentParityFixture();
    final asset = fixture.assets.first.copyWith(
      storagePolicy: ProjectAssetStoragePolicy.external,
      externalLocator: const ExternalAssetLocator(
        pathHint: '/a/art.svg',
        securityBookmark: 'a',
      ),
    );
    final source = fixture.copyWith(assets: [asset, ...fixture.assets.skip(1)]);
    var state = EditorDocumentState(document: source);
    final history = EditorHistory();
    history.markSaved(
      history.captureSaveSnapshot(
        fingerprints.calculate(source).persistence.value,
      ),
    );
    final result = coordinator.execute(
      current: state,
      history: history,
      expectedProjectId: source.id,
      expectedRevision: state.revision,
      kind: DocumentOperationKind.settingsAddAsset,
      operation: (document) => DocumentOperationResult.success(
        document: document.copyWith(
          assets: [
            asset.copyWith(
              externalLocator: const ExternalAssetLocator(
                pathHint: '/b/art.svg',
                securityBookmark: 'b',
              ),
            ),
            ...document.assets.skip(1),
          ],
        ),
        affectedScopes: const {DocumentScope.assets},
        summary: DocumentChangeSummary(
          action: 'relink-asset',
          entityIds: [asset.id.value],
        ),
      ),
    );
    state = result.state;
    expect(
      history.isDirty(
        currentFingerprint: fingerprints
            .calculate(state.document)
            .persistence
            .value,
      ),
      isTrue,
    );
    state = coordinator.undo(current: state, history: history).state;
    expect(
      history.isDirty(
        currentFingerprint: fingerprints
            .calculate(state.document)
            .persistence
            .value,
      ),
      isFalse,
    );
  });
}

final class _FailureInjector implements DocumentTransactionFailureInjector {
  const _FailureInjector(this.point);
  final DocumentTransactionFailurePoint point;
  @override
  void check(DocumentTransactionFailurePoint current) {
    if (current == point) throw StateError('injected ${point.name} failure');
  }
}

final class _FailingRetention implements HistoryAssetRetention {
  bool fail = false;
  final Map<HistoryEntryId, Set<ProjectAssetId>> live = {};
  @override
  void retain(HistoryEntryId entryId, Set<ProjectAssetId> assetIds) {
    if (fail) throw StateError('injected retention failure');
    live[entryId] = assetIds;
  }

  @override
  void release(HistoryEntryId entryId) => live.remove(entryId);
}

ProjectDocument _documentWithGeometry() {
  final source = projectDocumentParityFixture();
  final stroke = source.strokes.single;
  return source.copyWith(strokes: [stroke.copyWith(geometry: _geometry())]);
}

StrokePathGeometry _geometry() => StrokePathGeometry(
  start: const Offset(0.1, 0.2),
  segments: const [
    StrokeCubicSegment(
      control1: Offset(0.2, 0.1),
      control2: Offset(0.4, 0.3),
      end: Offset(0.5, 0.2),
    ),
    StrokeLineSegment(end: Offset(0.8, 0.5)),
  ],
);

IdAllocationContext _ids(ProjectDocument document) => IdAllocationContext(
  generator: FakeIdGenerator(),
  usedIds: [
    document.id,
    ...document.assets.map((item) => item.id),
    ...document.strokes.map((item) => item.id),
    ...document.strokes.expand(
      (item) => item.pausePoints.map((pause) => pause.id),
    ),
    ...document.sections.map((item) => item.id),
    ...document.scenes.map((item) => item.id),
    ...document.audioTracks.map((item) => item.id),
  ],
);
