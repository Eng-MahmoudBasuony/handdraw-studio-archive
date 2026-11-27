import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_committer.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/operations/mask_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/path_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/project_settings_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/scene_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/stroke_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/timeline_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/validation/project_document_validator.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';

import 'support/fake_id_generator.dart';
import 'support/project_document_parity_fixture.dart';

void main() {
  const validator = ProjectDocumentValidator();

  group('2A.7-prep-A strokes', () {
    const operations = StrokeDocumentOperations();

    test(
      'add, duplicate, direction, visibility, reveal, and delete stay valid',
      () {
        final source = _editableDocument();
        final sectionId = source.sections.first.id;
        final added = operations.add(
          document: source,
          input: AddStrokeInput(
            sectionId: sectionId,
            name: 'Authored',
            points: const [DocumentPoint(0.2, 0.2), DocumentPoint(0.4, 0.4)],
          ),
          ids: _ids(source),
        );
        expect(added.isSuccess, isTrue);
        final addedId = added.document.strokes.last.id;
        final duplicated = operations.duplicate(
          document: added.document,
          strokeId: addedId,
          ids: _ids(added.document),
        );
        final directed = operations.setDirection(
          document: duplicated.document,
          strokeId: addedId,
          reversed: true,
        );
        final hidden = operations.setHidden(
          document: directed.document,
          strokeId: addedId,
          hidden: true,
        );
        final revealed = operations.setReveal(
          document: hidden.document,
          strokeId: addedId,
          revealOnly: true,
          style: DocumentRevealStyle.directionalWipe,
        );
        final deleted = operations.delete(
          document: revealed.document,
          strokeId: addedId,
        );
        expect(deleted.document.strokes, hasLength(source.strokes.length + 1));
        expect(validator.validate(deleted.document).isValid, isTrue);
        expect(revealed.affectedScopes, contains(DocumentScope.masks));
      },
    );

    test('Auto Path/Reveal batch is one semantic result', () {
      final source = _editableDocument();
      final result = operations.applyBatch(
        document: source,
        input: BatchStrokeApplication(
          strokes: source.strokes,
          sections: source.sections,
          sectionOrder: source.sectionOrder.reversed.toList(),
          action: 'apply-auto-reveal',
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(result.summary.action, 'apply-auto-reveal');
      expect(
        result.affectedScopes,
        containsAll({
          DocumentScope.strokes,
          DocumentScope.sections,
          DocumentScope.ordering,
        }),
      );
      expect(validator.validate(result.document).isValid, isTrue);
    });

    test('stroke pause IDs allocate once and survive update/delete', () {
      final source = _editableDocument();
      final strokeId = source.strokes.first.id;
      final added = operations.addPausePoint(
        document: source,
        strokeId: strokeId,
        progress: 0.4,
        duration: TimelineDuration.fromMicroseconds(300000),
        ids: _ids(source),
      );
      final pauseId = added.document.strokes.first.pausePoints.single.id;
      final updated = operations.updatePausePoint(
        document: added.document,
        strokeId: strokeId,
        pauseId: pauseId,
        progress: 0.6,
        duration: TimelineDuration.fromMicroseconds(500000),
        keepHandVisible: false,
      );
      expect(updated.document.strokes.first.pausePoints.single.progress, 0.6);
      final deleted = operations.deletePausePoint(
        document: updated.document,
        strokeId: strokeId,
        pauseId: pauseId,
      );
      expect(deleted.document.strokes.first.pausePoints, isEmpty);
      expect(validator.validate(deleted.document).isValid, isTrue);
    });

    test('duplicating a stroke remaps every persistent pause ID', () {
      final source = _editableDocument();
      final strokeId = source.strokes.first.id;
      final withPause = operations.addPausePoint(
        document: source,
        strokeId: strokeId,
        progress: 0.4,
        duration: TimelineDuration.fromMicroseconds(300000),
        ids: _ids(source),
      );
      final duplicated = operations.duplicate(
        document: withPause.document,
        strokeId: strokeId,
        ids: _ids(withPause.document),
      );
      final original = duplicated.document.strokes.first;
      final copy = duplicated.document.strokes[1];
      expect(copy.pausePoints.single.id, isNot(original.pausePoints.single.id));
      expect(validator.validate(duplicated.document).isValid, isTrue);
    });
  });

  group('2A.7-prep-B timing', () {
    const operations = TimelineDocumentOperations();

    test(
      'authored values stay independent and reset removes no derived value',
      () {
        final source = _editableDocument();
        final id = source.sections.first.id;
        var result = operations.setPauseBefore(
          document: source,
          sectionId: id,
          duration: TimelineDuration.fromMicroseconds(400000),
        );
        result = operations.setPauseAfter(
          document: result.document,
          sectionId: id,
          duration: TimelineDuration.fromMicroseconds(600000),
        );
        result = operations.setDurationOverride(
          document: result.document,
          sectionId: id,
          duration: TimelineDuration.fromMicroseconds(2000000),
        );
        result = operations.setTransitionAfter(
          document: result.document,
          sectionId: id,
          duration: TimelineDuration.fromMicroseconds(250000),
        );
        final timing = result.document.sections.first.timing;
        expect(timing.pauseBefore.microseconds, 400000);
        expect(timing.pauseAfter.microseconds, 600000);
        expect(timing.animationDuration?.microseconds, 2000000);
        expect(timing.transitionAfter.microseconds, 250000);
        expect(
          operations
              .reset(document: result.document, sectionId: id)
              .document
              .sections
              .first
              .timing
              .isDefault,
          isTrue,
        );
      },
    );

    test('audio cue validates its typed track reference', () {
      final source = _editableDocument();
      final result = operations.setAudioCue(
        document: source,
        sectionId: source.sections.last.id,
        anchor: AudioCueAnchor(
          audioTrackId: source.audioTracks.single.id,
          sourceMediaTime: TimelineTime.fromMicroseconds(900000),
        ),
      );
      expect(result.isSuccess, isTrue);
      expect(validator.validate(result.document).isValid, isTrue);
      final failure = operations.setAudioCue(
        document: source,
        sectionId: source.sections.first.id,
        anchor: AudioCueAnchor(
          audioTrackId: AudioTrackId('missing'),
          sourceMediaTime: TimelineTime.zero,
        ),
      );
      expect(failure.isSuccess, isFalse);
      expect(identical(failure.document, source), isTrue);
    });
  });

  group('2A.7-prep-C order and scenes', () {
    const operations = SceneDocumentOperations();

    test(
      'multi-reorder preserves selected order and scene membership is singular',
      () {
        final source = _editableDocument();
        final moved = operations.reorderSections(
          document: source,
          sectionIds: [source.sectionOrder.last, source.sectionOrder.first],
          insertionIndex: 0,
        );
        expect(moved.document.sectionOrder, source.sectionOrder);
        final created = operations.createScene(
          document: moved.document,
          name: 'Grouped',
          sectionIds: moved.document.sectionOrder,
          ids: _ids(moved.document),
        );
        expect(
          created.document.scenes.single.sectionIds,
          created.document.sectionOrder,
        );
        expect(validator.validate(created.document).isValid, isTrue);
      },
    );

    test(
      'move, lock, scene reorder, ungroup, and section delete remain valid',
      () {
        var document = _editableDocument();
        final first = operations.createScene(
          document: document,
          name: 'First',
          sectionIds: [document.sectionOrder.first],
          ids: _ids(document),
        );
        document = first.document;
        final second = operations.createScene(
          document: document,
          name: 'Second',
          sectionIds: [document.sectionOrder.last],
          ids: _ids(document),
        );
        document = second.document;
        final target = document.scenes.last.id;
        document = operations
            .moveSectionBetweenScenes(
              document: document,
              sectionId: document.sectionOrder.first,
              destinationSceneId: target,
              insertionIndex: 0,
            )
            .document;
        document = operations
            .setLocked(document: document, sceneId: target, locked: false)
            .document;
        document = operations
            .reorderScene(
              document: document,
              sceneId: target,
              insertionIndex: 0,
            )
            .document;
        document = operations
            .ungroup(
              document: document,
              sectionIds: [document.sectionOrder.first],
            )
            .document;
        document = operations
            .deleteSection(
              document: document,
              sectionId: document.sectionOrder.last,
            )
            .document;
        expect(validator.validate(document).isValid, isTrue);
      },
    );
  });

  group('2A.7-prep-D nodes and masks', () {
    const paths = PathDocumentOperations();
    const masks = MaskDocumentOperations();

    test('one committed node drag creates one history-ready result', () {
      final source = _editableDocument();
      final strokeId = source.strokes.first.id;
      final added = paths.addNode(
        document: source,
        strokeId: strokeId,
        segmentIndex: 0,
      );
      final moved = paths.moveNode(
        document: added.document,
        strokeId: strokeId,
        node: const DocumentPathNodeReference(
          kind: DocumentPathNodeKind.endAnchor,
          segmentIndex: 0,
        ),
        destination: const DocumentPoint(0.35, 0.25),
      );
      final smooth = paths.setNodeSmooth(
        document: moved.document,
        strokeId: strokeId,
        anchorIndex: 1,
        smooth: true,
      );
      expect(moved.summary.action, 'move-path-node');
      expect(moved.summary.changeCount, 1);
      expect(
        smooth.document.strokes.first.geometry!.smoothAnchors,
        contains(1),
      );
      expect(validator.validate(smooth.document).isValid, isTrue);
    });

    test(
      'anchor drag carries adjacent handles and quadratic controls edit',
      () {
        final source = _editableDocument();
        final strokeId = source.strokes.first.id;
        final moved = paths.moveNode(
          document: source,
          strokeId: strokeId,
          node: const DocumentPathNodeReference(
            kind: DocumentPathNodeKind.endAnchor,
            segmentIndex: 0,
          ),
          destination: const DocumentPoint(0.6, 0.3),
        );
        final cubic = moved.document.strokes.first.geometry!.segments.first;
        expect(cubic, isA<StrokeCubicSegment>());
        expect((cubic as StrokeCubicSegment).control2.dx, closeTo(0.5, 1e-12));
        expect(cubic.control2.dy, closeTo(0.4, 1e-12));

        final quadratic = StrokePathGeometry(
          start: const Offset(0.1, 0.1),
          segments: const [
            StrokeQuadraticSegment(
              control: Offset(0.2, 0.2),
              end: Offset(0.4, 0.1),
            ),
          ],
        );
        final quadraticDocument = source.copyWith(
          strokes: [
            source.strokes.first.copyWith(geometry: quadratic),
            source.strokes.last,
          ],
        );
        final controlMoved = paths.moveNode(
          document: quadraticDocument,
          strokeId: strokeId,
          node: const DocumentPathNodeReference(
            kind: DocumentPathNodeKind.quadraticControl,
            segmentIndex: 0,
          ),
          destination: const DocumentPoint(0.3, 0.35),
        );
        final changed =
            controlMoved.document.strokes.first.geometry!.segments.single
                as StrokeQuadraticSegment;
        expect(changed.control, const Offset(0.3, 0.35));
      },
    );

    test('split path allocates one stroke and updates section ownership', () {
      final source = _editableDocument();
      final strokeId = source.strokes.first.id;
      final split = paths.splitPath(
        document: source,
        strokeId: strokeId,
        anchorIndex: 1,
        ids: _ids(source),
      );
      expect(split.isSuccess, isTrue);
      expect(split.summary.action, 'split-path');
      expect(split.document.strokes, hasLength(source.strokes.length + 1));
      final section = split.document.sections.first;
      expect(section.strokeIds, hasLength(2));
      expect(section.strokeIds.first, strokeId);
      expect(section.strokeIds.last, split.document.strokes[1].id);
      expect(split.document.strokes[1].pausePoints, isEmpty);
      expect(validator.validate(split.document).isValid, isTrue);
    });

    test('mask add/remove/reset and batch are immutable', () {
      final source = _editableDocument();
      final strokeId = source.strokes.first.id;
      final mask = DocumentVectorMaskStroke(
        geometry: _geometry(),
        width: 0.05,
        erase: false,
      );
      final added = masks.add(document: source, strokeId: strokeId, mask: mask);
      expect(source.strokes.first.vectorMaskStrokes, isEmpty);
      expect(added.document.strokes.first.vectorMaskStrokes, hasLength(1));
      final removed = masks.remove(
        document: added.document,
        strokeId: strokeId,
        maskIndex: 0,
      );
      final batch = masks.applyBatch(
        document: removed.document,
        changes: {
          strokeId: [mask],
        },
      );
      final reset = masks.reset(document: batch.document, strokeId: strokeId);
      expect(reset.document.strokes.first.vectorMaskStrokes, isEmpty);
      expect(validator.validate(reset.document).isValid, isTrue);
    });
  });

  group('2A.7-prep-E project settings', () {
    const operations = ProjectSettingsOperations();

    test(
      'canvas, hand, output, frame rate, and export stay document-owned',
      () {
        final source = _editableDocument();
        var result = operations.setCanvas(
          document: source,
          canvas: const ProjectCanvas(width: 3840, height: 2160),
        );
        result = operations.setHand(
          document: result.document,
          configuration: source.handConfiguration.copyWith(scale: 0.4),
        );
        result = operations.setExport(
          document: result.document,
          configuration: source.exportConfiguration.copyWith(
            presetId: ExportPresetId.finalCutOverlay4k,
          ),
          frameRate: FrameRate.fps60,
        );
        expect(result.document.canvas.width, 3840);
        expect(result.document.handConfiguration.scale, 0.4);
        expect(result.document.frameRate, FrameRate.fps60);
        expect(validator.validate(result.document).isValid, isTrue);
        final reset = operations.resetDefaults(document: result.document);
        expect(reset.document.canvas.width, 1920);
        expect(reset.document.handConfiguration.scale, 0.4);
        expect(
          reset.document.handConfiguration.penTip,
          result.document.handConfiguration.penTip,
        );
        expect(reset.document.strokes, hasLength(source.strokes.length));
      },
    );

    test('canvas background is normalized and survives output resizing', () {
      final source = _editableDocument();
      final styled = operations.setCanvasBackground(
        document: source,
        background: const CanvasBackground.preset(CanvasBackgroundPreset.linen),
      );
      final resized = operations.setExport(
        document: styled.document,
        configuration: source.exportConfiguration,
        outputSize: const ProjectCanvas(width: 3840, height: 2160),
      );

      expect(
        resized.document.canvas.background,
        const CanvasBackground.preset(CanvasBackgroundPreset.linen),
      );
      expect(validator.validate(resized.document).isValid, isTrue);
    });

    test('assets, Voice Guide, New, and Duplicate use explicit allocation', () {
      final source = _editableDocument();
      final muted = operations.setVoiceGuideMuted(
        document: source,
        muted: true,
      );
      expect(muted.isSuccess, isTrue);
      expect(muted.document.audioTracks.single.muted, isTrue);
      expect(validator.validate(muted.document).isValid, isTrue);
      final unmuted = operations.setVoiceGuideMuted(
        document: muted.document,
        muted: false,
      );
      expect(unmuted.document.audioTracks.single.muted, isFalse);
      final clear = operations.clearVoiceGuide(document: source);
      expect(clear.document.voiceGuide, isNull);
      expect(clear.document.sections.first.timing.audioCueAnchor, isNull);
      final attached = operations.attachVoiceGuide(
        document: clear.document,
        assetId: source.audioTracks.single.assetId,
        displayName: 'Replacement',
        ids: _ids(clear.document),
      );
      expect(attached.document.voiceGuide?.displayName, 'Replacement');
      final duplicate = operations.duplicateProject(
        document: attached.document,
        ids: _ids(attached.document),
      );
      expect(duplicate.document.id, isNot(attached.document.id));
      final fresh = operations.createNew(
        current: duplicate.document,
        ids: _ids(duplicate.document),
      );
      expect(fresh.document.strokes, isEmpty);
      expect(validator.validate(duplicate.document).isValid, isTrue);
      expect(validator.validate(fresh.document).isValid, isTrue);
      final artworkHash = attached.document.assets
          .singleWhere((asset) => asset.id == attached.document.artworkAssetId)
          .contentHash;
      final placed = attached.document.copyWith(
        artworkPlacement: const ProjectArtworkPlacement(
          encodedBounds: DocumentRect(
            left: 0,
            top: 0,
            right: 1920,
            bottom: 1080,
          ),
          visibleBounds: DocumentRect(
            left: 200,
            top: 100,
            right: 1720,
            bottom: 980,
          ),
          destination: DocumentRect(left: 0, top: 0, right: 1920, bottom: 1080),
        ),
        pathProcessingMetadata: ProjectPathProcessingMetadata(
          engineId: 'handdraw-smart-path',
          algorithmVersion: 1,
          sourceAssetHash: artworkHash,
          suspectedFrameDetection: true,
          suspectedFrameConfidenceThreshold: 0.96,
        ),
      );
      final cleared = operations.clearArtwork(document: placed);
      expect(cleared.document.strokes, isEmpty);
      expect(cleared.document.audioTracks, isNotEmpty);
      expect(cleared.document.artworkPlacement, isNull);
      expect(cleared.document.cameraTrack, isNull);
      expect(cleared.document.pathProcessingMetadata, isNull);
      expect(cleared.document.timeline.camera.enabled, isFalse);
      expect(cleared.document.contentMetadata.entities, isEmpty);
      expect(cleared.affectedScopes, contains(DocumentScope.settings));
      expect(validator.validate(cleared.document).isValid, isTrue);
    });
  });

  test('operation does not advance revision; commit advances exactly once', () {
    final source = _editableDocument();
    final operation = const StrokeDocumentOperations().setHidden(
      document: source,
      strokeId: source.strokes.first.id,
      hidden: true,
    );
    const committer = EditorDocumentCommitter();
    final current = EditorDocumentState(document: source);
    final committed = committer.commit(current, operation.document);
    expect(current.revision.value, 0);
    expect(committed.revision.value, 1);
  });
}

ProjectDocument _editableDocument() {
  final source = projectDocumentParityFixture();
  final secondSection = ProjectSection(
    id: SectionId('section-body'),
    name: 'Body',
    strokeIds: [StrokeId('stroke-body')],
    assetId: source.artworkAssetId,
  );
  final geometry = _geometry();
  return source.copyWith(
    strokes: [
      source.strokes.first.copyWith(
        geometry: geometry,
        points: [
          for (final point in geometry.sample())
            DocumentPoint(point.dx, point.dy),
        ],
      ),
      ProjectStroke(
        id: StrokeId('stroke-body'),
        sectionId: secondSection.id,
        name: 'Body',
        points: const [DocumentPoint(0.2, 0.5), DocumentPoint(0.8, 0.5)],
        assetId: source.artworkAssetId,
      ),
    ],
    sections: [source.sections.first, secondSection],
    sectionOrder: [source.sections.first.id, secondSection.id],
    scenes: const [],
  );
}

StrokePathGeometry _geometry() => StrokePathGeometry(
  start: const Offset(0.1, 0.2),
  segments: const [
    StrokeCubicSegment(
      control1: Offset(0.2, 0.1),
      control2: Offset(0.4, 0.3),
      end: Offset(0.5, 0.2),
    ),
    StrokeLineSegment(end: Offset(0.8, 0.5)),
  ],
);

IdAllocationContext _ids(ProjectDocument document) => IdAllocationContext(
  generator: FakeIdGenerator(),
  usedIds: [
    document.id,
    ...document.assets.map((item) => item.id),
    ...document.strokes.map((item) => item.id),
    ...document.strokes.expand(
      (item) => item.pausePoints.map((pause) => pause.id),
    ),
    ...document.sections.map((item) => item.id),
    ...document.scenes.map((item) => item.id),
    ...document.audioTracks.map((item) => item.id),
  ],
);
