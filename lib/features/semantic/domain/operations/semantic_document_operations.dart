import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';

/// Pure, history-ready mutations of user-owned semantic metadata.
final class SemanticDocumentOperations {
  const SemanticDocumentOperations();

  DocumentOperationResult setRole({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required SemanticContentRole? value,
  }) => _update(
    document,
    target,
    (current) => current.copyWith(contentRole: value),
    'set-semantic-role',
  );

  DocumentOperationResult setTextSensitive({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required bool value,
  }) => _update(
    document,
    target,
    (current) => current.copyWith(textSensitive: value),
    'set-text-sensitive',
  );

  DocumentOperationResult setMinimumPreferredZoom({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required PreferredSemanticZoom? value,
  }) => _update(
    document,
    target,
    (current) => current.copyWith(minimumPreferredZoom: value),
    'set-minimum-preferred-zoom',
  );

  DocumentOperationResult setImportance({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required SemanticImportance value,
  }) => _update(
    document,
    target,
    (current) => current.copyWith(importance: value),
    'set-semantic-importance',
  );

  DocumentOperationResult setKeepTogether({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required bool value,
  }) => _update(
    document,
    target,
    (current) => current.copyWith(keepTogether: value),
    'set-keep-together',
  );

  DocumentOperationResult setCameraExcluded({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required bool value,
  }) => _update(
    document,
    target,
    (current) => current.copyWith(cameraExcluded: value),
    'set-camera-excluded',
  );

  DocumentOperationResult setDirectionAndLanguage({
    required ProjectDocument document,
    required SemanticTargetReference target,
    required KnownTextDirection direction,
    String? languageHint,
  }) => _update(document, target, (current) {
    final previous = current.textMetadata;
    return current.copyWith(
      textMetadata: ImportedTextMetadata(
        originalText: previous?.originalText,
        direction: direction,
        directionProvenance: DirectionProvenance.explicit,
        languageHint: _nullableTrim(languageHint),
        fontSize: previous?.fontSize,
        lineCount: previous?.lineCount,
        sourceKind: previous?.sourceKind ?? TextSourceKind.userDeclared,
        sourceProvenance: previous?.sourceProvenance ?? 'user-declared',
      ),
    );
  }, 'set-text-direction-language');

  DocumentOperationResult clearDirectionAndLanguage({
    required ProjectDocument document,
    required SemanticTargetReference target,
  }) => _update(document, target, (current) {
    final previous = current.textMetadata;
    if (previous == null) return current;
    final preserveImportedText =
        previous.originalText != null ||
        previous.fontSize != null ||
        previous.lineCount != null ||
        previous.sourceKind != TextSourceKind.userDeclared;
    return current.copyWith(
      textMetadata: preserveImportedText
          ? ImportedTextMetadata(
              originalText: previous.originalText,
              fontSize: previous.fontSize,
              lineCount: previous.lineCount,
              sourceKind: previous.sourceKind,
              sourceProvenance: previous.sourceProvenance,
            )
          : null,
    );
  }, 'clear-text-direction-language');

  DocumentOperationResult _update(
    ProjectDocument document,
    SemanticTargetReference target,
    EntitySemanticMetadata Function(EntitySemanticMetadata) transform,
    String action,
  ) {
    if (!_targetExists(document, target)) {
      return DocumentOperationResult.failure(
        document: document,
        code: DocumentOperationFailureCode.missingEntity,
        message: 'Semantic target ${target.stableKey} does not exist.',
      );
    }
    final entities = [...document.contentMetadata.entities];
    final index = entities.indexWhere((value) => value.target == target);
    final current = index < 0
        ? EntitySemanticMetadata(target: target)
        : entities[index];
    final updated = transform(current);
    if (index < 0) {
      entities.add(updated);
    } else {
      entities[index] = updated;
    }
    entities.sort((a, b) => a.target.stableKey.compareTo(b.target.stableKey));
    return DocumentOperationResult.success(
      document: document.copyWith(
        contentMetadata: document.contentMetadata.copyWith(entities: entities),
      ),
      affectedScopes: const {DocumentScope.semantic},
      summary: DocumentChangeSummary(
        action: action,
        entityIds: {target.stableKey},
      ),
    );
  }

  bool _targetExists(
    ProjectDocument document,
    SemanticTargetReference target,
  ) => switch (target.kind) {
    SemanticTargetKind.stroke => document.strokes.any(
      (value) => value.id.value == target.value,
    ),
    SemanticTargetKind.section => document.sections.any(
      (value) => value.id.value == target.value,
    ),
    SemanticTargetKind.scene => document.scenes.any(
      (value) => value.id.value == target.value,
    ),
    SemanticTargetKind.asset => document.assets.any(
      (value) => value.id.value == target.value,
    ),
  };
}

String? _nullableTrim(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
