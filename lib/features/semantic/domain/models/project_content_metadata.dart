import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

enum SemanticTargetKind { stroke, section, scene, asset }

enum SemanticContentRole {
  title,
  heading,
  body,
  label,
  illustration,
  decoration,
}

enum SemanticImportance { minimal, low, normal, high, critical }

enum KnownTextDirection { ltr, rtl, mixed, neutral, unknown }

enum DirectionProvenance {
  explicit,
  sourceMetadata,
  inferredFromKnownText,
  projectFallback,
  unknown,
}

enum TextSourceKind {
  nativeText,
  svgText,
  importerSupplied,
  userDeclared,
  geometryOnly,
  rasterUnknown,
}

enum SemanticMetadataProvenance { imported, userAuthored }

final class SemanticTargetReference {
  const SemanticTargetReference._(this.kind, this.value);
  factory SemanticTargetReference.stroke(StrokeId id) =>
      SemanticTargetReference._(SemanticTargetKind.stroke, id.value);
  factory SemanticTargetReference.section(SectionId id) =>
      SemanticTargetReference._(SemanticTargetKind.section, id.value);
  factory SemanticTargetReference.scene(SceneId id) =>
      SemanticTargetReference._(SemanticTargetKind.scene, id.value);
  factory SemanticTargetReference.asset(ProjectAssetId id) =>
      SemanticTargetReference._(SemanticTargetKind.asset, id.value);
  factory SemanticTargetReference.decoded(
    SemanticTargetKind kind,
    String value,
  ) {
    if (value.trim().isEmpty) {
      throw const FormatException('Empty semantic target');
    }
    return SemanticTargetReference._(kind, value.trim());
  }
  final SemanticTargetKind kind;
  final String value;
  String get stableKey => '${kind.name}:$value';
  @override
  bool operator ==(Object other) =>
      other is SemanticTargetReference &&
      kind == other.kind &&
      value == other.value;
  @override
  int get hashCode => Object.hash(kind, value);
}

final class PreferredSemanticZoom {
  const PreferredSemanticZoom._(this.value);
  factory PreferredSemanticZoom(double value) {
    if (!value.isFinite || value < .02 || value > 20) {
      throw ArgumentError.value(
        value,
        'value',
        'Preferred zoom must be in [0.02, 20].',
      );
    }
    return PreferredSemanticZoom._(value);
  }
  final double value;
}

final class ImportedTextMetadata {
  const ImportedTextMetadata({
    this.originalText,
    this.direction = KnownTextDirection.unknown,
    this.directionProvenance = DirectionProvenance.unknown,
    this.languageHint,
    this.fontSize,
    this.lineCount,
    required this.sourceKind,
    required this.sourceProvenance,
  });
  final String? originalText;
  final KnownTextDirection direction;
  final DirectionProvenance directionProvenance;
  final String? languageHint;
  final double? fontSize;
  final int? lineCount;
  final TextSourceKind sourceKind;
  final String sourceProvenance;
}

final class EntitySemanticMetadata {
  const EntitySemanticMetadata({
    required this.target,
    this.contentRole,
    this.textMetadata,
    this.importance = SemanticImportance.normal,
    this.keepTogether = false,
    this.cameraExcluded = false,
    this.textSensitive = false,
    this.minimumPreferredZoom,
    this.provenance = SemanticMetadataProvenance.userAuthored,
  });
  final SemanticTargetReference target;
  final SemanticContentRole? contentRole;
  final ImportedTextMetadata? textMetadata;
  final SemanticImportance importance;
  final bool keepTogether;
  final bool cameraExcluded;
  final bool textSensitive;
  final PreferredSemanticZoom? minimumPreferredZoom;
  final SemanticMetadataProvenance provenance;

  EntitySemanticMetadata copyWith({
    Object? contentRole = _unset,
    Object? textMetadata = _unset,
    SemanticImportance? importance,
    bool? keepTogether,
    bool? cameraExcluded,
    bool? textSensitive,
    Object? minimumPreferredZoom = _unset,
    SemanticMetadataProvenance? provenance,
  }) => EntitySemanticMetadata(
    target: target,
    contentRole: identical(contentRole, _unset)
        ? this.contentRole
        : contentRole as SemanticContentRole?,
    textMetadata: identical(textMetadata, _unset)
        ? this.textMetadata
        : textMetadata as ImportedTextMetadata?,
    importance: importance ?? this.importance,
    keepTogether: keepTogether ?? this.keepTogether,
    cameraExcluded: cameraExcluded ?? this.cameraExcluded,
    textSensitive: textSensitive ?? this.textSensitive,
    minimumPreferredZoom: identical(minimumPreferredZoom, _unset)
        ? this.minimumPreferredZoom
        : minimumPreferredZoom as PreferredSemanticZoom?,
    provenance: provenance ?? this.provenance,
  );
}

final class ProjectContentMetadata {
  ProjectContentMetadata({
    List<EntitySemanticMetadata> entities = const [],
    this.projectLocaleHint,
  }) : entities = List.unmodifiable(entities);
  const ProjectContentMetadata.empty()
    : entities = const [],
      projectLocaleHint = null;
  final List<EntitySemanticMetadata> entities;
  final String? projectLocaleHint;
  EntitySemanticMetadata? forTarget(SemanticTargetReference target) {
    for (final value in entities) {
      if (value.target == target) return value;
    }
    return null;
  }

  ProjectContentMetadata copyWith({
    List<EntitySemanticMetadata>? entities,
    Object? projectLocaleHint = _unset,
  }) => ProjectContentMetadata(
    entities: entities ?? this.entities,
    projectLocaleHint: identical(projectLocaleHint, _unset)
        ? this.projectLocaleHint
        : projectLocaleHint as String?,
  );
}

const _unset = Object();
