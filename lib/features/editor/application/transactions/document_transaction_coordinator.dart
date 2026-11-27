import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/document_revision.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';

typedef PureDocumentOperation =
    DocumentOperationResult Function(ProjectDocument document);

enum DocumentTransactionFailurePoint {
  operation,
  validation,
  retention,
  historyCommit,
  undoRestore,
  redoRestore,
}

abstract interface class DocumentTransactionFailureInjector {
  void check(DocumentTransactionFailurePoint point);
}

final class NoDocumentTransactionFailureInjection
    implements DocumentTransactionFailureInjector {
  const NoDocumentTransactionFailureInjection();
  @override
  void check(DocumentTransactionFailurePoint point) {}
}

abstract interface class ScopedDocumentChangeDetector {
  bool hasChanges(
    ProjectDocument before,
    ProjectDocument after,
    Set<DocumentScope> scopes,
  );
}

enum DocumentTransactionFailureCode {
  staleDocumentRevision,
  wrongProjectSession,
  documentOperationFailed,
  documentValidationFailed,
  assetRetentionFailed,
  historyTransactionFailed,
  historyRestoreFailed,
  sessionBoundaryOperation,
  invalidOperationPolicy,
}

final class DocumentTransactionFailure {
  const DocumentTransactionFailure(this.code, this.message, [this.cause]);
  final DocumentTransactionFailureCode code;
  final String message;
  final Object? cause;
}

final class DocumentTransactionResult {
  const DocumentTransactionResult._({
    required this.state,
    this.failure,
    this.noOp = false,
  });
  const DocumentTransactionResult.success(EditorDocumentState state)
    : this._(state: state);
  const DocumentTransactionResult.noOp(EditorDocumentState state)
    : this._(state: state, noOp: true);
  const DocumentTransactionResult.failure(
    EditorDocumentState state,
    DocumentTransactionFailure failure,
  ) : this._(state: state, failure: failure);
  final EditorDocumentState state;
  final DocumentTransactionFailure? failure;
  final bool noOp;
  bool get isSuccess => failure == null;
}

final class DocumentTransactionCoordinator {
  const DocumentTransactionCoordinator({
    required this.changeDetector,
    this.policies = const DocumentOperationPolicyRegistry(),
    this.validator = const ProjectDocumentValidator(),
    this.failureInjector = const NoDocumentTransactionFailureInjection(),
  });

  final ScopedDocumentChangeDetector changeDetector;
  final DocumentOperationPolicyRegistry policies;
  final ProjectDocumentValidator validator;
  final DocumentTransactionFailureInjector failureInjector;

  DocumentTransactionResult execute({
    required EditorDocumentState current,
    required EditorHistory history,
    required ProjectId expectedProjectId,
    required DocumentRevision expectedRevision,
    required DocumentOperationKind kind,
    required PureDocumentOperation operation,
    String? mergeProperty,
  }) {
    if (current.document.id != expectedProjectId) {
      return _failure(
        current,
        DocumentTransactionFailureCode.wrongProjectSession,
        'The operation belongs to a different project session.',
      );
    }
    if (current.revision != expectedRevision) {
      return _failure(
        current,
        DocumentTransactionFailureCode.staleDocumentRevision,
        'The expected document revision is stale.',
      );
    }
    final policy = policies.policyFor(kind);
    if (policy.sessionBoundary) {
      return _failure(
        current,
        DocumentTransactionFailureCode.sessionBoundaryOperation,
        'This operation belongs to the document session lifecycle.',
      );
    }

    late final DocumentOperationResult result;
    try {
      failureInjector.check(DocumentTransactionFailurePoint.operation);
      result = operation(current.document);
    } catch (error) {
      return _failure(
        current,
        DocumentTransactionFailureCode.documentOperationFailed,
        'The document operation threw before producing a candidate.',
        error,
      );
    }
    if (!result.isSuccess) {
      return _failure(
        current,
        DocumentTransactionFailureCode.documentOperationFailed,
        result.failure!.message,
        result.failure,
      );
    }
    if (result.document.id != current.document.id ||
        result.affectedScopes.any(
          (scope) => !policy.allowedScopes.contains(scope),
        )) {
      return _failure(
        current,
        DocumentTransactionFailureCode.invalidOperationPolicy,
        'The operation result violates its centralized transaction policy.',
      );
    }
    try {
      failureInjector.check(DocumentTransactionFailurePoint.validation);
    } catch (error) {
      return _failure(
        current,
        DocumentTransactionFailureCode.documentValidationFailed,
        'Candidate validation failed before history mutation.',
        error,
      );
    }
    if (!validator.validate(result.document).isValid) {
      return _failure(
        current,
        DocumentTransactionFailureCode.documentValidationFailed,
        'The operation candidate is invalid.',
      );
    }
    if (!changeDetector.hasChanges(
      current.document,
      result.document,
      result.affectedScopes,
    )) {
      return DocumentTransactionResult.noOp(current);
    }

    final entities = result.summary.entityIds.toList()..sort();
    final allowMerge = policy.canCoalesce && mergeProperty != null;
    final beginFailure = history.begin(
      current,
      HistoryTransactionDescriptor(
        operation: policy.code,
        entityIds: entities,
        mergeKey: allowMerge
            ? HistoryMergeKey(
                '${kind.name}:$mergeProperty:${entities.join(',')}',
              )
            : null,
        allowCoalescing: allowMerge,
      ),
    );
    if (beginFailure != null) return _historyFailure(current, beginFailure);
    final addFailure = history.addFrom(
      expectedBase: current.document,
      operation: result,
    );
    if (addFailure != null) {
      history.cancel();
      return _historyFailure(current, addFailure);
    }
    try {
      failureInjector.check(DocumentTransactionFailurePoint.retention);
    } catch (error) {
      history.cancel();
      return _failure(
        current,
        DocumentTransactionFailureCode.assetRetentionFailed,
        'Provisional asset retention failed.',
        error,
      );
    }
    try {
      failureInjector.check(DocumentTransactionFailurePoint.historyCommit);
    } catch (error) {
      history.cancel();
      return _failure(
        current,
        DocumentTransactionFailureCode.historyTransactionFailed,
        'History commit failed before publication.',
        error,
      );
    }
    final committed = history.commit(current);
    if (!committed.isSuccess) {
      return _historyFailure(current, committed.failure!);
    }
    return DocumentTransactionResult.success(committed.state);
  }

  DocumentTransactionResult undo({
    required EditorDocumentState current,
    required EditorHistory history,
  }) {
    try {
      failureInjector.check(DocumentTransactionFailurePoint.undoRestore);
    } catch (error) {
      return _failure(
        current,
        DocumentTransactionFailureCode.historyRestoreFailed,
        'Undo restoration failed before publication.',
        error,
      );
    }
    final restored = history.undo(current);
    return restored.isSuccess
        ? DocumentTransactionResult.success(restored.state)
        : _failure(
            current,
            DocumentTransactionFailureCode.historyRestoreFailed,
            restored.failure!.message,
            restored.failure,
          );
  }

  DocumentTransactionResult redo({
    required EditorDocumentState current,
    required EditorHistory history,
  }) {
    try {
      failureInjector.check(DocumentTransactionFailurePoint.redoRestore);
    } catch (error) {
      return _failure(
        current,
        DocumentTransactionFailureCode.historyRestoreFailed,
        'Redo restoration failed before publication.',
        error,
      );
    }
    final restored = history.redo(current);
    return restored.isSuccess
        ? DocumentTransactionResult.success(restored.state)
        : _failure(
            current,
            DocumentTransactionFailureCode.historyRestoreFailed,
            restored.failure!.message,
            restored.failure,
          );
  }

  DocumentTransactionResult _historyFailure(
    EditorDocumentState current,
    EditorHistoryFailure failure,
  ) => _failure(
    current,
    failure.code == EditorHistoryFailureCode.assetRetentionFailed
        ? DocumentTransactionFailureCode.assetRetentionFailed
        : failure.code == EditorHistoryFailureCode.validationFailed
        ? DocumentTransactionFailureCode.documentValidationFailed
        : DocumentTransactionFailureCode.historyTransactionFailed,
    failure.message,
    failure,
  );

  DocumentTransactionResult _failure(
    EditorDocumentState state,
    DocumentTransactionFailureCode code,
    String message, [
    Object? cause,
  ]) => DocumentTransactionResult.failure(
    state,
    DocumentTransactionFailure(code, message, cause),
  );
}
