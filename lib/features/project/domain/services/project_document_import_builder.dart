import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/importing/imported_artwork_draft.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';

/// Creates the persistent aggregate directly from an SVG/raster import DTO.
final class ProjectDocumentImportBuilder {
  const ProjectDocumentImportBuilder({
    this.validator = const ProjectDocumentValidator(),
  });

  final ProjectDocumentValidator validator;

  ProjectDocument build(
    ImportedArtworkDraft draft, {
    required IdGenerator ids,
  }) {
    _validateSourceKeys(draft);
    final allocation = IdAllocationContext(generator: ids);
    final assetId = allocation.projectAssetId();
    final sections = <ProjectSection>[];
    final strokes = <ProjectStroke>[];
    final semanticEntities = <EntitySemanticMetadata>[];
    for (final sectionDraft in draft.sections) {
      final sectionId = allocation.sectionId();
      final sectionStrokeIds = <StrokeId>[];
      for (final strokeDraft in sectionDraft.strokes) {
        final strokeId = allocation.strokeId();
        sectionStrokeIds.add(strokeId);
        if (strokeDraft.textMetadata case final textMetadata?) {
          semanticEntities.add(
            EntitySemanticMetadata(
              target: SemanticTargetReference.stroke(strokeId),
              textMetadata: textMetadata,
              textSensitive: true,
              provenance: SemanticMetadataProvenance.imported,
            ),
          );
        }
        strokes.add(
          ProjectStroke(
            id: strokeId,
            sectionId: sectionId,
            name: strokeDraft.name,
            points: strokeDraft.points,
            assetId: assetId,
            geometry: strokeDraft.geometry,
            animationGeometry: strokeDraft.animationGeometry,
            isFilledShape: strokeDraft.isFilledShape,
            isTextShape: strokeDraft.isTextShape,
            isGlobalDecoration: strokeDraft.isGlobalDecoration,
            fillColorValue: strokeDraft.fillColorValue,
          ),
        );
      }
      sections.add(
        ProjectSection(
          id: sectionId,
          name: sectionDraft.name,
          strokeIds: sectionStrokeIds,
          assetId: assetId,
          timing: sectionDraft.timing,
        ),
      );
    }
    final assetDraft = draft.asset;
    final document = ProjectDocument(
      id: allocation.projectId(),
      title: draft.title,
      canvas: draft.canvas,
      frameRate: draft.frameRate,
      duration: draft.duration,
      artworkAssetId: assetId,
      assets: [
        ProjectAsset(
          id: assetId,
          kind: ProjectAssetKind.artwork,
          originalFileName: assetDraft.originalFileName,
          storagePolicy: assetDraft.storagePolicy,
          contentHash: assetDraft.contentHash,
          mediaType: assetDraft.mediaType,
          artworkSourceType: assetDraft.sourceType,
          externalLocator: assetDraft.externalLocator,
        ),
      ],
      strokes: strokes,
      sections: sections,
      sectionOrder: [for (final section in sections) section.id],
      scenes: const [],
      audioTracks: const [],
      contentMetadata: ProjectContentMetadata(entities: semanticEntities),
    );
    validator.validate(document).throwIfInvalid();
    return document;
  }

  void _validateSourceKeys(ImportedArtworkDraft draft) {
    final sectionKeys = <String>{};
    final strokeKeys = <String>{};
    for (final section in draft.sections) {
      if (section.sourceKey.trim().isEmpty ||
          !sectionKeys.add(section.sourceKey)) {
        throw ArgumentError.value(
          section.sourceKey,
          'sourceKey',
          'Imported section keys must be present and unique.',
        );
      }
      for (final stroke in section.strokes) {
        if (stroke.sourceKey.trim().isEmpty ||
            !strokeKeys.add(stroke.sourceKey)) {
          throw ArgumentError.value(
            stroke.sourceKey,
            'sourceKey',
            'Imported stroke keys must be present and unique.',
          );
        }
      }
    }
  }
}
