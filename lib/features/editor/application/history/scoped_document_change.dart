import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/semantic/domain/models/project_content_metadata.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';

enum DocumentFragmentKind {
  strokes,
  sections,
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

/// A bounded before/after aggregate. Values are immutable domain objects and
/// never contain decoded images, file handles, or asset bytes.
final class ScopedDocumentChange {
  const ScopedDocumentChange({
    required this.kind,
    required this.scopes,
    required this.before,
    required this.after,
    required this.estimatedBytes,
  });

  final DocumentFragmentKind kind;
  final Set<DocumentScope> scopes;
  final DocumentFragment before;
  final DocumentFragment after;
  final int estimatedBytes;

  ProjectDocument applyBefore(ProjectDocument document) =>
      before.apply(document);

  ProjectDocument applyAfter(ProjectDocument document) => after.apply(document);

  Set<ProjectAssetId> get retainedAssetIds => {
    ...before.referencedAssetIds,
    ...after.referencedAssetIds,
  };

  ScopedDocumentChange coalesceWith(ScopedDocumentChange newer) {
    if (kind != newer.kind || !_sameScopes(scopes, newer.scopes)) {
      throw ArgumentError('Only matching scoped changes can be coalesced.');
    }
    return ScopedDocumentChange(
      kind: kind,
      scopes: scopes,
      before: before,
      after: newer.after,
      estimatedBytes: before.estimatedBytes + newer.after.estimatedBytes,
    );
  }
}

final class CameraFragment extends DocumentFragment {
  const CameraFragment(this.track, this.timelineTrack);
  final ProjectCameraTrack? track;
  final PersistentCameraTimelineTrack timelineTrack;
  @override
  ProjectDocument apply(ProjectDocument document) => document.copyWith(
    cameraTrack: track,
    timeline: document.timeline.copyWith(camera: timelineTrack),
  );
  @override
  int get estimatedBytes =>
      64 +
      (track?.shots.fold<int>(
            0,
            (sum, shot) => sum + 160 + shot.keyframes.length * 96,
          ) ??
          0);
}

final class SemanticFragment extends DocumentFragment {
  const SemanticFragment(this.metadata);

  final ProjectContentMetadata metadata;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(contentMetadata: metadata);

  @override
  int get estimatedBytes => metadata.entities.fold<int>(
    64 + (metadata.projectLocaleHint?.length ?? 0) * 2,
    (total, entity) =>
        total +
        160 +
        entity.target.value.length * 2 +
        (entity.textMetadata?.originalText?.length ?? 0) * 2 +
        (entity.textMetadata?.languageHint?.length ?? 0) * 2,
  );
}

sealed class DocumentFragment {
  const DocumentFragment();

  ProjectDocument apply(ProjectDocument document);

  int get estimatedBytes;

  Set<ProjectAssetId> get referencedAssetIds => const {};
}

final class StrokeCollectionFragment extends DocumentFragment {
  StrokeCollectionFragment(List<ProjectStroke> strokes)
    : strokes = List.unmodifiable(strokes);

  final List<ProjectStroke> strokes;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(strokes: strokes);

  @override
  int get estimatedBytes => strokes.fold(64, (sum, stroke) {
    final geometryPoints = (stroke.geometry?.segments.length ?? 0) * 48;
    final animationPoints =
        (stroke.animationGeometry?.segments.length ?? 0) * 48;
    return sum +
        192 +
        stroke.name.length * 2 +
        stroke.points.length * 16 +
        geometryPoints +
        animationPoints +
        stroke.pausePoints.length * 64 +
        stroke.vectorMaskStrokes.length * 160;
  });

  @override
  Set<ProjectAssetId> get referencedAssetIds => {
    for (final stroke in strokes) ?stroke.assetId,
  };
}

final class SectionCollectionFragment extends DocumentFragment {
  SectionCollectionFragment(List<ProjectSection> sections)
    : sections = List.unmodifiable(sections);

  final List<ProjectSection> sections;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(sections: sections);

  @override
  int get estimatedBytes => sections.fold(
    64,
    (sum, section) =>
        sum + 192 + section.name.length * 2 + section.strokeIds.length * 32,
  );

  @override
  Set<ProjectAssetId> get referencedAssetIds => {
    for (final section in sections) ?section.assetId,
  };
}

final class OrderingFragment extends DocumentFragment {
  OrderingFragment(List<SectionId> sectionOrder)
    : sectionOrder = List.unmodifiable(sectionOrder);

  final List<SectionId> sectionOrder;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(sectionOrder: sectionOrder);

  @override
  int get estimatedBytes => 64 + sectionOrder.length * 32;
}

final class SceneCollectionFragment extends DocumentFragment {
  SceneCollectionFragment(List<ProjectScene> scenes)
    : scenes = List.unmodifiable(scenes);

  final List<ProjectScene> scenes;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(scenes: scenes);

  @override
  int get estimatedBytes => scenes.fold(
    64,
    (sum, scene) =>
        sum + 128 + scene.name.length * 2 + scene.sectionIds.length * 32,
  );
}

final class AssetCollectionFragment extends DocumentFragment {
  AssetCollectionFragment({
    required List<ProjectAsset> assets,
    this.artworkId,
    this.artworkPlacement,
  }) : assets = List.unmodifiable(assets);

  final List<ProjectAsset> assets;
  final ProjectAssetId? artworkId;
  final ProjectArtworkPlacement? artworkPlacement;

  @override
  ProjectDocument apply(ProjectDocument document) => document.copyWith(
    assets: assets,
    artworkAssetId: artworkId,
    artworkPlacement: artworkPlacement,
  );

  @override
  int get estimatedBytes => assets.fold(
    64,
    (sum, asset) =>
        sum +
        192 +
        asset.originalFileName.length * 2 +
        asset.contentHash.length * 2 +
        (asset.mediaType?.length ?? 0) * 2 +
        (asset.externalLocator?.pathHint.length ?? 0) * 2,
  );

  @override
  Set<ProjectAssetId> get referencedAssetIds => {
    ...assets.map((asset) => asset.id),
    ?artworkId,
  };
}

final class AudioFragment extends DocumentFragment {
  AudioFragment({
    required List<ProjectAudioTrack> tracks,
    required this.voiceGuide,
    required this.duration,
    required this.timeline,
  }) : tracks = List.unmodifiable(tracks);

  final List<ProjectAudioTrack> tracks;
  final ProjectVoiceGuide? voiceGuide;
  final TimelineDuration duration;
  final PersistentTimeline timeline;

  @override
  ProjectDocument apply(ProjectDocument document) => document.copyWith(
    audioTracks: tracks,
    voiceGuide: voiceGuide,
    duration: duration,
    timeline: timeline,
  );

  @override
  int get estimatedBytes => 96 + tracks.length * 128;

  @override
  Set<ProjectAssetId> get referencedAssetIds => {
    ...tracks.map((track) => track.assetId),
  };
}

final class CanvasFragment extends DocumentFragment {
  const CanvasFragment({
    required this.canvas,
    required this.frameRate,
    required this.duration,
  });

  final ProjectCanvas canvas;
  final FrameRate frameRate;
  final TimelineDuration duration;

  @override
  ProjectDocument apply(ProjectDocument document) => document.copyWith(
    canvas: canvas,
    frameRate: frameRate,
    duration: duration,
  );

  @override
  int get estimatedBytes => 96;
}

final class HandFragment extends DocumentFragment {
  const HandFragment(this.configuration);

  final ProjectHandConfiguration configuration;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(handConfiguration: configuration);

  @override
  int get estimatedBytes => 160;

  @override
  Set<ProjectAssetId> get referencedAssetIds => {?configuration.assetId};
}

final class ExportFragment extends DocumentFragment {
  const ExportFragment(this.configuration);

  final ProjectExportConfiguration configuration;

  @override
  ProjectDocument apply(ProjectDocument document) =>
      document.copyWith(exportConfiguration: configuration);

  @override
  int get estimatedBytes => 96;
}

final class SettingsFragment extends DocumentFragment {
  const SettingsFragment({
    required this.projectId,
    required this.title,
    required this.motion,
    required this.writingSound,
    required this.autoDirectorSettings,
    required this.pathProcessingMetadata,
  });

  final ProjectId projectId;
  final String title;
  final ProjectMotionConfiguration motion;
  final ProjectWritingSoundConfiguration writingSound;
  final ProjectAutoDirectorSettings autoDirectorSettings;
  final ProjectPathProcessingMetadata? pathProcessingMetadata;

  @override
  ProjectDocument apply(ProjectDocument document) => document.copyWith(
    id: projectId,
    title: title,
    motionConfiguration: motion,
    writingSoundConfiguration: writingSound,
    autoDirectorSettings: autoDirectorSettings,
    pathProcessingMetadata: pathProcessingMetadata,
  );

  @override
  int get estimatedBytes => 192 + title.length * 2;
}

List<ScopedDocumentChange> captureScopedChanges({
  required ProjectDocument before,
  required ProjectDocument after,
  required Set<DocumentScope> scopes,
}) {
  final grouped = <DocumentFragmentKind, Set<DocumentScope>>{};
  for (final scope in scopes) {
    final kind = switch (scope) {
      DocumentScope.strokes ||
      DocumentScope.paths ||
      DocumentScope.masks => DocumentFragmentKind.strokes,
      DocumentScope.sections ||
      DocumentScope.timing => DocumentFragmentKind.sections,
      DocumentScope.ordering => DocumentFragmentKind.ordering,
      DocumentScope.scenes => DocumentFragmentKind.scenes,
      DocumentScope.assets => DocumentFragmentKind.assets,
      DocumentScope.audio => DocumentFragmentKind.audio,
      DocumentScope.canvas => DocumentFragmentKind.canvas,
      DocumentScope.hand => DocumentFragmentKind.hand,
      DocumentScope.export => DocumentFragmentKind.export,
      DocumentScope.settings => DocumentFragmentKind.settings,
      DocumentScope.camera => DocumentFragmentKind.camera,
      DocumentScope.semantic => DocumentFragmentKind.semantic,
    };
    grouped.putIfAbsent(kind, () => <DocumentScope>{}).add(scope);
  }

  return [
    for (final entry in grouped.entries)
      _capture(entry.key, Set.unmodifiable(entry.value), before, after),
  ];
}

ScopedDocumentChange _capture(
  DocumentFragmentKind kind,
  Set<DocumentScope> scopes,
  ProjectDocument before,
  ProjectDocument after,
) {
  final beforeFragment = _fragment(kind, before);
  final afterFragment = _fragment(kind, after);
  return ScopedDocumentChange(
    kind: kind,
    scopes: scopes,
    before: beforeFragment,
    after: afterFragment,
    estimatedBytes:
        beforeFragment.estimatedBytes + afterFragment.estimatedBytes,
  );
}

DocumentFragment _fragment(
  DocumentFragmentKind kind,
  ProjectDocument document,
) {
  return switch (kind) {
    DocumentFragmentKind.strokes => StrokeCollectionFragment(document.strokes),
    DocumentFragmentKind.sections => SectionCollectionFragment(
      document.sections,
    ),
    DocumentFragmentKind.ordering => OrderingFragment(document.sectionOrder),
    DocumentFragmentKind.scenes => SceneCollectionFragment(document.scenes),
    DocumentFragmentKind.assets => AssetCollectionFragment(
      assets: document.assets,
      artworkId: document.artworkAssetId,
      artworkPlacement: document.artworkPlacement,
    ),
    DocumentFragmentKind.audio => AudioFragment(
      tracks: document.audioTracks,
      voiceGuide: document.voiceGuide,
      duration: document.duration,
      timeline: document.timeline,
    ),
    DocumentFragmentKind.canvas => CanvasFragment(
      canvas: document.canvas,
      frameRate: document.frameRate,
      duration: document.duration,
    ),
    DocumentFragmentKind.hand => HandFragment(document.handConfiguration),
    DocumentFragmentKind.export => ExportFragment(document.exportConfiguration),
    DocumentFragmentKind.settings => SettingsFragment(
      projectId: document.id,
      title: document.title,
      motion: document.motionConfiguration,
      writingSound: document.writingSoundConfiguration,
      autoDirectorSettings: document.autoDirectorSettings,
      pathProcessingMetadata: document.pathProcessingMetadata,
    ),
    DocumentFragmentKind.camera => CameraFragment(
      document.cameraTrack,
      document.timeline.camera,
    ),
    DocumentFragmentKind.semantic => SemanticFragment(document.contentMetadata),
  };
}

bool _sameScopes(Set<DocumentScope> left, Set<DocumentScope> right) =>
    left.length == right.length && left.containsAll(right);
