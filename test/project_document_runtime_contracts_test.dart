import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/editor_runtime_asset_resources.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/importing/imported_artwork_draft.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_import_builder.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';
import 'support/project_document_parity_fixture.dart';

void main() {
  test('SVG import draft builds ProjectDocument directly with stable IDs', () {
    final document = const ProjectDocumentImportBuilder().build(
      ImportedArtworkDraft(
        title: 'Imported SVG',
        canvas: const ProjectCanvas(width: 1280, height: 720),
        frameRate: FrameRate.fps30,
        duration: TimelineDuration.fromMicroseconds(3000000),
        asset: const ImportedArtworkAssetDraft(
          originalFileName: 'diagram.svg',
          sourceType: ArtworkSourceType.svg,
          storagePolicy: ProjectAssetStoragePolicy.embedded,
          contentHash: 'sha256:diagram',
          mediaType: 'image/svg+xml',
        ),
        sections: [
          ImportedSectionDraft(
            sourceKey: 'svg:g1',
            name: 'Group 1',
            strokes: [
              ImportedStrokeDraft(
                sourceKey: 'svg:path1',
                name: 'Path 1',
                points: const [DocumentPoint(0, 0), DocumentPoint(1, 1)],
              ),
            ],
          ),
        ],
      ),
      ids: SequentialIdGenerator(),
    );

    expect(document.assets.single.artworkSourceType, ArtworkSourceType.svg);
    expect(document.strokes.single.sectionId, document.sections.single.id);
    expect(document.sectionOrder, [document.sections.single.id]);
  });

  test('one-way legacy view preserves current behavior metadata', () {
    final document = projectDocumentParityFixture();
    final view = LegacyProjectViewCache().resolve(
      EditorDocumentState(document: document),
    );

    expect(view.drawingImagePath, isNull);
    expect(view.handImagePath, isNull);
    expect(view.strokes.single.sceneGroupId, 'scene-title');
    expect(view.strokes.single.reversed, isTrue);
    expect(view.sceneGroups.single.locked, isFalse);
    expect(view.sectionTimings['section:section-title']?.voiceCueSeconds, 0.75);
    expect(view.voiceGuide?.path, isEmpty);
    expect(view.voiceGuide?.waveform, isEmpty);
  });

  test('runtime asset resources stay outside the persistent document', () {
    final resources = _MemoryRuntimeResources();
    final assetId = ProjectAssetId('asset-runtime');
    resources.bind(
      ResolvedEditorAssetResource(
        assetId: assetId,
        localReadablePath: '/resolved/art.svg',
      ),
    );
    expect(resources.lookup(assetId)?.localReadablePath, '/resolved/art.svg');
    resources.evict(assetId);
    expect(resources.lookup(assetId), isNull);
  });

  test('runtime import builder has no legacy reverse dependency', () {
    final source = File(
      'lib/features/project/domain/services/project_document_import_builder.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('HandDrawProject')));
    expect(source, isNot(contains('drawing_project.dart')));
  });
}

final class _MemoryRuntimeResources implements EditorRuntimeAssetResources {
  final Map<ProjectAssetId, ResolvedEditorAssetResource> _resources = {};

  @override
  void bind(ResolvedEditorAssetResource resource) {
    _resources[resource.assetId] = resource;
  }

  @override
  void clear() => _resources.clear();

  @override
  void evict(ProjectAssetId assetId) => _resources.remove(assetId);

  @override
  ResolvedEditorAssetResource? lookup(ProjectAssetId assetId) =>
      _resources[assetId];
}
