import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

enum DocumentScope {
  strokes,
  sections,
  paths,
  masks,
  timing,
  ordering,
  scenes,
  assets,
  audio,
  canvas,
  hand,
  export,
  settings,
  camera,
  semantic,
}

enum DocumentOperationFailureCode {
  missingEntity,
  duplicateEntity,
  invalidInput,
  inconsistentMembership,
  referencedEntity,
  unsupportedOperation,
  lockedEntity,
  overlap,
}

final class DocumentOperationFailure {
  const DocumentOperationFailure(this.code, this.message);

  final DocumentOperationFailureCode code;
  final String message;
}

final class DocumentChangeSummary {
  DocumentChangeSummary({
    required this.action,
    Iterable<String> entityIds = const [],
    this.changeCount = 1,
  }) : entityIds = Set.unmodifiable(entityIds);

  final String action;
  final Set<String> entityIds;
  final int changeCount;
}

/// Pure operation result. A failed operation returns the original document.
/// Revision advancement belongs exclusively to the editor commit boundary.
final class DocumentOperationResult {
  DocumentOperationResult.success({
    required this.document,
    required Iterable<DocumentScope> affectedScopes,
    required this.summary,
  }) : affectedScopes = Set.unmodifiable(affectedScopes),
       failure = null;

  DocumentOperationResult.failure({
    required this.document,
    required DocumentOperationFailureCode code,
    required String message,
  }) : affectedScopes = const {},
       summary = DocumentChangeSummary(action: 'rejected', changeCount: 0),
       failure = DocumentOperationFailure(code, message);

  final ProjectDocument document;
  final Set<DocumentScope> affectedScopes;
  final DocumentChangeSummary summary;
  final DocumentOperationFailure? failure;

  bool get isSuccess => failure == null;
}
