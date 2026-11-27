import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_committer.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/document_revision.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_factory.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';

void main() {
  test(
    'document replacement increments revision without runtime view state',
    () {
      final initial = EditorDocumentState(document: _document('project-a'));
      final next = initial.replace(_document('project-b'));
      expect(initial.revision, DocumentRevision.initial);
      expect(next.revision, DocumentRevision(1));
      expect(next.document.id, ProjectId('project-b'));
    },
  );

  test('legacy bridge is cached and strictly one-way', () {
    final state = EditorDocumentState(document: _document('project-a'));
    final cache = LegacyProjectViewCache();
    final first = cache.resolve(state);
    final second = cache.resolve(state);

    expect(identical(first, second), isTrue);
    expect(first.timelineSectionOrder, ['section-a']);
    expect(first.strokes.single.id, 'stroke-a');
    expect(first.drawingImagePath, isNull);

    final replaced = state.replace(_document('project-b'));
    expect(identical(cache.resolve(replaced), first), isFalse);
  });

  test('1000 render frames build one legacy view for one revision', () {
    final state = EditorDocumentState(document: _document('project-a'));
    final cache = LegacyProjectViewCache();
    for (var frame = 0; frame < 1000; frame++) {
      cache.resolve(state);
    }
    expect(cache.buildCount, 1);
  });

  test('pure committer validates and increments one runtime revision', () {
    final initial = EditorDocumentState(document: _document('project-a'));
    final committed = const EditorDocumentCommitter().commit(
      initial,
      _document('project-b'),
    );

    expect(committed.document.id, ProjectId('project-b'));
    expect(committed.revision, DocumentRevision(1));
  });

  test('failed commit leaves runtime revision unchanged', () {
    final initial = EditorDocumentState(document: _document('project-a'));
    final invalid = initial.document.copyWith(
      canvas: const ProjectCanvas(width: 0, height: 720),
    );

    expect(
      () => const EditorDocumentCommitter().commit(initial, invalid),
      throwsA(isA<Exception>()),
    );
    expect(initial.revision, DocumentRevision.initial);
    expect(initial.document.canvas.width, 1280);
  });

  test('empty documents originate from the typed creation boundary', () {
    final document = const ProjectDocumentFactory().createEmpty(
      ids: FakeIdGenerator(),
    );
    expect(document.id.value, startsWith('project_'));
    expect(document.sections, isEmpty);
  });
}

ProjectDocument _document(String projectId) {
  final assetId = ProjectAssetId('asset-a');
  final sectionId = SectionId('section-a');
  final strokeId = StrokeId('stroke-a');
  return ProjectDocument(
    id: ProjectId(projectId),
    title: 'Editor document',
    canvas: const ProjectCanvas(width: 1280, height: 720),
    frameRate: FrameRate.fps30,
    duration: TimelineDuration.fromMicroseconds(3000000),
    assets: [
      ProjectAsset(
        id: assetId,
        kind: ProjectAssetKind.artwork,
        originalFileName: 'art.svg',
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:art',
        mediaType: 'image/svg+xml',
        artworkSourceType: ArtworkSourceType.svg,
      ),
    ],
    strokes: [
      ProjectStroke(
        id: strokeId,
        sectionId: sectionId,
        name: 'Stroke',
        points: const [DocumentPoint(0, 0), DocumentPoint(1, 1)],
      ),
    ],
    sections: [
      ProjectSection(id: sectionId, name: 'Section', strokeIds: [strokeId]),
    ],
    sectionOrder: [sectionId],
    scenes: const [],
    audioTracks: const [],
  );
}
