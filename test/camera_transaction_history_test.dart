import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/operations/camera_document_operations.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_transaction_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_scoped_document_change_detector.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  const coordinator = DocumentTransactionCoordinator(
    changeDetector: CanonicalScopedDocumentChangeDetector(),
  );
  const operations = CameraDocumentOperations();

  test(
    'camera operation commits once and undo/redo preserves generated IDs',
    () {
      final original = projectDocumentParityFixture();
      var state = EditorDocumentState(document: original);
      final history = EditorHistory();
      final track = ProjectCameraTrack(
        id: CameraTrackId('track'),
        shots: const [],
      );
      final result = coordinator.execute(
        current: state,
        history: history,
        expectedProjectId: original.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) => operations.createTrack(document, track),
      );
      expect(result.isSuccess, isTrue);
      expect(result.state.revision.value, 1);
      expect(history.undoEntries, hasLength(1));
      state = coordinator.undo(current: result.state, history: history).state;
      expect(state.document.cameraTrack, isNull);
      state = coordinator.redo(current: state, history: history).state;
      expect(state.document.cameraTrack!.id, CameraTrackId('track'));
    },
  );

  test(
    'no-op does not advance revision/history and move operations coalesce',
    () {
      final original = projectDocumentParityFixture();
      var state = EditorDocumentState(document: original);
      final history = EditorHistory();
      final created = coordinator.execute(
        current: state,
        history: history,
        expectedProjectId: original.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) => operations.createTrack(
          document,
          ProjectCameraTrack(id: CameraTrackId('track'), shots: [_shot()]),
        ),
      );
      state = created.state;
      final before = history.undoEntries.length;
      final noOp = coordinator.execute(
        current: state,
        history: history,
        expectedProjectId: original.id,
        expectedRevision: state.revision,
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) =>
            operations.setLock(document, CameraShotId('shot'), false),
      );
      expect(noOp.state.revision, state.revision);
      expect(history.undoEntries, hasLength(before));
      for (final us in [1000, 2000]) {
        final moved = coordinator.execute(
          current: state,
          history: history,
          expectedProjectId: original.id,
          expectedRevision: state.revision,
          kind: DocumentOperationKind.cameraEdit,
          mergeProperty: 'camera.shot.move:shot',
          operation: (document) => operations.moveShot(
            document,
            CameraShotId('shot'),
            TimelineTime.fromMicroseconds(us),
          ),
        );
        expect(moved.isSuccess, isTrue);
        state = moved.state;
      }
      expect(history.undoEntries.length, before + 1);
    },
  );
}

CameraShot _shot() => CameraShot(
  id: CameraShotId('shot'),
  startTime: TimelineTime.zero,
  duration: TimelineDuration.fromMicroseconds(1000),
  authorship: CameraAuthorship.auto,
  isLocked: false,
  keyframes: [
    CameraKeyframe(
      id: CameraKeyframeId('key'),
      offset: TimelineTime.zero,
      view: const CameraView.identity(),
    ),
  ],
);
