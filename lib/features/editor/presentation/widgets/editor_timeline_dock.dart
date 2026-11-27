import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/auto_path/domain/services/drawing_timeline_service.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/timeline_section_properties_dialog.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/anchored_menu_position.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/l10n/l10n.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/camera/application/camera_timeline_viewport_query.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/policies/camera_timeline_editing_policy.dart';
import 'package:handdraw_studio/features/camera/domain/services/scene_camera_track_projector.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_shot_properties_dialog.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/application/services/timeline_snap_service.dart';
import 'package:handdraw_studio/features/editor/presentation/timeline_follow_policy.dart';
import 'package:handdraw_studio/features/scene_split/presentation/smart_scene_split_dialog.dart';

String _timelineText(BuildContext context, String en, String ar) =>
    Directionality.of(context) == ui.TextDirection.rtl ? ar : en;

@immutable
class TimelineLaneGeometry {
  const TimelineLaneGeometry({
    required this.timelineDurationSeconds,
    required this.trackStartSeconds,
  });

  final double timelineDurationSeconds;
  final double trackStartSeconds;
}

typedef TimelineAudioLaneBuilder =
    Widget Function(BuildContext context, TimelineLaneGeometry geometry);

class EditorTimelineDock extends StatefulWidget {
  const EditorTimelineDock({
    super.key,
    required this.cubit,
    required this.previewProgress,
    required this.isPreviewing,
    required this.onSeek,
    this.onDrawingSeek,
    required this.onPreviewStroke,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    required this.playheadTime,
    this.drawingPlayheadTime,
    this.cameraDiagnostics,
    this.cameraEditing,
    this.onAutoCamera,
    this.onRegenerateCameraRange,
    this.pendingCameraPlan,
    this.audioLaneBuilder,
    this.onPreviewCameraShot,
    this.height,
  });

  final EditorCubit cubit;
  final double previewProgress;
  final bool isPreviewing;
  final ValueChanged<double> onSeek;
  final ValueChanged<double>? onDrawingSeek;
  final ValueChanged<int> onPreviewStroke;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;
  final TimelineTime playheadTime;
  final TimelineTime? drawingPlayheadTime;
  final CameraTimelineDiagnostics? cameraDiagnostics;
  final CameraEditingCubit? cameraEditing;
  final VoidCallback? onAutoCamera;
  final ValueChanged<TimelineInterval>? onRegenerateCameraRange;
  final AutoDirectorPlan? pendingCameraPlan;
  final TimelineAudioLaneBuilder? audioLaneBuilder;
  final ValueChanged<CameraShot>? onPreviewCameraShot;
  final double? height;

  @override
  State<EditorTimelineDock> createState() => _EditorTimelineDockState();
}

class _EditorTimelineDockState extends State<EditorTimelineDock> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _sectionVisibilityKeys = {};
  StreamSubscription<EditorState>? _selectionSubscription;
  int? _observedStrokeIndex;
  String? _observedSmartSectionId;
  int _revealRequest = 0;
  double _zoom = 1;
  bool _followPlayhead = true;
  bool _followSuspendedByManualNavigation = false;
  double _lastPixelsPerSecond = 0;
  double _lastViewportWidth = 0;
  late CameraEditingCubit _cameraEditing;
  late bool _ownsCameraEditing;
  StreamSubscription<EditorState>? _cameraDocumentSubscription;

  EditorCubit get cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _ownsCameraEditing = widget.cameraEditing == null;
    _cameraEditing = widget.cameraEditing ?? CameraEditingCubit();
    _observeSelection(widget.cubit);
    _scheduleSelectedNodeReveal(widget.cubit.state);
    _observeCameraDocument(widget.cubit);
  }

  @override
  void didUpdateWidget(covariant EditorTimelineDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cameraEditing != widget.cameraEditing) {
      if (_ownsCameraEditing) _cameraEditing.close();
      _ownsCameraEditing = widget.cameraEditing == null;
      _cameraEditing = widget.cameraEditing ?? CameraEditingCubit();
    }
    if (oldWidget.cubit != widget.cubit) {
      _selectionSubscription?.cancel();
      _observeSelection(widget.cubit);
      _scheduleSelectedNodeReveal(widget.cubit.state);
      _cameraDocumentSubscription?.cancel();
      _observeCameraDocument(widget.cubit);
    }
    if (!oldWidget.isPreviewing && widget.isPreviewing) {
      _followSuspendedByManualNavigation = false;
    } else if (oldWidget.isPreviewing && !widget.isPreviewing) {
      _followSuspendedByManualNavigation = false;
    }
    if (_followPlayhead &&
        !_followSuspendedByManualNavigation &&
        widget.isPreviewing &&
        oldWidget.playheadTime != widget.playheadTime) {
      _schedulePlayheadFollow();
    }
  }

  @override
  void dispose() {
    _selectionSubscription?.cancel();
    _scrollController.dispose();
    _cameraDocumentSubscription?.cancel();
    if (_ownsCameraEditing) _cameraEditing.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = cubit.timelineNodes;
    final ranges = cubit.timelineSectionRanges;
    final metrics = projectTimelineSectionMetrics(cubit.project);
    final boundsBySection = {
      for (final id in cubit.timelineSectionOrder)
        id: cubit.timelineSectionBounds(id),
    };
    final compiledTimeline = cubit.compileTimeline();
    final compiledDuration = compiledTimeline.duration;
    final timelineDuration = math.max(
      0.001,
      compiledDuration.microseconds / Duration.microsecondsPerSecond,
    );
    // The Camera empty state is itself an actionable timeline state; hiding
    // the dock here made a first shot impossible to discover.
    final hasTimeline =
        nodes.isNotEmpty ||
        cubit.state.document.cameraTrack != null ||
        widget.cameraEditing != null ||
        widget.audioLaneBuilder != null;
    final currentSectionIds = cubit.timelineSectionOrder.toSet();
    _sectionVisibilityKeys.removeWhere(
      (sectionId, _) => !currentSectionIds.contains(sectionId),
    );
    final colors = context.studioColors;
    return _TimelineDragScope(
      onDragUpdate: _autoScrollForDrag,
      child: Material(
        key: const ValueKey('editor-timeline-dock'),
        color: colors.surface,
        child: SizedBox(
          height:
              widget.height ?? (widget.audioLaneBuilder == null ? 286 : 364),
          child: Column(
            children: [
              _TimelineToolbar(
                cubit: cubit,
                zoom: _zoom,
                onZoomChanged: (value) => setState(() => _zoom = value),
                followPlayhead: _followPlayhead,
                onFollowPlayheadChanged: (value) =>
                    setState(() => _followPlayhead = value),
              ),
              Divider(height: 1, color: colors.border),
              Expanded(
                child: hasTimeline
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final contentWidth = math.max(
                            constraints.maxWidth,
                            timelineDuration * 150 * _zoom,
                          );
                          final pixelsPerSecond =
                              contentWidth / timelineDuration;
                          _lastPixelsPerSecond = pixelsPerSecond;
                          _lastViewportWidth = constraints.maxWidth;
                          return Listener(
                            key: const ValueKey('timeline-scroll-surface'),
                            onPointerSignal: _handlePointerSignal,
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(
                                    dragDevices: const {
                                      ui.PointerDeviceKind.touch,
                                      ui.PointerDeviceKind.mouse,
                                      ui.PointerDeviceKind.stylus,
                                      ui.PointerDeviceKind.invertedStylus,
                                      ui.PointerDeviceKind.trackpad,
                                    },
                                  ),
                              child: Directionality(
                                // Time always increases physically left-to-right;
                                // Arabic affects labels, not the timeline axis.
                                textDirection: TextDirection.ltr,
                                child: Scrollbar(
                                  controller: _scrollController,
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    controller: _scrollController,
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: contentWidth,
                                      child: Stack(
                                        children: [
                                          Column(
                                            children: [
                                              _TimelineRuler(
                                                durationSeconds:
                                                    timelineDuration,
                                                onSeek: _manualSeek,
                                                onPanBy: _panBy,
                                              ),
                                              AnimatedBuilder(
                                                animation: _scrollController,
                                                builder: (context, _) => _CameraTimelineLane(
                                                  editor: cubit,
                                                  editing: _cameraEditing,
                                                  width: contentWidth,
                                                  viewportStart:
                                                      _scrollController
                                                          .hasClients
                                                      ? _scrollController.offset
                                                      : 0,
                                                  viewportWidth:
                                                      constraints.maxWidth,
                                                  duration:
                                                      TimelineDuration.fromMicroseconds(
                                                        (timelineDuration *
                                                                Duration
                                                                    .microsecondsPerSecond)
                                                            .round(),
                                                      ),
                                                  pixelsPerSecond:
                                                      pixelsPerSecond,
                                                  playhead: widget.playheadTime,
                                                  onAutoCamera:
                                                      widget.onAutoCamera,
                                                  onRegenerateCameraRange: widget
                                                      .onRegenerateCameraRange,
                                                  pendingPlan:
                                                      widget.pendingCameraPlan,
                                                  onPreviewShot: widget
                                                      .onPreviewCameraShot,
                                                  onSeek: (time) => _manualSeek(
                                                    time.microseconds /
                                                        math.max(
                                                          1,
                                                          (timelineDuration *
                                                                  Duration
                                                                      .microsecondsPerSecond)
                                                              .round(),
                                                        ),
                                                  ),
                                                  diagnostics:
                                                      widget.cameraDiagnostics,
                                                ),
                                              ),
                                              Expanded(
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                        0,
                                                        7,
                                                        0,
                                                        15,
                                                      ),
                                                  child: ClipRect(
                                                    child: OverflowBox(
                                                      alignment:
                                                          Alignment.centerLeft,
                                                      minWidth: 0,
                                                      maxWidth: double.infinity,
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        textDirection:
                                                            TextDirection.ltr,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          for (final node
                                                              in nodes)
                                                            _TimelineNodeClip(
                                                              cubit: cubit,
                                                              node: node,
                                                              sectionVisibilityKey:
                                                                  _sectionVisibilityKey,
                                                              onPreviewStroke:
                                                                  widget
                                                                      .onPreviewStroke,
                                                              pixelsPerSecond:
                                                                  pixelsPerSecond,
                                                              ranges: ranges,
                                                              boundsBySection:
                                                                  boundsBySection,
                                                              metrics: metrics,
                                                              onTimingChangeStart:
                                                                  widget
                                                                      .onTimingChangeStart,
                                                              onTimingChangeEnd:
                                                                  widget
                                                                      .onTimingChangeEnd,
                                                              onRevealTime:
                                                                  (
                                                                    seconds,
                                                                  ) => _revealDrawingTime(
                                                                    seconds,
                                                                    timelineDuration,
                                                                  ),
                                                              playheadSeconds:
                                                                  (widget.drawingPlayheadTime ??
                                                                          widget
                                                                              .playheadTime)
                                                                      .microseconds /
                                                                  Duration
                                                                      .microsecondsPerSecond,
                                                            ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (widget.audioLaneBuilder !=
                                                  null)
                                                SizedBox(
                                                  height: 72,
                                                  width: contentWidth,
                                                  child: widget.audioLaneBuilder!(
                                                    context,
                                                    TimelineLaneGeometry(
                                                      timelineDurationSeconds:
                                                          timelineDuration,
                                                      trackStartSeconds:
                                                          (compiledTimeline
                                                                  .voiceGuide
                                                                  ?.interval
                                                                  .start
                                                                  .microseconds ??
                                                              0) /
                                                          Duration
                                                              .microsecondsPerSecond,
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          Positioned(
                                            left:
                                                contentWidth *
                                                    (widget
                                                                .playheadTime
                                                                .microseconds /
                                                            math.max(
                                                              1,
                                                              compiledDuration
                                                                  .microseconds,
                                                            ))
                                                        .clamp(0.0, 1.0) -
                                                6,
                                            width: 12,
                                            top: 0,
                                            bottom: 10,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors
                                                  .resizeLeftRight,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.translucent,
                                                onHorizontalDragUpdate: (details) {
                                                  final current =
                                                      widget
                                                              .playheadTime
                                                              .microseconds /
                                                          math.max(
                                                            1,
                                                            compiledDuration
                                                                .microseconds,
                                                          ) +
                                                      details.delta.dx /
                                                          contentWidth;
                                                  _manualSeek(
                                                    current.clamp(0.0, 1.0),
                                                  );
                                                },
                                                child: Center(
                                                  child: Container(
                                                    key: const ValueKey(
                                                      'timeline-playhead',
                                                    ),
                                                    width: 2,
                                                    color: colors.warning,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Text(
                          context.l10n.emptyStrokesHelp,
                          style: TextStyle(color: colors.textMuted),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _autoScrollForDrag(DragUpdateDetails details) {
    if (!_scrollController.hasClients) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(details.globalPosition);
    const edge = 64.0;
    final delta = local.dx < edge
        ? -24.0
        : local.dx > renderObject.size.width - edge
        ? 24.0
        : 0.0;
    if (delta == 0) return;
    final target = (_scrollController.offset + delta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  GlobalKey _sectionVisibilityKey(String sectionId) =>
      _sectionVisibilityKeys.putIfAbsent(
        sectionId,
        () => GlobalKey(debugLabel: 'timeline-section-visibility:$sectionId'),
      );

  void _observeSelection(EditorCubit observedCubit) {
    _observedStrokeIndex = observedCubit.state.selectedStrokeIndex;
    _observedSmartSectionId = observedCubit.state.selectedSmartSectionId;
    _selectionSubscription = observedCubit.stream.listen((state) {
      final selectionChanged =
          state.selectedStrokeIndex != _observedStrokeIndex ||
          state.selectedSmartSectionId != _observedSmartSectionId;
      _observedStrokeIndex = state.selectedStrokeIndex;
      _observedSmartSectionId = state.selectedSmartSectionId;
      if (selectionChanged) _scheduleSelectedNodeReveal(state);
    });
  }

  void _observeCameraDocument(EditorCubit observedCubit) {
    _cameraDocumentSubscription = observedCubit.stream.listen((state) {
      final selectedId = _cameraEditing.state.primaryShotId;
      final selectedShot = selectedId == null
          ? null
          : state.document.cameraTrack?.shots
                .where((shot) => shot.id == selectedId)
                .firstOrNull;
      final selectedKeyframeId = _cameraEditing.state.selectedKeyframeId;
      final selectedView = selectedShot == null
          ? null
          : selectedShot.keyframes
                    .where((frame) => frame.id == selectedKeyframeId)
                    .firstOrNull
                    ?.view ??
                selectedShot.keyframes.lastOrNull?.view;
      if (selectedView != null &&
          !_cameraEditing.state.isEditorViewDirty &&
          selectedView != _cameraEditing.state.savedEditorView) {
        _cameraEditing.restoreEditorView(selectedView);
      }
      _cameraEditing.reconcile(
        state.document.cameraTrack?.shots.map((shot) => shot.id) ??
            const <CameraShotId>[],
        keyframes:
            state.document.cameraTrack?.shots.expand(
              (shot) => shot.keyframes.map((frame) => frame.id),
            ) ??
            const <CameraKeyframeId>[],
      );
    });
  }

  void _scheduleSelectedNodeReveal(EditorState state) {
    final sectionId = _focusedSectionId(state);
    if (sectionId == null) return;
    final request = ++_revealRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _revealRequest) return;
      final targetContext = _sectionVisibilityKeys[sectionId]?.currentContext;
      if (targetContext == null || !_scrollController.hasClients) return;
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String? _focusedSectionId(EditorState state) {
    final smartSectionId = state.selectedSmartSectionId;
    if (smartSectionId != null) return smartSectionId;
    final strokeIndex = state.selectedStrokeIndex;
    if (strokeIndex == null ||
        strokeIndex < 0 ||
        strokeIndex >= widget.cubit.project.strokes.length) {
      return null;
    }
    final stroke = widget.cubit.project.strokes[strokeIndex];
    return stroke.sectionId ?? 'stroke:${stroke.id}';
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scrollController.hasClients) return;
    // Native horizontal trackpad gestures continue through Scrollable. A
    // conventional vertical mouse wheel pans the horizontal timeline, which
    // is the expected editor behavior when the pointer is over this dock.
    if (event.scrollDelta.dy.abs() <= event.scrollDelta.dx.abs()) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      _followSuspendedByManualNavigation = true;
      final target = (_scrollController.offset + event.scrollDelta.dy).clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(target);
    });
  }

  void _schedulePlayheadFollow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_followPlayhead ||
          _followSuspendedByManualNavigation ||
          !_scrollController.hasClients) {
        return;
      }
      final playheadX =
          widget.playheadTime.microseconds /
          Duration.microsecondsPerSecond *
          _lastPixelsPerSecond;
      final target = const TimelineFollowPolicy().targetOffset(
        enabled: _followPlayhead,
        playheadX: playheadX,
        currentOffset: _scrollController.offset,
        viewportWidth: _lastViewportWidth,
        maximumOffset: _scrollController.position.maxScrollExtent,
      );
      if (target == null) return;
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _panBy(double pointerDelta) {
    if (!_scrollController.hasClients) return;
    _followSuspendedByManualNavigation = true;
    final target = (_scrollController.offset - pointerDelta).clamp(
      _scrollController.position.minScrollExtent,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.jumpTo(target);
  }

  void _manualSeek(double progress) {
    _followSuspendedByManualNavigation = true;
    widget.onSeek(progress);
  }

  void _revealDrawingTime(double seconds, double timelineDuration) {
    _cameraEditing.setCanvasMode(CameraCanvasMode.browse);
    _followSuspendedByManualNavigation = true;
    (widget.onDrawingSeek ?? widget.onSeek)(
      (seconds / timelineDuration).clamp(0.0, 1.0),
    );
  }
}

class _CameraTimelineLane extends StatefulWidget {
  const _CameraTimelineLane({
    required this.editor,
    required this.editing,
    required this.width,
    required this.viewportStart,
    required this.viewportWidth,
    required this.duration,
    required this.pixelsPerSecond,
    required this.playhead,
    required this.onSeek,
    this.onAutoCamera,
    this.onRegenerateCameraRange,
    this.pendingPlan,
    this.diagnostics,
    this.onPreviewShot,
  });

  final EditorCubit editor;
  final CameraEditingCubit editing;
  final double width;
  final double viewportStart;
  final double viewportWidth;
  final TimelineDuration duration;
  final double pixelsPerSecond;
  final TimelineTime playhead;
  final ValueChanged<TimelineTime> onSeek;
  final VoidCallback? onAutoCamera;
  final ValueChanged<TimelineInterval>? onRegenerateCameraRange;
  final AutoDirectorPlan? pendingPlan;
  final CameraTimelineDiagnostics? diagnostics;
  final ValueChanged<CameraShot>? onPreviewShot;

  @override
  State<_CameraTimelineLane> createState() => _CameraTimelineLaneState();
}

enum _CameraTrimEdge { start, end }

class _CameraTimelineLaneState extends State<_CameraTimelineLane> {
  static const _height = 74.0;
  final FocusNode _focus = FocusNode(debugLabel: 'camera-timeline');
  CameraShotId? _draggedId;
  double _dragOriginX = 0;
  bool _snapEnabled = true;
  int? _activePointer;
  ScrollHoldController? _scrollHold;
  ({CameraShotId shotId, _CameraTrimEdge edge})? _hoveredTrimHandle;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  ProjectCameraTrack? get _track {
    final document = widget.editor.state.document;
    final source = document.cameraTrack;
    final ranges = widget.editor.timelineSectionRanges;
    final intervals = const SceneCameraTrackProjector().resolveSceneIntervals(
      scenes: document.scenes,
      sectionIntervals: {
        for (final entry in ranges.entries)
          SectionId(entry.key): TimelineInterval(
            start: TimelineTime.fromMicroseconds(
              (entry.value.startSeconds * Duration.microsecondsPerSecond)
                  .round(),
            ),
            end: TimelineTime.fromMicroseconds(
              (entry.value.endSeconds * Duration.microsecondsPerSecond).round(),
            ),
            intervalType: 'editor-scene-section',
            entityId: entry.key,
            sourceOperation: 'camera-timeline-ui',
            documentRevision: 0,
          ),
      },
      documentRevision: 0,
    );
    final projected = source == null
        ? null
        : const SceneCameraTrackProjector().project(
            track: source,
            sceneIntervals: intervals,
          );
    final existingOwners = {
      for (final shot in projected?.shots ?? const <CameraShot>[])
        ?shot.ownerSceneId,
    };
    final placeholders = <CameraShot>[];
    for (final scene in document.scenes) {
      final span = intervals[scene.id];
      if (existingOwners.contains(scene.id) || span == null) continue;
      placeholders.add(
        const SceneCameraTrackProjector().placeholder(
          scene: scene,
          interval: span,
        ),
      );
    }
    if (projected == null && placeholders.isEmpty) return null;
    return (projected ??
            ProjectCameraTrack(
              id: CameraTrackId('scene-camera-preview'),
              shots: const [],
            ))
        .copyWith(shots: [...?projected?.shots, ...placeholders]);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CameraEditingCubit, CameraEditingState>(
    bloc: widget.editing,
    builder: (context, editing) {
      final track = _track;
      return Focus(
        focusNode: _focus,
        autofocus: false,
        onKeyEvent: (_, event) => _handleKey(event, editing, track),
        child: Semantics(
          container: true,
          label: _text(context, 'Camera track', 'مسار الكاميرا'),
          enabled: track?.enabled ?? true,
          child: SizedBox(
            key: const ValueKey('camera-timeline-track'),
            width: widget.width,
            height: editing.collapsed ? 36 : _height,
            child: Column(
              children: [
                _header(context, track, editing),
                if (!editing.collapsed)
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Listener(
                            onPointerDown: (event) {
                              if (_activePointer != null ||
                                  event.buttons != kPrimaryButton) {
                                return;
                              }
                              if (HardwareKeyboard.instance.isMetaPressed ||
                                  HardwareKeyboard.instance.isControlPressed ||
                                  HardwareKeyboard.instance.isShiftPressed) {
                                return;
                              }
                              final pressedShot = _shotAt(
                                event.localPosition.dx,
                                track,
                              );
                              if (pressedShot != null &&
                                  _isScenePlaceholder(pressedShot)) {
                                _activateScenePlaceholder(pressedShot);
                                return;
                              }
                              _activePointer = event.pointer;
                              _scrollHold = Scrollable.maybeOf(
                                context,
                              )?.position.hold(() {});
                              _beginDrag(
                                DragStartDetails(
                                  globalPosition: event.position,
                                  localPosition: event.localPosition,
                                ),
                                track,
                              );
                            },
                            onPointerMove: (event) {
                              if (_activePointer != event.pointer) return;
                              _updateDrag(
                                DragUpdateDetails(
                                  globalPosition: event.position,
                                  localPosition: event.localPosition,
                                  delta: event.delta,
                                ),
                                track,
                              );
                            },
                            onPointerUp: (event) {
                              if (_activePointer != event.pointer) return;
                              _activePointer = null;
                              _scrollHold?.cancel();
                              _scrollHold = null;
                              _finishDrag(track);
                            },
                            onPointerCancel: (event) {
                              if (_activePointer != event.pointer) return;
                              _activePointer = null;
                              _scrollHold?.cancel();
                              _scrollHold = null;
                              _cancelDrag();
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) =>
                                  _tap(details, editing, track),
                              onDoubleTapDown: (details) {
                                final shot = _shotAt(
                                  details.localPosition.dx,
                                  track,
                                );
                                if (shot != null &&
                                    !_isScenePlaceholder(shot)) {
                                  if (!widget.editing.state.selectedShotIds
                                      .contains(shot.id)) {
                                    widget.editing.select(
                                      shot.id,
                                      shots: track?.shots ?? const [],
                                    );
                                  }
                                  if (shot.keyframes.isNotEmpty) {
                                    final frame = shot.ownerSceneId == null
                                        ? shot.keyframes.last
                                        : shot.keyframes.first;
                                    widget.editing.selectKeyframe(
                                      shot.id,
                                      frame.id,
                                      preserveShotSelection: true,
                                    );
                                    widget.editing.restoreEditorView(
                                      frame.view,
                                    );
                                    widget.editing.setCanvasMode(
                                      CameraCanvasMode.editCamera,
                                    );
                                    widget.onSeek(shot.startTime);
                                  }
                                  _showInspector(context, shot);
                                }
                              },
                              child: MouseRegion(
                                key: const ValueKey(
                                  'camera-clips-mouse-region',
                                ),
                                cursor: _hoveredTrimHandle == null
                                    ? SystemMouseCursors.precise
                                    : SystemMouseCursors.resizeLeftRight,
                                onHover: (event) => _updateTrimHover(
                                  event.localPosition.dx,
                                  track,
                                ),
                                onExit: (_) => _clearTrimHover(),
                                child: RepaintBoundary(
                                  child: CustomPaint(
                                    key: const ValueKey('camera-clips-painter'),
                                    painter: _CameraTrackPainter(
                                      track: track,
                                      editing: editing,
                                      pixelsPerSecond: widget.pixelsPerSecond,
                                      colors: context.studioColors,
                                      localeIsArabic: _isArabic(context),
                                      viewportStart: widget.viewportStart,
                                      viewportWidth: widget.viewportWidth,
                                      diagnostics: widget.diagnostics,
                                      pendingPlan: widget.pendingPlan,
                                      drawingImage: widget.editor.drawingImage,
                                      projectSize: Size(
                                        widget.editor.project.canvasWidth
                                            .toDouble(),
                                        widget.editor.project.canvasHeight
                                            .toDouble(),
                                      ),
                                      artworkDestination: widget
                                          .editor
                                          .project
                                          .artworkDestination,
                                      sceneNames: {
                                        for (final scene
                                            in widget
                                                .editor
                                                .state
                                                .document
                                                .scenes)
                                          scene.id: scene.name,
                                      },
                                      hoveredTrimShotId:
                                          _hoveredTrimHandle?.shotId,
                                      hoveredTrimEdge: _hoveredTrimHandle?.edge,
                                    ),
                                    size: Size(widget.width, _height - 32),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (track == null || track.shots.isEmpty)
                          Positioned.fill(
                            child: Center(
                              child: Text(
                                _text(
                                  context,
                                  'Compose the view above, then Add Camera',
                                  'اضبط المنظر بالأعلى ثم أضف لقطة كاميرا',
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _header(
    BuildContext context,
    ProjectCameraTrack? track,
    CameraEditingState editing,
  ) {
    final colors = context.studioColors;
    final selected = _primaryShot(editing, track);
    return Container(
      height: 32,
      padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          Icon(Icons.videocam_outlined, size: 16, color: colors.accent),
          const SizedBox(width: 6),
          Text(
            _text(context, 'Camera', 'الكاميرا'),
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
          if (selected != null) ...[
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                _cameraShotLabel(context, selected),
                textDirection: _isArabic(context)
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(fontSize: 10, color: colors.textSecondary),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            key: const ValueKey('camera-track-collapse'),
            tooltip: editing.collapsed
                ? _text(context, 'Show camera track', 'إظهار مسار الكاميرا')
                : _text(context, 'Collapse camera track', 'طي مسار الكاميرا'),
            onPressed: widget.editing.toggleCollapsed,
            icon: Icon(
              editing.collapsed ? Icons.expand_more : Icons.expand_less,
              size: 17,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
          ),
        ],
      ),
    );
  }

  KeyEventResult _handleKey(
    KeyEvent event,
    CameraEditingState editing,
    ProjectCameraTrack? track,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (editing.transientEdit != null) {
        _cancelDrag();
      } else {
        widget.editing.clear();
      }
      return KeyEventResult.handled;
    }
    final ids = editing.selectedShotIds;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (ids.isNotEmpty && widget.editor.deleteCameraShots(ids)) {
        widget.editing.clear();
      }
      return KeyEventResult.handled;
    }
    final modifier =
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed;
    if (modifier &&
        key == LogicalKeyboardKey.keyD &&
        editing.primaryShotId != null) {
      widget.editor.duplicateCameraShot(editing.primaryShotId!);
      return KeyEventResult.handled;
    }
    if (modifier && key == LogicalKeyboardKey.keyL && ids.isNotEmpty) {
      final selected =
          track?.shots.where((s) => ids.contains(s.id)).toList() ?? const [];
      widget.editor.setCameraShotsLocked(
        ids,
        !selected.every((s) => s.isLocked),
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS && editing.primaryShotId != null) {
      widget.editor.splitCameraShot(editing.primaryShotId!, widget.playhead);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _tap(
    TapUpDetails details,
    CameraEditingState editing,
    ProjectCameraTrack? track,
  ) {
    _focus.requestFocus();
    final keyframeHit = _keyframeAt(details.localPosition.dx, track);
    if (keyframeHit != null) {
      widget.editing.selectKeyframe(keyframeHit.$1.id, keyframeHit.$2.id);
      widget.editing.restoreEditorView(keyframeHit.$2.view);
      widget.editing.setCanvasMode(CameraCanvasMode.editCamera);
      widget.onSeek(
        TimelineTime.fromMicroseconds(
          keyframeHit.$1.startTime.microseconds +
              keyframeHit.$2.offset.microseconds,
        ),
      );
      return;
    }
    final shot = _shotAt(details.localPosition.dx, track);
    if (shot == null) {
      widget.editing.clear();
      return;
    }
    if (_isScenePlaceholder(shot)) {
      _activateScenePlaceholder(shot);
      return;
    }
    if (_propertiesHit(details.localPosition.dx, shot)) {
      if (!editing.selectedShotIds.contains(shot.id)) {
        widget.editing.select(shot.id, shots: track!.shots);
      }
      _showInspector(context, shot);
      return;
    }
    widget.editing.select(
      shot.id,
      toggle:
          HardwareKeyboard.instance.isMetaPressed ||
          HardwareKeyboard.instance.isControlPressed,
      range: HardwareKeyboard.instance.isShiftPressed,
      shots: track!.shots,
    );
    if (!HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        shot.keyframes.isNotEmpty) {
      final frame = shot.ownerSceneId == null
          ? shot.keyframes.last
          : shot.keyframes.first;
      widget.editing.selectKeyframe(shot.id, frame.id);
      widget.editing.restoreEditorView(frame.view);
      widget.editing.setCanvasMode(CameraCanvasMode.editCamera);
      widget.onSeek(shot.startTime);
    }
  }

  void _beginDrag(DragStartDetails details, ProjectCameraTrack? track) {
    _focus.requestFocus();
    final trimHit = _trimHandleAt(details.localPosition.dx, track);
    final shot = trimHit?.shot ?? _shotAt(details.localPosition.dx, track);
    if (shot == null || _isScenePlaceholder(shot)) return;
    final keyframeHit = _keyframeAt(details.localPosition.dx, track);
    final frame = keyframeHit?.$1.id == shot.id
        ? keyframeHit!.$2
        : shot.ownerSceneId == null
        ? shot.keyframes.lastOrNull
        : shot.keyframes.firstOrNull;
    if (frame != null) {
      widget.editing.selectKeyframe(shot.id, frame.id);
      widget.editing.restoreEditorView(frame.view);
      widget.editing.setCanvasMode(CameraCanvasMode.editCamera);
      widget.onSeek(
        keyframeHit?.$1.id == shot.id
            ? TimelineTime.fromMicroseconds(
                shot.startTime.microseconds + frame.offset.microseconds,
              )
            : shot.startTime,
      );
    }
    if (shot.isLocked || shot.ownerSceneId != null || track?.enabled == false) {
      return;
    }
    final mode = switch (trimHit?.edge) {
      _CameraTrimEdge.start => CameraInteractionMode.trimmingStart,
      _CameraTrimEdge.end => CameraInteractionMode.trimmingEnd,
      null => CameraInteractionMode.moving,
    };
    _draggedId = shot.id;
    _dragOriginX = details.localPosition.dx;
    _snapEnabled = !HardwareKeyboard.instance.isAltPressed;
    if (!widget.editing.state.selectedShotIds.contains(shot.id)) {
      widget.editing.select(shot.id, shots: track!.shots);
    }
    final selected = track!.shots.where(
      (item) => widget.editing.state.selectedShotIds.contains(item.id),
    );
    if (mode == CameraInteractionMode.moving && selected.length > 1) {
      if (selected.any((item) => item.isLocked)) return;
      widget.editing.beginMoveGroup(selected);
    } else {
      widget.editing.begin(shot, mode);
    }
  }

  bool _isScenePlaceholder(CameraShot shot) =>
      shot.id.value.startsWith('scene-camera-placeholder:');

  void _activateScenePlaceholder(CameraShot placeholder) {
    final sceneId = placeholder.ownerSceneId;
    if (sceneId == null || !widget.editor.ensureSceneCameraClip(sceneId)) {
      return;
    }
    final created = widget.editor.state.document.cameraTrack?.shots
        .where((item) => item.ownerSceneId == sceneId)
        .firstOrNull;
    if (created == null || created.keyframes.isEmpty) return;
    widget.editing.selectKeyframe(created.id, created.keyframes.first.id);
    widget.editing.restoreEditorView(created.keyframes.first.view);
    widget.editing.setCanvasMode(CameraCanvasMode.editCamera);
    widget.onSeek(created.startTime);
  }

  void _updateDrag(DragUpdateDetails details, ProjectCameraTrack? track) {
    final transient = widget.editing.state.transientEdit;
    final id = _draggedId;
    if (transient == null || id == null || track == null) return;
    final deltaUs =
        ((details.localPosition.dx - _dragOriginX) /
                widget.pixelsPerSecond *
                Duration.microsecondsPerSecond)
            .round();
    var start = transient.originalStart;
    var duration = transient.originalDuration;
    TimelineTime candidate;
    switch (widget.editing.state.interactionMode) {
      case CameraInteractionMode.moving:
        candidate = TimelineTime.fromMicroseconds(
          math.max(0, start.microseconds + deltaUs),
        );
        final snap = _snap(candidate, track, id);
        start = snap.time;
        final snappedDelta =
            start.microseconds - transient.originalStart.microseconds;
        final selectedIds = widget.editing.state.transientEdits.keys.toSet();
        final edits = <CameraShotId, CameraTransientEdit>{};
        var invalid = false;
        for (final entry in widget.editing.state.transientEdits.entries) {
          final shifted = TimelineTime.fromMicroseconds(
            math.max(0, entry.value.originalStart.microseconds + snappedDelta),
          );
          final overlaps = _overlapsSelection(
            shifted,
            entry.value.originalDuration,
            track,
            selectedIds,
          );
          invalid = invalid || overlaps;
          edits[entry.key] = entry.value.copyWith(
            previewStart: shifted,
            invalid: overlaps,
            snapGuide: entry.key == id ? snap.guide : null,
          );
        }
        if (invalid) {
          edits.updateAll((_, edit) => edit.copyWith(invalid: true));
        }
        widget.editing.updateGroup(edits);
      case CameraInteractionMode.trimmingStart:
        final maxStart =
            transient.originalStart.microseconds +
            transient.originalDuration.microseconds -
            CameraTimelineEditingPolicy.minimumShotDuration.microseconds;
        candidate = TimelineTime.fromMicroseconds(
          (transient.originalStart.microseconds + deltaUs)
              .clamp(0, maxStart)
              .toInt(),
        );
        final snap = _snap(candidate, track, id);
        start = TimelineTime.fromMicroseconds(
          snap.time.microseconds.clamp(0, maxStart).toInt(),
        );
        duration = TimelineDuration.fromMicroseconds(
          transient.originalStart.microseconds +
              transient.originalDuration.microseconds -
              start.microseconds,
        );
        widget.editing.update(
          transient.copyWith(
            previewStart: start,
            previewDuration: duration,
            invalid: _overlaps(start, duration, track, id),
            snapGuide: start == snap.time ? snap.guide : null,
          ),
        );
      case CameraInteractionMode.trimmingEnd:
        candidate = TimelineTime.fromMicroseconds(
          math.max(
            transient.originalStart.microseconds +
                CameraTimelineEditingPolicy.minimumShotDuration.microseconds,
            transient.originalStart.microseconds +
                transient.originalDuration.microseconds +
                deltaUs,
          ),
        );
        final snap = _snap(candidate, track, id);
        duration = TimelineDuration.fromMicroseconds(
          math.max(
            CameraTimelineEditingPolicy.minimumShotDuration.microseconds,
            snap.time.microseconds - transient.originalStart.microseconds,
          ),
        );
        widget.editing.update(
          transient.copyWith(
            previewDuration: duration,
            invalid: _overlaps(start, duration, track, id),
            snapGuide: snap.guide,
          ),
        );
      case CameraInteractionMode.idle:
        break;
    }
  }

  TimelineSnapResult _snap(
    TimelineTime candidate,
    ProjectCameraTrack track,
    CameraShotId excluded,
  ) {
    final targets = <TimelineTime>[TimelineTime.zero, widget.playhead];
    final excludedIds = widget.editing.state.transientEdits.keys.toSet()
      ..add(excluded);
    for (final shot in track.shots.where((s) => !excludedIds.contains(s.id))) {
      targets
        ..add(shot.startTime)
        ..add(shot.endTime);
    }
    for (final range in widget.editor.timelineSectionRanges.values) {
      targets
        ..add(
          TimelineTime.fromMicroseconds(
            (range.startSeconds * Duration.microsecondsPerSecond).round(),
          ),
        )
        ..add(
          TimelineTime.fromMicroseconds(
            (range.endSeconds * Duration.microsecondsPerSecond).round(),
          ),
        );
    }
    return const TimelineSnapService().snap(
      candidate: candidate,
      targets: targets,
      pixelsPerSecond: widget.pixelsPerSecond,
      enabled: _snapEnabled,
    );
  }

  void _finishDrag(ProjectCameraTrack? track) {
    final state = widget.editing.state;
    final edit = state.transientEdit;
    final id = _draggedId;
    if (edit == null || id == null || edit.invalid) return _cancelDrag();
    switch (state.interactionMode) {
      case CameraInteractionMode.moving:
        final starts = {
          for (final entry in state.transientEdits.entries)
            if (entry.value.previewStart != entry.value.originalStart)
              entry.key: entry.value.previewStart,
        };
        if (starts.isNotEmpty) {
          widget.editor.moveCameraShots(starts);
        }
      case CameraInteractionMode.trimmingStart:
        if (edit.previewStart != edit.originalStart ||
            edit.previewDuration != edit.originalDuration) {
          widget.editor.resizeCameraShotFromStart(id, edit.previewStart);
        }
      case CameraInteractionMode.trimmingEnd:
        if (edit.previewDuration != edit.originalDuration) {
          widget.editor.resizeCameraShot(id, edit.previewDuration);
        }
      case CameraInteractionMode.idle:
        break;
    }
    _cancelDrag();
  }

  void _cancelDrag() {
    _draggedId = null;
    _activePointer = null;
    _scrollHold?.cancel();
    _scrollHold = null;
    widget.editing.cancelInteraction();
  }

  void _updateTrimHover(double x, ProjectCameraTrack? track) {
    if (_activePointer != null) return;
    final hit = _trimHandleAt(x, track);
    final next = hit == null ? null : (shotId: hit.shot.id, edge: hit.edge);
    if (next == _hoveredTrimHandle) return;
    setState(() => _hoveredTrimHandle = next);
  }

  void _clearTrimHover() {
    if (_hoveredTrimHandle == null || _activePointer != null) return;
    setState(() => _hoveredTrimHandle = null);
  }

  ({CameraShot shot, _CameraTrimEdge edge})? _trimHandleAt(
    double x,
    ProjectCameraTrack? track,
  ) {
    if (track == null || !track.enabled) return null;
    ({CameraShot shot, _CameraTrimEdge edge})? best;
    var bestScore = double.infinity;
    for (final shot in track.shots.reversed) {
      if (shot.isLocked ||
          shot.ownerSceneId != null ||
          _isScenePlaceholder(shot)) {
        continue;
      }
      for (final edge in _CameraTrimEdge.values) {
        final handleX = edge == _CameraTrimEdge.start
            ? _x(shot.startTime)
            : _x(shot.endTime);
        final distance = (handleX - x).abs();
        if (distance > 11) continue;
        final selectedBias = widget.editing.state.primaryShotId == shot.id
            ? -1.0
            : 0.0;
        final score = distance + selectedBias;
        if (score < bestScore) {
          best = (shot: shot, edge: edge);
          bestScore = score;
        }
      }
    }
    return best;
  }

  bool _overlaps(
    TimelineTime start,
    TimelineDuration duration,
    ProjectCameraTrack track,
    CameraShotId excluded,
  ) {
    final end = start.microseconds + duration.microseconds;
    return track.shots.any(
      (s) =>
          s.id != excluded &&
          start.microseconds < s.endTime.microseconds &&
          end > s.startTime.microseconds,
    );
  }

  bool _overlapsSelection(
    TimelineTime start,
    TimelineDuration duration,
    ProjectCameraTrack track,
    Set<CameraShotId> selected,
  ) {
    final end = start.microseconds + duration.microseconds;
    return track.shots.any(
      (shot) =>
          !selected.contains(shot.id) &&
          start.microseconds < shot.endTime.microseconds &&
          end > shot.startTime.microseconds,
    );
  }

  CameraShot? _shotAt(double x, ProjectCameraTrack? track) {
    if (track == null) return null;
    final us = (x / widget.pixelsPerSecond * Duration.microsecondsPerSecond)
        .round();
    for (final shot in track.shots.reversed) {
      if (us >= shot.startTime.microseconds && us < shot.endTime.microseconds) {
        return shot;
      }
    }
    return null;
  }

  bool _propertiesHit(double x, CameraShot shot) {
    final width = _x(shot.endTime) - _x(shot.startTime);
    return width >= 76 && x >= _x(shot.endTime) - 25;
  }

  (CameraShot, CameraKeyframe)? _keyframeAt(
    double x,
    ProjectCameraTrack? track,
  ) {
    if (track == null) return null;
    for (final shot in track.shots.reversed) {
      for (final frame in shot.keyframes.reversed) {
        final frameX =
            _x(shot.startTime) +
            frame.offset.microseconds /
                Duration.microsecondsPerSecond *
                widget.pixelsPerSecond;
        if ((frameX - x).abs() <= 6) return (shot, frame);
      }
    }
    return null;
  }

  double _x(TimelineTime time) =>
      time.microseconds /
      Duration.microsecondsPerSecond *
      widget.pixelsPerSecond;

  CameraShot? _primaryShot(
    CameraEditingState editing,
    ProjectCameraTrack? track,
  ) {
    final id = editing.primaryShotId;
    if (id == null || track == null) return null;
    return track.shots.where((s) => s.id == id).firstOrNull;
  }

  // Kept only as a compatibility hook for downstream integrations; the
  // simple camera UI no longer exposes this menu.
  // ignore: unused_element
  Future<void> _showContextMenu(
    BuildContext context, {
    required Offset localPosition,
    required Offset globalPosition,
    required ProjectCameraTrack? track,
  }) async {
    final shot = _shotAt(localPosition.dx, track);
    if (shot == null) return;
    _focus.requestFocus();
    if (!widget.editing.state.selectedShotIds.contains(shot.id)) {
      widget.editing.select(shot.id, shots: track!.shots);
    }
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    final overlayBox = overlay?.context.findRenderObject() as RenderBox?;
    if (overlayBox == null || !overlayBox.hasSize) return;
    final action = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      constraints: BoxConstraints(
        maxHeight: math.max(96, overlayBox.size.height - 24),
        minWidth: 190,
        maxWidth: math.min(320, overlayBox.size.width - 16),
      ),
      position: anchoredMenuPosition(
        overlay: overlayBox,
        globalPosition: globalPosition,
      ),
      items: [
        PopupMenuItem(
          key: const ValueKey('camera-menu-duplicate'),
          value: 'duplicate',
          child: Text(_text(context, 'Duplicate', 'تكرار')),
        ),
        PopupMenuItem(
          key: const ValueKey('camera-menu-split'),
          value: 'split',
          child: Text(_text(context, 'Split at playhead', 'تقسيم عند المؤشر')),
        ),
        PopupMenuItem(
          key: const ValueKey('camera-menu-lock'),
          value: 'lock',
          child: Text(
            shot.isLocked
                ? _text(context, 'Unlock', 'إلغاء القفل')
                : _text(context, 'Lock', 'قفل'),
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('camera-menu-manual'),
          value: 'manual',
          enabled: !shot.isLocked && shot.authorship == CameraAuthorship.auto,
          child: Text(_text(context, 'Convert to Manual', 'تحويل إلى يدوي')),
        ),
        PopupMenuItem(
          key: const ValueKey('camera-menu-auto'),
          value: 'auto',
          enabled: !shot.isLocked && shot.authorship == CameraAuthorship.manual,
          child: Text(_text(context, 'Convert to Auto', 'تحويل إلى تلقائي')),
        ),
        PopupMenuItem(
          key: const ValueKey('camera-menu-regenerate'),
          value: 'regenerate',
          child: Text(
            _text(context, 'Regenerate this range', 'إعادة إنشاء هذا النطاق'),
          ),
        ),
        PopupMenuItem(
          key: const ValueKey('camera-menu-delete'),
          value: 'delete',
          enabled: !shot.isLocked,
          child: Text(_text(context, 'Delete', 'حذف')),
        ),
      ],
    );
    if (!mounted) return;
    _focus.requestFocus();
    if (action == 'duplicate') widget.editor.duplicateCameraShot(shot.id);
    if (action == 'split') {
      widget.editor.splitCameraShot(shot.id, widget.playhead);
    }
    if (action == 'lock') {
      widget.editor.setCameraShotsLocked({shot.id}, !shot.isLocked);
    }
    if (action == 'manual') {
      widget.editor.setCameraShotAuthorship(shot.id, CameraAuthorship.manual);
    }
    if (action == 'auto') {
      widget.editor.setCameraShotAuthorship(shot.id, CameraAuthorship.auto);
    }
    if (action == 'regenerate') {
      widget.onRegenerateCameraRange?.call(
        TimelineInterval(start: shot.startTime, end: shot.endTime),
      );
    }
    if (action == 'delete' && widget.editor.deleteCameraShots({shot.id})) {
      widget.editing.clear();
    }
  }

  Future<void> _showInspector(BuildContext context, CameraShot shot) async {
    await showCameraShotPropertiesDialog(
      context: context,
      editor: widget.editor,
      editing: widget.editing,
      shot: shot,
    );
  }
}

class _CameraTrackPainter extends CustomPainter {
  const _CameraTrackPainter({
    required this.track,
    required this.editing,
    required this.pixelsPerSecond,
    required this.colors,
    required this.localeIsArabic,
    required this.viewportStart,
    required this.viewportWidth,
    this.diagnostics,
    this.pendingPlan,
    required this.drawingImage,
    required this.projectSize,
    required this.artworkDestination,
    required this.sceneNames,
    this.hoveredTrimShotId,
    this.hoveredTrimEdge,
  });
  final ProjectCameraTrack? track;
  final CameraEditingState editing;
  final double pixelsPerSecond;
  final StudioThemeColors colors;
  final bool localeIsArabic;
  final double viewportStart;
  final double viewportWidth;
  final CameraTimelineDiagnostics? diagnostics;
  final AutoDirectorPlan? pendingPlan;
  final ui.Image? drawingImage;
  final Size projectSize;
  final Rect? artworkDestination;
  final Map<SceneId, String> sceneNames;
  final CameraShotId? hoveredTrimShotId;
  final _CameraTrimEdge? hoveredTrimEdge;

  @override
  void paint(Canvas canvas, Size size) {
    diagnostics?.painterRepaints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.surface);
    final shots = track?.shots ?? const <CameraShot>[];
    if (shots.isEmpty && pendingPlan == null) {
      final text = TextPainter(
        text: TextSpan(
          text: localeIsArabic ? 'لا توجد لقطات كاميرا' : 'No camera shots',
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        ),
        textDirection: localeIsArabic ? TextDirection.rtl : TextDirection.ltr,
      )..layout();
      text.paint(canvas, Offset(10, (size.height - text.height) / 2));
      return;
    }
    _paintGhosts(canvas, size);
    for (final shot in _visibleShots(shots)) {
      final shotNumber = shots.indexOf(shot) + 1;
      final transient = editing.transientEdits[shot.id];
      final start = transient?.previewStart ?? shot.startTime;
      final duration = transient?.previewDuration ?? shot.duration;
      final left =
          start.microseconds / Duration.microsecondsPerSecond * pixelsPerSecond;
      final width = math.max(
        3.0,
        duration.microseconds /
            Duration.microsecondsPerSecond *
            pixelsPerSecond,
      );
      final selected = editing.selectedShotIds.contains(shot.id);
      final placeholder = shot.keyframes.isEmpty && shot.ownerSceneId != null;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 4, width, size.height - 8),
        const Radius.circular(5),
      );
      final disabled = track?.enabled == false;
      canvas.drawRRect(
        rect,
        Paint()
          ..color = transient?.invalid == true
              ? colors.dangerContainer
              : placeholder
              ? colors.surfaceAlt
              : selected
              ? colors.selectedSurfaceStrong
              : colors.surfaceElevated,
      );
      if (!placeholder && drawingImage != null && width >= 42) {
        final previewRect = Rect.fromLTWH(
          left + 2,
          6,
          math.max(0, width - 4),
          math.max(0, size.height - 12),
        );
        canvas.save();
        canvas.clipRRect(rect);
        canvas.translate(previewRect.left, previewRect.top);
        CameraShotThumbnailPainter(
          image: drawingImage!,
          view: shot.keyframes.last.view,
          projectSize: projectSize,
          artworkDestination: artworkDestination,
        ).paint(canvas, previewRect.size);
        canvas.drawRect(
          Offset.zero & previewRect.size,
          Paint()..color = colors.appBackground.withValues(alpha: .58),
        );
        canvas.restore();
      }
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = transient?.invalid == true
              ? colors.danger
              : disabled
              ? colors.ignored
              : placeholder
              ? colors.accent.withValues(alpha: .55)
              : colors.border,
      );
      if (shot.isLocked) {
        canvas.drawRect(
          Rect.fromLTWH(left, 4, math.min(width, 4), size.height - 8),
          Paint()..color = colors.warning,
        );
      }
      final movement = placeholder
          ? (localeIsArabic ? 'أضف حركة' : 'Add motion')
          : shot.keyframes.any(
              (f) => f.incomingTransition.type == CameraTransitionType.fade,
            )
          ? (localeIsArabic ? 'تلاشي' : 'Fade')
          : shot.keyframes.any(
              (f) => f.incomingTransition.type == CameraTransitionType.move,
            )
          ? (localeIsArabic ? 'حركة' : 'Move')
          : (localeIsArabic ? 'قطع' : 'Cut');
      final displayLabel = shot.label == null || shot.label == 'Camera Shot'
          ? (localeIsArabic ? 'لقطة كاميرا' : 'Camera Shot')
          : shot.label!;
      final sceneName = shot.ownerSceneId == null
          ? null
          : sceneNames[shot.ownerSceneId!];
      final moveSeconds = shot.keyframes.isEmpty
          ? 0.0
          : shot.keyframes.last.incomingTransition.duration.microseconds /
                Duration.microsecondsPerSecond;
      final holdSeconds = math.max(
        0,
        shot.duration.microseconds / Duration.microsecondsPerSecond -
            moveSeconds,
      );
      final durationLabel =
          '${holdSeconds.toStringAsFixed(1)}s + '
          '${moveSeconds.toStringAsFixed(1)}s';
      final text = TextPainter(
        text: TextSpan(
          text: '$shotNumber · $displayLabel · $movement',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 9,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: math.max(0, width - 10));
      canvas.save();
      canvas.clipRRect(rect);
      text.paint(canvas, Offset(left + 5, 7));
      if (!placeholder && width >= 66) {
        final details = TextPainter(
          text: TextSpan(
            text: sceneName == null
                ? durationLabel
                : '$sceneName · $durationLabel',
            style: TextStyle(color: colors.textSecondary, fontSize: 8),
          ),
          textDirection: localeIsArabic ? TextDirection.rtl : TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(0, width - 30));
        details.paint(canvas, Offset(left + 5, size.height - 17));
        final properties = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(Icons.tune_rounded.codePoint),
            style: TextStyle(
              fontFamily: Icons.tune_rounded.fontFamily,
              package: Icons.tune_rounded.fontPackage,
              color: colors.accent,
              fontSize: 14,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        properties.paint(canvas, Offset(left + width - 21, 7));
      }
      if (!placeholder && width >= 28) {
        final transitionRatio = shot.duration.isZero
            ? 0.0
            : (moveSeconds /
                      (shot.duration.microseconds /
                          Duration.microsecondsPerSecond))
                  .clamp(0.0, 1.0);
        canvas.drawRect(
          Rect.fromLTWH(
            left + 2,
            size.height - 5,
            (width - 4) * transitionRatio,
            2,
          ),
          Paint()..color = colors.accent,
        );
        canvas.drawRect(
          Rect.fromLTWH(
            left + 2 + (width - 4) * transitionRatio,
            size.height - 5,
            (width - 4) * (1 - transitionRatio),
            2,
          ),
          Paint()..color = colors.warning,
        );
      }
      final canTrim =
          !placeholder &&
          !shot.isLocked &&
          shot.ownerSceneId == null &&
          disabled == false;
      final hovered = hoveredTrimShotId == shot.id;
      if ((selected && !placeholder) || (canTrim && hovered)) {
        for (final edge in _CameraTrimEdge.values) {
          final active =
              editing.primaryShotId == shot.id &&
              ((edge == _CameraTrimEdge.start &&
                      editing.interactionMode ==
                          CameraInteractionMode.trimmingStart) ||
                  (edge == _CameraTrimEdge.end &&
                      editing.interactionMode ==
                          CameraInteractionMode.trimmingEnd));
          final hot = active || (hovered && hoveredTrimEdge == edge);
          final edgeX = edge == _CameraTrimEdge.start
              ? left + 3.5
              : left + width - 3.5;
          if (hot) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(
                  center: Offset(edgeX, size.height / 2),
                  width: 10,
                  height: 28,
                ),
                const Radius.circular(5),
              ),
              Paint()..color = colors.accent.withValues(alpha: .2),
            );
          }
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(edgeX, size.height / 2),
                width: hot ? 5 : 3,
                height: hot ? 22 : 16,
              ),
              const Radius.circular(3),
            ),
            Paint()
              ..color = transient?.invalid == true
                  ? colors.danger
                  : hot
                  ? colors.accentSoft
                  : colors.accent,
          );
        }
      }
      if (placeholder) {
        final hint = TextPainter(
          text: TextSpan(
            text: localeIsArabic
                ? '+ إنشاء كاميرا للمشهد'
                : '+ Create scene camera',
            style: TextStyle(color: colors.accent, fontSize: 9),
          ),
          textDirection: localeIsArabic ? TextDirection.rtl : TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: math.max(0, width - 10));
        hint.paint(canvas, Offset(left + 5, 28));
      } else if (shot.ownerSceneId != null && shot.keyframes.isNotEmpty) {
        _paintSceneCurve(canvas, shot, left, width, size.height);
      }
      canvas.restore();
    }
    final guide = editing.transientEdit?.snapGuide;
    if (guide != null) {
      final x =
          guide.microseconds / Duration.microsecondsPerSecond * pixelsPerSecond;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = colors.warning
          ..strokeWidth = 1,
      );
    }
  }

  void _paintSceneCurve(
    Canvas canvas,
    CameraShot shot,
    double left,
    double width,
    double height,
  ) {
    if (width < 44 || shot.duration.isZero) return;
    final frames = shot.keyframes;
    final zooms = frames
        .map((frame) => 1 / frame.view.viewportWidth)
        .toList(growable: false);
    final minimum = zooms.reduce(math.min);
    final maximum = zooms.reduce(math.max);
    final range = math.max(.01, maximum - minimum);
    final curveTop = 27.0;
    final curveBottom = height - 8;
    final path = Path();
    for (var index = 0; index < frames.length; index++) {
      final x =
          left +
          6 +
          (width - 12) *
              frames[index].offset.microseconds /
              shot.duration.microseconds;
      final y =
          curveBottom -
          (curveBottom - curveTop) * (zooms[index] - minimum) / range;
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 1; index < frames.length; index++) {
      final transition = frames[index].incomingTransition.duration;
      if (transition.isZero) continue;
      final transitionStart =
          frames[index].offset.microseconds - transition.microseconds;
      final x =
          left +
          6 +
          (width - 12) * transitionStart / shot.duration.microseconds;
      canvas.drawLine(
        Offset(x, curveTop),
        Offset(x, curveBottom),
        Paint()..color = colors.border.withValues(alpha: .65),
      );
    }
  }

  void _paintGhosts(Canvas canvas, Size size) {
    final plan = pendingPlan;
    if (plan == null) return;
    final fill = Paint()
      ..color = colors.accent.withValues(alpha: .22)
      ..style = PaintingStyle.fill;
    final border = Paint()
      ..color = colors.accent.withValues(alpha: .85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final shot in _visibleGhosts(plan.proposedShots)) {
      final left =
          shot.interval.start.microseconds /
          Duration.microsecondsPerSecond *
          pixelsPerSecond;
      final width =
          shot.interval.duration.microseconds /
          Duration.microsecondsPerSecond *
          pixelsPerSecond;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 6, math.max(2, width), size.height - 12),
        const Radius.circular(5),
      );
      canvas.drawRRect(rect, fill);
      canvas.drawRRect(rect, border);
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder =>
      (size) => [
        for (final shot in _visibleShots(track?.shots ?? const <CameraShot>[]))
          CustomPainterSemantics(
            rect: Rect.fromLTWH(
              shot.startTime.microseconds /
                  Duration.microsecondsPerSecond *
                  pixelsPerSecond,
              0,
              math.max(
                3,
                shot.duration.microseconds /
                    Duration.microsecondsPerSecond *
                    pixelsPerSecond,
              ),
              size.height,
            ),
            properties: SemanticsProperties(
              label:
                  '${shot.label ?? (localeIsArabic ? 'لقطة' : 'Shot')}, ${_timecode(shot.startTime)}, ${_durationCode(shot.duration)}, ${shot.authorship.name}${shot.isLocked ? ', locked' : ''}',
              selected: editing.selectedShotIds.contains(shot.id),
              enabled: track?.enabled ?? true,
              button: true,
              textDirection: localeIsArabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          ),
        for (final shot in _visibleGhosts(
          pendingPlan?.proposedShots ?? const <ProposedCameraShot>[],
        ))
          CustomPainterSemantics(
            rect: Rect.fromLTWH(
              shot.interval.start.microseconds /
                  Duration.microsecondsPerSecond *
                  pixelsPerSecond,
              0,
              math.max(
                3,
                shot.interval.duration.microseconds /
                    Duration.microsecondsPerSecond *
                    pixelsPerSecond,
              ),
              size.height,
            ),
            properties: SemanticsProperties(
              label: localeIsArabic
                  ? 'لقطة كاميرا مقترحة'
                  : 'Proposed camera ghost clip',
              readOnly: true,
              textDirection: localeIsArabic
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          ),
      ];

  @override
  bool shouldRepaint(covariant _CameraTrackPainter old) =>
      old.track != track ||
      old.editing != editing ||
      old.pixelsPerSecond != pixelsPerSecond ||
      old.viewportStart != viewportStart ||
      old.viewportWidth != viewportWidth ||
      old.pendingPlan != pendingPlan ||
      old.drawingImage != drawingImage ||
      old.projectSize != projectSize ||
      old.artworkDestination != artworkDestination ||
      !mapEquals(old.sceneNames, sceneNames) ||
      old.hoveredTrimShotId != hoveredTrimShotId ||
      old.hoveredTrimEdge != hoveredTrimEdge ||
      old.colors != colors;

  @override
  bool shouldRebuildSemantics(covariant _CameraTrackPainter old) =>
      shouldRepaint(old);

  Iterable<CameraShot> _visibleShots(List<CameraShot> shots) sync* {
    yield* const CameraTimelineViewportQuery().visibleShots(
      shots: shots,
      viewportStart: viewportStart,
      viewportWidth: viewportWidth,
      pixelsPerSecond: pixelsPerSecond,
    );
  }

  Iterable<ProposedCameraShot> _visibleGhosts(
    List<ProposedCameraShot> shots,
  ) sync* {
    final startSeconds = viewportStart / pixelsPerSecond;
    final endSeconds = (viewportStart + viewportWidth) / pixelsPerSecond;
    for (final shot in shots) {
      final start =
          shot.interval.start.microseconds / Duration.microsecondsPerSecond;
      final end =
          shot.interval.end.microseconds / Duration.microsecondsPerSecond;
      if (end >= startSeconds && start <= endSeconds) yield shot;
    }
  }
}

final class CameraTimelineDiagnostics {
  int painterRepaints = 0;
}

bool _isArabic(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'ar';
String _text(BuildContext context, String english, String arabic) =>
    _isArabic(context) ? arabic : english;
String _cameraShotLabel(BuildContext context, CameraShot shot) =>
    shot.label == null || shot.label == 'Camera Shot'
    ? _text(context, 'Camera Shot', 'لقطة كاميرا')
    : shot.label!;
String _timecode(TimelineTime time) {
  final totalFrames = (time.microseconds * 30 / Duration.microsecondsPerSecond)
      .round();
  final frames = totalFrames % 30;
  final totalSeconds = totalFrames ~/ 30;
  final seconds = totalSeconds % 60;
  final minutes = (totalSeconds ~/ 60) % 60;
  final hours = totalSeconds ~/ 3600;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
}

String _durationCode(TimelineDuration duration) =>
    (duration.microseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

class _TimelineToolbar extends StatelessWidget {
  const _TimelineToolbar({
    required this.cubit,
    required this.zoom,
    required this.onZoomChanged,
    required this.followPlayhead,
    required this.onFollowPlayheadChanged,
  });

  final EditorCubit cubit;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final bool followPlayhead;
  final ValueChanged<bool> onFollowPlayheadChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.studioColors;
    return SizedBox(
      height: 43,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep the editing controls reachable before text labels begin to
          // compete with the fixed playhead and zoom controls. The scene split
          // action keeps its label at ordinary editor widths, but falls back to
          // the same discoverable tooltip/icon treatment on very narrow docks.
          final compact = constraints.maxWidth < 1600;
          final veryCompact = constraints.maxWidth < 800;
          final ultraCompact = constraints.maxWidth < 500;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                const Icon(Icons.video_library_outlined, size: 17),
                if (!ultraCompact) ...[
                  const SizedBox(width: 7),
                  Text(
                    l10n.scenePlanner,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: 12),
                ],
                if (cubit.state.hasDrawing)
                  if (veryCompact)
                    IconButton(
                      key: const ValueKey('open-smart-scene-split'),
                      tooltip: _timelineText(
                        context,
                        'Split into scenes',
                        'تقسيم إلى مشاهد',
                      ),
                      onPressed: cubit.state.isAnalyzingSmartPaths
                          ? null
                          : () => showSmartSceneSplitDialog(context, cubit),
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.auto_awesome_mosaic, size: 17),
                    )
                  else
                    TextButton.icon(
                      key: const ValueKey('open-smart-scene-split'),
                      onPressed: cubit.state.isAnalyzingSmartPaths
                          ? null
                          : () => showSmartSceneSplitDialog(context, cubit),
                      icon: const Icon(Icons.auto_awesome_mosaic, size: 15),
                      label: Text(
                        _timelineText(
                          context,
                          'Split into scenes',
                          'تقسيم إلى مشاهد',
                        ),
                      ),
                    ),
                if (cubit.smartSections.isNotEmpty)
                  if (compact)
                    IconButton(
                      key: const ValueKey('auto-arrange-timeline-dock'),
                      tooltip: l10n.autoArrangeTimeline,
                      onPressed: cubit.autoArrangeTimeline,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.auto_awesome, size: 17),
                    )
                  else
                    TextButton.icon(
                      key: const ValueKey('auto-arrange-timeline-dock'),
                      onPressed: cubit.autoArrangeTimeline,
                      icon: const Icon(Icons.auto_awesome, size: 15),
                      label: Text(l10n.autoArrangeTimeline),
                    ),
                if (cubit.selectedTimelineSectionIds.isNotEmpty)
                  if (compact)
                    IconButton.filledTonal(
                      key: const ValueKey('group-selected-timeline'),
                      tooltip: l10n.groupSelectedTimeline(
                        cubit.selectedTimelineSectionIds.length,
                      ),
                      onPressed: cubit.createTimelineGroupFromSelection,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 16,
                      ),
                    )
                  else
                    FilledButton.tonalIcon(
                      key: const ValueKey('group-selected-timeline'),
                      onPressed: cubit.createTimelineGroupFromSelection,
                      icon: const Icon(
                        Icons.create_new_folder_outlined,
                        size: 15,
                      ),
                      label: Text(
                        l10n.groupSelectedTimeline(
                          cubit.selectedTimelineSectionIds.length,
                        ),
                      ),
                    ),
                const Spacer(),
                IconButton(
                  key: const ValueKey('follow-playhead-toggle'),
                  tooltip: _timelineText(
                    context,
                    'Follow Playhead',
                    'متابعة مؤشر التشغيل',
                  ),
                  onPressed: () => onFollowPlayheadChanged(!followPlayhead),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  color: followPlayhead ? colors.accent : colors.textMuted,
                  icon: Icon(
                    followPlayhead
                        ? Icons.my_location
                        : Icons.location_disabled,
                    size: 17,
                  ),
                ),
                if (cubit.smartSections.isNotEmpty)
                  IconButton(
                    key: const ValueKey('draw-scene-group'),
                    tooltip: l10n.drawSceneGroup,
                    onPressed: () => cubit.setTool(
                      cubit.tool == EditorTool.sceneGroup
                          ? EditorTool.select
                          : EditorTool.sceneGroup,
                    ),
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      cubit.tool == EditorTool.sceneGroup
                          ? Icons.close
                          : Icons.gesture,
                      size: 18,
                    ),
                  ),
                if (cubit.timelineSceneGroups.isNotEmpty)
                  IconButton(
                    tooltip: l10n.resetSceneGroups,
                    onPressed: cubit.clearSceneGroups,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.folder_off_outlined, size: 18),
                  ),
                IconButton(
                  key: const ValueKey('timeline-zoom-out'),
                  tooltip: l10n.zoomOut,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: zoom <= 0.5
                      ? null
                      : () => onZoomChanged(math.max(0.5, zoom - 0.5)),
                  icon: const Icon(Icons.zoom_out, size: 17),
                ),
                if (constraints.maxWidth >= 900) ...[
                  SizedBox(
                    width: 125,
                    child: Slider(
                      key: const ValueKey('timeline-zoom-slider'),
                      value: zoom,
                      min: 0.5,
                      max: 12,
                      divisions: 23,
                      onChanged: onZoomChanged,
                    ),
                  ),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${zoom.toStringAsFixed(zoom % 1 == 0 ? 0 : 1)}×',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.studioColors.textMuted,
                        fontSize: 10,
                        fontFeatures: const [ui.FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
                IconButton(
                  key: const ValueKey('timeline-zoom-in'),
                  tooltip: l10n.zoomIn,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: zoom >= 12
                      ? null
                      : () => onZoomChanged(math.min(12, zoom + 0.5)),
                  icon: const Icon(Icons.zoom_in, size: 17),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimelineRuler extends StatelessWidget {
  const _TimelineRuler({
    required this.durationSeconds,
    required this.onSeek,
    required this.onPanBy,
  });

  final double durationSeconds;
  final ValueChanged<double> onSeek;
  final ValueChanged<double> onPanBy;

  void _seekFromPosition(BuildContext context, Offset localPosition) {
    final width = context.size?.width ?? 1;
    onSeek((localPosition.dx / width).clamp(0, 1));
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.precise,
    child: Listener(
      onPointerMove: (event) {
        if (event.kind == ui.PointerDeviceKind.mouse &&
            (event.buttons & kMiddleMouseButton) != 0) {
          onPanBy(event.delta.dx);
        }
      },
      child: GestureDetector(
        key: const ValueKey('timeline-ruler'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) =>
            _seekFromPosition(context, details.localPosition),
        onHorizontalDragStart: (details) =>
            _seekFromPosition(context, details.localPosition),
        onHorizontalDragUpdate: (details) =>
            _seekFromPosition(context, details.localPosition),
        child: SizedBox(
          height: 25,
          width: double.infinity,
          child: CustomPaint(
            painter: _TimelineRulerPainter(
              color: context.studioColors.textMuted,
              border: context.studioColors.border,
              durationSeconds: durationSeconds,
            ),
          ),
        ),
      ),
    ),
  );
}

class _TimelineRulerPainter extends CustomPainter {
  const _TimelineRulerPainter({
    required this.color,
    required this.border,
    required this.durationSeconds,
  });

  final Color color;
  final Color border;
  final double durationSeconds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 1),
      Offset(size.width, size.height - 1),
      Paint()..color = border,
    );
    const divisions = 10;
    for (var index = 0; index <= divisions; index++) {
      final x = size.width * index / divisions;
      canvas.drawLine(
        Offset(x, size.height - (index.isEven ? 9 : 5)),
        Offset(x, size.height),
        Paint()..color = color,
      );
      if (index.isEven) {
        final seconds = durationSeconds * index / divisions;
        final text = TextPainter(
          text: TextSpan(
            text: '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)}s',
            style: TextStyle(color: color, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        text.paint(canvas, Offset(x + 3, 2));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineRulerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.border != border ||
      oldDelegate.durationSeconds != durationSeconds;
}

class _TimelineDragData {
  const _TimelineDragData.node(String nodeKey)
    : nodeKeys = const [],
      singleNodeKey = nodeKey,
      sceneId = null,
      sectionId = null;

  const _TimelineDragData.nodes(this.nodeKeys)
    : singleNodeKey = null,
      sceneId = null,
      sectionId = null;

  const _TimelineDragData.member({
    required this.sceneId,
    required this.sectionId,
  }) : nodeKeys = const [],
       singleNodeKey = null;

  final List<String> nodeKeys;
  final String? singleNodeKey;
  final String? sceneId;
  final String? sectionId;

  List<String> get topLevelNodeKeys =>
      singleNodeKey == null ? nodeKeys : <String>[singleNodeKey!];

  bool get isTopLevel => topLevelNodeKeys.isNotEmpty;
}

class _TimelineNodeClip extends StatefulWidget {
  const _TimelineNodeClip({
    required this.cubit,
    required this.node,
    required this.sectionVisibilityKey,
    required this.onPreviewStroke,
    required this.pixelsPerSecond,
    required this.ranges,
    required this.boundsBySection,
    required this.metrics,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    required this.onRevealTime,
    required this.playheadSeconds,
  });

  final EditorCubit cubit;
  final DrawingTimelineNode node;
  final GlobalKey Function(String sectionId) sectionVisibilityKey;
  final ValueChanged<int> onPreviewStroke;
  final double pixelsPerSecond;
  final Map<String, DrawingTimelineRange> ranges;
  final Map<String, Rect?> boundsBySection;
  final Map<String, ProjectTimelineSectionMetrics> metrics;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;
  final ValueChanged<double> onRevealTime;
  final double playheadSeconds;

  @override
  State<_TimelineNodeClip> createState() => _TimelineNodeClipState();
}

class _TimelineNodeClipState extends State<_TimelineNodeClip> {
  bool _insertAfter = false;

  EditorCubit get cubit => widget.cubit;
  DrawingTimelineNode get node => widget.node;

  @override
  Widget build(BuildContext context) {
    final group = node.scene;
    final width = math.max(
      1.0,
      node.allSectionIds.fold<double>(
        0,
        (sum, id) =>
            sum +
            (widget.ranges[id]?.durationSeconds ?? 0) * widget.pixelsPerSecond,
      ),
    );
    final starts = node.allSectionIds
        .map((id) => widget.ranges[id]?.startSeconds)
        .whereType<double>();
    final ends = node.allSectionIds
        .map((id) => widget.ranges[id]?.endSeconds)
        .whereType<double>();
    final nodeStart = starts.isEmpty ? 0.0 : starts.reduce(math.min);
    final nodeEnd = ends.isEmpty ? nodeStart : ends.reduce(math.max);
    final playedFraction = nodeEnd <= nodeStart
        ? 0.0
        : ((widget.playheadSeconds - nodeStart) / (nodeEnd - nodeStart)).clamp(
            0.0,
            1.0,
          );
    return DragTarget<_TimelineDragData>(
      onWillAcceptWithDetails: (details) =>
          details.data.isTopLevel &&
          !details.data.topLevelNodeKeys.contains(node.key),
      onMove: (details) {
        final box = context.findRenderObject();
        if (box is! RenderBox) return;
        final after =
            box.globalToLocal(details.offset).dx >= box.size.width / 2;
        if (after != _insertAfter) setState(() => _insertAfter = after);
      },
      onAcceptWithDetails: (details) {
        final nodeIndex = cubit.timelineNodes.indexWhere(
          (candidate) => candidate.key == node.key,
        );
        if (nodeIndex < 0) return;
        cubit.reorderTimelineNodes(
          details.data.topLevelNodeKeys,
          nodeIndex + (_insertAfter ? 1 : 0),
        );
      },
      builder: (context, candidates, _) {
        final accepting = candidates.isNotEmpty;
        return SizedBox(
          key: ValueKey('timeline-node-${node.key}'),
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: group == null
                      ? KeyedSubtree(
                          key: widget.sectionVisibilityKey(
                            node.singleSectionId,
                          ),
                          child: _SectionClip(
                            cubit: cubit,
                            sectionId: node.singleSectionId,
                            onPreviewStroke: widget.onPreviewStroke,
                            dragData: _dragData,
                            range: widget.ranges[node.singleSectionId],
                            normalizedBounds:
                                widget.boundsBySection[node.singleSectionId],
                            metrics: widget.metrics[node.singleSectionId],
                            onTimingChangeStart: widget.onTimingChangeStart,
                            onTimingChangeEnd: widget.onTimingChangeEnd,
                            onRevealTime: widget.onRevealTime,
                            // Account for the node gutter and the clip's own
                            // padding. The regular header needs enough room for
                            // selection plus both contextual actions; switching
                            // earlier keeps every control visible at narrow
                            // timeline scales instead of overflowing or being
                            // clipped.
                            compact: width < 132,
                          ),
                        )
                      : _SceneClip(
                          cubit: cubit,
                          group: group,
                          sectionVisibilityKey: widget.sectionVisibilityKey,
                          onPreviewStroke: widget.onPreviewStroke,
                          nodeKey: node.key,
                          highlighted: false,
                          ranges: widget.ranges,
                          boundsBySection: widget.boundsBySection,
                          pixelsPerSecond: widget.pixelsPerSecond,
                          metrics: widget.metrics,
                          onTimingChangeStart: widget.onTimingChangeStart,
                          onTimingChangeEnd: widget.onTimingChangeEnd,
                          onRevealTime: widget.onRevealTime,
                        ),
                ),
              ),
              if (playedFraction > 0)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        key: ValueKey('timeline-node-played:${node.key}'),
                        widthFactor: playedFraction,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: context.studioColors.accent.withValues(
                              alpha: 0.13,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (accepting)
                Positioned(
                  key: ValueKey(
                    'timeline-insertion-${_insertAfter ? 'after' : 'before'}:${node.key}',
                  ),
                  left: _insertAfter ? null : -2,
                  right: _insertAfter ? -2 : null,
                  top: -4,
                  bottom: -4,
                  child: _TimelineInsertionIndicator(
                    itemCount: candidates.first!.topLevelNodeKeys.length,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  _TimelineDragData get _dragData {
    final selected = cubit.selectedTimelineSectionIds;
    if (!selected.contains(node.singleSectionId) || selected.length < 2) {
      return _TimelineDragData.node(node.key);
    }
    final keys = [
      for (final candidate in cubit.timelineNodes)
        if (candidate.allSectionIds.any(selected.contains)) candidate.key,
    ];
    return _TimelineDragData.nodes(List.unmodifiable(keys));
  }
}

class _TimelineInsertionIndicator extends StatelessWidget {
  const _TimelineInsertionIndicator({required this.itemCount});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return IgnorePointer(
      child: Column(
        children: [
          Icon(Icons.arrow_drop_down, size: 14, color: colors.warning),
          Expanded(
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: colors.warning,
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: colors.warning.withValues(alpha: 0.45),
                    blurRadius: 5,
                  ),
                ],
              ),
            ),
          ),
          if (itemCount > 1)
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.warning,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  '$itemCount',
                  style: TextStyle(
                    color: colors.pathMarkerText,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SceneClip extends StatelessWidget {
  const _SceneClip({
    required this.cubit,
    required this.group,
    required this.sectionVisibilityKey,
    required this.onPreviewStroke,
    required this.nodeKey,
    required this.highlighted,
    required this.ranges,
    required this.boundsBySection,
    required this.pixelsPerSecond,
    required this.metrics,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    required this.onRevealTime,
  });

  final EditorCubit cubit;
  final DrawingSceneGroup group;
  final GlobalKey Function(String sectionId) sectionVisibilityKey;
  final ValueChanged<int> onPreviewStroke;
  final String nodeKey;
  final bool highlighted;
  final Map<String, DrawingTimelineRange> ranges;
  final Map<String, Rect?> boundsBySection;
  final double pixelsPerSecond;
  final Map<String, ProjectTimelineSectionMetrics> metrics;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;
  final ValueChanged<double> onRevealTime;

  @override
  Widget build(BuildContext context) {
    final selected = cubit.selectedTimelineSceneId == group.id;
    final selectedMembers = group.sectionIds
        .where(cubit.selectedTimelineSectionIds.contains)
        .length;
    final allMembersSelected = selectedMembers == group.sectionIds.length;
    final sceneSelectionValue = selectedMembers == 0
        ? false
        : allMembersSelected
        ? true
        : null;
    return _ClipDragSource(
      key: ValueKey('timeline-drag-scene:$nodeKey'),
      data: _TimelineDragData.node(nodeKey),
      child: DecoratedBox(
        decoration: _clipDecoration(
          context,
          selected: selected || highlighted,
          scene: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 31,
              child: LayoutBuilder(
                builder: (context, constraints) => InkWell(
                  onTap: () {
                    cubit.selectTimelineScene(group.id);
                    onRevealTime(
                      _representativeTimelineTime(
                        group.sectionIds.map((id) => ranges[id]),
                      ),
                    );
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PositionedDirectional(
                        start: 1,
                        child: _CompactTimelineCheckbox(
                          key: ValueKey('timeline-select-scene:${group.id}'),
                          value: sceneSelectionValue,
                          tristate: true,
                          onChanged: (_) => cubit.setTimelineSectionsSelected(
                            group.sectionIds,
                            selected: !allMembersSelected,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: 24,
                        child: IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 25,
                            height: 25,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () =>
                              cubit.toggleTimelineSceneExpanded(group.id),
                          icon: Icon(
                            group.collapsed
                                ? Icons.chevron_right
                                : Icons.expand_more,
                            size: 17,
                          ),
                        ),
                      ),
                      if (constraints.maxWidth >= 100)
                        Padding(
                          padding: const EdgeInsetsDirectional.fromSTEB(
                            52,
                            0,
                            28,
                            0,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.movie_filter_outlined, size: 14),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  group.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      PositionedDirectional(
                        end: 1,
                        child: IconButton(
                          constraints: const BoxConstraints.tightFor(
                            width: 25,
                            height: 25,
                          ),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onPressed: () => cubit.deleteSceneGroup(group.id),
                          icon: const Icon(Icons.close, size: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: group.collapsed
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(7, 3, 7, 7),
                      child: Row(
                        children: [
                          for (final id in group.sectionIds)
                            Expanded(
                              child: KeyedSubtree(
                                key: sectionVisibilityKey(id),
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 2,
                                  ),
                                  child: _SectionTimelinePreview(
                                    cubit: cubit,
                                    sectionId: id,
                                    range: ranges[id],
                                    metrics: metrics[id],
                                    image: cubit.drawingImage,
                                    normalizedBounds: boundsBySection[id],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  : Row(
                      children: [
                        for (final id in group.sectionIds)
                          KeyedSubtree(
                            key: sectionVisibilityKey(id),
                            child: SizedBox(
                              width: math.max(
                                1,
                                (ranges[id]?.durationSeconds ?? 0) *
                                        pixelsPerSecond -
                                    (2 / math.max(1, group.sectionIds.length)),
                              ),
                              child: DragTarget<_TimelineDragData>(
                                onWillAcceptWithDetails: (details) =>
                                    details.data.sceneId == group.id &&
                                    details.data.sectionId != id,
                                onAcceptWithDetails: (details) =>
                                    cubit.reorderTimelineSceneMember(
                                      group.id,
                                      details.data.sectionId!,
                                      id,
                                    ),
                                builder: (context, candidates, _) => Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    3,
                                    1,
                                    3,
                                    5,
                                  ),
                                  child: _SectionClip(
                                    cubit: cubit,
                                    sectionId: id,
                                    onPreviewStroke: onPreviewStroke,
                                    compact: true,
                                    highlighted: candidates.isNotEmpty,
                                    dragData: _TimelineDragData.member(
                                      sceneId: group.id,
                                      sectionId: id,
                                    ),
                                    range: ranges[id],
                                    normalizedBounds: boundsBySection[id],
                                    metrics: metrics[id],
                                    onTimingChangeStart: onTimingChangeStart,
                                    onTimingChangeEnd: onTimingChangeEnd,
                                    onRevealTime: onRevealTime,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionClip extends StatelessWidget {
  const _SectionClip({
    required this.cubit,
    required this.sectionId,
    required this.onPreviewStroke,
    required this.dragData,
    required this.range,
    required this.normalizedBounds,
    required this.metrics,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    required this.onRevealTime,
    this.compact = false,
    this.highlighted = false,
  });

  final EditorCubit cubit;
  final String sectionId;
  final ValueChanged<int> onPreviewStroke;
  final _TimelineDragData dragData;
  final DrawingTimelineRange? range;
  final Rect? normalizedBounds;
  final ProjectTimelineSectionMetrics? metrics;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;
  final ValueChanged<double> onRevealTime;
  final bool compact;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final section = _smartSection;
    final clipRange = range;
    final index = cubit.timelineSectionOrder.indexOf(sectionId) + 1;
    final selected = section != null
        ? cubit.selectedSmartSectionId == sectionId
        : _isAppliedSelected;
    final selectedForBatch = cubit.selectedTimelineSectionIds.contains(
      sectionId,
    );
    final showActions = selected || selectedForBatch;
    return _ClipDragSource(
      key: ValueKey('timeline-drag-section:$sectionId'),
      data: dragData,
      child: InkWell(
        onTap: () {
          _select();
          onRevealTime(_representativeTimelineTime([range]));
        },
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: _clipDecoration(
            context,
            selected: selected || selectedForBatch || highlighted,
          ),
          child: Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 5, vertical: 2)
                : const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (compact)
                  SizedBox(
                    height: 22,
                    width: double.infinity,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        PositionedDirectional(
                          start: -3,
                          child: _CompactTimelineCheckbox(
                            key: ValueKey('timeline-select-$sectionId'),
                            value: selectedForBatch,
                            onChanged: (_) =>
                                cubit.toggleTimelineSectionSelection(sectionId),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            clipRange == null
                                ? '$index · $_label'
                                : '$index · '
                                      '${_formatTimelineTime(clipRange.startSeconds)}–'
                                      '${_formatTimelineTime(clipRange.endSeconds)}',
                            key: clipRange == null
                                ? null
                                : ValueKey('timeline-time-$sectionId'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.studioColors.warning,
                              fontSize: 8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (showActions)
                          PositionedDirectional(
                            end: -4,
                            child: PopupMenuButton<_TimelineClipAction>(
                              key: ValueKey('timeline-actions-$sectionId'),
                              padding: EdgeInsets.zero,
                              iconSize: 15,
                              tooltip: context.l10n.viewMenu,
                              onSelected: (action) =>
                                  _handleAction(context, action),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: _TimelineClipAction.view,
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.visibility_outlined,
                                      size: 17,
                                    ),
                                    title: Text(context.l10n.viewMenu),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _TimelineClipAction.delete,
                                  child: ListTile(
                                    dense: true,
                                    leading: const Icon(
                                      Icons.delete_outline,
                                      size: 17,
                                    ),
                                    title: Text(context.l10n.deleteStroke),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: Checkbox(
                          key: ValueKey('timeline-select-$sectionId'),
                          value: cubit.selectedTimelineSectionIds.contains(
                            sectionId,
                          ),
                          visualDensity: VisualDensity.compact,
                          onChanged: (_) =>
                              cubit.toggleTimelineSectionSelection(sectionId),
                        ),
                      ),
                      const SizedBox(width: 4),
                      CircleAvatar(
                        radius: 9,
                        backgroundColor: context.studioColors.warning,
                        foregroundColor: context.studioColors.pathMarkerText,
                        child: Text(
                          '$index',
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (showActions) ...[
                        _TimelineActionButton(
                          key: ValueKey('timeline-view-$sectionId'),
                          icon: Icons.visibility_outlined,
                          tooltip: context.l10n.viewMenu,
                          onPressed: () => _showPropertiesDialog(context),
                        ),
                        _TimelineActionButton(
                          key: ValueKey('timeline-delete-$sectionId'),
                          icon: Icons.delete_outline,
                          tooltip: context.l10n.deleteStroke,
                          onPressed: () => _confirmDelete(context),
                        ),
                      ] else if (section != null)
                        PopupMenuButton<SmartSectionMode>(
                          padding: EdgeInsets.zero,
                          iconSize: 15,
                          initialValue: section.mode,
                          onSelected: (mode) =>
                              cubit.setSmartSectionMode(sectionId, mode),
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: SmartSectionMode.handDraw,
                              child: Text(context.l10n.hand),
                            ),
                            PopupMenuItem(
                              value: SmartSectionMode.revealText,
                              child: Text(context.l10n.reveal),
                            ),
                            PopupMenuItem(
                              value: SmartSectionMode.ignore,
                              child: Text(context.l10n.hidePath),
                            ),
                          ],
                        )
                      else
                        const Icon(Icons.drag_indicator, size: 15),
                    ],
                  ),
                if (!compact) const SizedBox(height: 3),
                Expanded(
                  child: _SectionTimelinePreview(
                    key: ValueKey('timeline-thumbnail-$sectionId'),
                    cubit: cubit,
                    sectionId: sectionId,
                    range: range,
                    metrics: metrics,
                    image: cubit.drawingImage,
                    normalizedBounds: normalizedBounds,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          _label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: Directionality.of(context),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            decoration: section?.mode == SmartSectionMode.ignore
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                      if (clipRange != null) ...[
                        const SizedBox(width: 2),
                        Flexible(
                          flex: 2,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(
                              '${_formatTimelineTime(clipRange.startSeconds)}  —  '
                              '${_formatTimelineTime(clipRange.endSeconds)}',
                              key: ValueKey('timeline-time-$sectionId'),
                              maxLines: 1,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                color: context.studioColors.textMuted,
                                fontSize: 9,
                                fontFeatures: const [
                                  ui.FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  SmartPathSection? get _smartSection {
    for (final section in cubit.smartSections) {
      if (section.id == sectionId) return section;
    }
    return null;
  }

  String get _label {
    final section = _smartSection;
    if (section != null) return section.label;
    for (final stroke in cubit.project.strokes) {
      final key = stroke.sectionId ?? 'stroke:${stroke.id}';
      if (key == sectionId) return stroke.name;
    }
    return sectionId;
  }

  bool get _isAppliedSelected {
    final selected = cubit.selectedStrokeIndex;
    if (selected == null || selected >= cubit.project.strokes.length) {
      return false;
    }
    final stroke = cubit.project.strokes[selected];
    return (stroke.sectionId ?? 'stroke:${stroke.id}') == sectionId;
  }

  void _select() {
    final section = _smartSection;
    if (section != null) {
      cubit.selectSmartSection(sectionId);
      return;
    }
    final index = cubit.project.strokes.indexWhere((stroke) {
      final key = stroke.sectionId ?? 'stroke:${stroke.id}';
      return key == sectionId;
    });
    if (index >= 0) cubit.selectStroke(index);
  }

  String get _timingKey =>
      sectionId.startsWith('stroke:') ? sectionId : 'section:$sectionId';

  void _handleAction(BuildContext context, _TimelineClipAction action) {
    switch (action) {
      case _TimelineClipAction.view:
        _showPropertiesDialog(context);
      case _TimelineClipAction.delete:
        _confirmDelete(context);
    }
  }

  Future<void> _showPropertiesDialog(BuildContext context) async {
    final timing = cubit.sectionTiming(_timingKey);
    final resolvedMetrics =
        metrics ?? projectTimelineSectionMetrics(cubit.project)[sectionId];
    final pause = timing.pauseAfterSeconds;
    final transition =
        timing.transitionAfterSeconds ??
        resolvedMetrics?.transitionAfterSeconds ??
        0;
    final estimatedAnimation = math.max(
      0.05,
      (range?.durationSeconds ?? 1) - pause - transition,
    );
    final strokeIndex = cubit.project.strokes.indexWhere((stroke) {
      final key = stroke.sectionId ?? 'stroke:${stroke.id}';
      return key == sectionId;
    });
    if (strokeIndex >= 0) cubit.selectStroke(strokeIndex);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => TimelineSectionPropertiesDialog(
        cubit: cubit,
        sectionId: sectionId,
        label: _label,
        preview: _SectionThumbnail(
          image: cubit.drawingImage,
          normalizedBounds: normalizedBounds,
        ),
        // The persisted override is the section's 1× baseline. Present the
        // resolved duration after overall and per-section speed so the dialog,
        // clip width, Preview and MOV all report the same real time.
        animationSeconds:
            resolvedMetrics?.animationSeconds ??
            timing.animationDurationSeconds ??
            estimatedAnimation,
        speedMultiplier: timing.speedMultiplier,
        pauseSeconds: pause,
        transitionSeconds: transition,
        pauseBeforeSeconds: timing.pauseBeforeSeconds,
        pauseBeforeEnabled: timing.pauseBeforeEnabled,
        pauseAfterEnabled: timing.pauseAfterEnabled,
        handEntranceAnimation: timing.handEntranceAnimation,
        handEntranceDurationSeconds: timing.handEntranceDurationSeconds,
        handExitAnimation: timing.handExitAnimation,
        handExitDurationSeconds: timing.handExitDurationSeconds,
        keepHandVisibleAfterDrawing: timing.keepHandVisibleAfterDrawing,
        allowTransition:
            cubit.timelineSectionOrder.indexOf(sectionId) <
            cubit.timelineSectionOrder.length - 1,
        strokeIndex: strokeIndex < 0 ? null : strokeIndex,
        smartSection: _smartSection,
        onPreviewStroke: strokeIndex < 0
            ? null
            : () => onPreviewStroke(strokeIndex),
        onTimingChangeStart: onTimingChangeStart,
        onTimingChangeEnd: onTimingChangeEnd,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.deleteTimelineSectionTitle),
        content: Text(context.l10n.deleteTimelineSectionDescription(_label)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.tonalIcon(
            key: const ValueKey('confirm-delete-timeline-section'),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline, size: 17),
            label: Text(context.l10n.deleteStroke),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    onTimingChangeStart();
    cubit.deleteTimelineSection(sectionId);
    onTimingChangeEnd();
  }
}

class _CompactTimelineCheckbox extends StatelessWidget {
  const _CompactTimelineCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.tristate = false,
  });

  final bool? value;
  final ValueChanged<bool?> onChanged;
  final bool tristate;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: Checkbox(
      value: value,
      tristate: tristate,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      side: BorderSide(color: context.studioColors.textMuted, width: 1.4),
      onChanged: onChanged,
    ),
  );
}

enum _TimelineClipAction { view, delete }

double _representativeTimelineTime(Iterable<DrawingTimelineRange?> ranges) {
  final available = ranges.whereType<DrawingTimelineRange>().toList();
  if (available.isEmpty) return 0;
  final start = available.map((range) => range.startSeconds).reduce(math.min);
  final end = available.map((range) => range.endSeconds).reduce(math.max);
  return math.max(start, end - 1 / Duration.microsecondsPerSecond);
}

class _TimelineActionButton extends StatelessWidget {
  const _TimelineActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon, size: 15),
  );
}

String _formatTimelineTime(double seconds) {
  final safe = math.max(0, seconds);
  final minutes = safe ~/ 60;
  final remainder = safe - minutes * 60;
  final wholeSecond = (remainder - remainder.round()).abs() < 0.05;
  final formattedSeconds = remainder.toStringAsFixed(wholeSecond ? 0 : 1);
  return '$minutes:${formattedSeconds.padLeft(wholeSecond ? 2 : 4, '0')}';
}

class _SectionTimelinePreview extends StatelessWidget {
  const _SectionTimelinePreview({
    super.key,
    required this.cubit,
    required this.sectionId,
    required this.range,
    required this.metrics,
    required this.image,
    required this.normalizedBounds,
  });

  final EditorCubit cubit;
  final String sectionId;
  final DrawingTimelineRange? range;
  final ProjectTimelineSectionMetrics? metrics;
  final ui.Image? image;
  final Rect? normalizedBounds;

  @override
  Widget build(BuildContext context) {
    final timingKey = sectionId.startsWith('stroke:')
        ? sectionId
        : 'section:$sectionId';
    final timing = cubit.sectionTiming(timingKey);
    final order = cubit.timelineSectionOrder;
    final isFirst = order.isNotEmpty && order.first == sectionId;
    final resolved = metrics;
    final totalSeconds = math.max(
      0.001,
      range?.durationSeconds ?? resolved?.totalSeconds ?? 1,
    );
    final leadingSeconds = isFirst
        ? math.min(cubit.project.startDelaySeconds, totalSeconds)
        : 0.0;
    final drawStartSeconds = resolved == null
        ? 0.0
        : leadingSeconds +
              resolved.pauseBeforeSeconds +
              resolved.handEntranceSeconds;
    final drawSeconds = resolved?.animationSeconds ?? totalSeconds;
    final pauseAfterStartSeconds = drawStartSeconds + drawSeconds;
    return Stack(
      fit: StackFit.expand,
      children: [
        _SectionThumbnail(
          image: image,
          normalizedBounds: normalizedBounds,
          clipPolygons: _thumbnailMasks(cubit.project)[sectionId] ?? const [],
        ),
        _SectionTimingOverlay(
          sectionId: sectionId,
          totalSeconds: totalSeconds,
          drawStartSeconds: drawStartSeconds,
          drawSeconds: drawSeconds,
          pauseBeforeStartSeconds: leadingSeconds,
          pauseBeforeSeconds: resolved?.pauseBeforeSeconds ?? 0,
          pauseBeforeEnabled:
              timing.pauseBeforeEnabled ||
              (resolved?.pauseBeforeSeconds ?? 0) > 0,
          pauseAfterStartSeconds: pauseAfterStartSeconds,
          pauseAfterSeconds: resolved?.pauseAfterSeconds ?? 0,
          pauseAfterEnabled:
              timing.pauseAfterEnabled ||
              (resolved?.pauseAfterSeconds ?? 0) > 0,
        ),
      ],
    );
  }
}

class _SectionTimingOverlay extends StatelessWidget {
  const _SectionTimingOverlay({
    required this.sectionId,
    required this.totalSeconds,
    required this.drawStartSeconds,
    required this.drawSeconds,
    required this.pauseBeforeStartSeconds,
    required this.pauseBeforeSeconds,
    required this.pauseBeforeEnabled,
    required this.pauseAfterStartSeconds,
    required this.pauseAfterSeconds,
    required this.pauseAfterEnabled,
  });

  final String sectionId;
  final double totalSeconds;
  final double drawStartSeconds;
  final double drawSeconds;
  final double pauseBeforeStartSeconds;
  final double pauseBeforeSeconds;
  final bool pauseBeforeEnabled;
  final double pauseAfterStartSeconds;
  final double pauseAfterSeconds;
  final bool pauseAfterEnabled;

  @override
  Widget build(BuildContext context) {
    final warning = context.studioColors.warning;
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final drawLeft = _x(drawStartSeconds, width);
          final remainingWidth = math.max(0.0, width - drawLeft);
          final drawWidth = math.min(
            remainingWidth,
            math.max(math.min(3.0, remainingWidth), _x(drawSeconds, width)),
          );
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                key: ValueKey('timeline-draw-window:$sectionId'),
                left: drawLeft,
                top: 2,
                bottom: 2,
                width: drawWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: warning.withValues(alpha: .06),
                    border: Border.all(color: warning, width: 1.5),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: [
                      BoxShadow(
                        color: warning.withValues(alpha: .2),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                ),
              ),
              if (pauseBeforeEnabled)
                _pauseMarker(
                  context,
                  key: ValueKey('timeline-pause-before:$sectionId'),
                  left: _x(pauseBeforeStartSeconds, width),
                  seconds: pauseBeforeSeconds,
                  availableWidth: width,
                  semanticLabel: _text(
                    context,
                    'Pause before drawing',
                    'توقف قبل الرسم',
                  ),
                ),
              if (pauseAfterEnabled)
                _pauseMarker(
                  context,
                  key: ValueKey('timeline-pause-after:$sectionId'),
                  left: _x(pauseAfterStartSeconds, width),
                  seconds: pauseAfterSeconds,
                  availableWidth: width,
                  semanticLabel: _text(
                    context,
                    'Pause after drawing',
                    'توقف بعد الرسم',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _x(double seconds, double width) =>
      (seconds / totalSeconds * width).clamp(0.0, width);

  Widget _pauseMarker(
    BuildContext context, {
    required Key key,
    required double left,
    required double seconds,
    required double availableWidth,
    required String semanticLabel,
  }) {
    final warning = context.studioColors.warning;
    final markerWidth = math.min(
      math.max(12.0, _x(seconds, availableWidth)),
      availableWidth,
    );
    final safeLeft = left
        .clamp(0.0, math.max(0.0, availableWidth - markerWidth))
        .toDouble();
    return Positioned(
      key: key,
      left: safeLeft,
      top: 4,
      bottom: 4,
      width: markerWidth,
      child: Semantics(
        label: semanticLabel,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: warning.withValues(alpha: .88),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Icon(
            Icons.pause_rounded,
            size: 9,
            color: context.studioColors.pathMarkerText,
          ),
        ),
      ),
    );
  }
}

final _thumbnailMaskCache = Expando<Map<String, List<List<Offset>>>>();

Map<String, List<List<Offset>>> _thumbnailMasks(HandDrawProject project) =>
    _thumbnailMaskCache[project] ??= _buildThumbnailMasks(project);

Map<String, List<List<Offset>>> _buildThumbnailMasks(HandDrawProject project) {
  final groups = <String, Set<List<List<Offset>>>>{};
  final unmasked = <String>{};
  for (final stroke in project.strokes) {
    final id = stroke.sectionId;
    if (id == null) continue;
    if (stroke.clipPolygons.isEmpty) unmasked.add(id);
    groups.putIfAbsent(id, () => {}).add(stroke.clipPolygons);
  }
  return {
    for (final entry in groups.entries)
      if (!unmasked.contains(entry.key))
        entry.key: List.unmodifiable(
          entry.value.expand((polygons) => polygons),
        ),
  };
}

class _SectionThumbnail extends StatelessWidget {
  const _SectionThumbnail({
    required this.image,
    required this.normalizedBounds,
    this.clipPolygons = const [],
  });

  final ui.Image? image;
  final Rect? normalizedBounds;
  final List<List<Offset>> clipPolygons;

  @override
  Widget build(BuildContext context) {
    final source = image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.studioColors.appBackground,
          border: Border.all(color: context.studioColors.border),
        ),
        child: source == null
            ? Center(
                child: Icon(
                  Icons.image_outlined,
                  size: 15,
                  color: context.studioColors.textMuted,
                ),
              )
            : CustomPaint(
                painter: _SectionThumbnailPainter(
                  image: source,
                  normalizedBounds: normalizedBounds,
                  clipPolygons: clipPolygons,
                ),
                child: const SizedBox.expand(),
              ),
      ),
    );
  }
}

class _SectionThumbnailPainter extends CustomPainter {
  const _SectionThumbnailPainter({
    required this.image,
    required this.normalizedBounds,
    this.clipPolygons = const [],
  });

  final ui.Image image;
  final Rect? normalizedBounds;
  final List<List<Offset>> clipPolygons;

  @override
  void paint(Canvas canvas, Size size) {
    final normalized = _safeThumbnailBounds(normalizedBounds);
    final source = Rect.fromLTRB(
      normalized.left * image.width,
      normalized.top * image.height,
      normalized.right * image.width,
      normalized.bottom * image.height,
    );
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.save();
    if (clipPolygons.isNotEmpty) {
      final mask = Path()..fillType = PathFillType.evenOdd;
      for (final polygon in clipPolygons) {
        if (polygon.length < 3) continue;
        mask.addPolygon([
          for (final p in polygon)
            Offset(
              destination.left +
                  (p.dx - normalized.left) /
                      normalized.width *
                      destination.width,
              destination.top +
                  (p.dy - normalized.top) /
                      normalized.height *
                      destination.height,
            ),
        ], true);
      }
      canvas.clipPath(mask);
    }
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  Rect _safeThumbnailBounds(Rect? value) {
    var bounds = value ?? const Rect.fromLTWH(0, 0, 1, 1);
    if (bounds.width < 0.02 || bounds.height < 0.02) {
      bounds = Rect.fromCenter(
        center: bounds.center,
        width: math.max(0.02, bounds.width),
        height: math.max(0.02, bounds.height),
      );
    }
    final padding = math.max(bounds.width, bounds.height) * 0.12;
    return Rect.fromLTRB(
      (bounds.left - padding).clamp(0.0, 1.0),
      (bounds.top - padding).clamp(0.0, 1.0),
      (bounds.right + padding).clamp(0.0, 1.0),
      (bounds.bottom + padding).clamp(0.0, 1.0),
    );
  }

  @override
  bool shouldRepaint(covariant _SectionThumbnailPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.normalizedBounds != normalizedBounds ||
      !listEquals(oldDelegate.clipPolygons, clipPolygons);
}

class _ClipDragSource extends StatelessWidget {
  const _ClipDragSource({super.key, required this.data, required this.child});

  final _TimelineDragData data;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final itemCount = data.topLevelNodeKeys.length;
    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: Draggable<_TimelineDragData>(
        data: data,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        rootOverlay: true,
        maxSimultaneousDrags: 1,
        onDragUpdate: _TimelineDragScope.maybeOf(context)?.onDragUpdate,
        feedback: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              elevation: 10,
              borderRadius: BorderRadius.circular(7),
              child: SizedBox(
                width: 142,
                height: 104,
                child: IgnorePointer(
                  child: Opacity(opacity: 0.92, child: child),
                ),
              ),
            ),
            if (itemCount > 1)
              Positioned(
                right: -7,
                top: -7,
                child: CircleAvatar(
                  key: const ValueKey('timeline-multi-drag-count'),
                  radius: 12,
                  backgroundColor: context.studioColors.warning,
                  foregroundColor: context.studioColors.pathMarkerText,
                  child: Text(
                    '$itemCount',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
        childWhenDragging: Opacity(opacity: 0.28, child: child),
        child: child,
      ),
    );
  }
}

class _TimelineDragScope extends InheritedWidget {
  const _TimelineDragScope({required this.onDragUpdate, required super.child});

  final ValueChanged<DragUpdateDetails> onDragUpdate;

  static _TimelineDragScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_TimelineDragScope>();

  @override
  bool updateShouldNotify(covariant _TimelineDragScope oldWidget) => false;
}

BoxDecoration _clipDecoration(
  BuildContext context, {
  required bool selected,
  bool scene = false,
}) => BoxDecoration(
  color: selected
      ? context.studioColors.selectedSurfaceStrong
      : scene
      ? context.studioColors.surfaceElevated
      : context.studioColors.selectedSurface.withValues(alpha: 0.62),
  borderRadius: BorderRadius.circular(7),
  border: Border.all(
    color: selected
        ? context.studioColors.warning
        : scene
        ? context.studioColors.accent
        : context.studioColors.border,
    width: selected ? 1.8 : 1,
  ),
);
