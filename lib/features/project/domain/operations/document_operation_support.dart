import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';

ProjectStroke? strokeById(ProjectDocument document, StrokeId id) {
  for (final stroke in document.strokes) {
    if (stroke.id == id) return stroke;
  }
  return null;
}

ProjectSection? sectionById(ProjectDocument document, SectionId id) {
  for (final section in document.sections) {
    if (section.id == id) return section;
  }
  return null;
}

ProjectScene? sceneById(ProjectDocument document, SceneId id) {
  for (final scene in document.scenes) {
    if (scene.id == id) return scene;
  }
  return null;
}

DocumentOperationResult missing(
  ProjectDocument document,
  String type,
  Object id,
) => DocumentOperationResult.failure(
  document: document,
  code: DocumentOperationFailureCode.missingEntity,
  message: '$type $id does not exist.',
);

DocumentOperationResult invalid(ProjectDocument document, String message) =>
    DocumentOperationResult.failure(
      document: document,
      code: DocumentOperationFailureCode.invalidInput,
      message: message,
    );
