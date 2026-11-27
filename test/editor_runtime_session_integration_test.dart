import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_session_coordinator.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/koni_project_container_store.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/voice_guide/infrastructure/voice_guide_service.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

import 'support/legacy_editor_state_fixture.dart';

void main() {
  test(
    'preview and export snapshots reuse only the captured revision',
    () async {
      final cubit = EditorCubit();
      final timeline = cubit.compileTimeline();
      final count = cubit.timelineCompilationCount;
      final preview = await cubit.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.preview,
      );
      final export = await cubit.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.export,
      );
      expect(identical(preview.timeline, timeline), isTrue);
      expect(identical(export.timeline, timeline), isTrue);
      expect(cubit.timelineCompilationCount, count);
      cubit.setDuration(9);
      final changed = await cubit.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.preview,
      );
      expect(identical(changed.timeline, timeline), isFalse);
      expect(identical(preview.timeline, timeline), isTrue);
      await preview.release();
      await export.release();
      await changed.release();
      await cubit.close();
    },
  );

  test(
    'render snapshot stays immutable across edits and editor close',
    () async {
      final cubit = EditorCubit();
      final snapshot = await cubit.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.export,
      );
      final capturedDuration = snapshot.project.durationSeconds;

      cubit.setDuration(9);
      expect(cubit.project.durationSeconds, 9);
      expect(snapshot.project.durationSeconds, capturedDuration);

      await cubit.close();
      await snapshot.release();
      await snapshot.release();
    },
  );

  test(
    'EditorCubit save, new, and open cross atomic session boundaries',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'handdraw-runtime-session-',
      );
      final projectPath = '${temporary.path}/round-trip.koni';
      const containers = KoniProjectContainerStore();
      final coordinator = EditorSessionCoordinator(
        staging: FileEditorAssetStagingStore(
          Directory('${temporary.path}/staging'),
        ),
        containerStore: containers,
        fingerprints: const CanonicalDocumentFingerprintCalculator(),
        projectIds: SecureRandomIdGenerator(),
      );
      final cubit = EditorCubit(
        fileService: _ProjectPathFileService(projectPath),
        projectContainerStore: containers,
        sessionCoordinator: coordinator,
      );
      addTearDown(() async {
        await cubit.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final projectId = cubit.state.document.id;
      expect(cubit.isDirty, isTrue);
      expect(await cubit.saveProject(), projectPath);
      expect(cubit.isDirty, isFalse);

      cubit.newProject();
      expect(cubit.state.document.id, isNot(projectId));
      expect(cubit.isDirty, isTrue);

      await cubit.openProject();
      expect(cubit.state.document.id, projectId);
      expect(cubit.state.documentRevision.value, 0);
      expect(cubit.history.undoEntries, isEmpty);
      expect(cubit.isDirty, isFalse);
    },
  );

  test(
    'Save As keeps identity and history while replacing the target',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'handdraw-runtime-save-as-',
      );
      final firstPath = '${temporary.path}/first.koni';
      final secondPath = '${temporary.path}/second.koni';
      const containers = KoniProjectContainerStore();
      final picker = _SequenceProjectPathFileService([firstPath, secondPath]);
      final cubit = EditorCubit(
        fileService: picker,
        projectContainerStore: containers,
        sessionCoordinator: EditorSessionCoordinator(
          staging: FileEditorAssetStagingStore(
            Directory('${temporary.path}/staging'),
          ),
          containerStore: containers,
          fingerprints: const CanonicalDocumentFingerprintCalculator(),
          projectIds: SecureRandomIdGenerator(),
        ),
      );
      addTearDown(() async {
        await cubit.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      final projectId = cubit.state.document.id;
      expect(await cubit.saveProject(), firstPath);
      cubit.setDuration(7);
      final revision = cubit.state.documentRevision;
      final undoCount = cubit.history.undoEntries.length;

      expect(await cubit.saveProjectAs(), secondPath);
      expect(cubit.state.document.id, projectId);
      expect(cubit.state.documentRevision, revision);
      expect(cubit.history.undoEntries.length, undoCount);
      expect(cubit.isDirty, isFalse);
      expect(picker.savePickCount, 2);

      cubit.setDuration(8);
      expect(await cubit.saveProject(), secondPath);
      expect(picker.savePickCount, 2);
    },
  );

  test('stroke, timing, and scene edits share chronological history', () async {
    final cubit = EditorCubit(
      initialState: testEditorState(
        project: HandDrawProject(
          strokes: [
            DrawingStroke(
              id: 'stroke-a',
              name: 'Stroke A',
              sectionId: 'section-a',
              points: [Offset(0.1, 0.2), Offset(0.8, 0.2)],
            ),
          ],
          timelineSectionOrder: const ['section-a'],
        ),
      ),
    );
    addTearDown(cubit.close);
    final strokeId = cubit.state.document.strokes.single.id;
    final sectionId = cubit.state.document.sections.single.id;
    final initialRevision = cubit.state.documentRevision.value;

    cubit.reverseStroke(0);
    cubit.setSectionPauseBefore('section:${sectionId.value}', 0.6);
    cubit.toggleTimelineSectionSelection(sectionId.value);
    cubit.createTimelineGroupFromSelection();

    final sceneId = cubit.state.document.scenes.single.id;
    expect(cubit.history.undoEntries, hasLength(3));
    expect(cubit.state.documentRevision.value, initialRevision + 3);
    expect(cubit.state.document.strokes.single.id, strokeId);

    cubit.undoStroke();
    expect(cubit.state.document.scenes, isEmpty);
    cubit.undoStroke();
    expect(
      cubit.state.document.sections.single.timing.pauseBefore.microseconds,
      0,
    );
    cubit.undoStroke();
    expect(cubit.state.document.strokes.single.reversed, isFalse);
    expect(cubit.canUndo, isFalse);
    expect(cubit.canRedo, isTrue);

    cubit.redoStroke();
    expect(cubit.state.document.strokes.single.reversed, isTrue);
    cubit.redoStroke();
    expect(
      cubit.state.document.sections.single.timing.pauseBefore.microseconds,
      600000,
    );
    cubit.redoStroke();
    expect(cubit.state.document.scenes.single.id, sceneId);
    expect(cubit.state.document.strokes.single.id, strokeId);
    expect(cubit.canRedo, isFalse);
  });

  test(
    'full runtime workflow round-trips identity and render snapshots',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'handdraw-runtime-e2e-',
      );
      final projectPath = '${temporary.path}/workflow.koni';
      final voiceFile = File('${temporary.path}/guide.wav');
      await voiceFile.writeAsBytes([1, 3, 5, 7, 9]);
      final svgBytes = Uint8List.fromList(
        '''
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <path id="curve" fill="none" stroke="#111"
          d="M 10 50 C 30 10 70 90 90 50" />
      </svg>
    '''
            .codeUnits,
      );
      const containers = KoniProjectContainerStore();
      final fileService = _WorkflowFileService(projectPath, svgBytes);
      EditorCubit createCubit() => EditorCubit(
        fileService: fileService,
        voiceGuideService: _WorkflowVoiceGuideService(voiceFile.path),
        projectContainerStore: containers,
        sessionCoordinator: EditorSessionCoordinator(
          staging: FileEditorAssetStagingStore(
            Directory('${temporary.path}/staging'),
          ),
          containerStore: containers,
          fingerprints: const CanonicalDocumentFingerprintCalculator(),
          projectIds: SecureRandomIdGenerator(),
        ),
      );

      final authored = createCubit();
      EditorRenderSnapshot? preview;
      EditorRenderSnapshot? export;
      EditorCubit? reopened;
      addTearDown(() async {
        await preview?.release();
        await export?.release();
        await reopened?.close();
        await authored.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      expect(await authored.importDrawing(), DrawingImportResult.imported);
      await authored.analyzeSmartPaths();
      expect(authored.state.document.strokes, hasLength(1));

      authored.reverseStroke(0);
      final sectionId = authored.state.document.sections.single.id;
      authored.addStrokePausePoint(
        0,
        progress: 0.45,
        durationSeconds: 0.4,
        keepHandVisible: true,
      );
      authored.setSectionPauseBefore('section:${sectionId.value}', 0.3);
      authored.toggleTimelineSectionSelection(sectionId.value);
      authored.createTimelineGroupFromSelection();

      authored.selectStroke(0);
      const artworkRect = Rect.fromLTWH(0, 0, 100, 100);
      final start = authored.project.strokes.single.orderedGeometry!.start;
      expect(
        authored.beginPathNodeEdit(
          Offset(start.dx * 100, start.dy * 100),
          artworkRect,
        ),
        isTrue,
      );
      authored.updatePathNodeEdit(
        Offset(start.dx * 100 + 4, start.dy * 100 + 3),
        artworkRect,
      );
      authored.endPathNodeEdit();

      authored.setTool(EditorTool.maskReveal);
      authored.beginStroke(const Offset(20, 45), artworkRect);
      authored.updateStroke(const Offset(80, 55), artworkRect);
      authored.endStroke();
      expect(
        await authored.importVoiceGuide(),
        isTrue,
        reason: authored.statusMessage,
      );

      authored.undoStroke();
      authored.undoStroke();
      authored.redoStroke();
      authored.redoStroke();

      const fingerprints = CanonicalDocumentFingerprintCalculator();
      final before = authored.state.document;
      final beforeFingerprints = fingerprints.calculate(before);
      final idsBefore = _persistentIds(before);
      expect(await authored.saveProjectAs(), projectPath);
      expect(authored.isDirty, isFalse);
      await authored.close();

      final opened = reopened = createCubit();
      await opened.openProject();
      final after = opened.state.document;
      final afterFingerprints = fingerprints.calculate(after);
      expect(_persistentIds(after), idsBefore);
      expect(
        after.strokes.single.pausePoints.single.id,
        before.strokes.single.pausePoints.single.id,
      );
      expect(
        after.strokes.single.geometry?.toJson(),
        before.strokes.single.geometry?.toJson(),
      );
      expect(_maskSignature(after), _maskSignature(before));
      expect(_timingSignature(after), _timingSignature(before));
      expect(_sceneSignature(after), _sceneSignature(before));
      expect(_voiceSignature(after), _voiceSignature(before));
      expect(
        after.assets.map((asset) => asset.contentHash),
        before.assets.map((asset) => asset.contentHash),
      );
      expect(afterFingerprints.semantic, beforeFingerprints.semantic);
      expect(afterFingerprints.persistence, beforeFingerprints.persistence);

      final previewSnapshot = preview = await opened.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.preview,
      );
      final exportSnapshot = export = await opened.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.export,
      );
      expect(previewSnapshot.documentState.document, after);
      expect(exportSnapshot.documentState.document, after);
      expect(
        previewSnapshot.project.strokes.single.id,
        exportSnapshot.project.strokes.single.id,
      );
    },
  );

  test(
    'camera timeline mixed history save/open preserves every stable value',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'camera-ui-roundtrip-',
      );
      final projectPath = '${temporary.path}/camera.koni';
      const containers = KoniProjectContainerStore();
      EditorCubit createCubit() => EditorCubit(
        fileService: _ProjectPathFileService(projectPath),
        projectContainerStore: containers,
        sessionCoordinator: EditorSessionCoordinator(
          staging: FileEditorAssetStagingStore(
            Directory('${temporary.path}/staging'),
          ),
          containerStore: containers,
          fingerprints: const CanonicalDocumentFingerprintCalculator(),
          projectIds: SecureRandomIdGenerator(),
        ),
      );
      final authored = createCubit();
      EditorCubit? opened;
      addTearDown(() async {
        await authored.close();
        await opened?.close();
        if (await temporary.exists()) await temporary.delete(recursive: true);
      });

      authored.addCameraShotAt(TimelineTime.zero);
      final original = authored.state.document.cameraTrack!.shots.single;
      authored.moveCameraShot(
        original.id,
        TimelineTime.fromDuration(const Duration(milliseconds: 250)),
      );
      authored.resizeCameraShot(
        original.id,
        TimelineDuration.fromDuration(const Duration(seconds: 3)),
      );
      authored.addCameraKeyframe(
        original.id,
        TimelineTime.fromDuration(const Duration(seconds: 1)),
        const CameraView(centerX: .65, centerY: .4, viewportWidth: .55),
        transition: CameraTransition(
          type: CameraTransitionType.fade,
          duration: TimelineDuration.fromDuration(
            const Duration(milliseconds: 300),
          ),
          easing: CameraEasing.easeInOut,
        ),
      );
      authored.setCameraShotsLocked({original.id}, true);
      authored.undoStroke();
      authored.redoStroke();

      const fingerprints = CanonicalDocumentFingerprintCalculator();
      final before = authored.state.document;
      final beforePrints = fingerprints.calculate(before);
      final beforeShot = before.cameraTrack!.shots.single;
      expect(await authored.saveProjectAs(), projectPath);

      opened = createCubit();
      await opened.openProject();
      final after = opened.state.document;
      final afterShot = after.cameraTrack!.shots.single;
      expect(afterShot.id, beforeShot.id);
      expect(afterShot.startTime, beforeShot.startTime);
      expect(afterShot.duration, beforeShot.duration);
      expect(afterShot.authorship, beforeShot.authorship);
      expect(afterShot.isLocked, beforeShot.isLocked);
      expect(afterShot.keyframes, beforeShot.keyframes);
      expect(after.cameraTrack!.defaultView, before.cameraTrack!.defaultView);
      expect(fingerprints.calculate(after).semantic, beforePrints.semantic);
      expect(
        fingerprints.calculate(after).persistence,
        beforePrints.persistence,
      );
    },
  );
}

Set<String> _persistentIds(ProjectDocument document) => {
  document.id.value,
  ...document.assets.map((asset) => asset.id.value),
  ...document.strokes.map((stroke) => stroke.id.value),
  ...document.sections.map((section) => section.id.value),
  ...document.scenes.map((scene) => scene.id.value),
  ...document.audioTracks.map((track) => track.id.value),
};

List<Object?> _maskSignature(ProjectDocument document) => [
  for (final mask in document.strokes.single.vectorMaskStrokes)
    [
      mask.geometry.toJson(),
      mask.width,
      mask.feather,
      mask.clipToLayer,
      mask.erase,
    ],
];

List<Object?> _timingSignature(ProjectDocument document) {
  final timing = document.sections.single.timing;
  return [
    timing.pauseBefore.microseconds,
    timing.pauseAfter.microseconds,
    timing.animationDuration?.microseconds,
    timing.transitionAfter.microseconds,
    timing.speedMultiplier,
    timing.pauseHandBehavior.name,
    timing.audioCueAnchor?.sourceMediaTime.microseconds,
  ];
}

List<Object?> _sceneSignature(ProjectDocument document) => [
  for (final scene in document.scenes)
    [
      scene.id.value,
      scene.name,
      scene.locked,
      ...scene.sectionIds.map((id) => id.value),
    ],
];

List<Object?> _voiceSignature(ProjectDocument document) => [
  document.voiceGuide?.audioTrackId.value,
  document.voiceGuide?.displayName,
  document.voiceGuide?.originalFileName,
];

final class _ProjectPathFileService extends EditorFileService {
  const _ProjectPathFileService(this.path);
  final String path;

  @override
  Future<String?> pickProjectSavePath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => path;

  @override
  Future<String?> pickProjectOpenPath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => path;
}

final class _SequenceProjectPathFileService extends EditorFileService {
  _SequenceProjectPathFileService(this.paths);

  final List<String> paths;
  int savePickCount = 0;

  @override
  Future<String?> pickProjectSavePath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => paths[savePickCount++];
}

final class _WorkflowFileService extends EditorFileService {
  const _WorkflowFileService(this.projectPath, this.svgBytes);

  final String projectPath;
  final Uint8List svgBytes;

  @override
  Future<ImportedEditorAsset?> pickDrawing({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => loadImageBytes(path: 'workflow.svg', bytes: svgBytes);

  @override
  Future<String?> pickProjectSavePath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => projectPath;

  @override
  Future<String?> pickProjectOpenPath({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async => projectPath;
}

final class _WorkflowVoiceGuideService extends VoiceGuideService {
  const _WorkflowVoiceGuideService(this.path);

  final String path;

  @override
  Future<VoiceGuide?> importVoiceGuide({
    VoiceGuidePickerCopy copy = VoiceGuidePickerCopy.english,
  }) async => VoiceGuide(
    path: path,
    name: 'Guide',
    durationSeconds: 2,
    waveform: const [0.2, 0.8, 0.4],
  );
}
