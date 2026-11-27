import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_support.dart';

final class MaskDocumentOperations {
  const MaskDocumentOperations();

  DocumentOperationResult add({
    required ProjectDocument document,
    required StrokeId strokeId,
    required DocumentVectorMaskStroke mask,
  }) {
    if (!mask.width.isFinite ||
        mask.width <= 0 ||
        !mask.feather.isFinite ||
        mask.feather < 0) {
      return invalid(document, 'Mask width and feather must be valid.');
    }
    return _replace(
      document,
      strokeId,
      'add-mask-stroke',
      (strokes) => [...strokes, mask],
    );
  }

  DocumentOperationResult remove({
    required ProjectDocument document,
    required StrokeId strokeId,
    required int maskIndex,
  }) => _replace(document, strokeId, 'remove-mask-stroke', (strokes) {
    if (maskIndex < 0 || maskIndex >= strokes.length) return null;
    return List<DocumentVectorMaskStroke>.of(strokes)..removeAt(maskIndex);
  });

  DocumentOperationResult reset({
    required ProjectDocument document,
    required StrokeId strokeId,
  }) => _replace(document, strokeId, 'reset-mask', (_) => const []);

  DocumentOperationResult applyBatch({
    required ProjectDocument document,
    required Map<StrokeId, List<DocumentVectorMaskStroke>> changes,
  }) {
    if (changes.keys.any((id) => strokeById(document, id) == null) ||
        changes.values
            .expand((masks) => masks)
            .any(
              (mask) =>
                  !mask.width.isFinite ||
                  mask.width <= 0 ||
                  !mask.feather.isFinite ||
                  mask.feather < 0,
            )) {
      return invalid(document, 'Every batch mask target must exist.');
    }
    return DocumentOperationResult.success(
      document: document.copyWith(
        strokes: [
          for (final stroke in document.strokes)
            changes.containsKey(stroke.id)
                ? stroke.copyWith(vectorMaskStrokes: changes[stroke.id]!)
                : stroke,
        ],
      ),
      affectedScopes: const {DocumentScope.masks, DocumentScope.strokes},
      summary: DocumentChangeSummary(
        action: 'apply-mask-batch',
        entityIds: changes.keys.map((id) => id.value),
        changeCount: changes.length,
      ),
    );
  }

  DocumentOperationResult _replace(
    ProjectDocument document,
    StrokeId id,
    String action,
    List<DocumentVectorMaskStroke>? Function(List<DocumentVectorMaskStroke>)
    transform,
  ) {
    final stroke = strokeById(document, id);
    if (stroke == null) return missing(document, 'Stroke', id);
    final masks = transform(stroke.vectorMaskStrokes);
    if (masks == null) return invalid(document, 'The mask index is invalid.');
    return DocumentOperationResult.success(
      document: document.copyWith(
        strokes: [
          for (final item in document.strokes)
            item.id == id ? item.copyWith(vectorMaskStrokes: masks) : item,
        ],
      ),
      affectedScopes: const {DocumentScope.masks, DocumentScope.strokes},
      summary: DocumentChangeSummary(action: action, entityIds: [id.value]),
    );
  }
}
