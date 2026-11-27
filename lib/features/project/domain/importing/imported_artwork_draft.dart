import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';

/// Parser output that can become a ProjectDocument without touching the
/// legacy runtime model. It contains no decoded UI resources and no IDs.
final class ImportedArtworkDraft {
  ImportedArtworkDraft({
    required this.title,
    required this.canvas,
    required this.frameRate,
    required this.duration,
    required this.asset,
    required List<ImportedSectionDraft> sections,
  }) : sections = List.unmodifiable(sections);

  final String title;
  final ProjectCanvas canvas;
  final FrameRate frameRate;
  final TimelineDuration duration;
  final ImportedArtworkAssetDraft asset;
  final List<ImportedSectionDraft> sections;
}

final class ImportedArtworkAssetDraft {
  const ImportedArtworkAssetDraft({
    required this.originalFileName,
    required this.sourceType,
    required this.storagePolicy,
    required this.contentHash,
    required this.mediaType,
    this.externalLocator,
  });

  final String originalFileName;
  final ArtworkSourceType sourceType;
  final ProjectAssetStoragePolicy storagePolicy;
  final String contentHash;
  final String mediaType;
  final ExternalAssetLocator? externalLocator;
}

final class ImportedSectionDraft {
  ImportedSectionDraft({
    required this.sourceKey,
    required this.name,
    required List<ImportedStrokeDraft> strokes,
    this.timing = const DocumentSectionTiming(),
  }) : strokes = List.unmodifiable(strokes);

  final String sourceKey;
  final String name;
  final List<ImportedStrokeDraft> strokes;
  final DocumentSectionTiming timing;
}

final class ImportedStrokeDraft {
  ImportedStrokeDraft({
    required this.sourceKey,
    required this.name,
    required List<DocumentPoint> points,
    this.geometry,
    this.animationGeometry,
    this.isFilledShape = false,
    this.isTextShape = false,
    this.isGlobalDecoration = false,
    this.fillColorValue,
    this.textMetadata,
  }) : points = List.unmodifiable(points);

  final String sourceKey;
  final String name;
  final List<DocumentPoint> points;
  final StrokePathGeometry? geometry;
  final StrokePathGeometry? animationGeometry;
  final bool isFilledShape;
  final bool isTextShape;
  final bool isGlobalDecoration;
  final int? fillColorValue;
  final ImportedTextMetadata? textMetadata;
}
