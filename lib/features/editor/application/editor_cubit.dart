import 'package:handdraw_studio/features/codex_assistant/domain/codex_drawing_plan.dart';
import 'package:handdraw_studio/features/image_animation/application/image_parts_planner.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/macos_atomic_file_replacer.dart';
import 'package:handdraw_studio/features/image_animation/application/saved_drawing_import.dart';
import 'package:handdraw_studio/features/image_animation/application/image_animation_analyzer.dart';
import 'package:handdraw_studio/features/image_animation/domain/region_drawing_planner.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crypto/crypto.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:path/path.dart' as p;

import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_source_kind.dart';
import 'package:handdraw_studio/features/artwork_analysis/domain/artwork_animation_guidance.dart';
import 'package:handdraw_studio/features/artwork_analysis/application/artwork_animation_guidance_policy.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/default_artwork_path_facade.dart';
import 'package:handdraw_studio/features/artwork_analysis/infrastructure/raster_alpha_bounds_scanner.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_drawing_timeline_compiler_adapter.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_polygon_list.dart';
import 'package:handdraw_studio/features/project/domain/models/immutable_value_list.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/features/voice_guide/infrastructure/voice_guide_service.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_path_stroke_planner.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/polyline_bezier_fitter.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/auto_reveal_planner.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/opaque_raster_reveal_planner.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/outline_fill_reveal_planner.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/reference_reveal_motion_policy.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/scene_group_selector.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/drawing_timeline_service.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/region_auto_path_analyzer.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/scene_region_reveal_planner.dart';
import 'package:handdraw_studio/features/scene_split/domain/services/scene_split_stroke_orderer.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_library_repository.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/features/hand_library/infrastructure/file_hand_library_repository.dart';
import 'package:handdraw_studio/features/hand_library/infrastructure/memory_hand_library_repository.dart';
import 'package:handdraw_studio/features/hand_library/infrastructure/hand_image_loader.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/application/new_project_request.dart';
import 'package:handdraw_studio/features/editor/application/editor_document_state.dart';
import 'package:handdraw_studio/features/editor/application/history/editor_history.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_session_coordinator.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_operation_policy.dart';
import 'package:handdraw_studio/features/editor/application/transactions/document_transaction_coordinator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_scoped_document_change_detector.dart';
import 'package:handdraw_studio/features/editor/infrastructure/canonical_document_fingerprint_calculator.dart';
import 'package:handdraw_studio/features/editor/infrastructure/file_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/editor/infrastructure/memory_editor_asset_staging_store.dart';
import 'package:handdraw_studio/features/project/domain/operations/document_operation_result.dart';
import 'package:handdraw_studio/features/project/domain/operations/stroke_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/mask_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/path_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/scene_document_operations.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_allocation_context.dart';
import 'package:handdraw_studio/features/project/domain/identity/id_generator.dart';
import 'package:handdraw_studio/features/project/domain/importing/imported_artwork_draft.dart';
import 'package:handdraw_studio/features/project/domain/services/project_document_import_builder.dart';
import 'package:handdraw_studio/features/project/domain/services/artwork_placement_service.dart';
import 'package:handdraw_studio/features/project/domain/services/legacy_hand_calibration_migration.dart';
import 'package:handdraw_studio/features/project/application/container/project_container_ports.dart';
import 'package:handdraw_studio/features/project/infrastructure/container/koni_project_container_store.dart';
import 'package:handdraw_studio/features/project/infrastructure/legacy_project_view_cache.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/project/domain/operations/project_settings_operations.dart';
import 'package:handdraw_studio/features/project/domain/operations/timeline_document_operations.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/persistent_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/services/global_timeline_resolver.dart';
import 'package:handdraw_studio/features/timeline/domain/services/timeline_compiler.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/operations/camera_document_operations.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_application_service.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/semantic/domain/models/compiled_semantic_region_graph.dart';
import 'package:handdraw_studio/features/semantic/domain/services/semantic_region_compiler.dart';
import 'package:handdraw_studio/features/camera/domain/policies/camera_timeline_editing_policy.dart';
import 'package:handdraw_studio/features/camera/domain/policies/camera_view_policy.dart';
import 'package:handdraw_studio/features/camera/domain/models/camera_world_bounds.dart';
import 'package:handdraw_studio/features/camera/domain/services/quick_camera_fit_service.dart';
import 'package:handdraw_studio/features/camera/domain/services/simple_camera_view_adapter.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_zoom_in_out_preset_planner.dart';
import 'package:handdraw_studio/features/editor/domain/path_node_editor.dart';
import 'package:handdraw_studio/features/editor/domain/auto_path_result_summary.dart';
import 'package:handdraw_studio/features/editor/domain/manual_reveal_policy.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_artwork_import.dart';
import 'package:handdraw_studio/features/vector_import/domain/svg_reveal_layers.dart';

enum DrawingImportResult {
  imported,
  canceled,
  failed,
  superseded,
  alreadyInProgress,
}

final class EditorRenderSnapshot {
  EditorRenderSnapshot({
    required this.documentState,
    required this.state,
    required this.project,
    required this.timeline,
    required this.drawing,
    required this.drawingRevealBase,
    required this.svgRevealLayers,
    required this.hand,
    required this.release,
  });

  final EditorDocumentState documentState;
  final EditorState state;
  final HandDrawProject project;
  final CompiledTimeline timeline;
  final Image? drawing;
  final Image? drawingRevealBase;
  final SvgRevealLayers? svgRevealLayers;
  final Image? hand;
  final Future<void> Function() release;
}

EditorSessionCoordinator _defaultSessionCoordinator(
  ProjectContainerStore containerStore,
) => EditorSessionCoordinator(
  staging:
      const bool.fromEnvironment('FLUTTER_TEST') ||
          Platform.environment['FLUTTER_TEST'] == 'true'
      ? MemoryEditorAssetStagingStore()
      : FileEditorAssetStagingStore(
          Directory(
            '${Directory.systemTemp.path}/handdraw-studio-runtime-staging-$pid',
          ),
        ),
  containerStore: containerStore,
  fingerprints: const CanonicalDocumentFingerprintCalculator(),
  projectIds: SecureRandomIdGenerator(),
);

HandLibraryRepository _defaultHandLibraryRepository() =>
    const bool.fromEnvironment('FLUTTER_TEST') ||
        Platform.environment['FLUTTER_TEST'] == 'true'
    ? MemoryHandLibraryRepository()
    : FileHandLibraryRepository();

typedef TimelineCompileCallback =
    CompiledTimeline Function(ProjectDocument document, int documentRevision);

class EditorCubit extends Cubit<EditorState> {
  EditorCubit({
    EditorState? initialState,
    SmartPathEngine? smartPathEngine,
    ArtworkPathFacade? artworkPathFacade,
    AutoPathStrokePlanner? strokePlanner,
    AutoRevealPlanner? autoRevealPlanner,
    OpaqueRasterRevealPlanner? opaqueRasterRevealPlanner,
    OutlineFillRevealPlanner? outlineFillRevealPlanner,
    EditorFileService? fileService,
    HandLibraryRepository? handLibraryRepository,
    HandImageLoader? handImageLoader,
    VoiceGuideService? voiceGuideService,
    SceneGroupSelector? sceneGroupSelector,
    DrawingTimelineService? timelineService,
    RegionAutoPathAnalyzer? regionAutoPathAnalyzer,
    SceneRegionRevealPlanner? sceneRegionRevealPlanner,
    ProjectContainerStore? projectContainerStore,
    EditorSessionCoordinator? sessionCoordinator,
    TimelineCompileCallback? timelineCompiler,
  }) : _artworkPathFacade =
           artworkPathFacade ??
           DefaultArtworkPathFacade.standard(rasterEngine: smartPathEngine),
       _strokePlanner = strokePlanner ?? const AutoPathStrokePlanner(),
       _autoRevealPlanner = autoRevealPlanner ?? const AutoRevealPlanner(),
       _outlineFillRevealPlanner =
           outlineFillRevealPlanner ??
           OutlineFillRevealPlanner(
             fallbackPlanner:
                 opaqueRasterRevealPlanner ?? const OpaqueRasterRevealPlanner(),
           ),
       _fileService = fileService ?? const EditorFileService(),
       _handLibraryRepository =
           handLibraryRepository ?? _defaultHandLibraryRepository(),
       _handImageLoader = handImageLoader ?? const FlutterHandImageLoader(),
       _voiceGuideService = voiceGuideService ?? const VoiceGuideService(),
       _sceneGroupSelector = sceneGroupSelector ?? const SceneGroupSelector(),
       _timelineService = timelineService ?? const DrawingTimelineService(),
       _regionAutoPathAnalyzer =
           regionAutoPathAnalyzer ?? const RegionAutoPathAnalyzer(),
       _sceneRegionRevealPlanner =
           sceneRegionRevealPlanner ?? const SceneRegionRevealPlanner(),
       _sessionCoordinator =
           sessionCoordinator ??
           _defaultSessionCoordinator(
             projectContainerStore ??
                 const KoniProjectContainerStore(
                   atomicReplacer: MacosAtomicFileReplacer(),
                 ),
           ),
       _timelineCompiler =
           timelineCompiler ??
           ((document, revision) => const TimelineCompiler(
             drawingAdapter: LegacyDrawingTimelineCompilerAdapter(),
           ).compile(document: document, documentRevision: revision)),
       super(initialState ?? EditorState.initial()) {
    final configuration = state.document.handConfiguration;
    final finalSectionId = _finalDrawableSectionId(state.document);
    var keepHandVisibleAfterDrawing = false;
    if (finalSectionId != null) {
      keepHandVisibleAfterDrawing = state.document.sections
          .firstWhere((section) => section.id == finalSectionId)
          .timing
          .keepHandVisibleAfterDrawing;
    }
    _handApplicationDefaults = HandApplicationDefaults(
      scale: configuration.scale,
      rotationDegrees: configuration.rotationDegrees,
      flipX: configuration.flipX,
      keepHandVisibleAfterDrawing: keepHandVisibleAfterDrawing,
    );
    if (initialState != null) {
      final fingerprint = _sessionCoordinator.fingerprints
          .calculate(state.document)
          .persistence
          .value;
      _history.markSaved(_history.captureSaveSnapshot(fingerprint));
    }
  }

  final ArtworkPathFacade _artworkPathFacade;
  final AutoPathStrokePlanner _strokePlanner;
  final AutoRevealPlanner _autoRevealPlanner;
  final OutlineFillRevealPlanner _outlineFillRevealPlanner;
  final EditorFileService _fileService;
  final HandLibraryRepository _handLibraryRepository;
  final HandImageLoader _handImageLoader;
  HandApplicationDefaults _handApplicationDefaults =
      HandApplicationDefaults.fromPreset(BuiltInHands.defaultPreset);
  bool _handPreferencesDirty = false;
  Future<void>? _handPreferencesSaveInFlight;
  final VoiceGuideService _voiceGuideService;
  final SceneGroupSelector _sceneGroupSelector;
  final DrawingTimelineService _timelineService;
  final RegionAutoPathAnalyzer _regionAutoPathAnalyzer;
  final SceneRegionRevealPlanner _sceneRegionRevealPlanner;
  final EditorSessionCoordinator _sessionCoordinator;
  final TimelineCompileCallback _timelineCompiler;
  EditorSession? _session;
  final Map<ProjectAssetId, Uint8List> _embeddedAssetBytes = {};
  ProjectContainerLocation? _projectTarget;
  int _projectOpenGeneration = 0;
  bool _closing = false;
  final LegacyProjectViewCache _legacyProjectViews = LegacyProjectViewCache();
  final SecureRandomIdGenerator _idGenerator = SecureRandomIdGenerator();
  EditorHistory _history = EditorHistory();
  final DocumentTransactionCoordinator _transactions =
      const DocumentTransactionCoordinator(
        changeDetector: CanonicalScopedDocumentChangeDetector(),
      );
  int? _compiledTimelineRevision;
  CompiledTimeline? _compiledTimeline;
  InvalidTimelineIntervalException? _lastTimelineCompilationFailure;
  int _timelineCompilationCount = 0;

  InvalidTimelineIntervalException? get lastTimelineCompilationFailure =>
      _lastTimelineCompilationFailure;

  double get manualRevealWidth => const ManualRevealPolicy().resolve(
    projectRevealWidth: state.document.motionConfiguration.revealWidth,
    canvasHeight: state.document.canvas.height.toDouble(),
    authoredWidth: state.manualRevealWidth,
  );

  void setManualRevealWidth(double value) {
    final width = value.clamp(4.0, ManualRevealPolicy.maximumWidth);
    emit(state.copyWith(manualRevealWidth: width));
    final selectedIndex = state.selectedStrokeIndex;
    if ((state.tool != EditorTool.drawPath &&
            state.tool != EditorTool.revealText) ||
        selectedIndex == null ||
        selectedIndex < 0 ||
        selectedIndex >= state.document.strokes.length) {
      return;
    }
    final strokeId = state.document.strokes[selectedIndex].id;
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeSetReveal,
      mergeProperty: 'manual-reveal-width:${strokeId.value}',
      operation: (document) => const StrokeDocumentOperations().setRevealWidth(
        document: document,
        strokeId: strokeId,
        width: width,
      ),
      statusMessage: 'Manual reveal widened to ${width.round()} px',
    );
  }

  int _drawingImportGeneration = 0;
  _ClearedCanvasRuntime? _clearedCanvasRuntime;
  final PathNodeEditor _pathNodeEditor = const PathNodeEditor();
  int? _nodeEditStrokeIndex;
  StrokePathGeometry? _nodeEditGeometry;
  Offset? _nodeEditPrimaryPosition;
  List<SvgImportedPath> _cachedImportedSvgPaths = const [];
  Map<String, DrawingStroke> _pendingNativeStrokes = const {};
  Map<String, SceneRegion> _pendingSceneRegions = const {};
  var _sceneRegionAnalysisGeneration = 0;
  SmartPathCancellationToken? _sceneRegionCancellation;
  var _smartPathApplyGeneration = 0;
  AutoPathPlanningOperation? _autoPathPlanningOperation;
  SmartPathProcessingRecord? _pendingSmartPathProcessing;
  Stopwatch? _smartPathAnalysisStopwatch;
  Timer? _smartPathAnalysisTimer;

  HandDrawProject get project =>
      _legacyProjectViews.resolve(state.documentState);

  CompiledTimeline compileTimeline() {
    final revision = state.documentRevision.value;
    if (_compiledTimelineRevision == revision && _compiledTimeline != null) {
      return _compiledTimeline!;
    }
    late final CompiledTimeline compiled;
    try {
      compiled = _timelineCompiler(state.document, revision);
      _lastTimelineCompilationFailure = null;
    } on InvalidTimelineIntervalException catch (failure) {
      _lastTimelineCompilationFailure = failure;
      final lastGood = _compiledTimeline;
      if (lastGood != null) return lastGood;
      rethrow;
    }
    _timelineCompilationCount++;
    _compiledTimelineRevision = revision;
    _compiledTimeline = compiled;
    return compiled;
  }

  CompiledSemanticRegionGraph compileSemanticGraph() =>
      const SemanticRegionCompiler().compile(state.document);

  bool setAutoDirectorSettings(ProjectAutoDirectorSettings settings) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.settingsSetAutoDirector,
        mergeProperty: 'autoDirector.settings',
        operation: (document) => DocumentOperationResult.success(
          document: document.copyWith(autoDirectorSettings: settings),
          affectedScopes: const {DocumentScope.settings},
          summary: DocumentChangeSummary(action: 'autoDirector.settings'),
        ),
      );

  AutoDirectorApplyResult applyAutoDirectorPlan(
    AutoDirectorPlan plan, {
    ProjectAutoDirectorSettings? settings,
  }) {
    final service = AutoDirectorApplicationService();
    final result = service.applyPlan(
      plan: plan,
      currentDocument: state.document,
      currentTimeline: compileTimeline(),
      currentGraph: compileSemanticGraph(),
      allocation: _allocation(),
    );
    if (!result.isSuccess) return result;
    final committed = _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      operation: (_) {
        final operation = result.operation!;
        if (settings == null) return operation;
        return DocumentOperationResult.success(
          document: operation.document.copyWith(autoDirectorSettings: settings),
          affectedScopes: {...operation.affectedScopes, DocumentScope.settings},
          summary: DocumentChangeSummary(
            action: 'autoDirector.apply',
            entityIds: operation.summary.entityIds,
            changeCount: operation.summary.changeCount,
          ),
        );
      },
      statusMessage: 'Auto Camera applied',
    );
    return committed
        ? result
        : const AutoDirectorApplyResult.failure(
            AutoDirectorApplyFailureCode.invalidPlan,
            'Auto Camera transaction was rejected.',
          );
  }

  int get timelineCompilationCount => _timelineCompilationCount;

  EditorHistory get history => _history;
  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;
  bool get isDirty => _history.isDirty(
    fingerprintIfNeeded: () => _sessionCoordinator.fingerprints
        .calculate(state.document)
        .persistence
        .value,
  );

  Map<ProjectAssetId, EditorAssetStreamSource> _embeddedSessionSources(
    ProjectDocument document,
  ) => {
    for (final asset in document.assets)
      if (asset.storagePolicy == ProjectAssetStoragePolicy.embedded)
        if (_embeddedAssetBytes[asset.id] case final bytes?)
          asset.id: _MemoryProjectAssetSource(Uint8List.fromList(bytes)),
  };

  Future<EditorSession> _adoptDocumentSession({
    required EditorDocumentState documentState,
    EditorHistory? history,
    ProjectContainerLocation? target,
    bool clean = false,
  }) => _sessionCoordinator.createFromDocument(
    state: documentState,
    embeddedSources: _embeddedSessionSources(documentState.document),
    history: history,
    target: target,
    clean: clean,
  );

  Future<void> _installSession(EditorSession next) async {
    final previous = _session;
    _session = next;
    _history = next.history;
    if (previous != null && !identical(previous, next)) {
      await _sessionCoordinator.close(
        previous,
        clearHistory: !identical(previous.history, next.history),
      );
    }
  }

  Future<void> _bootstrapLegacyNewProject(
    EditorDocumentState initial,
    EditorHistory history,
  ) async {
    final candidate = await _adoptDocumentSession(
      documentState: initial,
      history: history,
    );
    if (_closing ||
        isClosed ||
        state.document.id != initial.document.id ||
        _session != null) {
      await _sessionCoordinator.close(candidate, clearHistory: false);
      return;
    }
    await _installSession(candidate);
  }

  Future<EditorRenderSnapshot> acquireRenderSnapshot({
    required StagedAssetReferenceKind kind,
  }) async {
    assert(
      kind == StagedAssetReferenceKind.preview ||
          kind == StagedAssetReferenceKind.export,
    );
    final captured = state;
    // Capture before yielding: edits during asset staging must not change the
    // snapshot's timing. Reuse the immutable timeline already used by controls.
    final capturedTimeline = compileTimeline();
    final compilationFailure = _lastTimelineCompilationFailure;
    if (compilationFailure != null) throw compilationFailure;
    final snapshotSession = await _sessionCoordinator.createFromDocument(
      state: captured.documentState,
      embeddedSources: _embeddedSessionSources(captured.document),
    );
    final leases = <StagedAssetLease>[];
    try {
      for (final asset in captured.document.assets) {
        leases.add(
          asset.storagePolicy == ProjectAssetStoragePolicy.external
              ? await _sessionCoordinator.staging.acquireVerifiedSnapshot(
                  sessionId: snapshotSession.id,
                  assetId: asset.id,
                  kind: kind,
                )
              : await _sessionCoordinator.staging.acquire(
                  sessionId: snapshotSession.id,
                  assetId: asset.id,
                  kind: kind,
                ),
        );
      }
      final drawing = captured.drawingImage?.clone();
      final reveal = captured.drawingRevealBaseImage?.clone();
      final hand = captured.handImage?.clone();
      final layers = captured.svgRevealLayers == null
          ? null
          : SvgRevealLayers(
              fills: captured.svgRevealLayers!.fills.clone(),
              strokes: captured.svgRevealLayers!.strokes.clone(),
              globalStrokes: captured.svgRevealLayers!.globalStrokes?.clone(),
            );
      var released = false;
      return EditorRenderSnapshot(
        documentState: captured.documentState,
        state: captured.copyWith(
          drawingImage: drawing,
          drawingRevealBaseImage: reveal,
          svgRevealLayers: layers,
          handImage: hand,
        ),
        project: _legacyProjectViews.resolve(captured.documentState),
        timeline: capturedTimeline,
        drawing: drawing,
        drawingRevealBase: reveal,
        svgRevealLayers: layers,
        hand: hand,
        release: () async {
          if (released) return;
          released = true;
          drawing?.dispose();
          reveal?.dispose();
          layers?.dispose();
          hand?.dispose();
          for (final lease in leases) {
            await lease.release();
          }
          await _sessionCoordinator.close(snapshotSession);
        },
      );
    } catch (_) {
      for (final lease in leases) {
        await lease.release();
      }
      await _sessionCoordinator.close(snapshotSession);
      rethrow;
    }
  }

  bool _executeDocumentOperation({
    required DocumentOperationKind kind,
    required PureDocumentOperation operation,
    String? mergeProperty,
    String? statusMessage,
  }) {
    final result = _transactions.execute(
      current: state.documentState,
      history: _history,
      expectedProjectId: state.document.id,
      expectedRevision: state.documentRevision,
      kind: kind,
      operation: (document) {
        final candidate = operation(document);
        if (!candidate.isSuccess ||
            !candidate.affectedScopes.contains(DocumentScope.sections)) {
          return candidate;
        }
        final adjusted = _applyPreferenceToNewFinalSection(
          before: document,
          after: candidate.document,
        );
        if (identical(adjusted, candidate.document)) return candidate;
        return DocumentOperationResult.success(
          document: adjusted,
          affectedScopes: candidate.affectedScopes,
          summary: candidate.summary,
        );
      },
      mergeProperty: mergeProperty,
    );
    if (!result.isSuccess) {
      emit(
        state.copyWith(
          statusMessage:
              result.failure?.message ?? 'The document operation failed.',
        ),
      );
      return false;
    }
    if (result.noOp) return false;
    emit(
      state.copyWith(
        documentState: result.state,
        statusMessage: statusMessage ?? state.statusMessage,
      ),
    );
    return true;
  }

  ProjectDocument _applyPreferenceToNewFinalSection({
    required ProjectDocument before,
    required ProjectDocument after,
  }) {
    final previousFinal = _finalDrawableSectionId(before);
    final nextFinal = _finalDrawableSectionId(after);
    if (nextFinal == null || nextFinal == previousFinal) return after;
    return _applyKeepPreferenceToFinalSection(after);
  }

  ProjectDocument _applyKeepPreferenceToFinalSection(ProjectDocument document) {
    final finalSectionId = _finalDrawableSectionId(document);
    if (finalSectionId == null) return document;
    final preferred = _handApplicationDefaults.keepHandVisibleAfterDrawing;
    final section = document.sections.firstWhere(
      (candidate) => candidate.id == finalSectionId,
    );
    if (section.timing.keepHandVisibleAfterDrawing == preferred) {
      return document;
    }
    return document.copyWith(
      sections: [
        for (final candidate in document.sections)
          candidate.id == finalSectionId
              ? candidate.copyWith(
                  timing: candidate.timing.copyWith(
                    keepHandVisibleAfterDrawing: preferred,
                  ),
                )
              : candidate,
      ],
    );
  }

  SectionId? _finalDrawableSectionId(ProjectDocument document) {
    for (final sectionId in document.sectionOrder.reversed) {
      if (document.strokes.any(
        (stroke) => !stroke.hidden && stroke.sectionId == sectionId,
      )) {
        return sectionId;
      }
    }
    return null;
  }

  IdAllocationContext _allocation() => IdAllocationContext(
    generator: _idGenerator,
    usedIds: [
      state.document.id,
      ...state.document.assets.map((item) => item.id),
      ...state.document.strokes.map((item) => item.id),
      for (final stroke in state.document.strokes)
        ...stroke.pausePoints.map((item) => item.id),
      ...state.document.sections.map((item) => item.id),
      ...state.document.scenes.map((item) => item.id),
      ...state.document.audioTracks.map((item) => item.id),
      if (state.document.cameraTrack case final track?) track.id,
      if (state.document.cameraTrack case final track?)
        ...track.shots.map((item) => item.id),
      if (state.document.cameraTrack case final track?)
        ...track.shots.expand(
          (item) => item.keyframes.map((keyframe) => keyframe.id),
        ),
    ],
  );

  bool _replaceDocument({
    required DocumentOperationKind kind,
    required ProjectDocument Function(ProjectDocument document) update,
    required Set<DocumentScope> affectedScopes,
    required String action,
    Iterable<String> entityIds = const [],
    String? statusMessage,
    String? mergeProperty,
  }) => _executeDocumentOperation(
    kind: kind,
    statusMessage: statusMessage,
    mergeProperty: mergeProperty,
    operation: (document) => DocumentOperationResult.success(
      document: update(document),
      affectedScopes: affectedScopes,
      summary: DocumentChangeSummary(
        action: action,
        entityIds: entityIds,
        changeCount: 1,
      ),
    ),
  );

  Image? get drawingImage => state.drawingImage;
  ProjectArtworkPlacement? get artworkPlacement =>
      state.document.artworkPlacement;

  bool setArtworkPlacement(ProjectArtworkPlacement placement) =>
      _replaceDocument(
        kind: DocumentOperationKind.settingsSetArtworkPlacement,
        update: (document) => document.copyWith(artworkPlacement: placement),
        affectedScopes: const {DocumentScope.assets},
        action: 'set-artwork-placement',
        entityIds: [if (state.document.artworkAssetId case final id?) id.value],
        statusMessage: 'Artwork placement updated.',
        mergeProperty: 'artwork-placement',
      );

  bool applyArtworkPlacementMode(ArtworkPlacementMode mode) {
    final placement = artworkPlacement;
    if (placement == null) return false;
    return setArtworkPlacement(
      const ArtworkPlacementService().applyMode(
        placement: placement,
        canvas: state.document.canvas,
        mode: mode,
      ),
    );
  }

  bool setArtworkImportIntent(ArtworkImportIntent intent) {
    final placement = artworkPlacement;
    if (placement == null) return false;
    if (intent == ArtworkImportIntent.fullScene) {
      // Full-scene means the authored destination remains untouched.
      return setArtworkPlacement(placement.copyWith(importIntent: intent));
    }
    final fitted = const ArtworkPlacementService().applyMode(
      placement: placement,
      canvas: state.document.canvas,
      mode: ArtworkPlacementMode.fitVisible,
    );
    return setArtworkPlacement(fitted.copyWith(importIntent: intent));
  }

  bool centerArtwork({bool horizontal = true, bool vertical = true}) {
    final placement = artworkPlacement;
    if (placement == null) return false;
    final rect = placement.destination;
    final width = rect.right - rect.left;
    final height = rect.bottom - rect.top;
    final left = horizontal
        ? (state.document.canvas.width - width) / 2
        : rect.left;
    final top = vertical
        ? (state.document.canvas.height - height) / 2
        : rect.top;
    return setArtworkPlacement(
      placement.copyWith(
        destination: DocumentRect(
          left: left,
          top: top,
          right: left + width,
          bottom: top + height,
        ),
      ),
    );
  }

  void previewArtworkDestination(DocumentRect destination) {
    if (artworkPlacement == null) return;
    emit(state.copyWith(transientArtworkDestination: destination));
  }

  void commitArtworkDestination() {
    final destination = state.transientArtworkDestination;
    final placement = artworkPlacement;
    if (destination == null || placement == null) return;
    emit(state.copyWith(transientArtworkDestination: null));
    setArtworkPlacement(placement.copyWith(destination: destination));
  }

  void cancelArtworkDestinationPreview() {
    if (state.transientArtworkDestination == null) return;
    emit(state.copyWith(transientArtworkDestination: null));
  }

  Image? get drawingRevealBaseImage => state.drawingRevealBaseImage;
  SvgRevealLayers? get svgRevealLayers => state.svgRevealLayers;
  Image? get handImage => state.handImage;
  EditorTool get tool => state.tool;
  List<Offset> get activeStroke => state.activeStroke;
  int? get selectedStrokeIndex => state.selectedStrokeIndex;
  DrawingStroke? get selectedStroke {
    final index = state.selectedStrokeIndex;
    if (index == null || index < 0 || index >= project.strokes.length) {
      return null;
    }
    return project.strokes[index];
  }

  PathNodeReference? get selectedPathNode => state.selectedPathNode;
  String? get selectedTimingSectionKey => state.selectedTimingSectionKey;
  List<SmartPathSection> get smartSections => state.smartSections;
  AutoPathResultSummary? get autoPathResult => state.autoPathResult;
  String? get selectedSmartSectionId => state.selectedSmartSectionId;
  SmartPathSection? get selectedSmartSection => state.selectedSmartSection;
  Set<String> get selectedTimelineSectionIds =>
      state.selectedTimelineSectionIds;
  String? get selectedTimelineSceneId => state.selectedTimelineSceneId;

  List<String> get timelineAvailableSectionIds => state.smartSections.isNotEmpty
      ? state.smartSections.map((section) => section.id).toList(growable: false)
      : _appliedTimelineSectionIds;

  List<String> get timelineSectionOrder => _timelineService.resolveOrder(
    availableSectionIds: timelineAvailableSectionIds,
    preferredOrder: project.timelineSectionOrder,
  );

  bool get keepHandVisibleAfterDrawing {
    final sectionKey = _finalDrawableSectionKey;
    return sectionKey == null
        ? _handApplicationDefaults.keepHandVisibleAfterDrawing
        : sectionTiming(sectionKey).keepHandVisibleAfterDrawing;
  }

  List<DrawingSceneGroup> get timelineSceneGroups {
    if (state.smartSections.isNotEmpty) {
      return [
        for (final scene in state.sceneDrafts)
          DrawingSceneGroup(
            id: scene.id,
            name: scene.name,
            sectionIds: scene.sectionIds,
            locked: scene.locked,
            collapsed: state.collapsedTimelineSceneIds.contains(scene.id),
          ),
      ];
    }
    final membersByGroup = <String, List<String>>{};
    for (final stroke in project.strokes) {
      final groupId = stroke.sceneGroupId;
      if (groupId == null) continue;
      final members = membersByGroup.putIfAbsent(groupId, () => []);
      final key = _appliedTimelineKey(stroke);
      if (!members.contains(key)) members.add(key);
    }
    return [
      for (final group in project.sceneGroups)
        if (membersByGroup[group.id]?.isNotEmpty ?? false)
          group.copyWith(sectionIds: membersByGroup[group.id]),
    ];
  }

  List<DrawingTimelineNode> get timelineNodes => _timelineService.buildNodes(
    order: timelineSectionOrder,
    groups: timelineSceneGroups,
  );

  Map<String, DrawingTimelineRange> get timelineSectionRanges => {
    for (final range in _timelineService.resolveRanges(
      project: project,
      order: timelineSectionOrder,
      smartSections: state.smartSections,
    ))
      range.sectionId: range,
  };

  Rect? timelineSectionBounds(String sectionId) =>
      _timelineService.resolveSectionBounds(
        sectionId: sectionId,
        smartSections: state.smartSections,
        strokes: project.strokes,
      );

  List<String> get _appliedTimelineSectionIds {
    final seen = <String>{};
    return [
      for (final stroke in project.strokes)
        if (seen.add(_appliedTimelineKey(stroke))) _appliedTimelineKey(stroke),
    ];
  }

  String _appliedTimelineKey(DrawingStroke stroke) =>
      stroke.sectionId ?? 'stroke:${stroke.id}';
  bool get isAnalyzingSmartPaths => state.isAnalyzingSmartPaths;
  bool get isAnalyzingSmartScenes =>
      state.isAnalyzingSmartPaths && _sceneRegionCancellation != null;
  String get statusMessage => state.statusMessage;
  bool get hasDrawing => state.hasDrawing;
  bool get hasHand => state.hasHand;
  bool get hasSmartSections => state.hasSmartSections;
  bool get hasCanvasContent => state.hasCanvasContent;
  bool get canPreview => state.canPreview;
  List<HandPreset> get handPresets => state.handPresets;
  HandPreset? get selectedHandPreset => state.selectedHandPreset;
  Offset get calibrationPenTip {
    final preset = state.selectedHandPreset;
    return preset != null && project.handPresetId != preset.id
        ? preset.penTip
        : project.penTip;
  }

  bool get calibrationHandFlipX {
    final preset = state.selectedHandPreset;
    return preset != null && project.handPresetId != preset.id
        ? preset.flipX
        : project.handFlipX;
  }

  bool get isHandLibraryLoading => state.isHandLibraryLoading;
  bool get isVoiceGuideLoading => state.isVoiceGuideLoading;
  bool get isVoiceGuideMissing => state.isVoiceGuideMissing;
  VoiceGuide? get voiceGuide => project.voiceGuide;
  String get activeHandName {
    final projectPresetId = project.handPresetId;
    for (final preset in state.handPresets) {
      if (preset.id == projectPresetId) return preset.name;
    }
    final path = project.handImagePath;
    if (path == null) return 'Not selected';
    return path.split('/').last;
  }

  Future<void> initializeHandLibrary() async {
    emit(state.copyWith(isHandLibraryLoading: true));
    try {
      final library = await _handLibraryRepository.load();
      final preset = library.selectedPreset;
      final defaults = library.resolvedApplicationDefaults;
      final loaded = await _handImageLoader.load(preset);
      if (isClosed) return;
      _activateHandPreset(
        library: library,
        preset: preset,
        defaults: defaults,
        loaded: loaded,
        statusMessage: 'Hand library ready',
      );
      _applyKeepHandPreferenceToCurrentFinalSection();
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isHandLibraryLoading: false,
          statusMessage: 'Could not load the hand library: $error',
        ),
      );
    }
  }

  Future<DrawingImportResult> importDrawing({
    ImportedEditorAsset? preparedAsset,
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async {
    // A native open panel is a single-flight operation. Starting another one
    // while the first is visible can leave one panel inactive and used to make
    // the first file click focus the window instead of selecting the row. It
    // would also supersede a perfectly valid result from the original picker.
    if (state.isDrawingImporting) {
      return DrawingImportResult.alreadyInProgress;
    }
    _projectOpenGeneration++;
    final generation = ++_drawingImportGeneration;
    final previousStatus = state.statusMessage;
    emit(
      state.copyWith(
        isDrawingImporting: true,
        statusMessage: 'Importing drawing…',
      ),
    );
    ImportedEditorAsset? asset;
    try {
      asset = preparedAsset ?? await _fileService.pickDrawing(copy: copy);
    } catch (error) {
      if (_closing || isClosed || generation != _drawingImportGeneration) {
        return DrawingImportResult.superseded;
      }
      emit(
        state.copyWith(
          isDrawingImporting: false,
          statusMessage: 'Could not import drawing: $error',
        ),
      );
      return DrawingImportResult.failed;
    }
    if (_closing || isClosed || generation != _drawingImportGeneration) {
      asset?.image.dispose();
      asset?.revealBaseImage?.dispose();
      asset?.svgRevealLayers?.strokes.dispose();
      asset?.svgRevealLayers?.globalStrokes?.dispose();
      return DrawingImportResult.superseded;
    }
    if (asset == null) {
      emit(
        state.copyWith(
          isDrawingImporting: false,
          statusMessage: previousStatus,
        ),
      );
      return DrawingImportResult.canceled;
    }
    final sourceEncoded = asset.sourceEncoded ?? asset.encoded;
    final sourceBytes = _decodeImportedSource(sourceEncoded);
    var importedDocument = const ProjectDocumentImportBuilder().build(
      ImportedArtworkDraft(
        title: p.basenameWithoutExtension(asset.path),
        canvas: state.document.canvas,
        frameRate: state.document.frameRate,
        duration: state.document.duration,
        asset: ImportedArtworkAssetDraft(
          originalFileName: p.basename(asset.path),
          sourceType: asset.sourceKind == ArtworkSourceKind.svg
              ? ArtworkSourceType.svg
              : ArtworkSourceType.raster,
          storagePolicy: ProjectAssetStoragePolicy.embedded,
          contentHash: 'sha256:${sha256.convert(sourceBytes)}',
          mediaType: asset.sourceKind == ArtworkSourceKind.svg
              ? 'image/svg+xml'
              : 'image/png',
        ),
        sections: const [],
      ),
      ids: _idGenerator,
    );
    final visibleArtworkBounds = _visibleArtworkBounds(asset);
    importedDocument = importedDocument.copyWith(
      motionConfiguration: state.document.motionConfiguration,
      artworkPlacement: const ArtworkPlacementService().createDefault(
        canvas: importedDocument.canvas,
        encodedWidth: asset.image.width.toDouble(),
        encodedHeight: asset.image.height.toDouble(),
        visibleBounds: visibleArtworkBounds,
      ),
      // Importing artwork replaces the canvas document, but it must not replace
      // the selected hand with the Technical Pen defaults while keeping the old
      // hand image in view. Rebuild the configuration from the selected preset
      // so its image, label, calibration, size, rotation, and flip stay atomic.
      handConfiguration: _selectedHandConfigurationForNewDocument(),
    );
    late final EditorSession nextSession;
    try {
      nextSession = await _sessionCoordinator.createFromDocument(
        state: EditorDocumentState(document: importedDocument),
        embeddedSources: {
          importedDocument.artworkAssetId!: _MemoryProjectAssetSource(
            sourceBytes,
          ),
        },
      );
    } catch (error) {
      asset.image.dispose();
      asset.revealBaseImage?.dispose();
      asset.svgRevealLayers?.strokes.dispose();
      asset.svgRevealLayers?.globalStrokes?.dispose();
      if (!isClosed && generation == _drawingImportGeneration) {
        emit(
          state.copyWith(
            isDrawingImporting: false,
            statusMessage: 'Could not stage imported drawing: $error',
          ),
        );
      }
      return DrawingImportResult.failed;
    }
    if (_closing || isClosed || generation != _drawingImportGeneration) {
      await _sessionCoordinator.close(nextSession);
      asset.image.dispose();
      asset.revealBaseImage?.dispose();
      asset.svgRevealLayers?.strokes.dispose();
      asset.svgRevealLayers?.globalStrokes?.dispose();
      return DrawingImportResult.superseded;
    }
    _cachedImportedSvgPaths = List.unmodifiable(asset.vectorPaths);
    _pendingNativeStrokes = const {};
    _clearedCanvasRuntime = null;
    _embeddedAssetBytes
      ..clear()
      ..[importedDocument.artworkAssetId!] = Uint8List.fromList(sourceBytes);
    _projectTarget = null;
    final retiringSession = _installSession(nextSession);
    emit(
      state.copyWith(
        documentState: EditorDocumentState(document: importedDocument),
        drawingImage: asset.image,
        drawingAnalysisEncoded: sourceEncoded,
        drawingRevealBaseImage: asset.revealBaseImage,
        svgRevealLayers: asset.svgRevealLayers,
        artworkAnimationGuidance: const ArtworkAnimationGuidancePolicy()
            .resolve(
              sourceKind: asset.sourceKind,
              rasterAnalysis: asset.rasterAlphaBounds,
            ),
        activeStroke: const [],
        selectedStrokeIndex: null,
        hoveredStrokeIndex: null,
        selectedPathNode: null,
        selectedPathNodes: const {},
        selectedTimingSectionKey: null,
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        selectedTimelineSectionIds: const {},
        selectedTimelineSceneId: null,
        sceneDrafts: const [],
        suggestionOrderCustomized: false,
        collapsedTimelineSceneIds: const {},
        isDrawingImporting: false,
        canvasRevision: state.canvasRevision + 1,
        tool: EditorTool.select,
        statusMessage: asset.sourceKind.name == 'svg'
            ? 'SVG imported without animation. Choose Auto Path, Auto Reveal, or draw manually.'
            : 'Drawing imported without animation. Choose Auto Path, Auto Reveal, or draw manually.',
      ),
    );
    await retiringSession;
    return DrawingImportResult.imported;
  }

  Uint8List _decodeImportedSource(String encoded) {
    try {
      return base64Decode(encoded);
    } on FormatException {
      return Uint8List.fromList(utf8.encode(encoded));
    }
  }

  Future<bool> importHand({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async {
    final asset = await _fileService.pickHand(copy: copy);
    if (asset == null) return false;
    final current = HandLibrarySnapshot(
      presets: state.handPresets,
      selectedPresetId:
          state.selectedHandPresetId ?? BuiltInHands.defaultPresetId,
      applicationDefaults: _handApplicationDefaults,
    );
    try {
      final library = await _handLibraryRepository.importCustom(
        current: current,
        sourcePath: asset.path,
        bytes: base64Decode(asset.encoded),
      );
      final preset = library.selectedPreset;
      final defaults = HandApplicationDefaults.fromPreset(
        preset,
        keepHandVisibleAfterDrawing:
            _handApplicationDefaults.keepHandVisibleAfterDrawing,
      );
      final configuredLibrary = library.copyWith(applicationDefaults: defaults);
      await _handLibraryRepository.save(configuredLibrary);
      _activateHandPreset(
        library: configuredLibrary,
        preset: preset,
        defaults: defaults,
        loaded: LoadedHandImage(
          bytes: base64Decode(asset.encoded),
          image: asset.image,
        ),
        statusMessage: 'Custom hand saved. Calibrate the pen tip once.',
      );
      return true;
    } catch (error) {
      emit(state.copyWith(statusMessage: 'Could not import hand: $error'));
      return false;
    }
  }

  Future<void> selectHandPreset(String presetId) async {
    HandPreset? preset;
    for (final candidate in state.handPresets) {
      if (candidate.id == presetId) {
        preset = candidate;
        break;
      }
    }
    if (preset == null || state.isHandLibraryLoading) return;
    emit(state.copyWith(isHandLibraryLoading: true));
    try {
      final loaded = await _handImageLoader.load(preset);
      final defaults = HandApplicationDefaults.fromPreset(
        preset,
        keepHandVisibleAfterDrawing:
            _handApplicationDefaults.keepHandVisibleAfterDrawing,
      );
      final library = HandLibrarySnapshot(
        presets: state.handPresets,
        selectedPresetId: preset.id,
        applicationDefaults: defaults,
      );
      await _handLibraryRepository.save(library);
      if (isClosed) return;
      _activateHandPreset(
        library: library,
        preset: preset,
        defaults: defaults,
        loaded: loaded,
        statusMessage: '${preset.name} selected',
      );
    } catch (error) {
      if (isClosed) return;
      emit(
        state.copyWith(
          isHandLibraryLoading: false,
          statusMessage: 'Could not select hand: $error',
        ),
      );
    }
  }

  void _activateHandPreset({
    required HandLibrarySnapshot library,
    required HandPreset preset,
    required HandApplicationDefaults defaults,
    required LoadedHandImage loaded,
    required String statusMessage,
  }) {
    _handApplicationDefaults = defaults;
    _executeDocumentOperation(
      kind: DocumentOperationKind.settingsSetHand,
      operation: (document) => const ProjectSettingsOperations().setHand(
        document: document,
        configuration: document.handConfiguration.copyWith(
          assetId: null,
          presetId: preset.id,
          penTip: DocumentPoint(preset.penTip.dx, preset.penTip.dy),
          scale: defaults.scale,
          rotationDegrees: defaults.rotationDegrees,
          flipX: defaults.flipX,
        ),
      ),
      statusMessage: statusMessage,
    );
    emit(
      state.copyWith(
        handImage: loaded.image,
        handPresets: library.presets,
        selectedHandPresetId: preset.id,
        isHandLibraryLoading: false,
        statusMessage: statusMessage,
      ),
    );
  }

  void setTool(EditorTool tool) {
    if (tool == EditorTool.sceneGroup && state.smartSections.isEmpty) {
      emit(
        state.copyWith(
          statusMessage: 'Run Auto Path before creating scene groups.',
        ),
      );
      return;
    }
    if (tool == EditorTool.drawPath || tool == EditorTool.revealText) {
      _repairSelectedHandConfigurationMismatch();
    }
    emit(
      state.copyWith(
        tool: tool,
        activeStroke: const [],
        selectedStrokeIndex:
            tool == EditorTool.select ||
                tool == EditorTool.maskReveal ||
                tool == EditorTool.maskErase
            ? state.selectedStrokeIndex
            : null,
        selectedPathNode: null,
        selectedPathNodes: const {},
      ),
    );
  }

  ProjectHandConfiguration _selectedHandConfigurationForNewDocument() {
    final preset = state.selectedHandPreset;
    final current = state.document.handConfiguration;
    if (preset == null ||
        (current.presetId != null &&
            current.presetId != preset.id &&
            preset.id == BuiltInHands.defaultPresetId)) {
      return current;
    }
    return ProjectHandConfiguration(
      presetId: preset.id,
      scale: _handApplicationDefaults.scale,
      rotationDegrees: _handApplicationDefaults.rotationDegrees,
      flipX: _handApplicationDefaults.flipX,
      penTip: DocumentPoint(preset.penTip.dx, preset.penTip.dy),
    );
  }

  void _repairSelectedHandConfigurationMismatch() {
    final preset = state.selectedHandPreset;
    final configuration = state.document.handConfiguration;
    if (preset == null || configuration.presetId == preset.id) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.settingsSetHand,
      operation: (document) => const ProjectSettingsOperations().setHand(
        document: document,
        configuration: document.handConfiguration.copyWith(
          assetId: null,
          presetId: preset.id,
          penTip: DocumentPoint(preset.penTip.dx, preset.penTip.dy),
          scale: _handApplicationDefaults.scale,
          rotationDegrees: _handApplicationDefaults.rotationDegrees,
          flipX: _handApplicationDefaults.flipX,
        ),
      ),
      statusMessage: 'Selected hand calibration restored',
    );
  }

  void beginStroke(Offset localPosition, Rect artworkRect) {
    if (!state.hasDrawing || state.tool == EditorTool.select) return;
    if (_isMaskTool(state.tool)) {
      final selected = state.selectedStrokeIndex;
      if (selected == null ||
          selected < 0 ||
          selected >= project.strokes.length) {
        emit(
          state.copyWith(
            statusMessage: 'Select a path before editing its reveal mask.',
          ),
        );
        return;
      }
      beginSectionTimingEdit();
    }
    emit(
      state.copyWith(
        activeStroke: [_toNormalized(localPosition, artworkRect, clamp: true)],
      ),
    );
  }

  void updateStroke(Offset localPosition, Rect artworkRect) {
    if (state.activeStroke.isEmpty) return;
    final point = _toNormalized(localPosition, artworkRect);
    if ((point - state.activeStroke.last).distance < 0.0025) return;
    emit(state.copyWith(activeStroke: [...state.activeStroke, point]));
  }

  void cancelActiveStroke() {
    if (state.activeStroke.isEmpty) return;
    emit(
      state.copyWith(activeStroke: const [], statusMessage: 'Edit canceled'),
    );
  }

  void endStroke() {
    if (state.activeStroke.length < 2) {
      emit(state.copyWith(activeStroke: const []));
      if (_isMaskTool(state.tool)) commitSectionTimingEdit();
      return;
    }
    if (_isMaskTool(state.tool)) {
      _commitVectorMaskStroke();
      return;
    }
    if (state.tool == EditorTool.sceneGroup) {
      _commitSceneGroupSelection();
      return;
    }
    final reducedPoints = _reducePoints(state.activeStroke);
    final geometry = const PolylineBezierFitter().fit(reducedPoints);
    final target = _manualStrokeTarget(state.document);
    final allocation = _allocation();
    final strokeId = allocation.strokeId();
    final existingSection = target.section;
    final sectionId = existingSection?.id ?? allocation.sectionId();
    final strokeName = 'Stroke ${state.document.strokes.length + 1}';
    final changed = _replaceDocument(
      kind: DocumentOperationKind.strokeAdd,
      update: (document) {
        final stroke = ProjectStroke(
          id: strokeId,
          sectionId: sectionId,
          name: strokeName,
          assetId: document.artworkAssetId,
          points: [
            for (final point in reducedPoints)
              DocumentPoint(point.dx, point.dy),
          ],
          geometry: geometry,
          revealOnly: state.tool == EditorTool.revealText,
          revealStyle: DocumentRevealStyle.brush,
          revealWidth:
              state.tool == EditorTool.drawPath ||
                  state.tool == EditorTool.revealText
              ? manualRevealWidth
              : document.motionConfiguration.revealWidth,
          clipPolygons: target.clipPolygons,
        );
        final strokes = List<ProjectStroke>.of(document.strokes);
        final insertionIndex = target.insertionSectionIds.isEmpty
            ? strokes.length
            : strokes.lastIndexWhere(
                    (item) =>
                        target.insertionSectionIds.contains(item.sectionId),
                  ) +
                  1;
        strokes.insert(insertionIndex, stroke);
        return document.copyWith(
          strokes: strokes,
          sections: existingSection == null
              ? [
                  ...document.sections,
                  ProjectSection(
                    id: sectionId,
                    name: 'Manual Drawing',
                    strokeIds: [strokeId],
                  ),
                ]
              : [
                  for (final section in document.sections)
                    section.id == sectionId
                        ? section.copyWith(
                            strokeIds: [...section.strokeIds, strokeId],
                          )
                        : section,
                ],
          sectionOrder: existingSection == null
              ? [...document.sectionOrder, sectionId]
              : document.sectionOrder,
        );
      },
      affectedScopes: const {
        DocumentScope.strokes,
        DocumentScope.sections,
        DocumentScope.ordering,
      },
      action: 'add-manual-stroke',
      entityIds: [strokeId.value, sectionId.value],
    );
    if (!changed) return;
    final selectedIndex = state.document.strokes.indexWhere(
      (stroke) => stroke.id == strokeId,
    );
    final strokeCount = state.document.strokes.length;
    emit(
      state.copyWith(
        activeStroke: const [],
        selectedStrokeIndex: selectedIndex < 0 ? null : selectedIndex,
        statusMessage: state.tool == EditorTool.revealText
            ? 'Smooth text reveal added'
            : '$strokeCount stroke(s) ready',
      ),
    );
  }

  _ManualStrokeTarget _manualStrokeTarget(ProjectDocument document) {
    final selectedSceneId = state.selectedTimelineSceneId;
    ProjectScene? selectedScene;
    if (selectedSceneId != null) {
      for (final scene in document.scenes) {
        if (scene.id.value == selectedSceneId) {
          selectedScene = scene;
          break;
        }
      }
    }
    if (selectedScene != null && selectedScene.sectionIds.isNotEmpty) {
      final sectionIds = selectedScene.sectionIds.toSet();
      ProjectSection? section;
      for (final sectionId in selectedScene.sectionIds.reversed) {
        section = document.sections
            .where((candidate) => candidate.id == sectionId)
            .firstOrNull;
        if (section != null) break;
      }
      return _ManualStrokeTarget(
        section: section,
        insertionSectionIds: sectionIds,
        clipPolygons: _manualSceneClip(document, sectionIds),
      );
    }

    final selectedSectionIds = state.selectedTimelineSectionIds;
    for (final sectionId in document.sectionOrder) {
      if (!selectedSectionIds.contains(sectionId.value)) continue;
      final section = document.sections
          .where((candidate) => candidate.id == sectionId)
          .firstOrNull;
      if (section != null) {
        return _ManualStrokeTarget(
          section: section,
          insertionSectionIds: {section.id},
          clipPolygons: _manualSceneClip(document, {section.id}),
        );
      }
    }

    return _ManualStrokeTarget(
      section: document.sections.firstOrNull,
      insertionSectionIds: const {},
      clipPolygons: const [],
    );
  }

  List<List<DocumentPoint>> _manualSceneClip(
    ProjectDocument document,
    Set<SectionId> sectionIds,
  ) {
    for (final stroke in document.strokes.reversed) {
      if (sectionIds.contains(stroke.sectionId) &&
          stroke.clipPolygons.isNotEmpty) {
        return stroke.clipPolygons;
      }
    }
    return const [];
  }

  void _commitSceneGroupSelection() {
    final enclosure = _reducePoints(state.activeStroke);
    final selectedIds = _sceneGroupSelector.select(
      enclosure: enclosure,
      sections: state.smartSections,
    );
    if (selectedIds.isEmpty) {
      emit(
        state.copyWith(
          activeStroke: const [],
          statusMessage: 'The enclosure did not contain an Auto Path section.',
        ),
      );
      return;
    }
    _createTimelineGroup(selectedIds, fromCanvas: true);
  }

  void toggleTimelineSectionSelection(String sectionId) {
    if (!timelineAvailableSectionIds.contains(sectionId)) return;
    final selected = state.selectedTimelineSectionIds.toSet();
    selected.contains(sectionId)
        ? selected.remove(sectionId)
        : selected.add(sectionId);
    emit(
      state.copyWith(
        selectedTimelineSectionIds: selected,
        selectedSmartSectionId: sectionId,
        selectedTimelineSceneId: null,
      ),
    );
  }

  void setTimelineSectionsSelected(
    Iterable<String> sectionIds, {
    required bool selected,
  }) {
    final available = timelineAvailableSectionIds.toSet();
    final affected = sectionIds.where(available.contains).toSet();
    if (affected.isEmpty) return;
    final next = state.selectedTimelineSectionIds.toSet();
    selected ? next.addAll(affected) : next.removeAll(affected);
    emit(
      state.copyWith(
        selectedTimelineSectionIds: next,
        selectedSmartSectionId: affected.first,
        selectedTimelineSceneId: null,
      ),
    );
  }

  void createTimelineGroupFromSelection() {
    _createTimelineGroup(state.selectedTimelineSectionIds);
  }

  void _createTimelineGroup(
    Iterable<String> selectedIds, {
    bool fromCanvas = false,
  }) {
    final selectedSet = selectedIds.toSet();
    if (selectedSet.isEmpty) return;
    if (state.smartSections.isNotEmpty) {
      final retained = <EditorSceneDraft>[
        for (final scene in state.sceneDrafts)
          if (scene.sectionIds.any((id) => !selectedSet.contains(id)))
            scene.copyWith(
              sectionIds: scene.sectionIds
                  .where((id) => !selectedSet.contains(id))
                  .toList(growable: false),
            ),
      ];
      final created = _timelineService.createGroup(
        order: timelineSectionOrder,
        selectedSectionIds: selectedSet,
        id: _idGenerator.sceneId().value,
        name: 'Scene ${retained.length + 1}',
      );
      final draft = EditorSceneDraft(
        id: created.group.id,
        name: created.group.name,
        sectionIds: created.group.sectionIds,
        locked: created.group.locked,
      );
      emit(
        state.copyWith(
          sceneDrafts: [...retained, draft],
          smartSections: _orderedSmartSections(created.order),
          suggestionOrderCustomized: true,
          activeStroke: const [],
          tool: EditorTool.select,
          selectedSmartSectionId: draft.sectionIds.first,
          selectedTimelineSectionIds: const {},
          selectedTimelineSceneId: draft.id,
          statusMessage: fromCanvas
              ? 'Optional canvas selection added as Scene ${retained.length + 1}.'
              : 'Scene ${retained.length + 1} created from the timeline selection.',
        ),
      );
      return;
    }
    final persistentIds = state.document.sectionOrder
        .where((id) => selectedSet.contains(id.value))
        .toList(growable: false);
    if (persistentIds.length != selectedSet.length) {
      emit(
        state.copyWith(
          activeStroke: const [],
          statusMessage:
              'Apply Auto Path before creating a persistent timeline scene.',
        ),
      );
      return;
    }
    final retainedGroups = <DrawingSceneGroup>[
      for (final group in timelineSceneGroups)
        if (group.sectionIds.any((id) => !selectedSet.contains(id)))
          group.copyWith(
            sectionIds: group.sectionIds
                .where((id) => !selectedSet.contains(id))
                .toList(growable: false),
          ),
    ];
    final created = _timelineService.createGroup(
      order: timelineSectionOrder,
      selectedSectionIds: selectedSet,
      id: 'scene-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Scene ${retainedGroups.length + 1}',
    );
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.sceneCreate,
      operation: (document) => const SceneDocumentOperations().createScene(
        document: document,
        name: created.group.name,
        sectionIds: persistentIds,
        ids: _allocation(),
      ),
    );
    if (!changed) return;
    final createdScene = state.document.scenes.last;
    emit(
      state.copyWith(
        activeStroke: const [],
        tool: EditorTool.select,
        selectedSmartSectionId: createdScene.sectionIds.first.value,
        selectedTimelineSectionIds: const {},
        selectedTimelineSceneId: createdScene.id.value,
        statusMessage: fromCanvas
            ? 'Optional canvas selection added as Scene ${state.document.scenes.length}.'
            : 'Scene ${state.document.scenes.length} created from the timeline selection.',
      ),
    );
  }

  void selectTimelineScene(String? id) {
    emit(
      state.copyWith(
        selectedTimelineSceneId: id,
        selectedSmartSectionId: id == null
            ? state.selectedSmartSectionId
            : null,
      ),
    );
  }

  void toggleTimelineSceneExpanded(String id) {
    final collapsed = state.collapsedTimelineSceneIds.toSet();
    collapsed.contains(id) ? collapsed.remove(id) : collapsed.add(id);
    emit(state.copyWith(collapsedTimelineSceneIds: collapsed));
  }

  void reorderTimelineNode(String draggedKey, String targetKey) {
    final order = _timelineService.reorderNode(
      order: timelineSectionOrder,
      groups: timelineSceneGroups,
      draggedKey: draggedKey,
      targetKey: targetKey,
    );
    if (_sameTimelineOrder(order, timelineSectionOrder)) return;
    if (state.smartSections.isNotEmpty) {
      emit(
        state.copyWith(
          smartSections: _orderedSmartSections(order),
          suggestionOrderCustomized: true,
          statusMessage: 'Timeline order updated.',
        ),
      );
      return;
    }
    _replaceDocument(
      kind: DocumentOperationKind.sceneReorderSections,
      update: (document) => _withSectionOrder(document, order),
      affectedScopes: const {DocumentScope.strokes, DocumentScope.ordering},
      action: 'reorder-timeline-node',
      entityIds: order,
      statusMessage: 'Timeline order updated.',
    );
  }

  void reorderTimelineNodes(Iterable<String> draggedKeys, int insertionIndex) {
    final order = _timelineService.reorderNodes(
      order: timelineSectionOrder,
      groups: timelineSceneGroups,
      draggedKeys: draggedKeys,
      insertionIndex: insertionIndex,
    );
    if (_sameTimelineOrder(order, timelineSectionOrder)) return;
    if (state.smartSections.isNotEmpty) {
      emit(
        state.copyWith(
          smartSections: _orderedSmartSections(order),
          suggestionOrderCustomized: true,
          statusMessage: draggedKeys.length > 1
              ? '${draggedKeys.length} timeline items moved together.'
              : 'Timeline order updated.',
        ),
      );
      return;
    }
    _replaceDocument(
      kind: DocumentOperationKind.sceneReorderSections,
      update: (document) => _withSectionOrder(document, order),
      affectedScopes: const {DocumentScope.strokes, DocumentScope.ordering},
      action: 'reorder-timeline-nodes',
      entityIds: draggedKeys,
      statusMessage: draggedKeys.length > 1
          ? '${draggedKeys.length} timeline items moved together.'
          : 'Timeline order updated.',
    );
  }

  void reorderTimelineSceneMember(
    String sceneId,
    String draggedSectionId,
    String targetSectionId,
  ) {
    DrawingSceneGroup? scene;
    for (final group in timelineSceneGroups) {
      if (group.id == sceneId) {
        scene = group;
        break;
      }
    }
    if (scene == null) return;
    final order = _timelineService.reorderSceneMember(
      order: timelineSectionOrder,
      scene: scene,
      draggedSectionId: draggedSectionId,
      targetSectionId: targetSectionId,
    );
    final orderedMembers = order
        .where(scene.sectionIds.toSet().contains)
        .toList(growable: false);
    if (state.smartSections.isNotEmpty) {
      emit(
        state.copyWith(
          smartSections: _orderedSmartSections(order),
          suggestionOrderCustomized: true,
          sceneDrafts: [
            for (final draft in state.sceneDrafts)
              draft.id == sceneId
                  ? draft.copyWith(sectionIds: orderedMembers)
                  : draft,
          ],
          statusMessage: 'Scene contents reordered.',
        ),
      );
      return;
    }
    _replaceDocument(
      kind: DocumentOperationKind.sceneReorderSections,
      update: (document) => _withSectionOrder(
        document,
        order,
        scenes: [
          for (final item in document.scenes)
            item.id.value == sceneId
                ? item.copyWith(
                    sectionIds: [
                      for (final id in orderedMembers) SectionId(id),
                    ],
                  )
                : item,
        ],
      ),
      affectedScopes: const {
        DocumentScope.strokes,
        DocumentScope.ordering,
        DocumentScope.scenes,
      },
      action: 'reorder-scene-member',
      entityIds: [sceneId, draggedSectionId, targetSectionId],
      statusMessage: 'Scene contents reordered.',
    );
  }

  List<SectionId> _persistentSectionOrder(
    ProjectDocument document,
    Iterable<String> requested,
  ) {
    final byValue = {for (final id in document.sectionOrder) id.value: id};
    final inserted = <SectionId>{};
    return [
      for (final value in requested)
        if (byValue[value] case final id? when inserted.add(id)) id,
      for (final id in document.sectionOrder)
        if (inserted.add(id)) id,
    ];
  }

  ProjectDocument _withSectionOrder(
    ProjectDocument document,
    Iterable<String> requested, {
    List<ProjectScene>? scenes,
  }) {
    final sectionOrder = _persistentSectionOrder(document, requested);
    final rank = {
      for (var index = 0; index < sectionOrder.length; index++)
        sectionOrder[index]: index,
    };
    final indexed = document.strokes.indexed.toList(growable: false)
      ..sort((left, right) {
        final sectionComparison = (rank[left.$2.sectionId] ?? rank.length)
            .compareTo(rank[right.$2.sectionId] ?? rank.length);
        return sectionComparison == 0
            ? left.$1.compareTo(right.$1)
            : sectionComparison;
      });
    return document.copyWith(
      sectionOrder: sectionOrder,
      strokes: [for (final item in indexed) item.$2],
      scenes: scenes,
    );
  }

  List<SmartPathSection> _orderedSmartSections(Iterable<String> order) {
    final byId = {
      for (final section in state.smartSections) section.id: section,
    };
    return [for (final id in order) ?byId.remove(id), ...byId.values];
  }

  StrokeId? _strokeIdAt(int index) {
    final strokes = project.strokes;
    if (index < 0 || index >= strokes.length) return null;
    return StrokeId(strokes[index].id);
  }

  Future<bool> _applyPlannedStrokes(
    List<DrawingStroke> source, {
    required String action,
    required String statusMessage,
    ProjectPathProcessingMetadata? pathProcessingMetadata,
    ProjectDocument? replacementBase,
    Map<SectionId, String> sectionNames = const {},
    Map<SectionId, DocumentSectionTiming> sectionTimings = const {},
    ProjectHandConfiguration? handConfiguration,
    ProjectMotionConfiguration? motionConfiguration,
    bool preserveExistingSections = false,
    bool Function()? isCancelled,
  }) async {
    final baselineDocument = state.document;
    final sectionOrder = <SectionId>[];
    final sectionStrokeIds = <SectionId, List<StrokeId>>{};
    final strokes = <ProjectStroke>[];
    final documentClipMasks =
        HashMap<
          List<List<Offset>>,
          ImmutablePolygonList<DocumentPoint>
        >.identity();
    final documentExclusionBounds =
        HashMap<List<Rect>, ImmutableValueList<DocumentRect>>.identity();
    for (var sourceIndex = 0; sourceIndex < source.length; sourceIndex++) {
      if (sourceIndex > 0 && sourceIndex % 128 == 0) {
        if (isClosed ||
            isCancelled?.call() == true ||
            !identical(state.document, baselineDocument)) {
          return false;
        }
        if (state.isAnalyzingSmartPaths) {
          emit(
            state.copyWith(
              smartPathProgress: SmartPathProgress(
                stage: SmartPathProgressStage.finalizing,
                fraction: 0.94 + (0.05 * sourceIndex / source.length),
              ),
            ),
          );
        }
        // Let pointer, paint, and cancellation events run between conversion
        // batches instead of monopolizing the UI isolate for a dense image.
        await Future<void>.delayed(Duration.zero);
      }
      final item = source[sourceIndex];
      final sectionId = SectionId(
        item.sectionId ?? 'manual-section-${item.id}',
      );
      final strokeId = StrokeId(item.id);
      if (!sectionStrokeIds.containsKey(sectionId)) {
        sectionOrder.add(sectionId);
        sectionStrokeIds[sectionId] = <StrokeId>[];
      }
      sectionStrokeIds[sectionId]!.add(strokeId);
      strokes.add(
        ProjectStroke(
          id: strokeId,
          sectionId: sectionId,
          name: item.name,
          points: [
            for (final point in item.points) DocumentPoint(point.dx, point.dy),
          ],
          assetId: state.document.artworkAssetId,
          geometry: item.geometry,
          animationGeometry: item.animationGeometry,
          isFilledShape: item.isFilledShape,
          isTextShape: item.isTextShape,
          isGlobalDecoration: item.isGlobalDecoration,
          fillColorValue: item.fillColorValue,
          hidden: item.hidden,
          reversed: item.reversed,
          revealOnly: item.revealOnly,
          isPaintStroke: item.isPaintStroke,
          paintRegion: item.paintRegion,
          revealStyle: item.revealStyle == RevealMaskStyle.directionalWipe
              ? DocumentRevealStyle.directionalWipe
              : DocumentRevealStyle.brush,
          clipBounds: item.clipBounds == null
              ? null
              : DocumentRect(
                  left: item.clipBounds!.left,
                  top: item.clipBounds!.top,
                  right: item.clipBounds!.right,
                  bottom: item.clipBounds!.bottom,
                ),
          clipPolygons: item.clipPolygons.isEmpty
              ? const []
              : documentClipMasks.putIfAbsent(
                  item.clipPolygons,
                  () => ImmutablePolygonList<DocumentPoint>.freeze([
                    for (final polygon in item.clipPolygons)
                      [
                        for (final point in polygon)
                          DocumentPoint(point.dx, point.dy),
                      ],
                  ]),
                ),
          exclusionBounds: documentExclusionBounds.putIfAbsent(
            item.exclusionBounds,
            () => ImmutableValueList.freeze([
              for (final rect in item.exclusionBounds)
                DocumentRect(
                  left: rect.left,
                  top: rect.top,
                  right: rect.right,
                  bottom: rect.bottom,
                ),
            ]),
          ),
          revealWidth: item.revealWidth,
          pausePoints: [
            for (final pause in item.pausePoints)
              DocumentStrokePause(
                id: StrokePauseId(pause.id),
                progress: pause.progress,
                duration: TimelineDuration.fromMicroseconds(
                  (pause.durationSeconds * Duration.microsecondsPerSecond)
                      .round(),
                ),
                keepHandVisible: pause.keepHandVisible,
              ),
          ],
          vectorMaskStrokes: [
            for (final mask in item.vectorMaskStrokes)
              DocumentVectorMaskStroke(
                geometry: mask.geometry,
                width: mask.widthFraction,
                erase: mask.operation == VectorMaskOperation.erase,
                feather: mask.featherFraction,
                clipToLayer: mask.clipToLayer,
              ),
          ],
        ),
      );
    }
    final existingSections = {
      for (final section in (replacementBase ?? state.document).sections)
        section.id: section,
    };
    if (isClosed ||
        isCancelled?.call() == true ||
        !identical(state.document, baselineDocument)) {
      return false;
    }
    return _executeDocumentOperation(
      kind: DocumentOperationKind.strokeApplyBatch,
      operation: (document) {
        final apply = preserveExistingSections
            ? const StrokeDocumentOperations().replaceSections
            : const StrokeDocumentOperations().applyBatch;
        final applied = apply(
          document: replacementBase ?? document,
          input: BatchStrokeApplication(
            strokes: strokes,
            sections: [
              for (final id in sectionOrder)
                ProjectSection(
                  id: id,
                  name:
                      sectionNames[id] ??
                      existingSections[id]?.name ??
                      id.value,
                  strokeIds: sectionStrokeIds[id]!,
                  assetId: document.artworkAssetId,
                  timing:
                      sectionTimings[id] ??
                      existingSections[id]?.timing ??
                      const DocumentSectionTiming(),
                ),
            ],
            sectionOrder: sectionOrder,
            action: action,
          ),
        );
        if (!applied.isSuccess) return applied;
        final withProcessing = pathProcessingMetadata == null
            ? applied
            : DocumentOperationResult.success(
                document: applied.document.copyWith(
                  pathProcessingMetadata: pathProcessingMetadata,
                ),
                affectedScopes: {
                  ...applied.affectedScopes,
                  DocumentScope.settings,
                },
                summary: applied.summary,
              );
        final withHand = handConfiguration == null
            ? withProcessing
            : DocumentOperationResult.success(
                document: withProcessing.document.copyWith(
                  handConfiguration: handConfiguration,
                ),
                affectedScopes: {
                  ...withProcessing.affectedScopes,
                  DocumentScope.hand,
                },
                summary: withProcessing.summary,
              );
        final withMotion = motionConfiguration == null
            ? withHand
            : DocumentOperationResult.success(
                document: withHand.document.copyWith(
                  motionConfiguration: motionConfiguration,
                ),
                affectedScopes: {
                  ...withHand.affectedScopes,
                  DocumentScope.settings,
                },
                summary: withHand.summary,
              );
        if (state.sceneDrafts.isEmpty) return withMotion;
        final available = sectionOrder.toSet();
        return DocumentOperationResult.success(
          document: withMotion.document.copyWith(
            scenes: [
              for (final draft in state.sceneDrafts)
                if (draft.sectionIds
                        .map(SectionId.new)
                        .where(available.contains)
                        .toList()
                    case final members when members.isNotEmpty)
                  ProjectScene(
                    id: SceneId(draft.id),
                    name: draft.name,
                    sectionIds: members,
                    locked: draft.locked,
                  ),
            ],
          ),
          affectedScopes: withMotion.affectedScopes,
          summary: withMotion.summary,
        );
      },
      statusMessage: statusMessage,
    );
  }

  ({
    Map<SectionId, DocumentSectionTiming> sectionTimings,
    ProjectMotionConfiguration motionConfiguration,
  })
  _referenceRevealMotionFor(List<DrawingStroke> strokes) {
    const policy = ReferenceRevealMotionPolicy();
    final durations = policy.sectionAnimationDurations(strokes);
    final orderedSectionIds = durations.keys.toList(growable: false);
    TimelineDuration seconds(double value) => TimelineDuration.fromMicroseconds(
      (value * Duration.microsecondsPerSecond).round(),
    );
    final drawingSeconds = durations.values.fold<double>(0, (a, b) => a + b);
    return (
      sectionTimings: {
        for (var index = 0; index < orderedSectionIds.length; index++)
          SectionId(orderedSectionIds[index]): DocumentSectionTiming(
            animationDuration: seconds(durations[orderedSectionIds[index]]!),
            transitionAfter: index == orderedSectionIds.length - 1
                ? TimelineDuration.zero
                : seconds(ReferenceRevealMotionPolicy.sectionTransitionSeconds),
            handExitAnimation: index == orderedSectionIds.length - 1
                ? SectionHandExitAnimation.moveOut
                : SectionHandExitAnimation.none,
            handExitDuration: index == orderedSectionIds.length - 1
                ? seconds(ReferenceRevealMotionPolicy.handExitSeconds)
                : TimelineDuration.zero,
          ),
      },
      motionConfiguration: state.document.motionConfiguration.copyWith(
        drawingDuration: seconds(drawingSeconds),
        startDelay: TimelineDuration.zero,
        endHold: seconds(ReferenceRevealMotionPolicy.finalHoldSeconds),
      ),
    );
  }

  bool _sameTimelineOrder(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  void reorderSceneGroup(int oldIndex, int newIndex) {
    final groups = List<DrawingSceneGroup>.of(project.sceneGroups);
    if (state.smartSections.isNotEmpty) {
      final drafts = List<EditorSceneDraft>.of(state.sceneDrafts);
      if (oldIndex < 0 || oldIndex >= drafts.length) return;
      final target = newIndex.clamp(0, drafts.length - 1);
      if (target == oldIndex) return;
      final moved = drafts.removeAt(oldIndex);
      drafts.insert(target, moved);
      emit(
        state.copyWith(
          sceneDrafts: drafts,
          statusMessage: 'Scene order updated.',
        ),
      );
      return;
    }
    if (oldIndex < 0 || oldIndex >= groups.length) return;
    final target = newIndex.clamp(0, groups.length - 1);
    if (target == oldIndex) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.sceneReorder,
      operation: (document) => const SceneDocumentOperations().reorderScene(
        document: document,
        sceneId: SceneId(groups[oldIndex].id),
        insertionIndex: target,
      ),
      statusMessage: 'Scene order updated.',
    );
  }

  void deleteSceneGroup(String id) {
    if (state.smartSections.isNotEmpty) {
      final drafts = state.sceneDrafts
          .where((scene) => scene.id != id)
          .toList(growable: false);
      if (drafts.length == state.sceneDrafts.length) return;
      emit(
        state.copyWith(
          sceneDrafts: drafts,
          selectedTimelineSceneId: state.selectedTimelineSceneId == id
              ? null
              : state.selectedTimelineSceneId,
          statusMessage: 'Scene group removed; its sections remain available.',
        ),
      );
      return;
    }
    final groups = timelineSceneGroups
        .where((group) => group.id != id)
        .toList(growable: false);
    if (groups.length == timelineSceneGroups.length) return;
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.sceneDelete,
      operation: (document) => const SceneDocumentOperations().deleteScene(
        document: document,
        sceneId: SceneId(id),
      ),
      statusMessage: 'Scene group removed; its sections remain available.',
    );
    if (!changed) return;
    emit(
      state.copyWith(
        selectedTimelineSceneId: state.selectedTimelineSceneId == id
            ? null
            : state.selectedTimelineSceneId,
        statusMessage: 'Scene group removed; its sections remain available.',
      ),
    );
  }

  void clearSceneGroups() {
    if (timelineSceneGroups.isEmpty) return;
    if (state.smartSections.isNotEmpty) {
      emit(
        state.copyWith(
          sceneDrafts: const [],
          activeStroke: const [],
          tool: EditorTool.select,
          selectedTimelineSceneId: null,
          statusMessage: 'Scene grouping reset to automatic ordering.',
        ),
      );
      return;
    }
    for (final scene in state.document.scenes.toList(growable: false)) {
      _executeDocumentOperation(
        kind: DocumentOperationKind.sceneDelete,
        operation: (document) => const SceneDocumentOperations().deleteScene(
          document: document,
          sceneId: scene.id,
        ),
      );
    }
    emit(
      state.copyWith(
        activeStroke: const [],
        tool: EditorTool.select,
        selectedTimelineSceneId: null,
        statusMessage: 'Scene grouping reset to automatic ordering.',
      ),
    );
  }

  bool _isMaskTool(EditorTool tool) =>
      tool == EditorTool.maskReveal || tool == EditorTool.maskErase;

  void _commitVectorMaskStroke() {
    final selected = state.selectedStrokeIndex;
    if (selected == null ||
        selected < 0 ||
        selected >= project.strokes.length) {
      emit(state.copyWith(activeStroke: const []));
      commitSectionTimingEdit();
      return;
    }
    final reduced = _reducePoints(state.activeStroke);
    final geometry = StrokePathGeometry(
      start: reduced.first,
      segments: [
        for (final point in reduced.skip(1)) StrokeLineSegment(end: point),
      ],
    );
    final operation = state.tool == EditorTool.maskErase
        ? VectorMaskOperation.erase
        : VectorMaskOperation.reveal;
    final strokeId = _strokeIdAt(selected);
    if (strokeId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.maskAdd,
      operation: (document) => const MaskDocumentOperations().add(
        document: document,
        strokeId: strokeId,
        mask: DocumentVectorMaskStroke(
          geometry: geometry,
          width: state.maskBrushWidth / state.document.canvas.height,
          feather: state.maskFeather / state.document.canvas.height,
          clipToLayer: state.maskClipToLayer,
          erase: operation == VectorMaskOperation.erase,
        ),
      ),
      statusMessage: operation == VectorMaskOperation.erase
          ? 'Reveal mask area erased'
          : 'Reveal mask area added',
    );
    emit(state.copyWith(activeStroke: const []));
    commitSectionTimingEdit();
  }

  void undoStroke() {
    final result = _transactions.undo(
      current: state.documentState,
      history: _history,
    );
    if (!result.isSuccess) return;
    final strokeCount = result.state.document.strokes.length;
    emit(
      state.copyWith(
        documentState: result.state,
        selectedStrokeIndex: _sanitizeStrokeIndex(
          state.selectedStrokeIndex,
          strokeCount,
        ),
        hoveredStrokeIndex: _sanitizeStrokeIndex(
          state.hoveredStrokeIndex,
          strokeCount,
        ),
        selectedPathNode: null,
        selectedPathNodes: const {},
        statusMessage: 'Change undone',
      ),
    );
  }

  void redoStroke() {
    final result = _transactions.redo(
      current: state.documentState,
      history: _history,
    );
    if (!result.isSuccess) return;
    final strokeCount = result.state.document.strokes.length;
    emit(
      state.copyWith(
        documentState: result.state,
        selectedStrokeIndex: _sanitizeStrokeIndex(
          state.selectedStrokeIndex,
          strokeCount,
        ),
        hoveredStrokeIndex: _sanitizeStrokeIndex(
          state.hoveredStrokeIndex,
          strokeCount,
        ),
        selectedPathNode: null,
        selectedPathNodes: const {},
        statusMessage: 'Change restored',
      ),
    );
  }

  int? _sanitizeStrokeIndex(int? index, int length) =>
      index != null && index >= 0 && index < length ? index : null;

  void deleteStroke(int index) {
    if (index < 0 || index >= project.strokes.length) return;
    final id = StrokeId(project.strokes[index].id);
    if (_executeDocumentOperation(
      kind: DocumentOperationKind.strokeDelete,
      operation: (document) => const StrokeDocumentOperations().delete(
        document: document,
        strokeId: id,
      ),
      statusMessage: 'Stroke deleted',
    )) {
      emit(
        state.copyWith(
          selectedStrokeIndex: null,
          hoveredStrokeIndex: null,
          selectedPathNode: null,
          selectedPathNodes: const {},
        ),
      );
    }
  }

  void reverseStroke(int index) {
    if (index < 0 || index >= project.strokes.length) return;
    final id = StrokeId(project.strokes[index].id);
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeReverse,
      operation: (document) => const StrokeDocumentOperations().reverse(
        document: document,
        strokeId: id,
      ),
      statusMessage: 'Stroke direction reversed',
    );
  }

  void toggleStrokeHidden(int index) {
    if (index < 0 || index >= project.strokes.length) return;
    final hidden = !project.strokes[index].hidden;
    final id = StrokeId(project.strokes[index].id);
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeSetHidden,
      operation: (document) => const StrokeDocumentOperations().setHidden(
        document: document,
        strokeId: id,
        hidden: hidden,
      ),
      statusMessage: hidden
          ? 'Path hidden from animation'
          : 'Path restored to animation',
    );
  }

  void resetStrokeMask(int index) {
    if (index < 0 || index >= project.strokes.length) return;
    if (project.strokes[index].vectorMaskStrokes.isEmpty) return;
    final id = StrokeId(project.strokes[index].id);
    _executeDocumentOperation(
      kind: DocumentOperationKind.maskReset,
      operation: (document) => const MaskDocumentOperations().reset(
        document: document,
        strokeId: id,
      ),
      statusMessage: 'Path mask reset',
    );
  }

  void setMaskBrushWidth(double value) {
    emit(state.copyWith(maskBrushWidth: value.clamp(2, 400)));
  }

  void setMaskFeather(double value) {
    emit(state.copyWith(maskFeather: value.clamp(0, 80)));
  }

  void setMaskOverlayVisible(bool visible) {
    emit(state.copyWith(maskOverlayVisible: visible));
  }

  void setMaskComparisonBefore(bool before) {
    emit(state.copyWith(maskComparisonBefore: before));
  }

  void setMaskClipToLayer(bool clip) {
    emit(state.copyWith(maskClipToLayer: clip));
  }

  void setNodeSnapEnabled(bool enabled) {
    emit(state.copyWith(nodeSnapEnabled: enabled));
  }

  void applyExportPreset(ExportPresetId id) {
    final preset = ExportPreset.byId(id);
    if (preset == null) {
      _setExport(
        state.document.exportConfiguration.copyWith(presetId: id),
        property: 'preset',
      );
      return;
    }
    final scale = preset.height / state.document.canvas.height;
    _executeDocumentOperation(
      kind: DocumentOperationKind.settingsSetExport,
      operation: (document) => DocumentOperationResult.success(
        document: document.copyWith(
          canvas: document.canvas.copyWith(
            width: preset.width,
            height: preset.height,
          ),
          frameRate: FrameRate(numerator: preset.frameRate),
          exportConfiguration: document.exportConfiguration.copyWith(
            presetId: id,
          ),
          motionConfiguration: document.motionConfiguration.copyWith(
            revealWidth: document.motionConfiguration.revealWidth * scale,
          ),
          strokes: [
            for (final stroke in document.strokes)
              stroke.copyWith(
                revealWidth: stroke.revealWidth == null
                    ? null
                    : stroke.revealWidth! * scale,
              ),
          ],
        ),
        affectedScopes: const {
          DocumentScope.export,
          DocumentScope.canvas,
          DocumentScope.settings,
          DocumentScope.strokes,
        },
        summary: DocumentChangeSummary(action: 'apply-export-preset'),
      ),
      mergeProperty: 'preset',
    );
  }

  void setExportFrameRate(int frameRate) {
    if (!const [24, 25, 30, 50, 60].contains(frameRate)) return;
    _setExport(
      state.document.exportConfiguration.copyWith(
        presetId: ExportPresetId.custom,
      ),
      frameRate: FrameRate(numerator: frameRate),
      property: 'frameRate',
    );
  }

  bool setCustomExportResolution({required int width, required int height}) {
    if (!ExportResolutionPolicy.isValid(width: width, height: height)) {
      return false;
    }
    final current = state.document;
    final heightScale = height / current.canvas.height;
    return _executeDocumentOperation(
      kind: DocumentOperationKind.settingsSetExport,
      operation: (document) => DocumentOperationResult.success(
        document: document.copyWith(
          canvas: document.canvas.copyWith(width: width, height: height),
          exportConfiguration: document.exportConfiguration.copyWith(
            presetId: ExportPresetId.custom,
          ),
          motionConfiguration: document.motionConfiguration.copyWith(
            revealWidth: document.motionConfiguration.revealWidth * heightScale,
          ),
          strokes: [
            for (final stroke in document.strokes)
              stroke.copyWith(
                revealWidth: stroke.revealWidth == null
                    ? null
                    : stroke.revealWidth! * heightScale,
              ),
          ],
        ),
        affectedScopes: const {
          DocumentScope.export,
          DocumentScope.canvas,
          DocumentScope.settings,
          DocumentScope.strokes,
        },
        summary: DocumentChangeSummary(action: 'set-custom-export-resolution'),
      ),
      mergeProperty: 'customResolution',
    );
  }

  void setExportAlphaMode(ExportAlphaMode mode) => _setExport(
    state.document.exportConfiguration.copyWith(alphaMode: mode),
    property: 'alphaMode',
  );

  void setExportRenderQuality(ExportRenderQuality quality) => _setExport(
    state.document.exportConfiguration.copyWith(renderQuality: quality),
    property: 'renderQuality',
  );

  void _setExport(
    ProjectExportConfiguration configuration, {
    FrameRate? frameRate,
    required String property,
  }) => _executeDocumentOperation(
    kind: DocumentOperationKind.settingsSetExport,
    operation: (document) => const ProjectSettingsOperations().setExport(
      document: document,
      configuration: configuration,
      frameRate: frameRate,
    ),
    mergeProperty: property,
  );

  void addNodeToSelectedPath() {
    final index = state.selectedStrokeIndex;
    final reference = state.selectedPathNode;
    if (index == null || reference == null) return;
    final stroke = project.strokes[index];
    final geometry = stroke.orderedGeometry;
    if (geometry == null || geometry.segments.isEmpty) return;
    final segmentIndex = reference.kind == PathNodeKind.endAnchor
        ? reference.segmentIndex
        : reference.segmentIndex >= 0
        ? reference.segmentIndex
        : 0;
    final edited = _pathNodeEditor.splitSegment(geometry, segmentIndex);
    _commitNodeGeometry(index, stroke, edited, 'Node added');
  }

  void deleteSelectedNode() {
    final index = state.selectedStrokeIndex;
    final reference = state.selectedPathNode;
    if (index == null || reference == null) return;
    final stroke = project.strokes[index];
    final geometry = stroke.orderedGeometry;
    if (geometry == null) return;
    final edited = _pathNodeEditor.deleteAnchor(geometry, reference);
    if (identical(edited, geometry)) return;
    _commitNodeGeometry(index, stroke, edited, 'Node deleted');
  }

  void setSelectedNodeSmooth(bool smooth) {
    final index = state.selectedStrokeIndex;
    final reference = state.selectedPathNode;
    if (index == null || reference == null) return;
    final stroke = project.strokes[index];
    final geometry = stroke.orderedGeometry;
    if (geometry == null) return;
    final edited = _pathNodeEditor.setAnchorSmooth(
      geometry,
      reference,
      smooth: smooth,
    );
    _commitNodeGeometry(
      index,
      stroke,
      edited,
      smooth ? 'Node converted to smooth' : 'Node converted to corner',
    );
  }

  void setSelectedNodeAsStart() {
    final index = state.selectedStrokeIndex;
    final reference = state.selectedPathNode;
    if (index == null || reference == null) return;
    final stroke = project.strokes[index];
    final geometry = stroke.orderedGeometry;
    if (geometry == null || !geometry.closed) return;
    final anchorIndex = reference.kind == PathNodeKind.startAnchor
        ? 0
        : reference.kind == PathNodeKind.endAnchor
        ? reference.segmentIndex + 1
        : null;
    if (anchorIndex == null) return;
    final edited = _pathNodeEditor.setStartAnchor(geometry, anchorIndex);
    _commitNodeGeometry(index, stroke, edited, 'Start node changed');
  }

  void splitSelectedPath() {
    final index = state.selectedStrokeIndex;
    final reference = state.selectedPathNode;
    if (index == null || reference == null) return;
    final stroke = project.strokes[index];
    final strokeId = _strokeIdAt(index);
    final geometry = stroke.orderedGeometry;
    if (geometry == null || reference.kind != PathNodeKind.endAnchor) return;
    if (strokeId == null) return;
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.pathSplit,
      operation: (document) => const PathDocumentOperations().splitPath(
        document: document,
        strokeId: strokeId,
        anchorIndex: reference.segmentIndex + 1,
        ids: _allocation(),
      ),
      statusMessage: 'Path split into two editable paths',
    );
    if (!changed) return;
    emit(
      state.copyWith(
        selectedStrokeIndex: index + 1,
        selectedPathNode: null,
        selectedPathNodes: const {},
        statusMessage: 'Path split into two editable paths',
      ),
    );
  }

  void joinStrokeWithNext(int index) {
    if (index < 0 || index + 1 >= project.strokes.length) return;
    final first = project.strokes[index];
    final second = project.strokes[index + 1];
    if (first.orderedGeometry == null || second.orderedGeometry == null) return;
    final strokeId = _strokeIdAt(index);
    final nextStrokeId = _strokeIdAt(index + 1);
    if (strokeId == null || nextStrokeId == null) return;
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.pathJoinWithNext,
      operation: (document) => const PathDocumentOperations().joinWithNext(
        document: document,
        strokeId: strokeId,
        nextStrokeId: nextStrokeId,
      ),
      statusMessage: 'Paths joined',
    );
    if (!changed) return;
    emit(
      state.copyWith(
        selectedStrokeIndex: index,
        selectedPathNode: null,
        selectedPathNodes: const {},
        statusMessage: 'Paths joined',
      ),
    );
  }

  void _commitNodeGeometry(
    int index,
    DrawingStroke stroke,
    StrokePathGeometry displayedGeometry,
    String message,
  ) {
    final storedGeometry = stroke.reversed
        ? displayedGeometry.reversed()
        : displayedGeometry;
    final fillReveal = stroke.isFilledShape
        ? _filledShapeReveal(storedGeometry)
        : null;
    _commitStrokeGeometry(
      index: index,
      geometry: storedGeometry,
      animationGeometry: fillReveal?.geometry,
      clipBounds: fillReveal?.bounds,
      preserveClipWhenNull: true,
      message: message,
    );
  }

  void _commitStrokeGeometry({
    required int index,
    required StrokePathGeometry geometry,
    required StrokePathGeometry? animationGeometry,
    required Rect? clipBounds,
    required bool preserveClipWhenNull,
    required String message,
    DocumentOperationKind kind = DocumentOperationKind.strokeReplaceGeometry,
    String? mergeProperty,
  }) {
    final strokeId = _strokeIdAt(index);
    if (strokeId == null) return;
    final changed = _replaceDocument(
      kind: kind,
      update: (document) => document.copyWith(
        strokes: [
          for (final stroke in document.strokes)
            stroke.id == strokeId
                ? stroke.copyWith(
                    geometry: geometry,
                    animationGeometry: animationGeometry,
                    points: [
                      for (final point in geometry.sample())
                        DocumentPoint(point.dx, point.dy),
                    ],
                    clipBounds: clipBounds == null && preserveClipWhenNull
                        ? stroke.clipBounds
                        : clipBounds == null
                        ? null
                        : DocumentRect(
                            left: clipBounds.left,
                            top: clipBounds.top,
                            right: clipBounds.right,
                            bottom: clipBounds.bottom,
                          ),
                  )
                : stroke,
        ],
      ),
      affectedScopes: kind == DocumentOperationKind.pathMoveNode
          ? const {DocumentScope.paths}
          : const {DocumentScope.strokes, DocumentScope.paths},
      action: 'replace-stroke-geometry',
      entityIds: [strokeId.value],
      statusMessage: message,
      mergeProperty: mergeProperty,
    );
    if (changed) emit(state.copyWith(selectedStrokeIndex: index));
  }

  void addStrokePausePoint(
    int strokeIndex, {
    required double progress,
    required double durationSeconds,
    required bool keepHandVisible,
  }) {
    if (strokeIndex < 0 || strokeIndex >= project.strokes.length) return;
    final strokeId = _strokeIdAt(strokeIndex);
    if (strokeId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeAddPausePoint,
      operation: (document) => const StrokeDocumentOperations().addPausePoint(
        document: document,
        strokeId: strokeId,
        progress: progress.clamp(0.01, 0.99),
        duration: TimelineDuration.fromMicroseconds(
          (durationSeconds.clamp(0.05, 60.0) * Duration.microsecondsPerSecond)
              .round(),
        ),
        ids: _allocation(),
        keepHandVisible: keepHandVisible,
      ),
      statusMessage: 'Pause point added',
    );
  }

  void updateStrokePausePoint(
    int strokeIndex,
    String pauseId, {
    required double progress,
    required double durationSeconds,
    required bool keepHandVisible,
  }) {
    if (strokeIndex < 0 || strokeIndex >= project.strokes.length) return;
    final strokeId = _strokeIdAt(strokeIndex);
    if (strokeId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeUpdatePausePoint,
      operation: (document) =>
          const StrokeDocumentOperations().updatePausePoint(
            document: document,
            strokeId: strokeId,
            pauseId: StrokePauseId(pauseId),
            progress: progress.clamp(0.01, 0.99),
            duration: TimelineDuration.fromMicroseconds(
              (durationSeconds.clamp(0.05, 60.0) *
                      Duration.microsecondsPerSecond)
                  .round(),
            ),
            keepHandVisible: keepHandVisible,
          ),
      mergeProperty: 'stroke-pause-$pauseId',
      statusMessage: 'Pause point updated',
    );
  }

  void deleteStrokePausePoint(int strokeIndex, String pauseId) {
    if (strokeIndex < 0 || strokeIndex >= project.strokes.length) return;
    final strokeId = _strokeIdAt(strokeIndex);
    if (strokeId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeDeletePausePoint,
      operation: (document) =>
          const StrokeDocumentOperations().deletePausePoint(
            document: document,
            strokeId: strokeId,
            pauseId: StrokePauseId(pauseId),
          ),
      statusMessage: 'Pause point deleted',
    );
  }

  void toggleStrokeRevealOnly(int index) {
    if (index < 0 || index >= project.strokes.length) return;
    final current = project.strokes[index];
    final strokeId = _strokeIdAt(index);
    if (strokeId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeSetReveal,
      operation: (document) => const StrokeDocumentOperations().setReveal(
        document: document,
        strokeId: strokeId,
        revealOnly: !current.revealOnly,
        style: current.revealStyle == RevealMaskStyle.directionalWipe
            ? DocumentRevealStyle.directionalWipe
            : DocumentRevealStyle.brush,
      ),
      statusMessage: current.revealOnly
          ? 'Stroke changed to hand drawing'
          : 'Stroke changed to reveal only',
    );
  }

  void setStrokeRevealOnly(int index, {required bool revealOnly}) {
    if (index < 0 || index >= project.strokes.length) return;
    if (project.strokes[index].revealOnly == revealOnly) {
      selectStroke(index);
      return;
    }
    final current = project.strokes[index];
    final strokeId = _strokeIdAt(index);
    if (strokeId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.strokeSetReveal,
      operation: (document) => const StrokeDocumentOperations().setReveal(
        document: document,
        strokeId: strokeId,
        revealOnly: revealOnly,
        style: current.revealStyle == RevealMaskStyle.directionalWipe
            ? DocumentRevealStyle.directionalWipe
            : DocumentRevealStyle.brush,
      ),
      statusMessage: revealOnly
          ? 'Stroke changed to reveal only'
          : 'Stroke changed to hand drawing',
    );
  }

  void moveStroke(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= project.strokes.length) return;
    if (target < 0 || target >= project.strokes.length) return;
    _reorderStrokeDocument(index, target, statusMessage: null);
  }

  void reorderStroke(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= project.strokes.length) return;
    final insertionIndex = newIndex;
    if (insertionIndex < 0 || insertionIndex >= project.strokes.length) {
      return;
    }
    if (insertionIndex == oldIndex) {
      selectStroke(oldIndex);
      return;
    }
    _reorderStrokeDocument(
      oldIndex,
      insertionIndex,
      statusMessage: 'Stroke reordered',
    );
  }

  void _reorderStrokeDocument(
    int oldIndex,
    int newIndex, {
    required String? statusMessage,
  }) {
    final orderedIds = [
      for (final stroke in project.strokes) StrokeId(stroke.id),
    ];
    final moved = orderedIds.removeAt(oldIndex);
    orderedIds.insert(newIndex, moved);
    final changed = _replaceDocument(
      kind: DocumentOperationKind.strokeApplyBatch,
      update: (document) {
        final rank = {
          for (var index = 0; index < orderedIds.length; index++)
            orderedIds[index]: index,
        };
        return document.copyWith(
          strokes: [
            for (final id in orderedIds)
              document.strokes.firstWhere((stroke) => stroke.id == id),
          ],
          sections: [
            for (final section in document.sections)
              section.copyWith(
                strokeIds: List<StrokeId>.of(section.strokeIds)
                  ..sort((a, b) => (rank[a] ?? 0).compareTo(rank[b] ?? 0)),
              ),
          ],
          sectionOrder: List<SectionId>.of(document.sectionOrder)
            ..sort((a, b) {
              final aSection = document.sections.firstWhere(
                (section) => section.id == a,
              );
              final bSection = document.sections.firstWhere(
                (section) => section.id == b,
              );
              final aRank = aSection.strokeIds
                  .map((id) => rank[id] ?? orderedIds.length)
                  .reduce(math.min);
              final bRank = bSection.strokeIds
                  .map((id) => rank[id] ?? orderedIds.length)
                  .reduce(math.min);
              return aRank.compareTo(bRank);
            }),
        );
      },
      affectedScopes: const {DocumentScope.sections, DocumentScope.ordering},
      action: 'reorder-stroke',
      entityIds: [moved.value],
      statusMessage: statusMessage,
    );
    if (changed) emit(state.copyWith(selectedStrokeIndex: newIndex));
  }

  void selectStroke(int index) {
    if (index < 0 || index >= project.strokes.length) return;
    emit(
      state.copyWith(
        selectedStrokeIndex: index,
        selectedSmartSectionId: null,
        selectedTimelineSceneId: null,
        selectedPathNode: null,
        selectedPathNodes: const {},
      ),
    );
  }

  bool selectStrokeAt(Offset localPosition, Rect artworkRect) {
    final index = _strokeIndexAt(localPosition, artworkRect);
    if (index == null) {
      emit(
        state.copyWith(
          selectedStrokeIndex: null,
          selectedSmartSectionId: null,
          selectedTimelineSceneId: null,
          selectedPathNode: null,
          selectedPathNodes: const {},
        ),
      );
      return false;
    }
    if (index == state.selectedStrokeIndex) return true;
    selectStroke(index);
    return true;
  }

  void hoverStrokeAt(Offset? localPosition, Rect artworkRect) {
    final index = localPosition == null
        ? null
        : _strokeIndexAt(localPosition, artworkRect);
    if (index == state.hoveredStrokeIndex) return;
    emit(state.copyWith(hoveredStrokeIndex: index));
  }

  int? _strokeIndexAt(Offset position, Rect artworkRect) {
    if (artworkRect.isEmpty || !artworkRect.inflate(12).contains(position)) {
      return null;
    }
    int? closestIndex;
    var closestDistance = 11.0;
    var closestArea = double.infinity;
    for (var index = project.strokes.length - 1; index >= 0; index--) {
      final stroke = project.strokes[index];
      if (stroke.hidden) continue;
      final path = buildDrawingStrokePath(stroke, artworkRect);
      final bounds = path.getBounds();
      if (!bounds.inflate(closestDistance).contains(position)) continue;
      if (stroke.isFilledShape && path.contains(position)) {
        final area = bounds.width * bounds.height;
        if (closestDistance > 0 || area < closestArea) {
          closestIndex = index;
          closestDistance = 0;
          closestArea = area;
        }
        continue;
      }
      for (final metric in path.computeMetrics()) {
        final sampleCount = math.max(1, (metric.length / 6).ceil());
        for (var sample = 0; sample <= sampleCount; sample++) {
          final tangent = metric.getTangentForOffset(
            metric.length * sample / sampleCount,
          );
          if (tangent == null) continue;
          final distance = (tangent.position - position).distance;
          if (distance < closestDistance) {
            closestIndex = index;
            closestDistance = distance;
            closestArea = bounds.width * bounds.height;
          }
        }
      }
    }
    return closestIndex;
  }

  bool beginPathNodeEdit(
    Offset localPosition,
    Rect artworkRect, {
    bool additiveSelection = false,
  }) {
    if (state.tool != EditorTool.select || artworkRect.isEmpty) return false;
    final strokeIndex = state.selectedStrokeIndex;
    if (strokeIndex == null ||
        strokeIndex < 0 ||
        strokeIndex >= project.strokes.length) {
      return false;
    }
    final geometry = project.strokes[strokeIndex].orderedGeometry;
    if (geometry == null) return false;
    PathNodePosition? closest;
    var closestDistance = 14.0;
    for (final node in _pathNodeEditor.nodes(geometry)) {
      final canvasPosition = Offset(
        artworkRect.left + node.position.dx * artworkRect.width,
        artworkRect.top + node.position.dy * artworkRect.height,
      );
      final distance = (canvasPosition - localPosition).distance;
      if (distance <= closestDistance) {
        closestDistance = distance;
        closest = node;
      }
    }
    if (closest == null) return false;
    final additive = additiveSelection;
    final selected = additive
        ? Set<PathNodeReference>.of(state.selectedPathNodes)
        : <PathNodeReference>{};
    if (additive && selected.contains(closest.reference)) {
      selected.remove(closest.reference);
    } else {
      selected.add(closest.reference);
    }
    if (selected.isEmpty) {
      emit(state.copyWith(selectedPathNode: null, selectedPathNodes: const {}));
      return true;
    }
    beginSectionTimingEdit();
    _nodeEditStrokeIndex = strokeIndex;
    _nodeEditGeometry = geometry;
    _nodeEditPrimaryPosition = closest.position;
    emit(
      state.copyWith(
        selectedPathNode: closest.reference,
        selectedPathNodes: selected,
      ),
    );
    return true;
  }

  void updatePathNodeEdit(Offset localPosition, Rect artworkRect) {
    final strokeIndex = _nodeEditStrokeIndex;
    final reference = state.selectedPathNode;
    if (strokeIndex == null ||
        reference == null ||
        artworkRect.isEmpty ||
        strokeIndex < 0 ||
        strokeIndex >= project.strokes.length) {
      return;
    }
    final stroke = project.strokes[strokeIndex];
    final displayedGeometry = _nodeEditGeometry ?? stroke.orderedGeometry;
    final primaryPosition = _nodeEditPrimaryPosition;
    if (displayedGeometry == null || primaryPosition == null) return;
    var destination = _toNormalized(localPosition, artworkRect, clamp: true);
    if (state.nodeSnapEnabled) {
      const grid = 200.0;
      destination = Offset(
        (destination.dx * grid).round() / grid,
        (destination.dy * grid).round() / grid,
      );
    }
    final delta = destination - primaryPosition;
    var editedDisplayed = displayedGeometry;
    final originalNodes = {
      for (final node in _pathNodeEditor.nodes(displayedGeometry))
        node.reference: node.position,
    };
    final selected = state.selectedPathNodes.isEmpty
        ? {reference}
        : state.selectedPathNodes;
    for (final selectedReference in selected) {
      final original = originalNodes[selectedReference];
      if (original == null) continue;
      editedDisplayed = _pathNodeEditor.move(
        editedDisplayed,
        selectedReference,
        original + delta,
      );
    }
    final storedGeometry = stroke.reversed
        ? editedDisplayed.reversed()
        : editedDisplayed;
    final fillReveal = stroke.isFilledShape
        ? _filledShapeReveal(storedGeometry)
        : null;
    _commitStrokeGeometry(
      index: strokeIndex,
      geometry: storedGeometry,
      animationGeometry: fillReveal?.geometry,
      clipBounds: fillReveal?.bounds,
      preserveClipWhenNull: false,
      message: 'Vector path node moved',
      kind: DocumentOperationKind.pathMoveNode,
      mergeProperty: 'path-node-drag-${stroke.id}',
    );
  }

  void endPathNodeEdit() {
    if (_nodeEditStrokeIndex == null) return;
    _nodeEditStrokeIndex = null;
    _nodeEditGeometry = null;
    _nodeEditPrimaryPosition = null;
    commitSectionTimingEdit();
  }

  void cancelPathNodeEdit() {
    if (_nodeEditStrokeIndex == null) return;
    final result = _transactions.undo(
      current: state.documentState,
      history: _history,
    );
    _nodeEditStrokeIndex = null;
    _nodeEditGeometry = null;
    _nodeEditPrimaryPosition = null;
    if (!result.isSuccess || result.noOp) return;
    emit(
      state.copyWith(
        documentState: result.state,
        statusMessage: 'Node edit canceled',
      ),
    );
  }

  /// Applies confirmed scene masks as lightweight, ordered hand reveals.
  ///
  /// Scene splitting must remain responsive even for detailed raster art, so
  /// this intentionally does not invoke OCR or Auto Path. Every scene becomes
  /// one clipped broad stroke with explicit hand entrance, drawing and exit
  /// timing shared by Preview and MOV export.
  Future<bool> applyOrderedSceneReveals(List<SceneRegion> regions) async {
    if (regions.isEmpty || state.isAnalyzingSmartPaths) return false;
    final plan = _sceneRegionRevealPlanner.build(
      regions: regions,
      canvasHeight: state.document.canvas.height.toDouble(),
    );
    if (plan.entries.isEmpty) {
      emit(
        state.copyWith(
          statusMessage: 'No drawable content was found in the scene masks.',
        ),
      );
      return false;
    }

    final referenceMotion = _referenceRevealMotionFor(plan.strokes);
    final statusMessage =
        '${plan.entries.length} ordered scene reveal(s) ready with one writing path each.';
    final changed = await _applyPlannedStrokes(
      plan.strokes,
      action: 'apply-ordered-scene-reveals',
      statusMessage: statusMessage,
      sectionNames: {
        for (final entry in plan.entries)
          SectionId(entry.region.id): entry.region.name,
      },
      sectionTimings: referenceMotion.sectionTimings,
      motionConfiguration: referenceMotion.motionConfiguration,
    );
    if (!changed || isClosed) return changed;
    emit(
      state.copyWith(
        activeStroke: const [],
        selectedStrokeIndex: plan.strokes.length - 1,
        smartSections: const [],
        autoPathResult: AutoPathResultSummary(
          sectionCount: plan.entries.length,
          pathCount: plan.entries.length,
          handSectionCount: 0,
          revealSectionCount: plan.entries.length,
          textSectionCount: 0,
          artworkSectionCount: plan.entries.length,
          nativeVectorCount: 0,
        ),
        selectedSmartSectionId: null,
        selectedTimelineSectionIds: const {},
        selectedTimelineSceneId: null,
        tool: EditorTool.select,
        isAnalyzingSmartPaths: false,
        smartPathProgress: null,
        smartPathAnalysisElapsed: Duration.zero,
        statusMessage: statusMessage,
      ),
    );
    return true;
  }

  /// Runs Auto Path independently inside every confirmed scene mask.
  ///
  /// Results keep the authored scene order and are committed through the same
  /// batch operation as ordinary Auto Path, so Preview, MOV and Undo continue
  /// to share one document timeline.
  Future<bool> analyzeSmartPathsByRegions(List<SceneRegion> regions) async {
    final drawing = state.drawingImage;
    if (drawing == null || regions.isEmpty || state.isAnalyzingSmartPaths) {
      return false;
    }
    final canvasRevision = state.canvasRevision;
    final operationGeneration = ++_sceneRegionAnalysisGeneration;
    _sceneRegionCancellation?.cancel();
    final cancellation = SmartPathCancellationToken();
    _sceneRegionCancellation = cancellation;
    _pendingSmartPathProcessing = const SmartPathProcessingRecord(
      engineId: 'handdraw-smart-scene-split',
      algorithmVersion: 1,
    );
    _pendingNativeStrokes = const {};
    _pendingSceneRegions = {for (final region in regions) region.id: region};
    emit(
      state.copyWith(
        isAnalyzingSmartPaths: true,
        smartPathProgress: const SmartPathProgress(
          stage: SmartPathProgressStage.preparingRaster,
          fraction: 0.01,
        ),
        smartPathAnalysisElapsed: Duration.zero,
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        statusMessage: 'Preparing ${regions.length} smart scene(s)…',
      ),
    );
    _startSmartPathProgressClock(canvasRevision, drawing);
    try {
      final sections = await _regionAutoPathAnalyzer.analyze(
        source: drawing,
        regions: regions,
        facade: _artworkPathFacade,
        cancellationToken: cancellation,
        isCancelled: () =>
            operationGeneration != _sceneRegionAnalysisGeneration ||
            !_ownsCanvasOperation(canvasRevision, drawing),
        onProgress: (index, count, update) {
          if (operationGeneration != _sceneRegionAnalysisGeneration ||
              !_ownsCanvasOperation(canvasRevision, drawing)) {
            return;
          }
          final fraction = (((index + update.fraction) / count) * 0.90).clamp(
            0.0,
            0.90,
          );
          _reportSmartPathProgress(
            canvasRevision,
            drawing,
            SmartPathProgress(stage: update.stage, fraction: fraction),
          );
        },
      );
      if (operationGeneration != _sceneRegionAnalysisGeneration) {
        return false;
      }
      if (!_ownsCanvasOperation(canvasRevision, drawing)) {
        _pendingSceneRegions = const {};
        _stopSmartPathProgressClock();
        return false;
      }
      final regionsById = {for (final region in regions) region.id: region};
      final pendingRegions = {...regionsById};
      for (final section in sections) {
        final region = regionsById[section.id.split('::').first];
        if (region != null) pendingRegions[section.id] = region;
      }
      _pendingSceneRegions = Map.unmodifiable(pendingRegions);
      if (sections.isEmpty) {
        _stopSmartPathProgressClock();
        _pendingSceneRegions = const {};
        emit(
          state.copyWith(
            isAnalyzingSmartPaths: false,
            smartPathProgress: null,
            smartPathAnalysisElapsed: Duration.zero,
            statusMessage: 'No drawable content was found in the scene masks.',
          ),
        );
        return false;
      }
      emit(
        state.copyWith(
          smartSections: sections,
          selectedSmartSectionId: sections.first.id,
          selectedTimelineSectionIds: const {},
          selectedTimelineSceneId: null,
          suggestionOrderCustomized: true,
          isAnalyzingSmartPaths: true,
          smartPathProgress: const SmartPathProgress(
            stage: SmartPathProgressStage.finalizing,
            fraction: 0.90,
          ),
          statusMessage: 'Finalizing ${sections.length} smart scene(s)…',
        ),
      );
      final applied = await applySmartPathSuggestions(
        isCancelled: () =>
            cancellation.isCancelled ||
            operationGeneration != _sceneRegionAnalysisGeneration ||
            !_ownsCanvasOperation(canvasRevision, drawing),
      );
      _stopSmartPathProgressClock();
      return applied;
    } catch (error) {
      if (operationGeneration != _sceneRegionAnalysisGeneration) return false;
      _pendingSceneRegions = const {};
      _stopSmartPathProgressClock();
      if (!_ownsCanvasOperation(canvasRevision, drawing)) return false;
      emit(
        state.copyWith(
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: 'Smart scene split failed: $error',
        ),
      );
      return false;
    } finally {
      if (identical(_sceneRegionCancellation, cancellation)) {
        _sceneRegionCancellation = null;
      }
    }
  }

  void cancelSmartSceneAnalysis() {
    _sceneRegionAnalysisGeneration++;
    _sceneRegionCancellation?.cancel();
    _sceneRegionCancellation = null;
    _pendingSceneRegions = const {};
    _stopSmartPathProgressClock();
    if (state.isAnalyzingSmartPaths) {
      emit(
        state.copyWith(
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: 'Smart scene analysis cancelled.',
        ),
      );
    }
  }

  Future<void> analyzeSmartPaths({bool autoApply = true}) async {
    final encoded = state.drawingAnalysisEncoded;
    final drawing = state.drawingImage;
    if (drawing == null || encoded == null || encoded.isEmpty) {
      emit(
        state.copyWith(
          statusMessage: 'Import a drawing before using Auto Path.',
        ),
      );
      return;
    }
    final canvasRevision = state.canvasRevision;
    _pendingSmartPathProcessing = null;
    _pendingNativeStrokes = const {};
    emit(
      state.copyWith(
        isAnalyzingSmartPaths: true,
        smartPathProgress: const SmartPathProgress(
          stage: SmartPathProgressStage.recognizingText,
          fraction: 0.01,
        ),
        smartPathAnalysisElapsed: Duration.zero,
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        statusMessage: 'Detecting text, shapes, and pen paths…',
      ),
    );
    _startSmartPathProgressClock(canvasRevision, drawing);
    try {
      final result = await _artworkPathFacade.analyze(
        _artworkPathRequest(
          drawing,
          encoded,
          onProgress: (update) =>
              _reportSmartPathProgress(canvasRevision, drawing, update),
        ),
      );
      final analysis = result.analysis;
      if (!_ownsCanvasOperation(canvasRevision, drawing)) {
        _stopSmartPathProgressClock();
        return;
      }
      _stopSmartPathProgressClock();
      _pendingSmartPathProcessing = analysis.processing;
      _pendingNativeStrokes = _nativeStrokesFrom(result.nativePaths);
      final nativeSvgSections = result.nativePaths.isEmpty
          ? _nativeSvgSmartSections(project)
          : analysis.sections
                .where(
                  (section) => section.id.startsWith(_svgEditSectionPrefix),
                )
                .toList(growable: false);
      final hasNativeSvgText =
          project.strokes.any(
            (stroke) => _isNativeSvgStroke(stroke) && stroke.isTextShape,
          ) ||
          result.nativePaths.any((path) => path.isText);
      final sections = result.nativePaths.isNotEmpty
          ? analysis.sections
          : nativeSvgSections.isEmpty
          ? analysis.sections
          : [
              ...nativeSvgSections,
              if (!hasNativeSvgText)
                ...analysis.sections.where(
                  (section) => section.kind == SmartSectionKind.text,
                ),
            ];
      final suffix = analysis.warnings.isEmpty
          ? ''
          : ' • ${analysis.warnings.first}';
      final autoOrder = _suggestTimelineOrder(sections);
      final byId = {for (final section in sections) section.id: section};
      final orderedSections = [
        for (final id in autoOrder) ?byId.remove(id),
        ...byId.values,
      ];
      final suspectedFrames = orderedSections
          .where((section) => section.isSuspectedFrame)
          .toList(growable: false);
      emit(
        state.copyWith(
          smartSections: orderedSections,
          selectedSmartSectionId: sections.isEmpty ? null : sections.first.id,
          selectedStrokeIndex: null,
          tool: EditorTool.select,
          selectedTimelineSectionIds: const {},
          selectedTimelineSceneId: null,
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: sections.isEmpty
              ? 'Auto Path did not find a clear section.$suffix'
              : suspectedFrames.isNotEmpty
              ? '${suspectedFrames.length} high-confidence frame candidate(s) excluded for review. Restore any intentional border, then apply.$suffix'
              : nativeSvgSections.isEmpty
              ? '${sections.length} section(s) detected and ready.$suffix'
              : '${nativeSvgSections.length} native SVG path(s) preserved; ${sections.length - nativeSvgSections.length} raster text section(s) detected.$suffix',
        ),
      );
      if (sections.isNotEmpty && autoApply && suspectedFrames.isEmpty) {
        await applySmartPathSuggestions();
      }
    } catch (error) {
      _stopSmartPathProgressClock();
      if (!_ownsCanvasOperation(canvasRevision, drawing)) return;
      emit(
        state.copyWith(
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: 'Auto Path failed: $error',
        ),
      );
    }
  }

  final _imageAnimationAnalyzer = ImageAnimationAnalyzer();
  int _imageAnimationGeneration = 0;
  bool _imageAnimationRunning = false;
  bool get isImageAnimationAnalyzing => _imageAnimationRunning;

  void cancelImageAnimation() {
    _imageAnimationGeneration++;
    _imageAnimationAnalyzer.cancel();
    if (_imageAnimationRunning && !isClosed) {
      emit(
        state.copyWith(isAnalyzingSmartPaths: false, smartPathProgress: null),
      );
    }
    _imageAnimationRunning = false;
  }

  void openImageAnimationControls() =>
      emit(state.copyWith(imageAnimationControlsOpen: true));

  void setImagePathEditing(bool value) => emit(
    state.copyWith(
      editingImagePaths: value,
      selectedStrokeIndex: value ? state.selectedStrokeIndex : null,
    ),
  );

  void setShowDrawingHand(bool value) => _setMotion(
    state.document.motionConfiguration.copyWith(showDrawingHand: value),
    'showDrawingHand',
  );

  void setImageAnimationEffect(String value) {
    if (!['drawPaint', 'reveal', 'penReveal'].contains(value)) return;
    _setMotion(
      state.document.motionConfiguration.copyWith(imageAnimationEffect: value),
      'imageAnimationEffect',
    );
  }

  Future<bool> applyCodexDrawingPlan(
    CodexDrawingPlan plan,
    ProjectDocument expected, {
    ProjectDocument? replacementBase,
    void Function(Object error)? onFailure,
  }) async {
    if (!identical(state.document, expected) || state.isAnalyzingSmartPaths) {
      return false;
    }
    return prepareImageAnimation(
      effect: 'drawPaint',
      regions: plan.regions,
      codexPlan: plan,
      codexReplacementBase: replacementBase,
      onFailure: onFailure,
    );
  }

  Future<bool> prepareImageAnimation({
    String? effect,
    List<SceneRegion>? regions,
    CodexDrawingPlan? codexPlan,
    ProjectDocument? codexReplacementBase,
    void Function(Object error)? onFailure,
  }) async {
    if (!hasDrawing || state.isAnalyzingSmartPaths) return false;
    final drawing = state.drawingImage!;
    final revision = state.canvasRevision;
    final expectedDocument = state.document;
    final baseline = codexReplacementBase ?? expectedDocument;
    final generation = ++_imageAnimationGeneration;
    final selectedEffect =
        effect ??
        (['reveal', 'penReveal'].contains(project.imageAnimationEffect)
            ? project.imageAnimationEffect
            : 'drawPaint');
    _imageAnimationRunning = true;
    emit(
      state.copyWith(
        isAnalyzingSmartPaths: true,
        smartPathProgress: const SmartPathProgress(
          stage: SmartPathProgressStage.readingPixels,
          fraction: 0,
        ),
        activeStroke: const [],
      ),
    );
    try {
      if (regions != null && regions.isNotEmpty) {
        final target = _manualStrokeTarget(baseline).section;
        final prefix = 'image-part-${DateTime.now().microsecondsSinceEpoch}';
        final parts = [
          for (var i = 0; i < regions.length; i++)
            regions[i].copyWith(
              id: i == 0 && target != null ? target.id.value : '$prefix-$i',
            ),
        ];
        bool cancelled() =>
            isClosed ||
            generation != _imageAnimationGeneration ||
            !_ownsCanvasOperation(revision, drawing) ||
            !identical(state.document, expectedDocument);
        final paths = selectedEffect == 'drawPaint'
            ? await const ImagePartsPlanner().build(
                source: drawing,
                regions: parts,
                analyzer: _imageAnimationAnalyzer,
                isCancelled: cancelled,
                revealRegionIds: {
                  if (codexPlan != null)
                    for (var i = 0; i < parts.length; i++)
                      if (codexPlan.parts[i].mode == 'reveal') parts[i].id,
                },
                textRegionIds: {
                  if (codexPlan != null)
                    for (var i = 0; i < parts.length; i++)
                      if (codexPlan.parts[i].mode == 'write') parts[i].id,
                },
                backgroundExclusions: {
                  if (codexPlan != null)
                    for (var i = 0; i < parts.length; i++)
                      if (codexPlan.parts[i].excludeText &&
                          codexPlan.parts[i].mode == 'reveal')
                        parts[i].id: [
                          for (final bounds in codexPlan.textExclusionBounds)
                            if (bounds.overlaps(codexPlan.parts[i].bounds))
                              bounds.intersect(codexPlan.parts[i].bounds),
                        ],
                },
                canvasHeight: baseline.canvas.height.toDouble(),
              )
            : _sceneRegionRevealPlanner
                  .build(
                    regions: parts,
                    canvasHeight: baseline.canvas.height.toDouble(),
                  )
                  .strokes;
        if (paths == null || paths.isEmpty || cancelled()) return false;
        final applied = await _applyPlannedStrokes(
          paths,
          action: 'prepare-image-parts',
          replacementBase: codexReplacementBase,
          sectionTimings: {
            if (codexPlan != null)
              for (var i = 0; i < parts.length; i++)
                SectionId(parts[i].id): DocumentSectionTiming(
                  animationDuration: TimelineDuration.fromMicroseconds(
                    (codexPlan.parts[i].seconds *
                            Duration.microsecondsPerSecond)
                        .round(),
                  ),
                  keepHandVisibleAfterDrawing: codexPlan.showHand,
                ),
          },
          statusMessage: '${parts.length} image parts ready.',
          sectionNames: {
            for (final part in parts) SectionId(part.id): part.name,
          },
          motionConfiguration: baseline.motionConfiguration.copyWith(
            imageAnimationEffect: selectedEffect,
            showDrawingHand:
                codexPlan?.showHand ??
                baseline.motionConfiguration.showDrawingHand,
          ),
          preserveExistingSections: true,
          isCancelled: () => generation != _imageAnimationGeneration,
        );
        if (!isClosed && generation == _imageAnimationGeneration) {
          emit(
            state.copyWith(
              tool: EditorTool.select,
              activeStroke: const [],
              selectedStrokeIndex: null,
              smartSections: const [],
              autoPathResult: null,
              selectedSmartSectionId: null,
            ),
          );
        }
        return applied;
      }
      final encoded = state.drawingAnalysisEncoded;
      final bytes = selectedEffect == 'penReveal'
          ? Uint8List(0)
          : encoded != null
          ? base64Decode(encoded)
          : (await drawing.toByteData(
              format: ImageByteFormat.png,
            ))!.buffer.asUint8List();
      if (generation != _imageAnimationGeneration) return false;
      final plan = selectedEffect == 'penReveal'
          ? null
          : await _imageAnimationAnalyzer.analyze(bytes);
      if ((plan == null && selectedEffect != 'penReveal') ||
          generation != _imageAnimationGeneration ||
          !_ownsCanvasOperation(revision, drawing) ||
          !identical(state.document, expectedDocument)) {
        return false;
      }
      final target = _manualStrokeTarget(baseline).section;
      final section = target?.id ?? _allocation().sectionId();
      final paths = selectedEffect == 'penReveal'
          ? [
              DrawingStroke(
                id: 'single-pen-reveal',
                name: 'Single pen reveal',
                sectionId: section.value,
                points: const [Offset(0, .5), Offset(1, .5)],
                revealOnly: true,
                isPaintStroke: true,
                revealStyle: RevealMaskStyle.directionalWipe,
                clipBounds: const Rect.fromLTWH(0, 0, 1, 1),
              ),
            ]
          : selectedEffect == 'reveal'
          ? const OpaqueRasterRevealPlanner()
                .build(project: project)
                .map(
                  (s) =>
                      s.copyWith(sectionId: section.value, isPaintStroke: true),
                )
                .toList()
          : plan!
                .ordered(ImageDrawingOrder.regionFirst)
                .map(
                  (s) => s.stroke.copyWith(
                    sectionId: section.value,
                    isPaintStroke: s.role == ImageStrokeRole.paint,
                    paintRegion: s.region,
                  ),
                )
                .toList();
      // Prefix IDs to avoid collisions with paths retained in other scenes.
      final unique = [
        for (final stroke in paths)
          stroke.copyWith(id: '${section.value}-${stroke.id}'),
      ];
      final applied = await _applyPlannedStrokes(
        unique,
        action: 'prepare-image-animation',
        statusMessage: 'Drawing ready.',
        sectionNames: {section: target?.name ?? 'Image animation'},
        motionConfiguration: baseline.motionConfiguration.copyWith(
          imageAnimationEffect: selectedEffect,
        ),
        preserveExistingSections: true,
        isCancelled: () => generation != _imageAnimationGeneration,
      );
      if (!isClosed && generation == _imageAnimationGeneration) {
        emit(
          state.copyWith(
            tool: EditorTool.select,
            selectedStrokeIndex: null,
            smartSections: const [],
            autoPathResult: null,
            selectedSmartSectionId: null,
          ),
        );
      }
      return applied;
    } catch (error) {
      onFailure?.call(error);
      if (!isClosed && generation == _imageAnimationGeneration) {
        emit(state.copyWith(statusMessage: '$error'));
      }
      return false;
    } finally {
      if (!isClosed && generation == _imageAnimationGeneration) {
        _imageAnimationRunning = false;
        emit(
          state.copyWith(isAnalyzingSmartPaths: false, smartPathProgress: null),
        );
      }
    }
  }

  void setStrokePainting(int index, bool paint) {
    final id = _strokeIdAt(index);
    if (id == null) return;
    _replaceDocument(
      kind: DocumentOperationKind.strokeApplyBatch,
      update: (d) => d.copyWith(
        strokes: [
          for (final s in d.strokes)
            s.id == id
                ? s.copyWith(
                    isPaintStroke: paint,
                    revealWidth: paint ? 32.0 : 8.0,
                  )
                : s,
        ],
      ),
      affectedScopes: const {DocumentScope.strokes},
      action: 'set-stroke-paint-role',
      entityIds: [id.value],
    );
  }

  void orderImageStrokes(bool regionsFirst) {
    final section = _manualStrokeTarget(state.document).section;
    if (section == null) return;
    _replaceDocument(
      kind: DocumentOperationKind.strokeApplyBatch,
      update: (d) {
        final sorted = d.strokes
            .where((s) => s.sectionId == section.id)
            .toList();
        final rank = {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
        sorted.sort((a, b) {
          final group = regionsFirst
              ? a.paintRegion.compareTo(b.paintRegion)
              : (a.isPaintStroke ? 1 : 0).compareTo(b.isPaintStroke ? 1 : 0);
          return group != 0 ? group : rank[a.id]!.compareTo(rank[b.id]!);
        });
        var index = 0;
        return d.copyWith(
          strokes: [
            for (final s in d.strokes)
              s.sectionId == section.id ? sorted[index++] : s,
          ],
          sections: [
            for (final s in d.sections)
              s.id == section.id
                  ? s.copyWith(strokeIds: sorted.map((s) => s.id).toList())
                  : s,
          ],
        );
      },
      affectedScopes: const {
        DocumentScope.strokes,
        DocumentScope.sections,
        DocumentScope.ordering,
      },
      action: 'order-image-strokes',
      entityIds: [section.id.value],
    );
  }

  Future<void> createAutoReveal() async {
    final encoded = state.drawingAnalysisEncoded;
    final drawing = state.drawingImage;
    if (drawing == null || encoded == null || encoded.isEmpty) {
      emit(
        state.copyWith(
          statusMessage: 'Import a drawing before using Auto Reveal.',
        ),
      );
      return;
    }
    final canvasRevision = state.canvasRevision;
    final opaqueRasterBytes = await _opaqueRasterBytes(encoded);
    if (opaqueRasterBytes != null) {
      if (!_ownsCanvasOperation(canvasRevision, drawing)) return;
      final outlineFillPlan = await _outlineFillRevealPlanner.build(
        encoded: opaqueRasterBytes,
        project: project,
      );
      if (!_ownsCanvasOperation(canvasRevision, drawing)) return;
      final plannedStrokes = outlineFillPlan.strokes;
      final statusMessage = outlineFillPlan.usedSafeFallback
          ? 'Auto Reveal ready with a continuous side-to-side hand sweep.'
          : 'Smart Region Reveal ready with ${outlineFillPlan.selectedAlgorithmLabel} detail analysis.';
      final referenceMotion = _referenceRevealMotionFor(plannedStrokes);
      final changed = await _applyPlannedStrokes(
        plannedStrokes,
        action: outlineFillPlan.usedSafeFallback
            ? 'apply-opaque-raster-auto-reveal'
            : 'apply-smart-region-reveal',
        statusMessage: statusMessage,
        sectionTimings: referenceMotion.sectionTimings,
        motionConfiguration: referenceMotion.motionConfiguration,
      );
      if (!changed) return;
      emit(
        state.copyWith(
          activeStroke: const [],
          selectedStrokeIndex: plannedStrokes.length - 1,
          smartSections: const [],
          selectedSmartSectionId: null,
          selectedTimelineSectionIds: const {},
          selectedTimelineSceneId: null,
          tool: EditorTool.select,
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: statusMessage,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        isAnalyzingSmartPaths: true,
        smartPathProgress: const SmartPathProgress(
          stage: SmartPathProgressStage.recognizingText,
          fraction: 0.01,
        ),
        smartPathAnalysisElapsed: Duration.zero,
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        statusMessage: 'Building a smooth reveal for the entire artwork…',
      ),
    );
    _startSmartPathProgressClock(canvasRevision, drawing);
    try {
      final result = await _artworkPathFacade.analyze(
        _artworkPathRequest(
          drawing,
          encoded,
          onProgress: (update) =>
              _reportSmartPathProgress(canvasRevision, drawing, update),
        ),
      );
      final analysis = result.analysis;
      if (!_ownsCanvasOperation(canvasRevision, drawing)) {
        _stopSmartPathProgressClock();
        return;
      }
      _stopSmartPathProgressClock();
      final generatedNative = _nativeStrokesFrom(
        result.nativePaths,
      ).values.toList(growable: false);
      final nativeSvgStrokes = generatedNative.isEmpty
          ? _nativeSvgStrokes(project)
          : generatedNative;
      final hasNativeSvgText = nativeSvgStrokes.any(
        (stroke) => stroke.isTextShape,
      );
      final revealSections = nativeSvgStrokes.isEmpty
          ? analysis.sections
          : hasNativeSvgText
          ? const <SmartPathSection>[]
          : analysis.sections
                .where((section) => section.kind == SmartSectionKind.text)
                .toList(growable: false);
      final plan = nativeSvgStrokes.isNotEmpty && revealSections.isEmpty
          ? const AutoRevealPlan(strokes: [], usedFallback: false)
          : _autoRevealPlanner.build(
              sections: revealSections,
              project: project,
            );
      final plannedStrokes = nativeSvgStrokes.isEmpty
          ? plan.strokes
          : [
              for (final stroke in nativeSvgStrokes)
                stroke.copyWith(
                  revealOnly: true,
                  revealStyle: stroke.isFilledShape || stroke.isTextShape
                      ? RevealMaskStyle.directionalWipe
                      : RevealMaskStyle.brush,
                ),
              ...plan.strokes,
            ];
      final statusMessage = nativeSvgStrokes.isNotEmpty
          ? 'Auto Reveal ready using native SVG geometry; raster tracing was skipped.'
          : plan.usedFallback
          ? 'Auto Reveal ready using a full-artwork directional wipe.'
          : 'Auto Reveal ready: ${plan.strokes.length} section(s) in visual order.';
      final referenceMotion = _referenceRevealMotionFor(plannedStrokes);
      final changed = await _applyPlannedStrokes(
        plannedStrokes,
        action: 'apply-auto-reveal',
        statusMessage: statusMessage,
        sectionTimings: referenceMotion.sectionTimings,
        motionConfiguration: referenceMotion.motionConfiguration,
      );
      if (!changed) return;
      emit(
        state.copyWith(
          activeStroke: const [],
          selectedStrokeIndex: plannedStrokes.isEmpty
              ? null
              : plannedStrokes.length - 1,
          smartSections: const [],
          selectedSmartSectionId: null,
          selectedTimelineSectionIds: const {},
          selectedTimelineSceneId: null,
          tool: EditorTool.select,
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: statusMessage,
        ),
      );
    } catch (error) {
      _stopSmartPathProgressClock();
      if (!_ownsCanvasOperation(canvasRevision, drawing)) return;
      final nativeSvgStrokes = _nativeSvgStrokes(project);
      final fallback = nativeSvgStrokes.isEmpty
          ? _autoRevealPlanner.build(sections: const [], project: project)
          : AutoRevealPlan(
              strokes: [
                for (final stroke in project.strokes)
                  if (_isNativeSvgStroke(stroke))
                    stroke.copyWith(
                      revealOnly: true,
                      revealStyle: stroke.isFilledShape || stroke.isTextShape
                          ? RevealMaskStyle.directionalWipe
                          : RevealMaskStyle.brush,
                    )
                  else if (!stroke.id.startsWith('auto-'))
                    stroke,
              ],
              usedFallback: false,
            );
      final statusMessage = nativeSvgStrokes.isEmpty
          ? 'Auto Reveal ready with the safe full-artwork fallback.'
          : 'Auto Reveal ready using native SVG geometry; OCR was unavailable.';
      final referenceMotion = _referenceRevealMotionFor(fallback.strokes);
      final changed = await _applyPlannedStrokes(
        fallback.strokes,
        action: 'apply-auto-reveal-fallback',
        statusMessage: statusMessage,
        sectionTimings: referenceMotion.sectionTimings,
        motionConfiguration: referenceMotion.motionConfiguration,
      );
      if (!changed) return;
      emit(
        state.copyWith(
          activeStroke: const [],
          selectedStrokeIndex: fallback.strokes.length - 1,
          smartSections: const [],
          selectedSmartSectionId: null,
          selectedTimelineSectionIds: const {},
          selectedTimelineSceneId: null,
          tool: EditorTool.select,
          isAnalyzingSmartPaths: false,
          smartPathProgress: null,
          smartPathAnalysisElapsed: Duration.zero,
          statusMessage: statusMessage,
        ),
      );
    }
  }

  Future<Uint8List?> _opaqueRasterBytes(String previewEncoded) async {
    if (project.drawingSourceKind != ArtworkSourceKind.raster) return null;
    final encoded = project.drawingSourceBase64 ?? previewEncoded;
    final bytes = _decodeEmbeddedBytes(encoded);
    if (bytes.isEmpty) return null;
    try {
      final result = await _fileService.rasterAlphaBoundsScanner.scan(bytes);
      return result.status == RasterAlphaBoundsStatus.opaque ? bytes : null;
    } on Object {
      // Analysis uncertainty must preserve the established raster behavior.
      return null;
    }
  }

  void selectSmartSection(String id) {
    if (!state.smartSections.any((section) => section.id == id)) return;
    emit(
      state.copyWith(
        selectedSmartSectionId: id,
        selectedTimelineSceneId: null,
        selectedStrokeIndex: null,
      ),
    );
  }

  bool selectSmartSectionAt(Offset normalizedPoint) {
    final matches =
        state.smartSections
            .where(
              (section) =>
                  section.bounds.inflate(0.006).contains(normalizedPoint),
            )
            .toList()
          ..sort(
            (a, b) =>
                a.bounds.size.longestSide.compareTo(b.bounds.size.longestSide),
          );
    if (matches.isEmpty) return false;
    selectSmartSection(matches.first.id);
    return true;
  }

  void setSmartSectionMode(String id, SmartSectionMode mode) {
    final sections = state.smartSections
        .map(
          (section) =>
              section.id == id ? section.copyWith(mode: mode) : section,
        )
        .toList(growable: false);
    if (!sections.any((section) => section.id == id)) return;
    emit(state.copyWith(smartSections: sections, selectedSmartSectionId: id));
  }

  void setAllSmartSectionModes(SmartSectionMode mode) {
    emit(
      state.copyWith(
        smartSections: state.smartSections
            .map((section) => section.copyWith(mode: mode))
            .toList(growable: false),
      ),
    );
  }

  void autoArrangeTimeline() {
    if (state.smartSections.isEmpty) return;
    final order = _suggestTimelineOrder(state.smartSections);
    final groups = _timelineService.sanitizeGroups(
      groups: project.sceneGroups,
      availableSectionIds: order,
    );
    // Auto Arrange keeps user-created scenes, but makes every scene atomic by
    // placing its members together in the suggested spatial/semantic order.
    var arranged = order;
    for (final group in groups.reversed) {
      final members = arranged
          .where(group.sectionIds.toSet().contains)
          .toList(growable: false);
      if (members.isEmpty) continue;
      final memberSet = members.toSet();
      final first = arranged.indexWhere(memberSet.contains);
      final remainder = arranged
          .where((id) => !memberSet.contains(id))
          .toList();
      remainder.insertAll(first.clamp(0, remainder.length), members);
      arranged = remainder;
    }
    final byId = {
      for (final section in state.smartSections) section.id: section,
    };
    emit(
      state.copyWith(
        smartSections: [for (final id in arranged) ?byId[id]],
        suggestionOrderCustomized: true,
        statusMessage: 'Timeline arranged by semantic flow and pen travel.',
      ),
    );
  }

  List<String> _suggestTimelineOrder(List<SmartPathSection> sections) {
    final strokes = _strokePlanner
        .build(sections: sections, project: project)
        .strokes;
    final seen = <String>{};
    return _timelineService.resolveOrder(
      availableSectionIds: sections
          .where((section) => section.mode != SmartSectionMode.ignore)
          .map((section) => section.id),
      preferredOrder: [
        for (final stroke in strokes)
          if (stroke.sectionId case final id?)
            if (seen.add(id)) id,
      ],
    );
  }

  Future<bool> applySmartPathSuggestions({bool Function()? isCancelled}) async {
    if (state.smartSections.isEmpty || isCancelled?.call() == true) {
      return false;
    }
    await _cancelAutoPathPlanning();
    final applyGeneration = ++_smartPathApplyGeneration;
    bool operationIsCancelled() =>
        applyGeneration != _smartPathApplyGeneration ||
        isCancelled?.call() == true;
    if (!state.isAnalyzingSmartPaths) {
      emit(
        state.copyWith(
          isAnalyzingSmartPaths: true,
          smartPathProgress: const SmartPathProgress(
            stage: SmartPathProgressStage.finalizing,
            fraction: 0.90,
          ),
          statusMessage: 'Finalizing automatic paths…',
        ),
      );
    }
    try {
      final applied = await _applySmartPathSuggestionsInternal(
        isCancelled: operationIsCancelled,
      );
      if (!applied &&
          applyGeneration == _smartPathApplyGeneration &&
          !isClosed &&
          state.isAnalyzingSmartPaths) {
        emit(
          state.copyWith(
            isAnalyzingSmartPaths: false,
            smartPathProgress: null,
            smartPathAnalysisElapsed: Duration.zero,
          ),
        );
      }
      return applied;
    } catch (error) {
      if (applyGeneration == _smartPathApplyGeneration && !isClosed) {
        emit(
          state.copyWith(
            isAnalyzingSmartPaths: false,
            smartPathProgress: null,
            smartPathAnalysisElapsed: Duration.zero,
            statusMessage: 'Could not finalize automatic paths: $error',
          ),
        );
      }
      rethrow;
    }
  }

  Future<bool> _applySmartPathSuggestionsInternal({
    bool Function()? isCancelled,
  }) async {
    final svgSections = {
      for (final section in state.smartSections)
        if (section.id.startsWith(_svgEditSectionPrefix))
          section.id.substring(_svgEditSectionPrefix.length): section,
    };
    final sceneSplitRegions = _orderedPendingSceneRegions();
    final isSceneSplit = sceneSplitRegions.isNotEmpty;
    final planning = _strokePlanner.startResponsive(
      sections: state.smartSections,
      project: project,
      // Let Auto Path establish its normal semantic reading order first. The
      // scene pass below groups that stable result by the authored scene order.
      // Passing every generated sub-section as an explicit timeline order here
      // used to freeze the analyzer's incidental order and made the hand jump
      // back to earlier artwork inside a scene.
      sceneGroups: isSceneSplit ? const [] : timelineSceneGroups,
      timelineSectionOrder: isSceneSplit || !state.suggestionOrderCustomized
          ? const []
          : timelineSectionOrder,
    );
    _autoPathPlanningOperation = planning;
    late final AutoPathPlan planned;
    try {
      planned = await planning.result;
    } on AutoPathPlanningCancelled {
      return false;
    } finally {
      if (identical(_autoPathPlanningOperation, planning)) {
        _autoPathPlanningOperation = null;
      }
    }
    if (isCancelled?.call() == true) return false;
    final plan = !isSceneSplit
        ? planned
        : AutoPathPlan(
            const SceneSplitStrokeOrderer().order(
              strokes: planned.strokes,
              regions: sceneSplitRegions,
              sectionRegions: _pendingSceneRegions,
            ),
          );
    await Future<void>.delayed(Duration.zero);
    final textExclusions = state.smartSections
        .where((section) => section.kind == SmartSectionKind.text)
        .map(
          (section) => section.bounds
              .inflate(0.003)
              .intersect(const Rect.fromLTWH(0, 0, 1, 1)),
        )
        .toList(growable: false);
    if (svgSections.isNotEmpty) beginSectionTimingEdit();
    final nativeById = {
      for (final stroke in project.strokes)
        if (svgSections.containsKey(stroke.id)) stroke.id: stroke,
      ..._pendingNativeStrokes,
    };
    final insertedNativeIds = <String>{};
    final preciseTextStrokeCounts = <String, int>{};
    final orderedSuggestions = <DrawingStroke>[];
    final sceneClipMasks = <String, ImmutablePolygonList<Offset>>{
      for (final region in _pendingSceneRegions.values)
        region.id: ImmutablePolygonList<Offset>.freeze(region.maskPolygons),
    };
    var rasterPathCount = 0;
    for (
      var suggestionIndex = 0;
      suggestionIndex < plan.strokes.length;
      suggestionIndex++
    ) {
      if (suggestionIndex > 0 && suggestionIndex % 128 == 0) {
        if (isCancelled?.call() == true) return false;
        if (state.isAnalyzingSmartPaths) {
          emit(
            state.copyWith(
              smartPathProgress: SmartPathProgress(
                stage: SmartPathProgressStage.finalizing,
                fraction: 0.90 + (0.04 * suggestionIndex / plan.strokes.length),
              ),
            ),
          );
        }
        await Future<void>.delayed(Duration.zero);
      }
      final suggested = plan.strokes[suggestionIndex];
      final sectionId = suggested.sectionId;
      if (sectionId != null && sectionId.startsWith(_svgEditSectionPrefix)) {
        final strokeId = sectionId.substring(_svgEditSectionPrefix.length);
        final original = nativeById[strokeId];
        final section = svgSections[strokeId];
        if (original == null ||
            section == null ||
            section.mode == SmartSectionMode.ignore) {
          continue;
        }
        if ((original.isTextShape || original.isFilledShape) &&
            section.hasPreciseTrace &&
            section.mode == SmartSectionMode.handDraw) {
          insertedNativeIds.add(strokeId);
          final traceIndex = preciseTextStrokeCounts.update(
            strokeId,
            (value) => value + 1,
            ifAbsent: () => 0,
          );
          orderedSuggestions.add(
            suggested.copyWith(
              id: '$strokeId:glyph-$traceIndex',
              name: suggested.revealOnly
                  ? '${original.name} • Complete'
                  : original.name,
              isTextShape: original.isTextShape,
              isFilledShape: original.isFilledShape,
              fillColorValue: original.fillColorValue,
              revealStyle: RevealMaskStyle.brush,
              sectionId: original.sectionId,
              clipBounds: original.isTextShape
                  ? suggested.clipBounds ?? original.clipBounds
                  : original.clipBounds,
              exclusionBounds: original.isTextShape
                  ? [
                      ...original.exclusionBounds,
                      for (final bounds in suggested.exclusionBounds)
                        if (!original.exclusionBounds.contains(bounds)) bounds,
                    ]
                  : original.exclusionBounds,
              vectorMaskStrokes: original.vectorMaskStrokes,
              sceneGroupId: suggested.sceneGroupId,
            ),
          );
          continue;
        }
        if (!insertedNativeIds.add(strokeId)) continue;
        orderedSuggestions.add(
          original.copyWith(
            revealOnly: section.mode == SmartSectionMode.revealText,
            revealStyle: original.isFilledShape || original.isTextShape
                ? RevealMaskStyle.directionalWipe
                : RevealMaskStyle.brush,
            exclusionBounds: original.isFilledShape
                ? original.exclusionBounds.isEmpty
                      ? textExclusions
                      : original.exclusionBounds
                : original.exclusionBounds,
            sceneGroupId: suggested.sceneGroupId,
          ),
        );
        continue;
      }
      final sceneRegion = sectionId == null
          ? null
          : _pendingSceneRegions[sectionId];
      orderedSuggestions.add(
        sceneRegion == null
            ? suggested
            : suggested.copyWith(
                sectionId: sceneRegion.id,
                clipPolygons: sceneClipMasks[sceneRegion.id]!,
              ),
      );
      rasterPathCount++;
    }
    final preservedNonSvg = project.strokes.where(
      (stroke) =>
          !svgSections.containsKey(stroke.id) && !stroke.id.startsWith('auto-'),
    );
    final strokes = [...preservedNonSvg, ...orderedSuggestions];
    final sections = state.smartSections;
    final sceneRegionCount = _pendingSceneRegions.values
        .map((region) => region.id)
        .toSet()
        .length;
    final resultSummary = AutoPathResultSummary(
      sectionCount: sceneRegionCount == 0 ? sections.length : sceneRegionCount,
      pathCount: orderedSuggestions.length,
      handSectionCount: sections
          .where((section) => section.mode == SmartSectionMode.handDraw)
          .length,
      revealSectionCount: sections
          .where((section) => section.mode == SmartSectionMode.revealText)
          .length,
      textSectionCount: sections
          .where((section) => section.kind == SmartSectionKind.text)
          .length,
      artworkSectionCount: sections
          .where((section) => section.kind != SmartSectionKind.text)
          .length,
      nativeVectorCount: svgSections.length,
    );
    final statusMessage = svgSections.isEmpty
        ? '${plan.strokes.length} automatic path(s) added. Preview is ready.'
        : '${insertedNativeIds.length} native SVG path(s) preserved in visual order without raster duplication; $rasterPathCount text path(s) added.';
    final changed = await _applyPlannedStrokes(
      strokes,
      action: 'apply-auto-path',
      statusMessage: statusMessage,
      pathProcessingMetadata: _acceptedPathProcessingMetadata(),
      sectionNames: {
        for (final section in state.smartSections)
          SectionId(_pendingSceneRegions[section.id]?.id ?? section.id):
              _pendingSceneRegions[section.id]?.name ?? section.label,
      },
      isCancelled: isCancelled,
    );
    if (!changed) {
      _pendingSceneRegions = const {};
      if (!isClosed && state.isAnalyzingSmartPaths) {
        emit(
          state.copyWith(
            isAnalyzingSmartPaths: false,
            smartPathProgress: null,
            smartPathAnalysisElapsed: Duration.zero,
          ),
        );
      }
      return false;
    }
    emit(
      state.copyWith(
        selectedStrokeIndex: strokes.isEmpty ? null : strokes.length - 1,
        smartSections: const [],
        autoPathResult: resultSummary,
        selectedSmartSectionId: null,
        selectedTimelineSectionIds: const {},
        selectedTimelineSceneId: null,
        tool: EditorTool.select,
        isAnalyzingSmartPaths: false,
        smartPathProgress: null,
        smartPathAnalysisElapsed: Duration.zero,
        statusMessage: statusMessage,
      ),
    );
    _pendingNativeStrokes = const {};
    _pendingSmartPathProcessing = null;
    _pendingSceneRegions = const {};
    if (svgSections.isNotEmpty) commitSectionTimingEdit();
    return true;
  }

  List<SceneRegion> _orderedPendingSceneRegions() {
    final seen = <String>{};
    return List.unmodifiable([
      for (final region in _pendingSceneRegions.values)
        if (seen.add(region.id)) region,
    ]);
  }

  void clearSmartPathSuggestions() {
    unawaited(_cancelAutoPathPlanning());
    _smartPathApplyGeneration++;
    emit(
      state.copyWith(
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        selectedTimelineSectionIds: const {},
        selectedTimelineSceneId: null,
        tool: EditorTool.select,
        isAnalyzingSmartPaths: false,
        smartPathProgress: null,
        smartPathAnalysisElapsed: Duration.zero,
        statusMessage: 'Auto Path suggestions cleared.',
      ),
    );
    _pendingNativeStrokes = const {};
    _pendingSmartPathProcessing = null;
    _pendingSceneRegions = const {};
  }

  Future<void> _cancelAutoPathPlanning() {
    final operation = _autoPathPlanningOperation;
    _autoPathPlanningOperation = null;
    return operation?.cancel() ?? Future<void>.value();
  }

  ProjectPathProcessingMetadata? _acceptedPathProcessingMetadata() {
    final processing = _pendingSmartPathProcessing;
    final artworkId = state.document.artworkAssetId;
    if (processing == null || artworkId == null) return null;
    ProjectAsset? artwork;
    for (final asset in state.document.assets) {
      if (asset.id == artworkId) {
        artwork = asset;
        break;
      }
    }
    if (artwork == null) return null;
    return ProjectPathProcessingMetadata(
      engineId: processing.engineId,
      algorithmVersion: processing.algorithmVersion,
      sourceAssetHash: artwork.contentHash,
      suspectedFrameDetection: processing.suspectedFrameDetection,
      suspectedFrameConfidenceThreshold:
          processing.suspectedFrameConfidenceThreshold,
    );
  }

  Future<void> setPenTip(Offset normalizedPoint) async {
    final penTip = Offset(
      normalizedPoint.dx.clamp(0.0, 1.0),
      normalizedPoint.dy.clamp(0.0, 1.0),
    );
    final selectedId = state.selectedHandPresetId;
    final updatedPresets = state.handPresets
        .map(
          (preset) => preset.id == selectedId
              ? preset.copyWith(penTip: penTip)
              : preset,
        )
        .toList(growable: false);
    _executeDocumentOperation(
      kind: DocumentOperationKind.settingsSetHand,
      operation: (document) => const ProjectSettingsOperations().setHand(
        document: document,
        configuration: document.handConfiguration.copyWith(
          penTip: DocumentPoint(penTip.dx, penTip.dy),
        ),
      ),
      statusMessage: 'Pen tip calibrated and saved',
    );
    emit(
      state.copyWith(
        handPresets: updatedPresets,
        statusMessage: 'Pen tip calibrated and saved',
      ),
    );
    if (selectedId == null) return;
    try {
      await _handLibraryRepository.save(
        HandLibrarySnapshot(
          presets: updatedPresets,
          selectedPresetId: selectedId,
          applicationDefaults: _handApplicationDefaults,
        ),
      );
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(statusMessage: 'Pen tip set, but save failed: $error'),
        );
      }
    }
  }

  bool clearCanvas() {
    _invalidateDrawingImport();
    if (!state.hasCanvasContent) {
      emit(state.copyWith(statusMessage: 'Canvas is already clear.'));
      return false;
    }
    _cachedImportedSvgPaths = const [];
    _pendingNativeStrokes = const {};
    _clearedCanvasRuntime = _ClearedCanvasRuntime(
      drawingImage: state.drawingImage,
      drawingAnalysisEncoded: state.drawingAnalysisEncoded,
      drawingRevealBaseImage: state.drawingRevealBaseImage,
      svgRevealLayers: state.svgRevealLayers,
      artworkAnimationGuidance: state.artworkAnimationGuidance,
    );
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.settingsClearArtwork,
      operation: (document) =>
          const ProjectSettingsOperations().clearArtwork(document: document),
      statusMessage: 'Canvas cleared. Hand and global settings were kept.',
    );
    if (!changed) return false;
    emit(
      state.copyWith(
        drawingImage: null,
        drawingAnalysisEncoded: null,
        drawingRevealBaseImage: null,
        svgRevealLayers: null,
        artworkAnimationGuidance: ArtworkAnimationGuidance.unknown,
        activeStroke: const [],
        selectedStrokeIndex: null,
        hoveredStrokeIndex: null,
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        selectedTimelineSectionIds: const {},
        selectedTimelineSceneId: null,
        isAnalyzingSmartPaths: false,
        canvasRevision: state.canvasRevision + 1,
        tool: EditorTool.select,
        statusMessage: 'Canvas cleared. Hand and global settings were kept.',
      ),
    );
    return true;
  }

  void restoreClearedCanvas() {
    final runtime = _clearedCanvasRuntime;
    if (runtime == null) return;
    final result = _transactions.undo(
      current: state.documentState,
      history: _history,
    );
    if (!result.isSuccess || result.noOp) return;
    _clearedCanvasRuntime = null;
    emit(
      state.copyWith(
        documentState: result.state,
        drawingImage: runtime.drawingImage,
        drawingAnalysisEncoded: runtime.drawingAnalysisEncoded,
        drawingRevealBaseImage: runtime.drawingRevealBaseImage,
        svgRevealLayers: runtime.svgRevealLayers,
        artworkAnimationGuidance: runtime.artworkAnimationGuidance,
        canvasRevision: state.canvasRevision + 1,
        statusMessage: 'Canvas content restored.',
      ),
    );
  }

  void resetDefaultSettings() {
    final activePresetId = state.document.handConfiguration.presetId;
    final activePreset = state.handPresets
        .where((preset) => preset.id == activePresetId)
        .firstOrNull;
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.settingsResetDefaults,
      operation: (document) => const ProjectSettingsOperations().resetDefaults(
        document: document,
        handConfiguration: activePreset == null
            ? document.handConfiguration
            : document.handConfiguration.copyWith(
                presetId: activePreset.id,
                scale: activePreset.defaultScale,
                rotationDegrees: activePreset.defaultRotationDegrees,
                flipX: activePreset.flipX,
                penTip: DocumentPoint(
                  activePreset.penTip.dx,
                  activePreset.penTip.dy,
                ),
              ),
      ),
      statusMessage: 'Settings reset to defaults. Canvas content was kept.',
    );
    if (changed && activePreset != null) {
      _updateHandApplicationDefaults(
        HandApplicationDefaults.fromPreset(
          activePreset,
          keepHandVisibleAfterDrawing:
              _handApplicationDefaults.keepHandVisibleAfterDrawing,
        ),
        persistImmediately: true,
      );
    }
  }

  bool setCanvasBackground(CanvasBackground background) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.settingsSetCanvas,
        operation: (document) => const ProjectSettingsOperations()
            .setCanvasBackground(document: document, background: background),
        statusMessage: 'Canvas background updated.',
      );

  double get imageAnimationDurationSeconds =>
      resolveProjectTimeline(project).durationSeconds;

  bool setImageAnimationDuration(double value) => _executeDocumentOperation(
    kind: DocumentOperationKind.timingResizeDrawing,
    operation: (document) =>
        const TimelineDocumentOperations().resizeDrawingDuration(
          document: document,
          resolvedDurationSeconds: imageAnimationDurationSeconds,
          targetSeconds: value,
        ),
    mergeProperty: 'imageAnimationDuration',
  );

  void setDuration(double value) => _executeDocumentOperation(
    kind: DocumentOperationKind.settingsSetCanvas,
    operation: (document) {
      final duration = TimelineDuration.fromMicroseconds(
        (value * Duration.microsecondsPerSecond).round(),
      );
      final holds =
          document.motionConfiguration.startDelay.microseconds +
          document.motionConfiguration.endHold.microseconds;
      return DocumentOperationResult.success(
        document: document.copyWith(
          duration: duration,
          motionConfiguration: document.motionConfiguration.copyWith(
            drawingDuration: TimelineDuration.fromMicroseconds(
              math.max(1000, duration.microseconds - holds),
            ),
          ),
        ),
        affectedScopes: const {DocumentScope.canvas, DocumentScope.settings},
        summary: DocumentChangeSummary(action: 'set-duration'),
      );
    },
    mergeProperty: 'duration',
  );

  void setDrawingSpeed(double value) => _setMotion(
    state.document.motionConfiguration.copyWith(
      drawingSpeed: value.clamp(
        minimumProjectDrawingSpeed,
        maximumProjectDrawingSpeed,
      ),
    ),
    'drawingSpeed',
  );

  void setPenTravelSpeed(double value) => _executeDocumentOperation(
    kind: DocumentOperationKind.timingSetPenTravelSpeed,
    operation: (document) =>
        const TimelineDocumentOperations().setPenTravelSpeed(
          document: document,
          multiplier: value.clamp(0.25, 4.0),
        ),
    mergeProperty: 'penTravelSpeed',
  );

  FitToDurationResult fitToDuration(double targetDurationSeconds) {
    final result = fitProjectToDuration(project, targetDurationSeconds);
    if (!result.isSuccess || result.drawingSpeed == null) return result;
    _setMotion(
      state.document.motionConfiguration.copyWith(
        drawingSpeed: result.drawingSpeed,
      ),
      'drawingSpeed',
      statusMessage:
          'Drawing fitted to ${result.resolvedDurationSeconds!.toStringAsFixed(2)}s.',
    );
    return result;
  }

  void setStartDelay(double value) => _setMotion(
    state.document.motionConfiguration.copyWith(
      startDelay: TimelineDuration.fromMicroseconds(
        (value.clamp(0.0, 10.0) * Duration.microsecondsPerSecond).round(),
      ),
    ),
    'startDelay',
  );

  void setEndHold(double value) => _setMotion(
    state.document.motionConfiguration.copyWith(
      endHold: TimelineDuration.fromMicroseconds(
        (value.clamp(0.0, 10.0) * Duration.microsecondsPerSecond).round(),
      ),
    ),
    'endHold',
  );

  void setRevealWidth(double value) => _setMotion(
    state.document.motionConfiguration.copyWith(revealWidth: value),
    'revealWidth',
  );

  void setHandScale(double value) {
    final scale = value.clamp(0.06, 0.90).toDouble();
    _setHand(state.document.handConfiguration.copyWith(scale: scale), 'scale');
    _updateHandApplicationDefaults(
      _handApplicationDefaults.copyWith(scale: scale),
    );
  }

  void setHandRotation(double value) {
    final rotation = value.clamp(-180.0, 180.0).toDouble();
    _setHand(
      state.document.handConfiguration.copyWith(rotationDegrees: rotation),
      'rotation',
    );
    _updateHandApplicationDefaults(
      _handApplicationDefaults.copyWith(rotationDegrees: rotation),
    );
  }

  void setHandFlipX(bool value) {
    _setHand(state.document.handConfiguration.copyWith(flipX: value), 'flipX');
    _updateHandApplicationDefaults(
      _handApplicationDefaults.copyWith(flipX: value),
      persistImmediately: true,
    );
  }

  void setWritingSoundEnabled(bool value) => _setWritingSound(
    state.document.writingSoundConfiguration.copyWith(enabled: value),
    'enabled',
  );

  void setWritingSoundPreset(WritingSoundPreset value) => _setWritingSound(
    state.document.writingSoundConfiguration.copyWith(preset: value),
    'preset',
  );

  void setWritingSoundVolume(double value) => _setWritingSound(
    state.document.writingSoundConfiguration.copyWith(
      volume: value.clamp(0.0, 1.0),
    ),
    'volume',
  );

  void _setMotion(
    ProjectMotionConfiguration configuration,
    String property, {
    String? statusMessage,
  }) => _executeDocumentOperation(
    kind: DocumentOperationKind.settingsSetMotion,
    operation: (document) => const ProjectSettingsOperations().setMotion(
      document: document,
      configuration: configuration,
    ),
    mergeProperty: property,
    statusMessage: statusMessage,
  );

  bool _setHand(ProjectHandConfiguration configuration, String property) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.settingsSetHand,
        operation: (document) => const ProjectSettingsOperations().setHand(
          document: document,
          configuration: configuration,
        ),
        mergeProperty: property,
      );

  void _updateHandApplicationDefaults(
    HandApplicationDefaults defaults, {
    bool persistImmediately = false,
  }) {
    _handApplicationDefaults = defaults;
    _handPreferencesDirty = true;
    if (persistImmediately) commitHandPreferences();
  }

  HandLibrarySnapshot _currentHandLibrarySnapshot() => HandLibrarySnapshot(
    presets: state.handPresets,
    selectedPresetId:
        state.selectedHandPresetId ?? BuiltInHands.defaultPresetId,
    applicationDefaults: _handApplicationDefaults,
  );

  void commitHandPreferences() {
    if (_handPreferencesSaveInFlight != null) return;
    final save = _saveHandPreferences();
    _handPreferencesSaveInFlight = save;
    unawaited(
      save.whenComplete(() {
        _handPreferencesSaveInFlight = null;
        if (_handPreferencesDirty && !isClosed) commitHandPreferences();
      }),
    );
  }

  Future<void> _saveHandPreferences() async {
    while (_handPreferencesDirty) {
      final snapshot = _currentHandLibrarySnapshot();
      _handPreferencesDirty = false;
      try {
        await _handLibraryRepository.save(snapshot);
      } catch (_) {
        _handPreferencesDirty = true;
        // Project edits must remain usable even if the application-support
        // preference file is temporarily unavailable.
        return;
      }
    }
  }

  void _setWritingSound(
    ProjectWritingSoundConfiguration configuration,
    String property,
  ) => _executeDocumentOperation(
    kind: DocumentOperationKind.settingsSetWritingSound,
    operation: (document) => const ProjectSettingsOperations().setWritingSound(
      document: document,
      configuration: configuration,
    ),
    mergeProperty: property,
  );

  SectionTiming sectionTiming(String sectionKey) {
    final id = _sectionIdForKey(sectionKey);
    if (id == null) return const SectionTiming();
    final timing = state.document.sections
        .firstWhere((section) => section.id == id)
        .timing;
    double seconds(TimelineDuration value) =>
        value.microseconds / Duration.microsecondsPerSecond;
    return SectionTiming(
      pauseBeforeEnabled:
          timing.pauseBeforeEnabled || !timing.pauseBefore.isZero,
      pauseBeforeSeconds: seconds(timing.pauseBefore),
      pauseAfterEnabled: timing.pauseAfterEnabled || !timing.pauseAfter.isZero,
      pauseAfterSeconds: seconds(timing.pauseAfter),
      animationDurationSeconds: timing.animationDuration == null
          ? null
          : seconds(timing.animationDuration!),
      transitionAfterSeconds: seconds(timing.transitionAfter),
      speedMultiplier: timing.speedMultiplier,
      pauseHandBehavior:
          timing.pauseHandBehavior == DocumentPauseHandBehavior.hide
          ? PauseHandBehavior.hide
          : PauseHandBehavior.keepVisible,
      voiceCueSeconds: timing.audioCueAnchor == null
          ? null
          : timing.audioCueAnchor!.sourceMediaTime.microseconds /
                Duration.microsecondsPerSecond,
      handEntranceAnimation: timing.handEntranceAnimation,
      handEntranceDurationSeconds: seconds(timing.handEntranceDuration),
      handExitAnimation: timing.handExitAnimation,
      handExitDurationSeconds: seconds(timing.handExitDuration),
      keepHandVisibleAfterDrawing: timing.keepHandVisibleAfterDrawing,
    );
  }

  SectionId? _sectionIdForKey(String key) {
    final raw = key.startsWith('section:')
        ? key.substring('section:'.length)
        : key;
    if (raw.startsWith('stroke:')) {
      final strokeId = StrokeId(raw.substring('stroke:'.length));
      for (final stroke in state.document.strokes) {
        if (stroke.id == strokeId) return stroke.sectionId;
      }
      return null;
    }
    for (final section in state.document.sections) {
      if (section.id.value == raw) return section.id;
    }
    return null;
  }

  void beginSectionTimingEdit() {}

  void commitSectionTimingEdit() {}

  void setSectionPauseBefore(String sectionKey, double seconds) =>
      _setSectionTiming(
        sectionKey,
        sectionTiming(
          sectionKey,
        ).copyWith(pauseBeforeSeconds: seconds.clamp(0.0, 60.0)),
      );

  void selectTimingSection(String? sectionKey) {
    emit(state.copyWith(selectedTimingSectionKey: sectionKey));
  }

  Future<bool> importVoiceGuide({
    VoiceGuidePickerCopy copy = VoiceGuidePickerCopy.english,
  }) async {
    if (state.isVoiceGuideLoading) return false;
    emit(state.copyWith(isVoiceGuideLoading: true));
    try {
      final guide = await _voiceGuideService.importVoiceGuide(copy: copy);
      if (guide == null) {
        if (!isClosed) emit(state.copyWith(isVoiceGuideLoading: false));
        return false;
      }
      if (isClosed) return false;
      final hash = await sha256.bind(File(guide.path).openRead()).first;
      if (isClosed) return false;
      final allocation = _allocation();
      final assetId = allocation.projectAssetId();
      final trackId = allocation.audioTrackId();
      final mediaDuration = TimelineDuration.fromMicroseconds(
        (guide.durationSeconds * Duration.microsecondsPerSecond).round(),
      );
      final voiceAsset = ProjectAsset(
        id: assetId,
        kind: ProjectAssetKind.audio,
        originalFileName: p.basename(guide.path),
        storagePolicy: ProjectAssetStoragePolicy.external,
        contentHash: 'sha256:$hash',
        mediaType: 'audio/*',
        externalLocator: ExternalAssetLocator(
          pathHint: guide.path,
          securityBookmark: guide.securityBookmark,
        ),
        mediaDuration: mediaDuration,
      );
      var session = _session;
      if (session == null || session.isClosed) {
        session = await _adoptDocumentSession(
          documentState: state.documentState,
          history: _history,
          target: _projectTarget,
        );
        await _installSession(session);
      }
      await _sessionCoordinator.staging.registerExternal(
        RegisterExternalAssetRequest(sessionId: session.id, asset: voiceAsset),
      );
      _sessionCoordinator.staging.retain(
        sessionId: session.id,
        assetId: assetId,
        kind: StagedAssetReferenceKind.activeDocument,
      );
      session.activeAssetIds.add(assetId);
      final changed = _replaceDocument(
        kind: DocumentOperationKind.settingsAttachVoiceGuide,
        update: (document) => document.copyWith(
          duration: document.duration.microseconds >= mediaDuration.microseconds
              ? document.duration
              : mediaDuration,
          assets: [...document.assets, voiceAsset],
          audioTracks: [
            ...document.audioTracks,
            ProjectAudioTrack(
              id: trackId,
              assetId: assetId,
              start: TimelineTime.zero,
              duration: mediaDuration,
              exportPolicy: AudioExportPolicy.referenceOnly,
            ),
          ],
          voiceGuide: ProjectVoiceGuide(
            audioTrackId: trackId,
            displayName: guide.name,
            originalFileName: p.basename(guide.path),
          ),
          timeline: PersistentTimeline(
            drawing: document.timeline.drawing,
            camera: document.timeline.camera,
            audio: [
              ...document.timeline.audio,
              PersistentAudioTimelineTrack(audioTrackId: trackId),
            ],
            voiceGuide: PersistentVoiceGuideTimelineTrack(
              audioTrackId: trackId,
            ),
            sceneMarkers: document.timeline.sceneMarkers,
            leadingHold: document.timeline.leadingHold,
            trailingHold: document.timeline.trailingHold,
          ),
        ),
        affectedScopes: const {DocumentScope.assets, DocumentScope.audio},
        action: 'attach-voice-guide',
        entityIds: [assetId.value, trackId.value],
        statusMessage: '${guide.name} imported as a preview-only Voice Guide.',
      );
      if (!changed) {
        _sessionCoordinator.staging.releaseReference(
          sessionId: session.id,
          assetId: assetId,
          kind: StagedAssetReferenceKind.activeDocument,
        );
        session.activeAssetIds.remove(assetId);
        return false;
      }
      _sessionCoordinator.publishHistoryState(session, state.documentState);
      emit(
        state.copyWith(
          isVoiceGuideLoading: false,
          isVoiceGuideMissing: false,
          statusMessage:
              '${guide.name} imported as a preview-only Voice Guide.',
        ),
      );
      return true;
    } catch (error) {
      if (!isClosed) {
        emit(
          state.copyWith(
            isVoiceGuideLoading: false,
            statusMessage: 'Could not import the Voice Guide: $error',
          ),
        );
      }
      return false;
    }
  }

  Future<bool> locateVoiceGuide({
    VoiceGuidePickerCopy copy = VoiceGuidePickerCopy.english,
  }) => importVoiceGuide(copy: copy);

  void removeVoiceGuide() {
    if (state.document.voiceGuide == null) return;
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.settingsClearVoiceGuide,
      operation: (document) =>
          const ProjectSettingsOperations().clearVoiceGuide(document: document),
      statusMessage: 'Voice Guide and its section cues removed.',
    );
    if (!changed) return;
    emit(
      state.copyWith(
        selectedTimingSectionKey: null,
        isVoiceGuideMissing: false,
        statusMessage: 'Voice Guide and its section cues removed.',
      ),
    );
  }

  bool setVoiceGuideMuted(bool muted) => _executeDocumentOperation(
    kind: DocumentOperationKind.settingsSetVoiceGuide,
    operation: (document) => const ProjectSettingsOperations()
        .setVoiceGuideMuted(document: document, muted: muted),
    statusMessage: muted ? 'Voice Guide muted.' : 'Voice Guide enabled.',
  );

  bool setSectionVoiceCue(String sectionKey, double cueSeconds) {
    final guide = state.document.voiceGuide;
    final sectionId = _sectionIdForKey(sectionKey);
    if (guide == null || sectionId == null) return false;
    final track = state.document.audioTracks.firstWhere(
      (item) => item.id == guide.audioTrackId,
    );
    final cue = cueSeconds.clamp(
      0.0,
      track.duration.microseconds / Duration.microsecondsPerSecond,
    );
    final anchor = AudioCueAnchor(
      audioTrackId: guide.audioTrackId,
      sourceMediaTime: TimelineTime.fromMicroseconds(
        (cue * Duration.microsecondsPerSecond).round(),
      ),
    );
    final candidateResult = const TimelineDocumentOperations().setAudioCue(
      document: state.document,
      sectionId: sectionId,
      anchor: anchor,
    );
    if (!candidateResult.isSuccess) return false;
    final candidate = candidateResult.document;
    final candidateView = LegacyProjectViewCache().resolve(
      EditorDocumentState(document: candidate),
    );
    final resolution = resolveProjectTimeline(
      candidateView,
    ).voiceCues[sectionKey];
    if (resolution == null || resolution.hasConflict) {
      emit(
        state.copyWith(
          selectedTimingSectionKey: sectionKey,
          statusMessage:
              'This section cannot start at the selected time because the previous section ends later.',
        ),
      );
      return false;
    }
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.timingSetAudioCue,
      operation: (document) => const TimelineDocumentOperations().setAudioCue(
        document: document,
        sectionId: sectionId,
        anchor: anchor,
      ),
      mergeProperty: 'voice-cue-${sectionId.value}',
      statusMessage: 'Voice cue linked at ${cue.toStringAsFixed(2)}s.',
    );
    if (!changed) return false;
    emit(
      state.copyWith(
        selectedTimingSectionKey: sectionKey,
        statusMessage: 'Voice cue linked at ${cue.toStringAsFixed(2)}s.',
      ),
    );
    return true;
  }

  void clearSectionVoiceCue(String sectionKey) {
    final current = sectionTiming(sectionKey);
    if (current.voiceCueSeconds == null) return;
    beginSectionTimingEdit();
    _setSectionTiming(sectionKey, current.copyWith(voiceCueSeconds: null));
    emit(
      state.copyWith(
        selectedTimingSectionKey: sectionKey,
        statusMessage: 'Voice cue cleared.',
      ),
    );
    commitSectionTimingEdit();
  }

  bool nudgeSectionVoiceCue(String sectionKey, double deltaSeconds) {
    final cue = sectionTiming(sectionKey).voiceCueSeconds;
    if (cue == null) return false;
    return setSectionVoiceCue(sectionKey, cue + deltaSeconds);
  }

  void setSectionPauseAfter(String sectionKey, double seconds) =>
      _setSectionTiming(
        sectionKey,
        sectionTiming(
          sectionKey,
        ).copyWith(pauseAfterSeconds: seconds.clamp(0.0, 60.0)),
      );

  void setKeepHandVisibleAfterDrawing(bool visible) {
    _updateHandApplicationDefaults(
      _handApplicationDefaults.copyWith(keepHandVisibleAfterDrawing: visible),
      persistImmediately: true,
    );
    final sectionKey = _finalDrawableSectionKey;
    if (sectionKey == null) return;
    final timing = sectionTiming(sectionKey);
    if (timing.keepHandVisibleAfterDrawing == visible) return;
    _setSectionTiming(
      sectionKey,
      timing.copyWith(keepHandVisibleAfterDrawing: visible),
    );
  }

  void _applyKeepHandPreferenceToCurrentFinalSection() {
    final sectionKey = _finalDrawableSectionKey;
    if (sectionKey == null) return;
    final timing = sectionTiming(sectionKey);
    final preferred = _handApplicationDefaults.keepHandVisibleAfterDrawing;
    if (timing.keepHandVisibleAfterDrawing == preferred) return;
    _setSectionTiming(
      sectionKey,
      timing.copyWith(keepHandVisibleAfterDrawing: preferred),
    );
  }

  String? get _finalDrawableSectionKey {
    for (final sectionKey in timelineSectionOrder.reversed) {
      final hasVisibleStroke = project.strokes.any(
        (stroke) => !stroke.hidden && _appliedTimelineKey(stroke) == sectionKey,
      );
      if (hasVisibleStroke) return sectionKey;
    }
    return null;
  }

  void setSectionSpeed(String sectionKey, double multiplier) =>
      _setSectionTiming(
        sectionKey,
        sectionTiming(sectionKey).copyWith(
          speedMultiplier: multiplier.clamp(0.25, 4.0),
          animationDurationSeconds: null,
        ),
      );

  void setTimelineSectionDurations({
    required String sectionId,
    required double animationSeconds,
    required double speedMultiplier,
    required double pauseSeconds,
    required double transitionSeconds,
    required double pauseBeforeSeconds,
    required bool pauseBeforeEnabled,
    required bool pauseAfterEnabled,
    required SectionHandEntranceAnimation handEntranceAnimation,
    required double handEntranceDurationSeconds,
    required SectionHandExitAnimation handExitAnimation,
    required double handExitDurationSeconds,
    required bool keepHandVisibleAfterDrawing,
  }) {
    final sectionKey = _timelineTimingKey(sectionId);
    if (sectionKey == _finalDrawableSectionKey) {
      _updateHandApplicationDefaults(
        _handApplicationDefaults.copyWith(
          keepHandVisibleAfterDrawing: keepHandVisibleAfterDrawing,
        ),
        persistImmediately: true,
      );
    }
    final effectiveSpeed =
        state.document.motionConfiguration.drawingSpeed.clamp(
          minimumProjectDrawingSpeed,
          maximumProjectDrawingSpeed,
        ) *
        speedMultiplier.clamp(0.25, 4.0);
    final baselineAnimationSeconds = (animationSeconds * effectiveSpeed).clamp(
      0.05,
      60.0 * maximumProjectDrawingSpeed * 4.0,
    );
    beginSectionTimingEdit();
    _setSectionTiming(
      sectionKey,
      sectionTiming(sectionKey).copyWith(
        speedMultiplier: speedMultiplier.clamp(0.25, 4.0),
        // Persist the 1× baseline. The production scheduler applies both the
        // overall project speed and this section multiplier exactly once.
        animationDurationSeconds: baselineAnimationSeconds,
        pauseBeforeEnabled: pauseBeforeEnabled,
        pauseBeforeSeconds: pauseBeforeSeconds.clamp(0.0, 60.0),
        pauseAfterEnabled: pauseAfterEnabled,
        pauseAfterSeconds: pauseSeconds.clamp(0.0, 60.0),
        transitionAfterSeconds: transitionSeconds.clamp(0.0, 60.0),
        handEntranceAnimation: handEntranceAnimation,
        handEntranceDurationSeconds:
            handEntranceAnimation == SectionHandEntranceAnimation.none
            ? 0
            : handEntranceDurationSeconds.clamp(0.05, 10.0),
        handExitAnimation: handExitAnimation,
        handExitDurationSeconds:
            handExitAnimation == SectionHandExitAnimation.none ||
                handExitAnimation == SectionHandExitAnimation.disappear
            ? 0
            : handExitDurationSeconds.clamp(0.05, 10.0),
        keepHandVisibleAfterDrawing: keepHandVisibleAfterDrawing,
      ),
    );
    commitSectionTimingEdit();
  }

  void deleteTimelineSection(String sectionId) {
    if (!timelineAvailableSectionIds.contains(sectionId)) return;
    final selected = state.selectedTimelineSectionIds.toSet()
      ..remove(sectionId);
    if (state.smartSections.isNotEmpty) {
      emit(
        state.copyWith(
          smartSections: state.smartSections
              .where((section) => section.id != sectionId)
              .toList(growable: false),
          selectedSmartSectionId: state.selectedSmartSectionId == sectionId
              ? null
              : state.selectedSmartSectionId,
          selectedTimelineSectionIds: selected,
          statusMessage: 'Timeline section removed.',
        ),
      );
      return;
    }
    final persistentId = _sectionIdForKey(sectionId);
    if (persistentId == null) return;
    final changed = _executeDocumentOperation(
      kind: DocumentOperationKind.sceneDeleteSection,
      operation: (document) => const SceneDocumentOperations().deleteSection(
        document: document,
        sectionId: persistentId,
      ),
      statusMessage: 'Timeline section removed.',
    );
    if (!changed) return;
    emit(
      state.copyWith(
        selectedSmartSectionId: state.selectedSmartSectionId == sectionId
            ? null
            : state.selectedSmartSectionId,
        selectedTimelineSectionIds: selected,
        selectedTimelineSceneId:
            state.document.scenes.any(
              (scene) => scene.id.value == state.selectedTimelineSceneId,
            )
            ? state.selectedTimelineSceneId
            : null,
        selectedStrokeIndex: state.document.strokes.isEmpty
            ? null
            : state.selectedStrokeIndex?.clamp(
                0,
                state.document.strokes.length - 1,
              ),
        statusMessage: 'Timeline section removed.',
      ),
    );
  }

  String _timelineTimingKey(String sectionId) =>
      sectionId.startsWith('stroke:') ? sectionId : 'section:$sectionId';

  void setSectionPauseHandBehavior(
    String sectionKey,
    PauseHandBehavior behavior,
  ) {
    beginSectionTimingEdit();
    _setSectionTiming(
      sectionKey,
      sectionTiming(sectionKey).copyWith(pauseHandBehavior: behavior),
    );
    commitSectionTimingEdit();
  }

  void resetSectionTiming(String sectionKey) {
    final sectionId = _sectionIdForKey(sectionKey);
    if (sectionId == null) return;
    _executeDocumentOperation(
      kind: DocumentOperationKind.timingReset,
      operation: (document) => const TimelineDocumentOperations().reset(
        document: document,
        sectionId: sectionId,
      ),
      statusMessage: 'Section timing reset',
    );
  }

  void _setSectionTiming(String sectionKey, SectionTiming timing) {
    final sectionId = _sectionIdForKey(sectionKey);
    if (sectionId == null) return;
    TimelineDuration duration(double seconds) =>
        TimelineDuration.fromMicroseconds(
          (seconds * Duration.microsecondsPerSecond).round(),
        );
    final guide = state.document.voiceGuide;
    _replaceDocument(
      kind: DocumentOperationKind.timingSetPauseBefore,
      update: (document) => document.copyWith(
        sections: [
          for (final section in document.sections)
            section.id == sectionId
                ? section.copyWith(
                    timing: DocumentSectionTiming(
                      pauseBefore: duration(timing.pauseBeforeSeconds),
                      pauseBeforeEnabled: timing.pauseBeforeEnabled,
                      pauseAfter: duration(timing.pauseAfterSeconds),
                      pauseAfterEnabled: timing.pauseAfterEnabled,
                      animationDuration: timing.animationDurationSeconds == null
                          ? null
                          : duration(timing.animationDurationSeconds!),
                      transitionAfter: duration(
                        timing.transitionAfterSeconds ?? 0,
                      ),
                      speedMultiplier: timing.speedMultiplier,
                      pauseHandBehavior:
                          timing.pauseHandBehavior == PauseHandBehavior.hide
                          ? DocumentPauseHandBehavior.hide
                          : DocumentPauseHandBehavior.keepVisible,
                      audioCueAnchor:
                          timing.voiceCueSeconds == null || guide == null
                          ? null
                          : AudioCueAnchor(
                              audioTrackId: guide.audioTrackId,
                              sourceMediaTime: TimelineTime.fromMicroseconds(
                                (timing.voiceCueSeconds! *
                                        Duration.microsecondsPerSecond)
                                    .round(),
                              ),
                            ),
                      handEntranceAnimation: timing.handEntranceAnimation,
                      handEntranceDuration: duration(
                        timing.handEntranceDurationSeconds,
                      ),
                      handExitAnimation: timing.handExitAnimation,
                      handExitDuration: duration(
                        timing.handExitDurationSeconds,
                      ),
                      keepHandVisibleAfterDrawing:
                          timing.keepHandVisibleAfterDrawing,
                    ),
                  )
                : section,
        ],
      ),
      affectedScopes: const {DocumentScope.timing, DocumentScope.sections},
      action: 'set-section-timing',
      entityIds: [sectionId.value],
      statusMessage: 'Advanced timing updated',
      mergeProperty: 'section-timing-${sectionId.value}',
    );
  }

  Future<String?> saveProject({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
    bool saveAs = false,
  }) async {
    final documentId = state.document.id;
    final generation = _projectOpenGeneration;
    bool ownsDocument() =>
        !_closing &&
        !isClosed &&
        state.document.id == documentId &&
        generation == _projectOpenGeneration;
    final destination =
        (!saveAs ? _projectTarget?.path : null) ??
        await _fileService.pickProjectSavePath(copy: copy);
    if (destination == null || !ownsDocument()) return null;
    final target = ProjectContainerLocation(destination);
    final snapshot = state.documentState;
    var session = _session;
    if (session == null ||
        session.isClosed ||
        session.state.document.id != snapshot.document.id) {
      session = await _adoptDocumentSession(
        documentState: snapshot,
        history: _history,
        target: _projectTarget,
      );
      if (!ownsDocument()) {
        await _sessionCoordinator.close(session, clearHistory: false);
        return null;
      }
      await _installSession(session);
    } else {
      await _sessionCoordinator.synchronizeDocumentAssets(
        session,
        state: snapshot,
        embeddedSources: _embeddedSessionSources(snapshot.document),
      );
    }
    if (!ownsDocument() || !identical(_session, session)) return null;
    await _sessionCoordinator.save(session, destination: target);
    if (ownsDocument() && identical(_session, session)) {
      _projectTarget = target;
      emit(state.copyWith(statusMessage: 'Project saved'));
    }
    return destination;
  }

  Future<String?> saveProjectAs({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) => saveProject(copy: copy, saveAs: true);

  Future<void> openProject({
    EditorFilePickerCopy copy = EditorFilePickerCopy.english,
  }) async {
    _invalidateDrawingImport();
    final generation = ++_projectOpenGeneration;
    final path = await _fileService.pickProjectOpenPath(copy: copy);
    if (path == null ||
        _closing ||
        isClosed ||
        generation != _projectOpenGeneration) {
      return;
    }
    final migrated = path.toLowerCase().endsWith('.hdrawlab')
        ? SavedDrawingImport.decode(await File(path).readAsString())
        : null;
    final nextSession = migrated == null
        ? await _sessionCoordinator.open(ProjectContainerLocation(path))
        : await _sessionCoordinator.createFromDocument(
            state: EditorDocumentState(document: migrated.document),
            embeddedSources: {
              for (final entry in migrated.sources.entries)
                entry.key: _MemoryProjectAssetSource(entry.value),
            },
          );
    final openedDocument = const LegacyHandCalibrationMigration().migrate(
      nextSession.state.document,
    );
    final embedded = <ProjectAssetId, Uint8List>{};
    ImportedEditorAsset? artworkRuntime;
    ImportedEditorAsset? handRuntime;
    Future<void> discardPrepared() async {
      artworkRuntime?.image.dispose();
      artworkRuntime?.revealBaseImage?.dispose();
      artworkRuntime?.svgRevealLayers?.strokes.dispose();
      artworkRuntime?.svgRevealLayers?.globalStrokes?.dispose();
      handRuntime?.image.dispose();
      await _sessionCoordinator.close(nextSession);
    }

    try {
      for (final asset in openedDocument.assets) {
        final lease = asset.storagePolicy == ProjectAssetStoragePolicy.external
            ? await _sessionCoordinator.staging.acquireVerifiedSnapshot(
                sessionId: nextSession.id,
                assetId: asset.id,
                kind: StagedAssetReferenceKind.preview,
              )
            : await _sessionCoordinator.staging.acquire(
                sessionId: nextSession.id,
                assetId: asset.id,
                kind: StagedAssetReferenceKind.preview,
              );
        late final Uint8List bytes;
        try {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in lease.openRead()) {
            builder.add(chunk);
          }
          bytes = builder.takeBytes();
        } finally {
          await lease.release();
        }
        if (asset.storagePolicy == ProjectAssetStoragePolicy.embedded) {
          embedded[asset.id] = bytes;
        }
        if (asset.id == openedDocument.artworkAssetId) {
          artworkRuntime = await _fileService.loadImageBytes(
            path: asset.originalFileName,
            bytes: bytes,
          );
        }
        if (asset.id == openedDocument.handConfiguration.assetId) {
          handRuntime = await _fileService.loadImageBytes(
            path: asset.originalFileName,
            bytes: bytes,
          );
        }
      }
    } catch (_) {
      await discardPrepared();
      rethrow;
    }
    if (_closing || isClosed || generation != _projectOpenGeneration) {
      await discardPrepared();
      return;
    }
    final preferredPreset = state.selectedHandPreset;
    var preferredHandImage = state.handImage;
    var loadedPreferredHand = false;
    if (preferredPreset != null && preferredHandImage == null) {
      try {
        preferredHandImage = (await _handImageLoader.load(
          preferredPreset,
        )).image;
        loadedPreferredHand = true;
      } catch (_) {
        // A portable project can still use its embedded hand if the global
        // library asset is unavailable on this machine.
      }
    }
    if (_closing || isClosed || generation != _projectOpenGeneration) {
      if (loadedPreferredHand) preferredHandImage?.dispose();
      await discardPrepared();
      return;
    }
    var document = preferredPreset == null
        ? openedDocument
        : openedDocument.copyWith(
            handConfiguration: _selectedHandConfigurationForNewDocument(),
          );
    document = _applyKeepPreferenceToFinalSection(document);
    final useApplicationHand =
        preferredPreset != null && preferredHandImage != null;
    final effectiveHandImage = useApplicationHand
        ? preferredHandImage
        : handRuntime?.image;
    _cachedImportedSvgPaths = const [];
    _pendingNativeStrokes = const {};
    _embeddedAssetBytes
      ..clear()
      ..addAll(embedded);
    _projectTarget = migrated == null ? ProjectContainerLocation(path) : null;
    // Installation and state publication are synchronous; retiring the old
    // session must not allow a newer open to be overwritten after an await.
    final retiringSession = _installSession(nextSession);
    final oldDrawing = state.drawingImage;
    final oldReveal = state.drawingRevealBaseImage;
    final oldLayers = state.svgRevealLayers;
    final oldHand = state.handImage;
    emit(
      state.copyWith(
        documentState: EditorDocumentState(document: document),
        drawingImage: artworkRuntime?.image,
        drawingAnalysisEncoded: artworkRuntime?.sourceEncoded,
        drawingRevealBaseImage: artworkRuntime?.revealBaseImage,
        svgRevealLayers: artworkRuntime?.svgRevealLayers,
        artworkAnimationGuidance: artworkRuntime == null
            ? ArtworkAnimationGuidance.unknown
            : const ArtworkAnimationGuidancePolicy().resolve(
                sourceKind: artworkRuntime.sourceKind,
                rasterAnalysis: artworkRuntime.rasterAlphaBounds,
              ),
        handImage: effectiveHandImage,
        activeStroke: const [],
        selectedStrokeIndex: null,
        hoveredStrokeIndex: null,
        smartSections: const [],
        autoPathResult: null,
        selectedSmartSectionId: null,
        selectedHandPresetId: state.selectedHandPresetId,
        canvasRevision: state.canvasRevision + 1,
        tool: EditorTool.select,
        statusMessage: artworkRuntime == null
            ? 'Project opened, but the drawing file is missing'
            : 'Project opened',
      ),
    );
    oldDrawing?.dispose();
    oldReveal?.dispose();
    oldLayers?.strokes.dispose();
    oldLayers?.globalStrokes?.dispose();
    if (useApplicationHand) {
      handRuntime?.image.dispose();
    } else if (!identical(oldHand, handRuntime?.image)) {
      oldHand?.dispose();
    }
    final guide = project.voiceGuide;
    await retiringSession;
    if (guide != null &&
        !_closing &&
        !isClosed &&
        identical(_session, nextSession)) {
      final accessible = await _voiceGuideService.canAccess(guide);
      if (!_closing && !isClosed && identical(_session, nextSession)) {
        emit(
          state.copyWith(
            isVoiceGuideMissing: !accessible,
            statusMessage: !accessible
                ? 'Voice Guide is missing. Locate or remove it to continue syncing.'
                : state.statusMessage,
          ),
        );
      }
    }
  }

  Future<bool> createNewProject(NewProjectRequest request) async {
    if (!request.isValid) return false;
    final generation = ++_projectOpenGeneration;
    _invalidateDrawingImport();
    _cachedImportedSvgPaths = const [];
    _pendingNativeStrokes = const {};
    final current = state.document;
    final retainedHandAssets = current.handConfiguration.assetId == null
        ? const <ProjectAsset>[]
        : current.assets
              .where((asset) => asset.id == current.handConfiguration.assetId)
              .toList(growable: false);
    final defaults = EditorState.initial().document;
    final blank = defaults.copyWith(
      id: _idGenerator.projectId(),
      title: request.title.trim(),
      canvas: ProjectCanvas(
        width: request.width,
        height: request.height,
        background: request.background == NewProjectBackground.transparent
            ? const CanvasBackground.transparent()
            : const CanvasBackground.solid(0xFFFFFFFF),
      ),
      frameRate: request.frameRate,
      creationDefaults: ProjectCreationDefaults(
        background: request.background == NewProjectBackground.transparent
            ? ProjectCanvasBackground.transparent
            : ProjectCanvasBackground.color,
        importIntent: request.defaultImportIntent,
      ),
      handConfiguration: _selectedHandConfigurationForNewDocument(),
      writingSoundConfiguration: current.writingSoundConfiguration,
      assets: retainedHandAssets,
    );
    _embeddedAssetBytes.removeWhere(
      (id, _) => !retainedHandAssets.any((asset) => asset.id == id),
    );
    final nextHistory = EditorHistory();
    final nextDocumentState = EditorDocumentState(document: blank);
    late final EditorSession nextSession;
    try {
      nextSession = await _adoptDocumentSession(
        documentState: nextDocumentState,
        history: nextHistory,
      );
    } catch (_) {
      return false;
    }
    if (_closing || isClosed || generation != _projectOpenGeneration) {
      await _sessionCoordinator.close(nextSession);
      return false;
    }
    _projectTarget = null;
    final retiringSession = _installSession(nextSession);
    emit(
      EditorState.initial().copyWith(
        documentState: nextDocumentState,
        handImage: state.handImage,
        handPresets: state.handPresets,
        selectedHandPresetId: state.selectedHandPresetId,
        canvasRevision: state.canvasRevision + 1,
        statusMessage: 'New project. Selected hand was kept.',
      ),
    );
    await retiringSession;
    return true;
  }

  void newProject() {
    _projectOpenGeneration++;
    _invalidateDrawingImport();
    final current = state.document;
    final retainedHandAssets = current.handConfiguration.assetId == null
        ? const <ProjectAsset>[]
        : current.assets
              .where((asset) => asset.id == current.handConfiguration.assetId)
              .toList(growable: false);
    final blank = EditorState.initial().document.copyWith(
      id: _idGenerator.projectId(),
      handConfiguration: _selectedHandConfigurationForNewDocument(),
      writingSoundConfiguration: current.writingSoundConfiguration,
      assets: retainedHandAssets,
    );
    final history = EditorHistory();
    final documentState = EditorDocumentState(document: blank);
    final previousSession = _session;
    _session = null;
    _history = history;
    _projectTarget = null;
    emit(
      EditorState.initial().copyWith(
        documentState: documentState,
        handImage: state.handImage,
        handPresets: state.handPresets,
        selectedHandPresetId: state.selectedHandPresetId,
        canvasRevision: state.canvasRevision + 1,
        statusMessage: 'New project. Selected hand was kept.',
      ),
    );
    if (previousSession != null) {
      unawaited(_sessionCoordinator.close(previousSession));
    }
    unawaited(_bootstrapLegacyNewProject(documentState, history));
  }

  CameraView suggestedCameraViewAt(TimelineTime time) {
    final resolved = const GlobalTimelineResolver().resolveAt(
      compileTimeline(),
      time,
    );
    final activeSectionId = resolved.drawing?.sectionId?.value;
    final selected = selectedStroke;
    Rect? bounds;
    if (selected != null &&
        !selected.hidden &&
        selected.sectionId == activeSectionId) {
      bounds = _normalizedStrokeBounds(selected);
    }
    bounds ??= activeSectionId == null
        ? null
        : _visibleSectionBounds(activeSectionId);
    final fit = const QuickCameraFitService().fit(
      bounds: bounds == null
          ? null
          : CameraWorldBounds(
              left: bounds.left,
              top: bounds.top,
              right: bounds.right,
              bottom: bounds.bottom,
            ),
      projectAspectRatio: project.canvasWidth / project.canvasHeight,
    );
    return fit.view ?? const CameraView.identity();
  }

  Rect? _normalizedStrokeBounds(DrawingStroke stroke) {
    // clipBounds describe the pixels the user sees. Animation points may be a
    // synthetic reveal guide (notably for SVG text/fills), so using them first
    // can place a camera frame beside the visible element.
    if (stroke.clipBounds case final visibleBounds?) return visibleBounds;
    if (stroke.orderedPoints.isEmpty) return null;
    var result = Rect.fromPoints(
      stroke.orderedPoints.first,
      stroke.orderedPoints.first,
    );
    for (final point in stroke.orderedPoints.skip(1)) {
      result = result.expandToInclude(Rect.fromPoints(point, point));
    }
    return result;
  }

  Rect? _visibleSectionBounds(String sectionId) {
    Rect? result;
    for (final stroke in project.strokes) {
      if (stroke.hidden || _appliedTimelineKey(stroke) != sectionId) continue;
      final bounds = _normalizedStrokeBounds(stroke);
      if (bounds == null || bounds.isEmpty) continue;
      result = result == null ? bounds : result.expandToInclude(bounds);
    }
    return result ?? timelineSectionBounds(sectionId);
  }

  bool addCameraShotAt(TimelineTime requested) =>
      addCameraShotAtWithView(requested, suggestedCameraViewAt(requested));

  bool ensureSceneCameraClip(SceneId sceneId) {
    final scene = state.document.scenes
        .where((item) => item.id == sceneId)
        .firstOrNull;
    if (scene == null) return false;
    final existing = state.document.cameraTrack?.shots
        .where((shot) => shot.ownerSceneId == sceneId)
        .firstOrNull;
    if (existing != null) return true;
    final ranges = timelineSectionRanges;
    final members = [for (final id in scene.sectionIds) ?ranges[id.value]];
    if (members.isEmpty) return false;
    final startSeconds = members
        .map((item) => item.startSeconds)
        .reduce(math.min);
    final endSeconds = members.map((item) => item.endSeconds).reduce(math.max);
    final durationSeconds = endSeconds - startSeconds;
    if (durationSeconds <= 0) return false;
    final start = TimelineTime.fromMicroseconds(
      (startSeconds * Duration.microsecondsPerSecond).round(),
    );
    final duration = TimelineDuration.fromMicroseconds(
      (durationSeconds * Duration.microsecondsPerSecond).round(),
    );
    final end = start + duration;
    final overlapping =
        state.document.cameraTrack?.shots
            .where(
              (shot) =>
                  shot.startTime.compareTo(end) < 0 &&
                  shot.endTime.compareTo(start) > 0,
            )
            .toList() ??
        <CameraShot>[];
    if (overlapping.any((shot) => shot.isLocked)) return false;
    final allocation = _allocation();
    final frames = <CameraKeyframe>[];
    if (overlapping.isNotEmpty) {
      for (final shot in overlapping) {
        for (final frame in shot.keyframes) {
          final absoluteUs =
              shot.startTime.microseconds + frame.offset.microseconds;
          final localUs = (absoluteUs - start.microseconds).clamp(
            0,
            duration.microseconds,
          );
          frames.add(
            CameraKeyframe(
              id: allocation.cameraKeyframeId(),
              offset: TimelineTime.fromMicroseconds(localUs),
              view: frame.view,
              incomingTransition: frame.incomingTransition,
            ),
          );
        }
      }
      frames.sort((a, b) => a.offset.compareTo(b.offset));
      if (frames.isNotEmpty) {
        final firstView = frames.first.view;
        final focusView = frames
            .reduce(
              (best, candidate) =>
                  candidate.view.viewportWidth < best.view.viewportWidth
                  ? candidate
                  : best,
            )
            .view;
        final endView = frames.last.view;
        final enterUs = math.min(
          const Duration(milliseconds: 900).inMicroseconds,
          (duration.microseconds * .25).round(),
        );
        final exitUs = math.min(
          const Duration(milliseconds: 900).inMicroseconds,
          (duration.microseconds * .25).round(),
        );
        frames
          ..clear()
          ..addAll([
            CameraKeyframe(
              id: allocation.cameraKeyframeId(),
              offset: TimelineTime.zero,
              view: firstView,
            ),
            CameraKeyframe(
              id: allocation.cameraKeyframeId(),
              offset: TimelineTime.fromMicroseconds(enterUs),
              view: focusView,
              incomingTransition: CameraTransition(
                type: enterUs == 0
                    ? CameraTransitionType.cut
                    : CameraTransitionType.move,
                duration: TimelineDuration.fromMicroseconds(enterUs),
                easing: CameraEasing.easeInOut,
              ),
            ),
            CameraKeyframe(
              id: allocation.cameraKeyframeId(),
              offset: TimelineTime.fromMicroseconds(duration.microseconds),
              view: endView,
              incomingTransition: CameraTransition(
                type: exitUs == 0
                    ? CameraTransitionType.cut
                    : CameraTransitionType.move,
                duration: TimelineDuration.fromMicroseconds(exitUs),
                easing: CameraEasing.easeInOut,
              ),
            ),
          ]);
      }
    }
    if (frames.isEmpty) {
      final wide =
          state.document.cameraTrack?.defaultView ??
          const CameraView.identity();
      final focus = suggestedCameraViewAt(start);
      final enterUs = math.min(
        const Duration(milliseconds: 900).inMicroseconds,
        (duration.microseconds * .25).round(),
      );
      final exitUs = math.min(
        const Duration(milliseconds: 900).inMicroseconds,
        (duration.microseconds * .25).round(),
      );
      frames.addAll([
        CameraKeyframe(
          id: allocation.cameraKeyframeId(),
          offset: TimelineTime.zero,
          view: wide,
        ),
        CameraKeyframe(
          id: allocation.cameraKeyframeId(),
          offset: TimelineTime.fromMicroseconds(enterUs),
          view: focus,
          incomingTransition: CameraTransition(
            type: CameraTransitionType.move,
            duration: TimelineDuration.fromMicroseconds(enterUs),
            easing: CameraEasing.easeInOut,
          ),
        ),
        CameraKeyframe(
          id: allocation.cameraKeyframeId(),
          offset: TimelineTime.fromMicroseconds(duration.microseconds),
          view: wide,
          incomingTransition: CameraTransition(
            type: CameraTransitionType.move,
            duration: TimelineDuration.fromMicroseconds(exitUs),
            easing: CameraEasing.easeInOut,
          ),
        ),
      ]);
    }
    final clip = CameraShot(
      id: allocation.cameraShotId(),
      startTime: start,
      duration: duration,
      authorship: CameraAuthorship.manual,
      isLocked: false,
      label: scene.name,
      ownerSceneId: sceneId,
      sceneConnection: CameraSceneConnection.cut,
      keyframes: frames,
    );
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      statusMessage: 'Scene camera clip created.',
      operation: (document) =>
          const CameraDocumentOperations().installSceneClip(
            document,
            trackId: document.cameraTrack?.id ?? allocation.cameraTrackId(),
            clip: clip,
            replacing: overlapping.map((shot) => shot.id).toSet(),
          ),
    );
  }

  bool setSceneCameraConnection(
    CameraShotId shotId,
    CameraSceneConnection connection,
  ) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    mergeProperty: 'camera.scene-connection:${shotId.value}',
    operation: (document) => const CameraDocumentOperations()
        .setSceneConnection(document, shotId, connection),
  );

  bool updateSceneCameraTiming({
    required CameraShotId shotId,
    required TimelineDuration enterDuration,
    required TimelineDuration exitDuration,
    required CameraEasing easing,
  }) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    mergeProperty: 'camera.scene-timing:${shotId.value}',
    operation: (document) =>
        const CameraDocumentOperations().setSceneClipTiming(
          document,
          shotId,
          enterDuration: enterDuration,
          exitDuration: exitDuration,
          easing: easing,
        ),
  );

  bool addCameraShotAtWithView(
    TimelineTime requested,
    CameraView? view, {
    SimpleCameraMovement movement = SimpleCameraMovement.ease,
    TimelineDuration? movementDuration,
    TimelineDuration? holdDuration,
  }) {
    if (view != null && !const CameraViewPolicy().isSafe(view)) return false;
    final allocation = _allocation();
    final trackId =
        state.document.cameraTrack?.id ?? allocation.cameraTrackId();
    final shotId = allocation.cameraShotId();
    final keyframeId = allocation.cameraKeyframeId();
    final transitionKeyframeId = allocation.cameraKeyframeId();
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      operation: (document) {
        const operations = CameraDocumentOperations();
        var working = document;
        if (working.cameraTrack == null) {
          final created = operations.createTrack(
            working,
            ProjectCameraTrack(id: trackId, shots: const []),
          );
          if (!created.isSuccess) return created;
          working = created.document;
        }
        final track = working.cameraTrack!;
        final requestedMovement =
            movementDuration ??
            TimelineDuration.fromDuration(const Duration(milliseconds: 600));
        final requestedHold =
            holdDuration ??
            TimelineDuration.fromDuration(const Duration(milliseconds: 1400));
        final configuredTransition = const SimpleCameraViewAdapter()
            .transitionFor(movement, requestedMovement);
        final incomingTransition = track.shots.isEmpty
            ? const CameraTransition()
            : configuredTransition;
        final shotDuration = TimelineDuration.fromMicroseconds(
          configuredTransition.duration.microseconds +
              requestedHold.microseconds,
        );
        final start = const CameraTimelineEditingPolicy().nearestAvailableStart(
          requested: requested,
          duration: shotDuration,
          shots: track.shots,
        );
        return operations.createShot(
          working,
          CameraShot(
            id: shotId,
            startTime: start,
            duration: shotDuration,
            authorship: CameraAuthorship.manual,
            isLocked: false,
            label: 'Camera Shot',
            keyframes: [
              CameraKeyframe(
                id: keyframeId,
                offset: TimelineTime.zero,
                view: view ?? track.defaultView,
              ),
              if (!incomingTransition.duration.isZero)
                CameraKeyframe(
                  id: transitionKeyframeId,
                  offset: TimelineTime.fromMicroseconds(
                    incomingTransition.duration.microseconds,
                  ),
                  view: view ?? track.defaultView,
                  incomingTransition: incomingTransition,
                ),
            ],
          ),
        );
      },
    );
  }

  bool setCameraKeyframeView(
    CameraShotId shotId,
    CameraKeyframeId keyframeId,
    CameraView view,
  ) {
    final wasAuto = state.document.cameraTrack?.shots
        .where((shot) => shot.id == shotId)
        .any((shot) => shot.authorship == CameraAuthorship.auto);
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      mergeProperty: 'camera.view:${keyframeId.value}',
      statusMessage: wasAuto == true ? 'Auto shot converted to Manual' : null,
      operation: (document) => const CameraDocumentOperations().setView(
        document,
        shotId,
        keyframeId,
        view,
      ),
    );
  }

  bool updateSimpleCameraView(CameraShotId shotId, CameraView view) {
    final shot = state.document.cameraTrack?.shots
        .where((item) => item.id == shotId)
        .firstOrNull;
    if (shot == null || shot.keyframes.isEmpty) return false;
    final transition = shot.keyframes.last.incomingTransition;
    final movementUs = transition.type == CameraTransitionType.cut
        ? 0
        : transition.duration.microseconds;
    final hold = TimelineDuration.fromMicroseconds(
      math.max(0, shot.duration.microseconds - movementUs),
    );
    final transitionKeyframeId = _allocation().cameraKeyframeId();
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      mergeProperty: 'camera.simple-view:${shotId.value}',
      operation: (document) =>
          const CameraDocumentOperations().setSimpleViewShot(
            document,
            shotId,
            view: view,
            transition: transition,
            holdDuration: hold,
            transitionKeyframeId: transitionKeyframeId,
          ),
    );
  }

  bool setCameraTrackEnabled(bool enabled) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    operation: (document) =>
        const CameraDocumentOperations().setTrackEnabled(document, enabled),
  );
  bool deleteCameraShots(Set<CameraShotId> ids) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    operation: (document) {
      var working = document;
      for (final id in ids) {
        final result = const CameraDocumentOperations().deleteShot(working, id);
        if (!result.isSuccess) return result;
        working = result.document;
      }
      return DocumentOperationResult.success(
        document: working,
        affectedScopes: const {DocumentScope.camera},
        summary: DocumentChangeSummary(
          action: 'camera.delete.selection',
          entityIds: ids.map((id) => id.value),
          changeCount: ids.length,
        ),
      );
    },
  );
  bool moveCameraShot(CameraShotId id, TimelineTime start) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.cameraEdit,
        mergeProperty: 'camera.move:${id.value}',
        operation: (document) =>
            const CameraDocumentOperations().moveShot(document, id, start),
      );
  bool moveCameraShots(Map<CameraShotId, TimelineTime> starts) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) {
          var working = document;
          for (final entry in starts.entries) {
            final result = const CameraDocumentOperations().moveShot(
              working,
              entry.key,
              entry.value,
            );
            if (!result.isSuccess) return result;
            working = result.document;
          }
          return DocumentOperationResult.success(
            document: working,
            affectedScopes: const {DocumentScope.camera},
            summary: DocumentChangeSummary(
              action: 'camera.move.selection',
              entityIds: starts.keys.map((id) => id.value),
              changeCount: starts.length,
            ),
          );
        },
      );
  bool resizeCameraShot(CameraShotId id, TimelineDuration duration) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.cameraEdit,
        mergeProperty: 'camera.resize:${id.value}',
        operation: (document) =>
            const CameraDocumentOperations().resizeShot(document, id, duration),
      );
  bool resizeCameraShotFromStart(CameraShotId id, TimelineTime start) {
    final key = _allocation().cameraKeyframeId();
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      mergeProperty: 'camera.resize.start:${id.value}',
      operation: (document) =>
          const CameraDocumentOperations().resizeShotFromStart(
            document,
            id,
            start: start,
            firstKeyframeId: key,
          ),
    );
  }

  bool trimCameraShot(
    CameraShotId id,
    TimelineTime trimStart,
    TimelineDuration duration,
  ) {
    final key = _allocation().cameraKeyframeId();
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      mergeProperty: 'camera.trim:${id.value}',
      operation: (document) => const CameraDocumentOperations().trimShot(
        document,
        id,
        trimStart: trimStart,
        duration: duration,
        firstKeyframeId: key,
      ),
    );
  }

  bool splitCameraShot(CameraShotId id, TimelineTime projectTime) {
    final shot = state.document.cameraTrack?.shots
        .where((item) => item.id == id)
        .firstOrNull;
    if (shot == null ||
        projectTime.compareTo(shot.startTime) <= 0 ||
        projectTime.compareTo(shot.endTime) >= 0) {
      return false;
    }
    final allocation = _allocation();
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      operation: (document) => const CameraDocumentOperations().splitShot(
        document,
        id,
        TimelineTime.fromMicroseconds(
          projectTime.microseconds - shot.startTime.microseconds,
        ),
        rightShotId: allocation.cameraShotId(),
        rightFirstKeyframeId: allocation.cameraKeyframeId(),
      ),
    );
  }

  bool duplicateCameraShot(CameraShotId id) {
    final source = state.document.cameraTrack?.shots
        .where((item) => item.id == id)
        .firstOrNull;
    if (source == null) return false;
    final allocation = _allocation();
    final start = const CameraTimelineEditingPolicy().nearestAvailableStart(
      requested: source.endTime,
      duration: source.duration,
      shots: state.document.cameraTrack!.shots,
    );
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      operation: (document) => const CameraDocumentOperations().duplicateShot(
        document,
        id,
        shotId: allocation.cameraShotId(),
        keyframeIds: [
          for (final _ in source.keyframes) allocation.cameraKeyframeId(),
        ],
        startTime: start,
      ),
    );
  }

  bool setCameraShotsLocked(Set<CameraShotId> ids, bool locked) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) {
          var working = document;
          for (final id in ids) {
            final result = const CameraDocumentOperations().setLock(
              working,
              id,
              locked,
            );
            if (!result.isSuccess) return result;
            working = result.document;
          }
          return DocumentOperationResult.success(
            document: working,
            affectedScopes: const {DocumentScope.camera},
            summary: DocumentChangeSummary(
              action: 'camera.lock.selection',
              entityIds: ids.map((id) => id.value),
              changeCount: ids.length,
            ),
          );
        },
      );
  bool setCameraShotAuthorship(CameraShotId id, CameraAuthorship authorship) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) => const CameraDocumentOperations().setAuthorship(
          document,
          id,
          authorship,
          overrideLock: true,
        ),
      );
  bool renameCameraShot(CameraShotId id, String? label) =>
      _executeDocumentOperation(
        kind: DocumentOperationKind.cameraEdit,
        operation: (document) =>
            const CameraDocumentOperations().renameShot(document, id, label),
      );
  bool setCameraTransition(
    CameraShotId shotId,
    CameraKeyframeId keyframeId,
    CameraTransition transition,
  ) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    operation: (document) => const CameraDocumentOperations().setTransition(
      document,
      shotId,
      keyframeId,
      transition,
    ),
  );

  bool updateSimpleCameraViewTiming({
    required CameraShotId shotId,
    required SimpleCameraMovement movement,
    required TimelineDuration movementDuration,
    required TimelineDuration holdDuration,
  }) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    mergeProperty: 'camera.simple-timing:${shotId.value}',
    operation: (document) {
      const adapter = SimpleCameraViewAdapter();
      final shot = document.cameraTrack?.shots
          .where((item) => item.id == shotId)
          .firstOrNull;
      if (shot == null || shot.keyframes.isEmpty) {
        return DocumentOperationResult.failure(
          document: document,
          code: DocumentOperationFailureCode.missingEntity,
          message: 'Camera shot does not exist.',
        );
      }
      final transition = adapter.transitionFor(movement, movementDuration);
      return const CameraDocumentOperations().setSimpleViewShot(
        document,
        shotId,
        view: shot.keyframes.last.view,
        transition: transition,
        holdDuration: holdDuration,
        transitionKeyframeId: _allocation().cameraKeyframeId(),
      );
    },
  );

  bool applyCameraZoomInOutPreset({
    required CameraShotId? sourceShotId,
    required TimelineTime startTime,
    required TimelineDuration totalDuration,
    required CameraView focusView,
    required double strength,
    required TimelineDuration zoomInDuration,
    required TimelineDuration zoomOutDuration,
    String wideLabel = 'Wide',
    String zoomInLabel = 'Zoom In',
    String zoomOutLabel = 'Zoom Out',
  }) {
    final allocation = _allocation();
    final trackId =
        state.document.cameraTrack?.id ?? allocation.cameraTrackId();
    final plan = const CameraZoomInOutPresetPlanner().build(
      startTime: startTime,
      totalDuration: totalDuration,
      wideView:
          state.document.cameraTrack?.defaultView ??
          const CameraView.identity(),
      focusView: focusView,
      strength: strength,
      zoomInDuration: zoomInDuration,
      zoomOutDuration: zoomOutDuration,
      wideLabel: wideLabel,
      zoomInLabel: zoomInLabel,
      zoomOutLabel: zoomOutLabel,
      ids: CameraZoomPresetIds(
        shots: [
          allocation.cameraShotId(),
          allocation.cameraShotId(),
          allocation.cameraShotId(),
        ],
        keyframes: [
          allocation.cameraKeyframeId(),
          allocation.cameraKeyframeId(),
          allocation.cameraKeyframeId(),
          allocation.cameraKeyframeId(),
          allocation.cameraKeyframeId(),
        ],
      ),
    );
    if (plan == null || !const CameraViewPolicy().isSafe(plan.closeView)) {
      emit(
        state.copyWith(
          statusMessage:
              'Zoom preset needs more time or a smaller zoom strength.',
        ),
      );
      return false;
    }
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      statusMessage: 'Zoom In then Out preset applied.',
      operation: (document) =>
          const CameraDocumentOperations().installZoomInOutPreset(
            document,
            trackId: trackId,
            sourceShotId: sourceShotId,
            shots: plan.shots,
          ),
    );
  }

  bool addCameraKeyframe(
    CameraShotId shotId,
    TimelineTime offset,
    CameraView view, {
    CameraTransition transition = const CameraTransition(),
  }) {
    final id = _allocation().cameraKeyframeId();
    return _executeDocumentOperation(
      kind: DocumentOperationKind.cameraEdit,
      operation: (document) => const CameraDocumentOperations().addKeyframe(
        document,
        shotId,
        CameraKeyframe(
          id: id,
          offset: offset,
          view: view,
          incomingTransition: transition,
        ),
      ),
    );
  }

  bool updateCameraShotInspector({
    required CameraShotId shotId,
    required String? label,
    required TimelineDuration duration,
    required bool locked,
  }) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    operation: (document) {
      const operations = CameraDocumentOperations();
      var result = operations.renameShot(
        document,
        shotId,
        label,
        overrideLock: true,
      );
      if (!result.isSuccess) return result;
      result = operations.resizeShot(
        result.document,
        shotId,
        duration,
        overrideLock: true,
      );
      if (!result.isSuccess) return result;
      return operations.setLock(result.document, shotId, locked);
    },
  );

  bool updateCameraKeyframeInspector({
    required CameraShotId shotId,
    required CameraKeyframeId keyframeId,
    required TimelineTime offset,
    required CameraTransition transition,
  }) => _executeDocumentOperation(
    kind: DocumentOperationKind.cameraEdit,
    operation: (document) {
      const operations = CameraDocumentOperations();
      var result = operations.moveKeyframe(
        document,
        shotId,
        keyframeId,
        offset,
      );
      if (!result.isSuccess) return result;
      return operations.setTransition(
        result.document,
        shotId,
        keyframeId,
        transition,
      );
    },
  );

  @override
  Future<void> close() async {
    _closing = true;
    _projectOpenGeneration++;
    cancelImageAnimation();
    if (_handPreferencesDirty) commitHandPreferences();
    await _handPreferencesSaveInFlight;
    _stopSmartPathProgressClock();
    _smartPathApplyGeneration++;
    await _cancelAutoPathPlanning();
    _sceneRegionAnalysisGeneration++;
    _sceneRegionCancellation?.cancel();
    _sceneRegionCancellation = null;
    _drawingImportGeneration++;
    _projectOpenGeneration++;
    final session = _session;
    _session = null;
    if (session != null) {
      await _sessionCoordinator.close(session);
    } else {
      _history.clear();
    }
    return super.close();
  }

  Offset _toNormalized(Offset point, Rect rect, {bool clamp = false}) {
    var dx = (point.dx - rect.left) / rect.width;
    var dy = (point.dy - rect.top) / rect.height;
    if (clamp) {
      dx = dx.clamp(0.0, 1.0);
      dy = dy.clamp(0.0, 1.0);
    }
    return Offset(dx, dy);
  }

  List<Offset> _reducePoints(List<Offset> source) {
    if (source.length <= 3) return List.of(source);
    final result = <Offset>[source.first];
    for (var index = 1; index < source.length - 1; index++) {
      if ((source[index] - result.last).distance >= 0.004) {
        result.add(source[index]);
      }
    }
    result.add(source.last);
    return result;
  }

  ArtworkPathRequest _artworkPathRequest(
    Image drawing,
    String preview, {
    SmartPathProgressCallback? onProgress,
  }) {
    final source = project.drawingSourceBase64 ?? preview;
    return ArtworkPathRequest(
      kind: project.drawingSourceKind,
      previewImage: drawing,
      previewBytes: _decodeEmbeddedBytes(preview),
      sourceBytes: _decodeEmbeddedBytes(source),
      cachedSvgPaths: _cachedImportedSvgPaths,
      onProgress: onProgress,
    );
  }

  void _startSmartPathProgressClock(int canvasRevision, Image drawing) {
    _stopSmartPathProgressClock();
    final stopwatch = Stopwatch()..start();
    _smartPathAnalysisStopwatch = stopwatch;
    _smartPathAnalysisTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ownsCanvasOperation(canvasRevision, drawing) ||
          !state.isAnalyzingSmartPaths ||
          isClosed) {
        _stopSmartPathProgressClock();
        return;
      }
      emit(state.copyWith(smartPathAnalysisElapsed: stopwatch.elapsed));
    });
  }

  void _reportSmartPathProgress(
    int canvasRevision,
    Image drawing,
    SmartPathProgress update,
  ) {
    if (isClosed ||
        !_ownsCanvasOperation(canvasRevision, drawing) ||
        !state.isAnalyzingSmartPaths) {
      return;
    }
    final current = state.smartPathProgress;
    if (current != null && update.fraction < current.fraction) return;
    emit(
      state.copyWith(
        smartPathProgress: update,
        smartPathAnalysisElapsed:
            _smartPathAnalysisStopwatch?.elapsed ?? Duration.zero,
      ),
    );
  }

  void _stopSmartPathProgressClock() {
    _smartPathAnalysisTimer?.cancel();
    _smartPathAnalysisTimer = null;
    _smartPathAnalysisStopwatch?.stop();
    _smartPathAnalysisStopwatch = null;
  }

  Map<String, DrawingStroke> _nativeStrokesFrom(List<SvgImportedPath> paths) {
    if (paths.isEmpty) return const {};
    final textExclusions = paths
        .where((path) => path.isText)
        .map(
          (path) => path.clipBounds
              .inflate(0.001)
              .intersect(const Rect.fromLTWH(0, 0, 1, 1)),
        )
        .toList(growable: false);
    return {
      for (var index = 0; index < paths.length; index++)
        'svg-${paths[index].id}-$index': DrawingStroke(
          id: 'svg-${paths[index].id}-$index',
          name: paths[index].id,
          geometry: paths[index].geometry,
          animationGeometry: paths[index].animationGeometry,
          isFilledShape: paths[index].isFilled,
          isTextShape: paths[index].isText,
          isGlobalDecoration: paths[index].isGlobalDecoration,
          fillColorValue: paths[index].fillColorValue,
          revealStyle: paths[index].isFilled || paths[index].isText
              ? RevealMaskStyle.directionalWipe
              : RevealMaskStyle.brush,
          clipBounds: paths[index].clipBounds,
          exclusionBounds: paths[index].isFilled ? textExclusions : const [],
          revealWidth:
              paths[index].recommendedRevealWidth * project.canvasHeight,
          sectionId: 'svg:${paths[index].id}',
        ),
    };
  }

  void _invalidateDrawingImport() {
    cancelImageAnimation();
    _drawingImportGeneration++;
    if (state.isDrawingImporting) {
      emit(state.copyWith(isDrawingImporting: false));
    }
  }

  bool _ownsCanvasOperation(int revision, Image drawing) =>
      !isClosed &&
      state.canvasRevision == revision &&
      identical(state.drawingImage, drawing);
}

Uint8List _decodeEmbeddedBytes(String encoded) {
  try {
    return base64Decode(encoded);
  } on FormatException {
    // Test doubles and migrated projects can carry a non-base64 placeholder.
    // Native SVG analysis only needs this when no parsed path cache exists.
    return Uint8List(0);
  }
}

const _svgEditSectionPrefix = 'svg-edit:';

DocumentRect _visibleArtworkBounds(ImportedEditorAsset asset) {
  final image = asset.image;
  final fallback = DocumentRect(
    left: 0,
    top: 0,
    right: image.width.toDouble(),
    bottom: image.height.toDouble(),
  );
  if (asset.vectorPaths.isEmpty) {
    final bounds = asset.rasterAlphaBounds?.bounds;
    if (bounds == null) return fallback;
    return DocumentRect(
      left: bounds.left.toDouble(),
      top: bounds.top.toDouble(),
      right: bounds.right.toDouble(),
      bottom: bounds.bottom.toDouble(),
    );
  }
  final bounds = asset.vectorPaths
      .map((path) => path.clipBounds)
      .reduce((left, right) => left.expandToInclude(right));
  return DocumentRect(
    left: bounds.left * image.width,
    top: bounds.top * image.height,
    right: bounds.right * image.width,
    bottom: bounds.bottom * image.height,
  );
}

bool _isNativeSvgStroke(DrawingStroke stroke) =>
    stroke.geometry != null && (stroke.sectionId?.startsWith('svg:') ?? false);

List<DrawingStroke> _nativeSvgStrokes(HandDrawProject project) =>
    project.strokes.where(_isNativeSvgStroke).toList(growable: false);

({StrokePathGeometry geometry, Rect bounds}) _filledShapeReveal(
  StrokePathGeometry source,
) {
  const unitRect = Rect.fromLTWH(0, 0, 1, 1);
  final bounds = source.toPath(unitRect).getBounds().intersect(unitRect);
  return (
    geometry: StrokePathGeometry(
      start: Offset(bounds.left, bounds.center.dy),
      segments: [
        StrokeLineSegment(end: Offset(bounds.right, bounds.center.dy)),
      ],
    ),
    bounds: bounds.inflate(0.001).intersect(unitRect),
  );
}

List<SmartPathSection> _nativeSvgSmartSections(HandDrawProject project) {
  const unitRect = Rect.fromLTWH(0, 0, 1, 1);
  final sections = <SmartPathSection>[];
  for (final stroke in _nativeSvgStrokes(project)) {
    final geometry = stroke.orderedGeometry!;
    final revealWidth =
        (stroke.revealWidth ?? project.revealWidth) / project.canvasHeight;
    final bounds = geometry
        .toPath(unitRect)
        .getBounds()
        .inflate(math.max(0.001, revealWidth * 0.5))
        .intersect(unitRect);
    sections.add(
      SmartPathSection(
        id: '$_svgEditSectionPrefix${stroke.id}',
        kind: stroke.isTextShape
            ? SmartSectionKind.text
            : SmartSectionKind.shape,
        bounds: bounds,
        label: stroke.name,
        paths: [SmartGeneratedPath(points: geometry.sample())],
        recommendedRevealWidth: revealWidth,
        mode: stroke.revealOnly
            ? SmartSectionMode.revealText
            : SmartSectionMode.handDraw,
      ),
    );
  }
  return List.unmodifiable(sections);
}

final class _ClearedCanvasRuntime {
  const _ClearedCanvasRuntime({
    required this.drawingImage,
    required this.drawingAnalysisEncoded,
    required this.drawingRevealBaseImage,
    required this.svgRevealLayers,
    required this.artworkAnimationGuidance,
  });

  final Image? drawingImage;
  final String? drawingAnalysisEncoded;
  final Image? drawingRevealBaseImage;
  final SvgRevealLayers? svgRevealLayers;
  final ArtworkAnimationGuidance artworkAnimationGuidance;
}

final class _ManualStrokeTarget {
  const _ManualStrokeTarget({
    required this.section,
    required this.insertionSectionIds,
    required this.clipPolygons,
  });

  final ProjectSection? section;
  final Set<SectionId> insertionSectionIds;
  final List<List<DocumentPoint>> clipPolygons;
}

final class _MemoryProjectAssetSource
    implements ProjectAssetByteSource, EditorMemoryAssetStreamSource {
  const _MemoryProjectAssetSource(this.bytes);
  @override
  final Uint8List bytes;

  @override
  Future<int> length() async => bytes.length;

  @override
  Stream<Uint8List> openRead() => Stream.value(bytes);
}
