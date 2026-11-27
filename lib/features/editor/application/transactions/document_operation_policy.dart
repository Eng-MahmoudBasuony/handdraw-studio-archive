import 'package:handdraw_studio/features/editor/application/history/editor_history_primitives.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';

/// Document edits classified by the centralized transaction policy.
enum DocumentOperationKind {
  strokeAdd,
  strokeDelete,
  strokeDuplicate,
  strokeReverse,
  strokeSetDirection,
  strokeSetHidden,
  strokeSetReveal,
  strokeReplaceGeometry,
  strokeAddPausePoint,
  strokeUpdatePausePoint,
  strokeDeletePausePoint,
  strokeApplyBatch,
  timingSetPauseBefore,
  timingSetPauseAfter,
  timingSetSpeedMultiplier,
  timingSetDurationOverride,
  timingSetTransitionAfter,
  timingSetPauseHandBehavior,
  timingSetAudioCue,
  timingClearAudioCue,
  timingReset,
  timingSetPenTravelSpeed,
  timingResizeDrawing,
  sceneReorderSection,
  sceneReorderSections,
  sceneDeleteSection,
  sceneCreate,
  sceneDelete,
  sceneGroup,
  sceneUngroup,
  sceneMoveSection,
  sceneReorder,
  sceneSetLocked,
  pathAddNode,
  pathDeleteNode,
  pathMoveNode,
  pathSetNodeSmooth,
  pathSplit,
  pathSetStartNode,
  pathJoinWithNext,
  maskAdd,
  maskRemove,
  maskReset,
  maskApplyBatch,
  settingsSetCanvas,
  settingsSetMotion,
  settingsSetHand,
  settingsSetWritingSound,
  settingsResetDefaults,
  settingsSetExport,
  settingsAddAsset,
  settingsSetArtworkPlacement,
  settingsRemoveAsset,
  settingsClearArtwork,
  settingsSetVoiceGuide,
  settingsAttachVoiceGuide,
  settingsClearVoiceGuide,
  settingsCreateNew,
  settingsDuplicateProject,
  settingsSetAutoDirector,
  cameraEdit,
}

final class DocumentOperationPolicy {
  const DocumentOperationPolicy({
    required this.code,
    required this.allowedScopes,
    required this.labelCode,
    this.canCoalesce = false,
    this.composite = false,
    this.assetRetention = false,
    this.sessionBoundary = false,
  });

  final HistoryOperationCode code;
  final Set<DocumentScope> allowedScopes;
  final String labelCode;
  final bool canCoalesce;
  final bool composite;
  final bool assetRetention;
  final bool sessionBoundary;
}

final class DocumentOperationPolicyRegistry {
  const DocumentOperationPolicyRegistry();

  DocumentOperationPolicy policyFor(DocumentOperationKind kind) =>
      switch (kind) {
        DocumentOperationKind.strokeAdd => _p(
          HistoryOperationCode.addStroke,
          _strokeSection,
          'stroke.add',
        ),
        DocumentOperationKind.strokeDelete => _p(
          HistoryOperationCode.deleteStroke,
          _strokeSection,
          'stroke.delete',
        ),
        DocumentOperationKind.strokeDuplicate => _p(
          HistoryOperationCode.duplicateStroke,
          _strokeSection,
          'stroke.duplicate',
        ),
        DocumentOperationKind.strokeReverse ||
        DocumentOperationKind.strokeSetDirection => _p(
          HistoryOperationCode.changeStroke,
          _strokeTiming,
          'stroke.change',
        ),
        DocumentOperationKind.strokeSetHidden ||
        DocumentOperationKind.strokeReplaceGeometry => _p(
          HistoryOperationCode.changeStroke,
          _strokePath,
          'stroke.change',
        ),
        DocumentOperationKind.strokeSetReveal => _p(
          HistoryOperationCode.changeStroke,
          _masks,
          'stroke.reveal',
          canCoalesce: true,
        ),
        DocumentOperationKind.strokeAddPausePoint ||
        DocumentOperationKind.strokeDeletePausePoint => _p(
          HistoryOperationCode.changePause,
          _strokeTiming,
          'pause.change',
        ),
        DocumentOperationKind.strokeUpdatePausePoint => _p(
          HistoryOperationCode.changePause,
          _strokeTiming,
          'pause.update',
          canCoalesce: true,
        ),
        DocumentOperationKind.strokeApplyBatch => _p(
          HistoryOperationCode.batchEdit,
          _sceneComposite,
          'stroke.batch',
          composite: true,
        ),

        DocumentOperationKind.timingSetPauseBefore ||
        DocumentOperationKind.timingSetPauseAfter ||
        DocumentOperationKind.timingSetSpeedMultiplier ||
        DocumentOperationKind.timingSetDurationOverride ||
        DocumentOperationKind.timingSetTransitionAfter ||
        DocumentOperationKind.timingSetPauseHandBehavior => _p(
          HistoryOperationCode.changeTiming,
          _timing,
          'timing.change',
          canCoalesce: true,
        ),
        DocumentOperationKind.timingSetAudioCue => _p(
          HistoryOperationCode.changeAudioCue,
          _timingAudio,
          'audioCue.set',
        ),
        DocumentOperationKind.timingClearAudioCue => _p(
          HistoryOperationCode.changeAudioCue,
          _timingAudio,
          'audioCue.clear',
        ),
        DocumentOperationKind.timingReset => _p(
          HistoryOperationCode.changeTiming,
          _timing,
          'timing.reset',
        ),
        DocumentOperationKind.timingSetPenTravelSpeed => _p(
          HistoryOperationCode.changeSettings,
          _timingSettings,
          'timing.penTravelSpeed',
          canCoalesce: true,
        ),

        DocumentOperationKind.sceneReorderSection ||
        DocumentOperationKind.sceneReorderSections => _p(
          HistoryOperationCode.reorderSections,
          _sceneComposite,
          'ordering.reorder',
          composite: true,
        ),
        DocumentOperationKind.sceneDeleteSection => _p(
          HistoryOperationCode.deleteSection,
          _sceneComposite,
          'section.delete',
          composite: true,
        ),
        DocumentOperationKind.sceneCreate ||
        DocumentOperationKind.sceneMoveSection ||
        DocumentOperationKind.sceneReorder ||
        DocumentOperationKind.sceneSetLocked => _p(
          HistoryOperationCode.changeScene,
          _scenes,
          'scene.change',
        ),
        DocumentOperationKind.sceneDelete => _p(
          HistoryOperationCode.changeScene,
          _sceneCamera,
          'scene.change',
          composite: true,
        ),
        DocumentOperationKind.sceneGroup ||
        DocumentOperationKind.sceneUngroup => _p(
          HistoryOperationCode.changeScene,
          _sceneComposite,
          'scene.membership',
          composite: true,
        ),

        DocumentOperationKind.pathAddNode ||
        DocumentOperationKind.pathDeleteNode ||
        DocumentOperationKind.pathSetNodeSmooth ||
        DocumentOperationKind.pathSetStartNode => _p(
          HistoryOperationCode.changePath,
          _paths,
          'path.change',
        ),
        DocumentOperationKind.pathMoveNode => _p(
          HistoryOperationCode.changePath,
          _paths,
          'path.moveNode',
          canCoalesce: true,
        ),
        DocumentOperationKind.pathSplit => _p(
          HistoryOperationCode.splitPath,
          _strokeSection,
          'path.split',
          composite: true,
        ),
        DocumentOperationKind.pathJoinWithNext => _p(
          HistoryOperationCode.joinPath,
          _strokeSection,
          'path.join',
          composite: true,
        ),

        DocumentOperationKind.maskAdd ||
        DocumentOperationKind.maskRemove ||
        DocumentOperationKind.maskReset => _p(
          HistoryOperationCode.changeMask,
          _masks,
          'mask.change',
        ),
        DocumentOperationKind.maskApplyBatch => _p(
          HistoryOperationCode.batchEdit,
          _masks,
          'mask.batch',
          composite: true,
        ),

        DocumentOperationKind.timingResizeDrawing => _p(
          HistoryOperationCode.changeSettings,
          const {
            DocumentScope.timing,
            DocumentScope.settings,
            DocumentScope.strokes,
          },
          'motion.resizeDuration',
          canCoalesce: true,
          composite: true,
        ),
        DocumentOperationKind.settingsSetCanvas => _p(
          HistoryOperationCode.changeCanvas,
          _canvasSettings,
          'canvas.change',
          canCoalesce: true,
        ),
        DocumentOperationKind.settingsSetMotion => _p(
          HistoryOperationCode.changeSettings,
          _timingSettings,
          'motion.change',
          canCoalesce: true,
        ),
        DocumentOperationKind.settingsSetHand => _p(
          HistoryOperationCode.changeHand,
          _handSettings,
          'hand.change',
          assetRetention: true,
        ),
        DocumentOperationKind.settingsSetWritingSound => _p(
          HistoryOperationCode.changeSettings,
          _audioSettings,
          'writingSound.change',
          canCoalesce: true,
        ),
        DocumentOperationKind.settingsResetDefaults => _p(
          HistoryOperationCode.batchEdit,
          _allSettings,
          'settings.reset',
          composite: true,
        ),
        DocumentOperationKind.settingsSetExport => _p(
          HistoryOperationCode.changeExport,
          _exportCanvas,
          'export.change',
          canCoalesce: true,
        ),
        DocumentOperationKind.settingsAddAsset => _p(
          HistoryOperationCode.changeAssets,
          _assets,
          'asset.add',
          assetRetention: true,
        ),
        DocumentOperationKind.settingsSetArtworkPlacement => _p(
          HistoryOperationCode.changeAssets,
          _assets,
          'artwork.placement',
          canCoalesce: true,
        ),
        DocumentOperationKind.settingsRemoveAsset => _p(
          HistoryOperationCode.changeAssets,
          _assets,
          'asset.remove',
          assetRetention: true,
        ),
        DocumentOperationKind.settingsClearArtwork => _p(
          HistoryOperationCode.changeAssets,
          _artworkComposite,
          'artwork.clear',
          composite: true,
          assetRetention: true,
        ),
        DocumentOperationKind.settingsSetVoiceGuide => _p(
          HistoryOperationCode.changeAudioCue,
          _audioSettings,
          'voiceGuide.set',
          assetRetention: true,
        ),
        DocumentOperationKind.settingsAttachVoiceGuide => _p(
          HistoryOperationCode.changeAssets,
          _assetsAudio,
          'voiceGuide.attach',
          composite: true,
          assetRetention: true,
        ),
        DocumentOperationKind.settingsClearVoiceGuide => _p(
          HistoryOperationCode.changeAudioCue,
          _timingAudio,
          'voiceGuide.clear',
          composite: true,
          assetRetention: true,
        ),
        DocumentOperationKind.settingsCreateNew => _p(
          HistoryOperationCode.changeSettings,
          _settings,
          'session.new',
          sessionBoundary: true,
        ),
        DocumentOperationKind.settingsDuplicateProject => _p(
          HistoryOperationCode.changeSettings,
          _all,
          'session.duplicate',
          sessionBoundary: true,
        ),
        DocumentOperationKind.settingsSetAutoDirector => _p(
          HistoryOperationCode.changeSettings,
          _settings,
          'autoDirector.settings',
          canCoalesce: true,
        ),
        DocumentOperationKind.cameraEdit => _p(
          HistoryOperationCode.changeSettings,
          _camera,
          'camera.edit',
          canCoalesce: true,
        ),
      };
}

DocumentOperationPolicy _p(
  HistoryOperationCode code,
  Set<DocumentScope> scopes,
  String label, {
  bool canCoalesce = false,
  bool composite = false,
  bool assetRetention = false,
  bool sessionBoundary = false,
}) => DocumentOperationPolicy(
  code: code,
  allowedScopes: scopes,
  labelCode: label,
  canCoalesce: canCoalesce,
  composite: composite,
  assetRetention: assetRetention,
  sessionBoundary: sessionBoundary,
);

const _strokeSection = {
  DocumentScope.strokes,
  DocumentScope.paths,
  DocumentScope.sections,
  DocumentScope.ordering,
};
const _strokePath = {DocumentScope.strokes, DocumentScope.paths};
const _strokeTiming = {
  DocumentScope.strokes,
  DocumentScope.paths,
  DocumentScope.timing,
};
const _timing = {DocumentScope.timing, DocumentScope.sections};
const _timingAudio = {
  DocumentScope.timing,
  DocumentScope.sections,
  DocumentScope.audio,
};
const _timingSettings = {DocumentScope.timing, DocumentScope.settings};
const _scenes = {DocumentScope.scenes, DocumentScope.ordering};
const _sceneCamera = {
  DocumentScope.scenes,
  DocumentScope.ordering,
  DocumentScope.camera,
};
const _camera = {DocumentScope.camera, DocumentScope.settings};
const _sceneComposite = {
  DocumentScope.scenes,
  DocumentScope.ordering,
  DocumentScope.sections,
  DocumentScope.strokes,
  DocumentScope.timing,
  DocumentScope.settings,
  DocumentScope.hand,
  DocumentScope.camera,
};
const _paths = {DocumentScope.paths, DocumentScope.strokes};
const _masks = {DocumentScope.masks, DocumentScope.strokes};
const _canvasSettings = {DocumentScope.canvas, DocumentScope.settings};
const _handSettings = {DocumentScope.hand, DocumentScope.settings};
const _audioSettings = {DocumentScope.audio, DocumentScope.settings};
const _allSettings = {
  DocumentScope.settings,
  DocumentScope.canvas,
  DocumentScope.export,
  DocumentScope.hand,
  DocumentScope.timing,
};
const _exportCanvas = {
  DocumentScope.export,
  DocumentScope.canvas,
  DocumentScope.settings,
  DocumentScope.strokes,
};
const _assets = {DocumentScope.assets};
const _artworkComposite = {
  DocumentScope.assets,
  DocumentScope.strokes,
  DocumentScope.sections,
  DocumentScope.ordering,
  DocumentScope.scenes,
  DocumentScope.camera,
  DocumentScope.semantic,
  DocumentScope.settings,
};
const _assetsAudio = {DocumentScope.assets, DocumentScope.audio};
const _settings = {DocumentScope.settings};
const _all = {...DocumentScope.values};
