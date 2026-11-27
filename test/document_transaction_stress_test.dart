import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_transaction_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_scoped_document_change_detector.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/project_settings_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/stroke_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/timeline_document_operations.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  test(
    '1000 mixed transactions restore both identities and release all asset refs',
    () {
      const seed = 52003;
      const coordinator = DocumentTransactionCoordinator(
        changeDetector: CanonicalScopedDocumentChangeDetector(),
      );
      const fingerprints = CanonicalDocumentFingerprintCalculator();
      final retention = _CountingRetention();
      final history = EditorHistory(
        limits: const EditorHistoryLimits(
          maxEntries: 1200,
          maxEstimatedBytes: 256 * 1024 * 1024,
        ),
        assetRetention: retention,
      );
      var state = EditorDocumentState(document: projectDocumentParityFixture());
      final initial = fingerprints.calculate(state.document);
      ProjectAssetId? transientAsset;

      for (var index = 0; index < 1000; index++) {
        final invocation = _operation(index, state.document, transientAsset);
        final result = coordinator.execute(
          current: state,
          history: history,
          expectedProjectId: state.document.id,
          expectedRevision: state.revision,
          kind: invocation.kind,
          operation: invocation.operation,
        );
        expect(
          result.isSuccess,
          isTrue,
          reason: 'seed=$seed operation=$index failure=${result.failure?.code}',
        );
        expect(result.noOp, isFalse, reason: 'seed=$seed operation=$index');
        state = result.state;
        if (index % 10 == 4) {
          transientAsset = ProjectAssetId('stress-asset-$index');
        }
        if (index % 10 == 9) transientAsset = null;
      }
      final finalIdentity = fingerprints.calculate(state.document);
      expect(history.undoEntries, hasLength(1000));

      for (var index = 0; index < 1000; index++) {
        final result = coordinator.undo(current: state, history: history);
        expect(result.isSuccess, isTrue, reason: 'seed=$seed undo=$index');
        state = result.state;
      }
      final undone = fingerprints.calculate(state.document);
      expect(undone.semantic, initial.semantic, reason: 'seed=$seed');
      expect(undone.persistence, initial.persistence, reason: 'seed=$seed');

      for (var index = 0; index < 1000; index++) {
        final result = coordinator.redo(current: state, history: history);
        expect(result.isSuccess, isTrue, reason: 'seed=$seed redo=$index');
        state = result.state;
      }
      final redone = fingerprints.calculate(state.document);
      expect(redone.semantic, finalIdentity.semantic, reason: 'seed=$seed');
      expect(
        redone.persistence,
        finalIdentity.persistence,
        reason: 'seed=$seed',
      );
      expect(retention.totalReferences, greaterThan(0));
      history.clear();
      expect(retention.totalReferences, 0);
      expect(retention.entries, isEmpty);
    },
  );
}

({DocumentOperationKind kind, PureDocumentOperation operation}) _operation(
  int index,
  ProjectDocument document,
  ProjectAssetId? transientAsset,
) {
  switch (index % 10) {
    case 0:
    case 5:
      return (
        kind: DocumentOperationKind.settingsSetMotion,
        operation: (current) => DocumentOperationResult.success(
          document: current.copyWith(title: 'Stress $index'),
          affectedScopes: const {DocumentScope.settings},
          summary: DocumentChangeSummary(action: 'stress-title'),
        ),
      );
    case 1:
    case 6:
      return (
        kind: DocumentOperationKind.strokeSetHidden,
        operation: (current) => const StrokeDocumentOperations().setHidden(
          document: current,
          strokeId: current.strokes.single.id,
          hidden: !current.strokes.single.hidden,
        ),
      );
    case 2:
    case 7:
      return (
        kind: DocumentOperationKind.timingSetPauseBefore,
        operation: (current) =>
            const TimelineDocumentOperations().setPauseBefore(
              document: current,
              sectionId: current.sections.single.id,
              duration: TimelineDuration.fromMicroseconds((index + 1) * 1000),
            ),
      );
    case 3:
    case 8:
      return (
        kind: DocumentOperationKind.settingsSetCanvas,
        operation: (current) => const ProjectSettingsOperations().setCanvas(
          document: current,
          canvas: ProjectCanvas(width: 1000 + index, height: 700),
        ),
      );
    case 4:
      final id = ProjectAssetId('stress-asset-$index');
      return (
        kind: DocumentOperationKind.settingsAddAsset,
        operation: (current) => ProjectSettingsOperations().addAsset(
          document: current,
          asset: ProjectAsset(
            id: id,
            kind: ProjectAssetKind.other,
            originalFileName: '${id.value}.bin',
            storagePolicy: ProjectAssetStoragePolicy.embedded,
            contentHash: 'sha256:${'0' * 64}',
          ),
        ),
      );
    case 9:
      return (
        kind: DocumentOperationKind.settingsRemoveAsset,
        operation: (current) => ProjectSettingsOperations().removeAsset(
          document: current,
          assetId: transientAsset!,
        ),
      );
  }
  throw StateError('unreachable');
}

final class _CountingRetention implements HistoryAssetRetention {
  final Map<HistoryEntryId, Set<ProjectAssetId>> entries = {};
  final Map<ProjectAssetId, int> counts = {};
  int get totalReferences => counts.values.fold(0, (sum, count) => sum + count);

  @override
  void retain(HistoryEntryId entryId, Set<ProjectAssetId> assetIds) {
    release(entryId);
    entries[entryId] = Set.of(assetIds);
    for (final id in assetIds) {
      counts[id] = (counts[id] ?? 0) + 1;
    }
  }

  @override
  void release(HistoryEntryId entryId) {
    for (final id in entries.remove(entryId) ?? const <ProjectAssetId>{}) {
      final next = (counts[id] ?? 1) - 1;
      if (next == 0) {
        counts.remove(id);
      } else {
        counts[id] = next;
      }
    }
  }
}
