import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  test('1000 seeded valid edits undo and redo without semantic corruption', () {
    const seed = 51002;
    final random = Random(seed);
    const fingerprints = CanonicalDocumentFingerprintCalculator();
    final history = EditorHistory(
      limits: const EditorHistoryLimits(
        maxEntries: 1200,
        maxEstimatedBytes: 256 * 1024 * 1024,
      ),
    );
    var state = EditorDocumentState(document: projectDocumentParityFixture());
    final initial = fingerprints.calculate(state.document).semantic;

    for (var index = 0; index < 1000; index++) {
      final operation = _randomOperation(state.document, random, index);
      final failure = history.begin(
        state,
        HistoryTransactionDescriptor(
          operation: operation.affectedScopes.length > 1
              ? HistoryOperationCode.batchEdit
              : _code(operation.affectedScopes.single),
          entityIds: {'seed-$seed', 'edit-$index'},
        ),
      );
      expect(failure, isNull, reason: 'seed=$seed edit=$index');
      expect(
        history.addFrom(expectedBase: state.document, operation: operation),
        isNull,
        reason: 'seed=$seed edit=$index',
      );
      final committed = history.commit(state);
      expect(committed.isSuccess, isTrue, reason: 'seed=$seed edit=$index');
      state = committed.state;
    }
    final finalFingerprint = fingerprints.calculate(state.document).semantic;
    expect(history.undoEntries, hasLength(1000));

    for (var index = 0; index < 1000; index++) {
      final undone = history.undo(state);
      expect(undone.isSuccess, isTrue, reason: 'seed=$seed undo=$index');
      state = undone.state;
    }
    expect(
      fingerprints.calculate(state.document).semantic,
      initial,
      reason: 'seed=$seed',
    );

    for (var index = 0; index < 1000; index++) {
      final redone = history.redo(state);
      expect(redone.isSuccess, isTrue, reason: 'seed=$seed redo=$index');
      state = redone.state;
    }
    expect(
      fingerprints.calculate(state.document).semantic,
      finalFingerprint,
      reason: 'seed=$seed',
    );
  });
}

DocumentOperationResult _randomOperation(
  ProjectDocument document,
  Random random,
  int index,
) {
  final stroke = document.strokes.single;
  final section = document.sections.single;
  final scene = document.scenes.single;
  switch (random.nextInt(5)) {
    case 0:
      return _result(document.copyWith(title: 'Title $index'), const {
        DocumentScope.settings,
      });
    case 1:
      return _result(
        document.copyWith(
          strokes: [stroke.copyWith(reversed: !stroke.reversed)],
        ),
        const {DocumentScope.strokes},
      );
    case 2:
      return _result(
        document.copyWith(
          sections: [
            section.copyWith(
              timing: section.timing.copyWith(
                pauseAfter: TimelineDuration.fromMicroseconds(
                  random.nextInt(900000),
                ),
              ),
            ),
          ],
        ),
        const {DocumentScope.timing},
      );
    case 3:
      return _result(
        document.copyWith(scenes: [scene.copyWith(locked: !scene.locked)]),
        const {DocumentScope.scenes},
      );
    default:
      return _result(
        document.copyWith(
          title: 'Batch $index',
          strokes: [stroke.copyWith(hidden: !stroke.hidden)],
        ),
        const {DocumentScope.settings, DocumentScope.strokes},
      );
  }
}

DocumentOperationResult _result(
  ProjectDocument document,
  Set<DocumentScope> scopes,
) => DocumentOperationResult.success(
  document: document,
  affectedScopes: scopes,
  summary: DocumentChangeSummary(action: 'stress-edit'),
);

HistoryOperationCode _code(DocumentScope scope) => switch (scope) {
  DocumentScope.strokes => HistoryOperationCode.changeStroke,
  DocumentScope.timing => HistoryOperationCode.changeTiming,
  DocumentScope.scenes => HistoryOperationCode.changeScene,
  _ => HistoryOperationCode.changeSettings,
};
