import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/project/domain/importing/imported_artwork_draft.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/services/artwork_placement_service.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_import_builder.dart';
import 'package:handdraw_studio/features/project/infrastructure/development_project_manifest_codec.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/fake_id_generator.dart';

void main() {
  const service = ArtworkPlacementService();

  test('matching aspect preserves the full authored canvas without crop', () {
    final placement = service.createDefault(
      canvas: const ProjectCanvas(width: 1920, height: 1080),
      encodedWidth: 1280,
      encodedHeight: 720,
    );
    expect(placement.destination.left, 0);
    expect(placement.destination.top, 0);
    expect(placement.destination.right, 1920);
    expect(placement.destination.bottom, 1080);
  });

  test(
    'editor fits real visible pixels without changing document placement',
    () {
      const placement = ProjectArtworkPlacement(
        encodedBounds: DocumentRect(left: 0, top: 0, right: 1000, bottom: 1000),
        visibleBounds: DocumentRect(
          left: 200,
          top: 400,
          right: 800,
          bottom: 600,
        ),
        destination: DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080),
      );
      final fitted = editorArtworkRectForVisibleContent(
        baseArtworkRect: const Rect.fromLTWH(0, 0, 1000, 500),
        canvasSize: const Size(1000, 500),
        placement: placement,
        padding: 50,
      );
      final visibleInEditor = Rect.fromLTRB(
        fitted.left + fitted.width * .2,
        fitted.top + fitted.height * .4,
        fitted.left + fitted.width * .8,
        fitted.top + fitted.height * .6,
      );

      expect(visibleInEditor.center, const Offset(500, 250));
      expect(visibleInEditor.left, closeTo(50, .001));
      expect(visibleInEditor.right, closeTo(950, .001));
      expect(placement.destination.right, 1920);
    },
  );

  test('editor keeps a full-scene visible image at the normal project fit', () {
    const base = Rect.fromLTWH(0, 0, 1000, 500);
    final fitted = editorArtworkRectForVisibleContent(
      baseArtworkRect: base,
      canvasSize: const Size(1000, 500),
      placement: const ProjectArtworkPlacement(
        encodedBounds: DocumentRect(left: 0, top: 0, right: 1000, bottom: 500),
        visibleBounds: DocumentRect(left: 0, top: 0, right: 1000, bottom: 500),
        destination: DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080),
      ),
    );
    expect(fitted, base);
  });

  test('different aspect contain-fits, centers, pads, and never crops', () {
    final placement = service.createDefault(
      canvas: const ProjectCanvas(width: 1920, height: 1080),
      encodedWidth: 1000,
      encodedHeight: 1000,
    );
    final rect = placement.destination;
    expect(rect.left, greaterThan(0));
    expect(rect.top, closeTo(43.2, .01));
    expect(rect.right, lessThan(1920));
    expect(rect.bottom, closeTo(1036.8, .01));
    expect((rect.left + rect.right) / 2, closeTo(960, .01));
  });

  test('encoded and visible bounds remain distinct across Save/Open', () {
    final draft = ImportedArtworkDraft(
      title: 'placement',
      canvas: const ProjectCanvas(width: 1920, height: 1080),
      frameRate: FrameRate(numerator: 30),
      duration: TimelineDuration.fromMicroseconds(2000000),
      asset: const ImportedArtworkAssetDraft(
        originalFileName: 'art.png',
        sourceType: ArtworkSourceType.raster,
        storagePolicy: ProjectAssetStoragePolicy.embedded,
        contentHash: 'sha256:test',
        mediaType: 'image/png',
      ),
      sections: const [],
    );
    final document = const ProjectDocumentImportBuilder()
        .build(draft, ids: SequentialIdGenerator())
        .copyWith(
          artworkPlacement: const ProjectArtworkPlacement(
            encodedBounds: DocumentRect(
              left: 0,
              top: 0,
              right: 1000,
              bottom: 800,
            ),
            visibleBounds: DocumentRect(
              left: 100,
              top: 80,
              right: 900,
              bottom: 720,
            ),
            destination: DocumentRect(
              left: 100,
              top: 50,
              right: 1820,
              bottom: 1030,
            ),
            importIntent: ArtworkImportIntent.element,
          ),
        );
    const codec = DevelopmentProjectManifestCodec();
    final restored = codec.decode(codec.encode(document));
    expect(restored.artworkPlacement!.encodedBounds.right, 1000);
    expect(restored.artworkPlacement!.visibleBounds.left, 100);
    expect(restored.artworkPlacement!.destination.right, 1820);
    expect(
      restored.artworkPlacement!.importIntent,
      ArtworkImportIntent.element,
    );
  });

  test(
    'full-scene intent preserves authored placement while element fits alpha bounds',
    () {
      const base = ProjectArtworkPlacement(
        encodedBounds: DocumentRect(left: 0, top: 0, right: 1000, bottom: 800),
        visibleBounds: DocumentRect(
          left: 400,
          top: 300,
          right: 600,
          bottom: 500,
        ),
        destination: DocumentRect(left: -20, top: 30, right: 980, bottom: 830),
      );
      expect(base.importIntent, ArtworkImportIntent.fullScene);
      final element = service.applyMode(
        placement: base.copyWith(importIntent: ArtworkImportIntent.element),
        canvas: const ProjectCanvas(width: 1920, height: 1080),
        mode: ArtworkPlacementMode.fitVisible,
      );
      expect(element.destination.left, greaterThan(0));
      expect(
        (element.destination.left + element.destination.right) / 2,
        closeTo(960, 1e-9),
      );
    },
  );

  test(
    'fit-visible, original, and fill modes retain their explicit policy',
    () {
      const base = ProjectArtworkPlacement(
        encodedBounds: DocumentRect(left: 0, top: 0, right: 1000, bottom: 800),
        visibleBounds: DocumentRect(
          left: 100,
          top: 100,
          right: 900,
          bottom: 500,
        ),
        destination: DocumentRect(left: 0, top: 0, right: 1000, bottom: 800),
      );
      const canvas = ProjectCanvas(width: 1920, height: 1080);
      for (final mode in ArtworkPlacementMode.values) {
        final result = service.applyMode(
          placement: base,
          canvas: canvas,
          mode: mode,
        );
        expect(result.mode, mode);
        expect(result.destination.right, greaterThan(result.destination.left));
        expect(result.destination.bottom, greaterThan(result.destination.top));
      }
    },
  );
}
