import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_content_visibility_service.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

import 'support/project_document_parity_fixture.dart';

void main() {
  const service = CameraContentVisibilityService();

  test(
    'uses the real visible artwork bounds, not transparent image padding',
    () {
      final source = projectDocumentParityFixture();
      final document = source.copyWith(
        strokes: const [],
        sections: const [],
        sectionOrder: const [],
        scenes: const [],
        artworkPlacement: const ProjectArtworkPlacement(
          encodedBounds: DocumentRect(
            left: 0,
            top: 0,
            right: 1000,
            bottom: 1000,
          ),
          visibleBounds: DocumentRect(
            left: 100,
            top: 100,
            right: 300,
            bottom: 300,
          ),
          destination: DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080),
        ),
      );

      expect(
        service.evaluate(
          document: document,
          view: const CameraView(centerX: .2, centerY: .2, viewportWidth: .3),
        ),
        CameraContentCoverage.fullyVisible,
      );
      expect(
        service.evaluate(
          document: document,
          view: const CameraView(centerX: .3, centerY: .3, viewportWidth: .2),
        ),
        CameraContentCoverage.partiallyVisible,
      );
      expect(
        service.evaluate(
          document: document,
          view: const CameraView(centerX: .8, centerY: .8, viewportWidth: .2),
        ),
        CameraContentCoverage.outside,
      );
    },
  );

  test('reports no content for a blank project', () {
    final source = projectDocumentParityFixture();
    final document = source.copyWith(
      artworkAssetId: null,
      artworkPlacement: null,
      assets: source.assets
          .where((asset) => asset.kind != ProjectAssetKind.artwork)
          .toList(),
      strokes: const [],
      sections: const [],
      sectionOrder: const [],
      scenes: const [],
    );
    expect(
      service.evaluate(document: document, view: const CameraView.identity()),
      CameraContentCoverage.noContent,
    );
  });
}
