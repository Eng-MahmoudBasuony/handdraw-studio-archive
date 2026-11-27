import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';

/// Pure commit boundary for persistent document edits.
///
/// Coordinators may keep pointer/drag state elsewhere and call this exactly
/// once when a transaction succeeds. Failed validation leaves the caller's
/// current state untouched.
final class EditorDocumentCommitter {
  const EditorDocumentCommitter({
    this.validator = const ProjectDocumentValidator(),
  });

  final ProjectDocumentValidator validator;

  EditorDocumentState commit(
    EditorDocumentState current,
    ProjectDocument candidate,
  ) {
    validator.validate(candidate).throwIfInvalid();
    return current.replace(candidate);
  }
}
