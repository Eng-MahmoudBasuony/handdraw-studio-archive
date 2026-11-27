import 'package:handdraw_studio/features/drawing_engine/domain/image_animation_render_policy.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/canvas_geometry.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/infrastructure/legacy_resolved_drawing_frame_adapter.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/branded_path_marker_painter.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/hand_image_painter.dart';
import 'package:handdraw_studio/features/drawing_engine/presentation/painters/reveal_compositor.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/domain/path_node_editor.dart';
import 'package:handdraw_studio/features/editor/domain/manual_reveal_policy.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_path_geometry.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/vector_reveal_mask.dart';
import 'package:handdraw_studio/l10n/l10n.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/models/resolved_camera_state.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_visual_compositor.dart';
import 'package:handdraw_studio/features/camera/domain/policies/hand_display_policy.dart';
import 'package:handdraw_studio/features/camera/presentation/hand_display_transform.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_canvas_overlay.dart';
import 'package:handdraw_studio/features/canvas_background/presentation/canvas_background_renderer.dart';

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({
    super.key,
    required this.cubit,
    required this.previewProgress,
    required this.isPreviewing,
    this.interactionLocked,
    required this.onSmartSectionSelected,
    this.previewStrokeIndex,
    this.renderSnapshot,
    this.resolvedFrame,
    this.resolvedFrameListenable,
    this.cameraEditing,
  });

  final EditorCubit cubit;
  final double previewProgress;
  final bool isPreviewing;

  /// Separates a visible preview frame from actively advancing playback.
  /// Paused preview frames remain directly editable.
  final bool? interactionLocked;
  final VoidCallback onSmartSectionSelected;
  final int? previewStrokeIndex;
  final EditorRenderSnapshot? renderSnapshot;
  final ResolvedProjectFrame? resolvedFrame;
  final ValueListenable<ResolvedProjectFrame?>? resolvedFrameListenable;
  final CameraEditingCubit? cameraEditing;

  @override
  Widget build(BuildContext context) {
    final editing = cameraEditing;
    if (editing == null) return _buildCanvas(context, Offset.zero);
    return BlocBuilder<CameraEditingCubit, CameraEditingState>(
      bloc: editing,
      builder: (context, state) =>
          _buildCanvas(context, state.canvasViewportOffset),
    );
  }

  Widget _buildCanvas(BuildContext context, Offset viewportOffset) {
    final renderProject = renderSnapshot?.project ?? cubit.project;
    final renderState = renderSnapshot?.state ?? cubit.state;
    return AspectRatio(
      aspectRatio: renderProject.canvasWidth / renderProject.canvasHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final interactionsDisabled = interactionLocked ?? isPreviewing;
          final cameraOutputPreview =
              cameraEditing?.state.cameraOutputEnabled(
                timelineFrameVisible: isPreviewing,
              ) ??
              false;
          final cameraViewEditing =
              cameraEditing?.state.canvasMode == CameraCanvasMode.editCamera;
          final effectiveViewportOffset =
              interactionsDisabled || cameraViewEditing
              ? Offset.zero
              : viewportOffset;
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final transientDestination = renderState.transientArtworkDestination;
          final baseArtworkRect = artworkRectFor(
            renderState.drawingImage,
            size,
            projectCanvasSize: Size(
              renderProject.canvasWidth.toDouble(),
              renderProject.canvasHeight.toDouble(),
            ),
            projectDestination: transientDestination == null
                ? renderProject.artworkDestination
                : Rect.fromLTRB(
                    transientDestination.left,
                    transientDestination.top,
                    transientDestination.right,
                    transientDestination.bottom,
                  ),
          );
          final editorArtworkRect = isPreviewing
              ? baseArtworkRect
              : editorArtworkRectForVisibleContent(
                  baseArtworkRect: baseArtworkRect,
                  canvasSize: size,
                  placement: renderState.document.artworkPlacement,
                );
          final editorContentFitted = editorArtworkRect != baseArtworkRect;
          final artworkRect = editorArtworkRect.shift(effectiveViewportOffset);
          final drawingCanvas = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: interactionsDisabled
                ? null
                : (details) {
                    if (cubit.tool == EditorTool.select) {
                      cubit.beginPathNodeEdit(
                        details.localPosition,
                        artworkRect,
                        additiveSelection:
                            HardwareKeyboard.instance.isShiftPressed,
                      );
                    } else {
                      cubit.beginStroke(details.localPosition, artworkRect);
                    }
                  },
            onPanUpdate: interactionsDisabled
                ? null
                : (details) {
                    if (cubit.tool == EditorTool.select) {
                      cubit.updatePathNodeEdit(
                        details.localPosition,
                        artworkRect,
                      );
                    } else {
                      cubit.updateStroke(details.localPosition, artworkRect);
                    }
                  },
            onPanEnd: interactionsDisabled
                ? null
                : (_) {
                    if (cubit.tool == EditorTool.select) {
                      cubit.endPathNodeEdit();
                    } else {
                      cubit.endStroke();
                    }
                  },
            onPanCancel: interactionsDisabled
                ? null
                : () {
                    if (cubit.tool == EditorTool.select) {
                      cubit.cancelPathNodeEdit();
                    } else {
                      cubit.cancelActiveStroke();
                    }
                  },
            onTapUp: interactionsDisabled
                ? null
                : (details) {
                    if (!artworkRect.contains(details.localPosition)) return;
                    if (cubit.hasSmartSections) {
                      final selected = cubit.selectSmartSectionAt(
                        Offset(
                          (details.localPosition.dx - artworkRect.left) /
                              artworkRect.width,
                          (details.localPosition.dy - artworkRect.top) /
                              artworkRect.height,
                        ),
                      );
                      if (selected) onSmartSectionSelected();
                    } else if (cubit.tool == EditorTool.select) {
                      cubit.selectStrokeAt(details.localPosition, artworkRect);
                    }
                  },
            child: MouseRegion(
              cursor: cubit.tool != EditorTool.select
                  ? SystemMouseCursors.precise
                  : SystemMouseCursors.basic,
              onHover: interactionsDisabled || cubit.tool != EditorTool.select
                  ? null
                  : (event) =>
                        cubit.hoverStrokeAt(event.localPosition, artworkRect),
              onExit: (_) => cubit.hoverStrokeAt(null, artworkRect),
              child: Builder(
                builder: (context) {
                  final painter = EditorCanvasPainter(
                    state: renderState,
                    project: renderProject,
                    previewProgress: previewProgress,
                    isPreviewing: isPreviewing,
                    cameraOutputPreview: cameraOutputPreview,
                    previewStrokeIndex: previewStrokeIndex,
                    resolvedFrame: resolvedFrame,
                    resolvedFrameListenable: resolvedFrameListenable,
                    interfaceTextDirection: Directionality.of(context),
                    emptyStateLabel: context.l10n.importDrawingToStart,
                    handModeLabel: context.l10n.hand,
                    revealModeLabel: context.l10n.reveal,
                    ignoreModeLabel: context.l10n.ignore,
                    pathsLabel: context.l10n.strokes,
                    colors: context.studioColors,
                    viewportOffset: effectiveViewportOffset,
                    revealPrewarmOwner: cubit,
                  );
                  unawaited(painter.prewarmReveal(size));
                  return CustomPaint(painter: painter, size: size);
                },
              ),
            ),
          );
          final editing = cameraEditing;
          final rawEditorScene = Stack(
            fit: StackFit.expand,
            children: [
              drawingCanvas,
              if (!interactionsDisabled &&
                  cubit.tool == EditorTool.select &&
                  cubit.artworkPlacement != null &&
                  !editorContentFitted &&
                  renderState.selectedStrokeIndex == null)
                _ArtworkTransformOverlay(
                  cubit: cubit,
                  artworkRect: artworkRect,
                  canvasSize: size,
                  projectSize: Size(
                    renderProject.canvasWidth.toDouble(),
                    renderProject.canvasHeight.toDouble(),
                  ),
                ),
            ],
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              rawEditorScene,
              if (editing != null)
                CameraCanvasOverlay(
                  editor: cubit,
                  editing: editing,
                  readOnly: interactionsDisabled,
                ),
            ],
          );
        },
      ),
    );
  }
}

Rect artworkRectFor(
  ui.Image? image,
  Size canvasSize, {
  Size? projectCanvasSize,
  Rect? projectDestination,
}) {
  if (projectDestination != null && projectCanvasSize != null) {
    return Rect.fromLTRB(
      projectDestination.left / projectCanvasSize.width * canvasSize.width,
      projectDestination.top / projectCanvasSize.height * canvasSize.height,
      projectDestination.right / projectCanvasSize.width * canvasSize.width,
      projectDestination.bottom / projectCanvasSize.height * canvasSize.height,
    );
  }
  return CanvasGeometry.contain(
    viewportSize: canvasSize,
    contentSize: image == null
        ? null
        : Size(image.width.toDouble(), image.height.toDouble()),
  );
}

/// Fits the editor viewport to the imported artwork's real visible pixels.
///
/// The returned rectangle still maps the complete encoded artwork, so drawing,
/// stroke, and camera coordinates keep one document-space contract. Only the
/// editor presentation is magnified; the document and exported output are not
/// changed.
Rect editorArtworkRectForVisibleContent({
  required Rect baseArtworkRect,
  required Size canvasSize,
  required ProjectArtworkPlacement? placement,
  double padding = 24,
  double maximumScale = 8,
}) {
  final encodedWidth = placement == null
      ? 0.0
      : placement.encodedBounds.right - placement.encodedBounds.left;
  final encodedHeight = placement == null
      ? 0.0
      : placement.encodedBounds.bottom - placement.encodedBounds.top;
  final visibleWidth = placement == null
      ? 0.0
      : placement.visibleBounds.right - placement.visibleBounds.left;
  final visibleHeight = placement == null
      ? 0.0
      : placement.visibleBounds.bottom - placement.visibleBounds.top;
  if (placement == null ||
      baseArtworkRect.isEmpty ||
      canvasSize.isEmpty ||
      encodedWidth <= 0 ||
      encodedHeight <= 0 ||
      visibleWidth <= 0 ||
      visibleHeight <= 0) {
    return baseArtworkRect;
  }
  final encoded = placement.encodedBounds;
  final visible = placement.visibleBounds;
  final visibleRect = Rect.fromLTRB(
    baseArtworkRect.left +
        (visible.left - encoded.left) / encodedWidth * baseArtworkRect.width,
    baseArtworkRect.top +
        (visible.top - encoded.top) / encodedHeight * baseArtworkRect.height,
    baseArtworkRect.left +
        (visible.right - encoded.left) / encodedWidth * baseArtworkRect.width,
    baseArtworkRect.top +
        (visible.bottom - encoded.top) / encodedHeight * baseArtworkRect.height,
  );
  if (visibleRect.isEmpty) return baseArtworkRect;
  final availableWidth = math.max(1.0, canvasSize.width - padding * 2);
  final availableHeight = math.max(1.0, canvasSize.height - padding * 2);
  final scale = math
      .min(
        availableWidth / visibleRect.width,
        availableHeight / visibleRect.height,
      )
      .clamp(1.0, maximumScale);
  if (scale <= 1.001) return baseArtworkRect;
  final targetCenter = Offset(canvasSize.width / 2, canvasSize.height / 2);
  final topLeft =
      targetCenter + (baseArtworkRect.topLeft - visibleRect.center) * scale;
  return topLeft &
      Size(baseArtworkRect.width * scale, baseArtworkRect.height * scale);
}

class _ArtworkTransformOverlay extends StatefulWidget {
  const _ArtworkTransformOverlay({
    required this.cubit,
    required this.artworkRect,
    required this.canvasSize,
    required this.projectSize,
  });

  final EditorCubit cubit;
  final Rect artworkRect;
  final Size canvasSize;
  final Size projectSize;

  @override
  State<_ArtworkTransformOverlay> createState() =>
      _ArtworkTransformOverlayState();
}

class _ArtworkTransformOverlayState extends State<_ArtworkTransformOverlay> {
  DocumentRect? _start;

  @override
  Widget build(BuildContext context) => Positioned.fromRect(
    rect: widget.artworkRect,
    child: Semantics(
      label: 'Selected artwork. Drag to move; drag a corner to resize.',
      container: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => _start = widget.cubit.artworkPlacement!.destination,
        onPanUpdate: (details) => _move(details.delta),
        onPanEnd: (_) => widget.cubit.commitArtworkDestination(),
        onPanCancel: widget.cubit.cancelArtworkDestinationPreview,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: context.studioColors.accent, width: 1.5),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final corner in _ArtworkCorner.values)
                _cornerHandle(context, corner),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _cornerHandle(BuildContext context, _ArtworkCorner corner) {
    const size = 12.0;
    return Positioned(
      left: corner.isLeft ? -size / 2 : null,
      right: corner.isLeft ? null : -size / 2,
      top: corner.isTop ? -size / 2 : null,
      bottom: corner.isTop ? null : -size / 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _start = widget.cubit.artworkPlacement!.destination,
        onPanUpdate: (details) => _resize(corner, details.delta),
        onPanEnd: (_) => widget.cubit.commitArtworkDestination(),
        onPanCancel: widget.cubit.cancelArtworkDestinationPreview,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.studioColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
          child: const SizedBox(width: size, height: size),
        ),
      ),
    );
  }

  void _move(Offset canvasDelta) {
    final current = widget.cubit.state.transientArtworkDestination ?? _start;
    if (current == null) return;
    final dx =
        canvasDelta.dx / widget.canvasSize.width * widget.projectSize.width;
    final dy =
        canvasDelta.dy / widget.canvasSize.height * widget.projectSize.height;
    widget.cubit.previewArtworkDestination(
      DocumentRect(
        left: current.left + dx,
        top: current.top + dy,
        right: current.right + dx,
        bottom: current.bottom + dy,
      ),
    );
  }

  void _resize(_ArtworkCorner corner, Offset canvasDelta) {
    final current = widget.cubit.state.transientArtworkDestination ?? _start;
    if (current == null) return;
    final aspect =
        (current.right - current.left) / (current.bottom - current.top);
    final rawDx =
        canvasDelta.dx / widget.canvasSize.width * widget.projectSize.width;
    final signedWidthDelta = corner.isLeft ? -rawDx : rawDx;
    final width = math.max(
      24.0,
      current.right - current.left + signedWidthDelta,
    );
    final height = width / aspect;
    widget.cubit.previewArtworkDestination(
      DocumentRect(
        left: corner.isLeft ? current.right - width : current.left,
        top: corner.isTop ? current.bottom - height : current.top,
        right: corner.isLeft ? current.right : current.left + width,
        bottom: corner.isTop ? current.bottom : current.top + height,
      ),
    );
  }
}

enum _ArtworkCorner {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight;

  bool get isLeft => this == topLeft || this == bottomLeft;
  bool get isTop => this == topLeft || this == topRight;
}

List<int> smartPathMarkerIndices(
  List<Offset> positions, {
  double minimumDistance = 18,
}) {
  final visible = <int>[];
  for (var index = 0; index < positions.length; index++) {
    if (index == 0 ||
        visible.every(
          (shown) =>
              (positions[shown] - positions[index]).distance >= minimumDistance,
        )) {
      visible.add(index);
    }
  }
  return List.unmodifiable(visible);
}

String smartSectionCanvasLabel({
  required int number,
  required SmartPathSection section,
  required String modeLabel,
  required String pathsLabel,
}) {
  final pathCount = section.mode == SmartSectionMode.handDraw
      ? ' • ${section.paths.length} $pathsLabel'
      : '';
  return '$number  $modeLabel$pathCount';
}

final Expando<EditorRevealPrewarmCoordinator> _editorRevealPrewarmCoordinators =
    Expando<EditorRevealPrewarmCoordinator>('editor-reveal-prewarm');

@visibleForTesting
final class EditorRevealPrewarmCoordinator {
  Object? _signature;
  Future<void>? _pending;
  var _generation = 0;

  Future<void> schedule(
    Object signature,
    Future<void> Function(bool Function() isCancelled) operation,
  ) {
    final pending = _pending;
    if (_signature == signature && pending != null) return pending;

    _signature = signature;
    final generation = ++_generation;
    late final Future<void> task;
    task = operation(() => generation != _generation).whenComplete(() {
      if (identical(_pending, task)) _pending = null;
    });
    _pending = task;
    return task;
  }
}

class EditorCanvasPainter extends CustomPainter {
  static const _showHandAlignmentDiagnostics = bool.fromEnvironment(
    'HANDDRAW_HAND_ALIGNMENT_DIAGNOSTICS',
  );
  EditorCanvasPainter({
    required this.state,
    required this.project,
    required this.previewProgress,
    required this.isPreviewing,
    this.cameraOutputPreview = false,
    required this.interfaceTextDirection,
    required this.emptyStateLabel,
    required this.handModeLabel,
    required this.revealModeLabel,
    required this.ignoreModeLabel,
    required this.pathsLabel,
    required this.colors,
    this.previewStrokeIndex,
    this.resolvedFrame,
    this.resolvedFrameListenable,
    this.viewportOffset = Offset.zero,
    this.revealPrewarmOwner,
  }) : super(repaint: resolvedFrameListenable);

  final EditorState state;
  final HandDrawProject project;
  final double previewProgress;
  final bool isPreviewing;
  final bool cameraOutputPreview;
  final TextDirection interfaceTextDirection;
  final String emptyStateLabel;
  final String handModeLabel;
  final String revealModeLabel;
  final String ignoreModeLabel;
  final String pathsLabel;
  final StudioThemeColors colors;
  final int? previewStrokeIndex;
  final ResolvedProjectFrame? resolvedFrame;
  final ValueListenable<ResolvedProjectFrame?>? resolvedFrameListenable;
  final Offset viewportOffset;
  final Object? revealPrewarmOwner;

  late final BrandedPathMarkerColors _pathMarkerColors =
      BrandedPathMarkerColors.fromStudio(colors);

  Future<void> prewarmReveal(Size size) {
    if (state.drawingImage == null ||
        project.strokes.length < denseRevealPrewarmPathThreshold) {
      return Future<void>.value();
    }
    final signature = (
      project.strokes,
      state.drawingImage,
      state.svgRevealLayers,
      state.drawingRevealBaseImage,
      size,
      viewportOffset,
      project.artworkDestination,
      state.transientArtworkDestination,
      project.revealWidth,
    );
    final owner = revealPrewarmOwner ?? this;
    final coordinator = _editorRevealPrewarmCoordinators[owner] ??=
        EditorRevealPrewarmCoordinator();
    final sourceImage = state.drawingImage;
    bool ownerInvalidated() =>
        owner is EditorCubit &&
        (owner.isClosed || !identical(owner.state.drawingImage, sourceImage));
    return coordinator.schedule(
      signature,
      (generationCancelled) => _performRevealPrewarm(
        size,
        () => generationCancelled() || ownerInvalidated(),
      ),
    );
  }

  Future<void> _performRevealPrewarm(
    Size size,
    bool Function() isCancelled,
  ) async {
    // Resolve image-dependent geometry while this painter still owns a live
    // image. Project switches dispose the previous ui.Image immediately after
    // emitting the next state, so no image getter may run after the yield.
    final drawing = state.drawingImage!;
    final transientDestination = state.transientArtworkDestination;
    final artworkRect = artworkRectFor(
      drawing,
      size,
      projectCanvasSize: Size(
        project.canvasWidth.toDouble(),
        project.canvasHeight.toDouble(),
      ),
      projectDestination: transientDestination == null
          ? project.artworkDestination
          : Rect.fromLTRB(
              transientDestination.left,
              transientDestination.top,
              transientDestination.right,
              transientDestination.bottom,
            ),
    ).shift(viewportOffset);
    // Run only after the frame that built this painter has painted. Rebuilds
    // with the same signature share the task above. A resize or project switch
    // advances the owner's generation and cooperatively stops stale work.
    await SchedulerBinding.instance.endOfFrame;
    if (isCancelled()) return;
    final snapshot = buildTimelineSnapshot(
      strokes: project.strokes,
      artworkRect: artworkRect,
      progress: 0.999999,
      durationSeconds: project.durationSeconds,
      drawingDurationSeconds: project.drawingDurationSeconds,
      drawingSpeed: project.drawingSpeed,
      penTravelSpeed: project.penTravelSpeed,
      startDelaySeconds: project.startDelaySeconds,
      endHoldSeconds: project.endHoldSeconds,
      sectionTimings: project.sectionTimings,
      timingRect: Rect.fromLTWH(
        0,
        0,
        project.canvasWidth.toDouble(),
        project.canvasHeight.toDouble(),
      ),
    );
    await prewarmRevealedArtwork(
      artworkRect: artworkRect,
      snapshot: snapshot,
      defaultRevealWidth: project.revealWidth,
      projectPixelScale: size.width / project.canvasWidth,
      svgRevealLayers: state.svgRevealLayers,
      hasRevealBaseImage: state.drawingRevealBaseImage != null,
      isCancelled: isCancelled,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final canvasRect = Offset.zero & size;
    _drawCheckerboard(canvas, canvasRect);
    if (!cameraOutputPreview || state.drawingImage == null) {
      const CanvasBackgroundRenderer().paint(
        canvas: canvas,
        rect: canvasRect,
        background: project.canvasBackground,
      );
    }
    final drawing = state.drawingImage;
    if (drawing == null) {
      _drawEmptyState(canvas, size);
      return;
    }

    final transientDestination = state.transientArtworkDestination;
    final artworkRect = artworkRectFor(
      drawing,
      size,
      projectCanvasSize: Size(
        project.canvasWidth.toDouble(),
        project.canvasHeight.toDouble(),
      ),
      projectDestination: transientDestination == null
          ? project.artworkDestination
          : Rect.fromLTRB(
              transientDestination.left,
              transientDestination.top,
              transientDestination.right,
              transientDestination.bottom,
            ),
    ).shift(viewportOffset);
    final isolatedStrokeIndex = previewStrokeIndex;
    final isIsolatedStrokePreview =
        isolatedStrokeIndex != null &&
        isolatedStrokeIndex >= 0 &&
        isolatedStrokeIndex < project.strokes.length;
    final sourcePreviewStrokes = isIsolatedStrokePreview
        ? [project.strokes[isolatedStrokeIndex]]
        : project.strokes;
    final previewStrokes = state.maskComparisonBefore
        ? sourcePreviewStrokes
              .map((stroke) => stroke.copyWith(vectorMaskStrokes: const []))
              .toList(growable: false)
        : sourcePreviewStrokes;
    final activeResolvedFrame = resolvedFrameListenable?.value ?? resolvedFrame;
    final resolvedDrawing = activeResolvedFrame?.drawing;
    final snapshot = !isIsolatedStrokePreview && activeResolvedFrame != null
        ? const LegacyResolvedDrawingFrameAdapter().resolveOrStaticArtwork(
            project: project,
            frame: resolvedDrawing,
            artworkRect: artworkRect,
            timingRect: Rect.fromLTWH(
              0,
              0,
              project.canvasWidth.toDouble(),
              project.canvasHeight.toDouble(),
            ),
          )
        : buildTimelineSnapshot(
            strokes: previewStrokes,
            artworkRect: artworkRect,
            progress: previewProgress,
            durationSeconds: isIsolatedStrokePreview
                ? 1
                : project.durationSeconds,
            drawingDurationSeconds: isIsolatedStrokePreview
                ? 1
                : project.drawingDurationSeconds,
            drawingSpeed: isIsolatedStrokePreview ? 1 : project.drawingSpeed,
            penTravelSpeed: isIsolatedStrokePreview
                ? 1
                : project.penTravelSpeed,
            startDelaySeconds: isIsolatedStrokePreview
                ? 0
                : project.startDelaySeconds,
            endHoldSeconds: isIsolatedStrokePreview
                ? 0
                : project.endHoldSeconds,
            sectionTimings: isIsolatedStrokePreview
                ? const {}
                : project.sectionTimings,
            timingRect: Rect.fromLTWH(
              0,
              0,
              project.canvasWidth.toDouble(),
              project.canvasHeight.toDouble(),
            ),
          );

    if (cameraOutputPreview) {
      final camera = !isIsolatedStrokePreview && activeResolvedFrame != null
          ? activeResolvedFrame.camera
          : const ResolvedSingleCameraView(CameraView.identity());
      const CameraVisualCompositor().paint(
        canvas: canvas,
        outputSize: size,
        projectSize: size,
        camera: camera,
        paintScene: (sceneCanvas, transform) {
          sceneCanvas.save();
          transform.apply(sceneCanvas);
          const CanvasBackgroundRenderer().paint(
            canvas: sceneCanvas,
            rect: canvasRect,
            background: project.canvasBackground,
          );
          if (snapshot.drawingComplete &&
              !ImageAnimationRenderPolicy.authored(project)) {
            _drawImage(sceneCanvas, drawing, artworkRect);
          } else {
            drawRevealedArtwork(
              canvas: sceneCanvas,
              image: drawing,
              revealBaseImage: state.drawingRevealBaseImage,
              svgRevealLayers: state.svgRevealLayers,
              artworkRect: artworkRect,
              snapshot: snapshot,
              defaultRevealWidth: project.revealWidth,
              rasterFilterQuality: ImageAnimationRenderPolicy.filter(project),
              projectPixelScale: size.width / project.canvasWidth,
            );
          }
          sceneCanvas.restore();
          _drawHand(
            sceneCanvas,
            snapshot,
            size,
            position: transform.transformPoint(
              ImageAnimationRenderPolicy.penPosition(
                project,
                snapshot,
                size.height,
              ),
            ),
            cameraTransform: transform,
          );
        },
      );
    } else if (isPreviewing) {
      if (snapshot.drawingComplete &&
          !ImageAnimationRenderPolicy.authored(project)) {
        _drawImage(canvas, drawing, artworkRect);
      } else {
        drawRevealedArtwork(
          canvas: canvas,
          image: drawing,
          revealBaseImage: state.drawingRevealBaseImage,
          svgRevealLayers: state.svgRevealLayers,
          artworkRect: artworkRect,
          snapshot: snapshot,
          defaultRevealWidth: project.revealWidth,
          rasterFilterQuality: ImageAnimationRenderPolicy.filter(project),
          projectPixelScale: size.width / project.canvasWidth,
        );
      }
      _drawHand(canvas, snapshot, size);
    } else {
      _drawImage(canvas, drawing, artworkRect);
      _drawStrokeGuides(canvas, artworkRect, size);
      _drawSceneGroups(canvas, artworkRect);
      _drawSmartSections(canvas, artworkRect);
    }
  }

  void _drawImage(
    Canvas canvas,
    ui.Image image,
    Rect destination, {
    double opacity = 1,
  }) {
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.high
        ..color = Colors.white.withValues(alpha: opacity),
    );
  }

  void _drawStrokeGuides(Canvas canvas, Rect artworkRect, Size size) {
    if (ImageAnimationRenderPolicy.authored(project) &&
        !state.editingImagePaths &&
        state.activeStroke.isEmpty) {
      return;
    }
    final selectedIndex = state.selectedStrokeIndex;
    final hoveredIndex = state.hoveredStrokeIndex;
    if (selectedIndex != null &&
        selectedIndex >= 0 &&
        selectedIndex < project.strokes.length) {
      final selectedPath = buildDrawingStrokePath(
        project.strokes[selectedIndex],
        artworkRect,
      );
      final bounds = selectedPath.getBounds().inflate(12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(10)),
        Paint()
          ..color = colors.warning.withValues(alpha: 0.09)
          ..style = PaintingStyle.fill,
      );
      final geometry = buildStrokeGeometry([
        project.strokes[selectedIndex],
      ], artworkRect);
      if (geometry.isNotEmpty) {
        for (final pause in geometry.first.pausePoints) {
          final position = geometry.first
              .tangentAt(geometry.first.length * pause.progress)
              .position;
          _drawPausePoint(canvas, position, pause.durationSeconds);
        }
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(10)),
        Paint()
          ..color = colors.warning.withValues(alpha: 0.52)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      final selectedStroke = project.strokes[selectedIndex];
      if (state.maskOverlayVisible) {
        for (final mask in selectedStroke.vectorMaskStrokes) {
          canvas.drawPath(
            mask.geometry.toPath(artworkRect),
            Paint()
              ..color =
                  (mask.operation == VectorMaskOperation.erase
                          ? colors.danger
                          : colors.success)
                      .withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = mask.widthFraction * artworkRect.height
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }
      }
      final editableGeometry = selectedStroke.orderedGeometry;
      if (state.tool == EditorTool.select && editableGeometry != null) {
        _drawEditableNodes(canvas, artworkRect, editableGeometry);
      }
    }
    final selectedPaint = Paint()
      ..color = colors.warning
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (hoveredIndex != null &&
        hoveredIndex != selectedIndex &&
        hoveredIndex >= 0 &&
        hoveredIndex < project.strokes.length) {
      canvas.drawPath(
        buildDrawingStrokePath(project.strokes[hoveredIndex], artworkRect),
        Paint()
          ..color = colors.accent.withValues(alpha: 0.78)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (selectedIndex != null &&
        selectedIndex >= 0 &&
        selectedIndex < project.strokes.length) {
      final path = buildDrawingStrokePath(
        project.strokes[selectedIndex],
        artworkRect,
      );
      if (state.tool == EditorTool.drawPath) {
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.reveal.withValues(alpha: 0.2)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _revealGuideWidth(
              project.strokes[selectedIndex].revealWidth,
              artworkRect,
            )
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      canvas.drawPath(path, selectedPaint);
      final metric = path.computeMetrics().firstOrNull;
      final start = metric?.getTangentForOffset(0)?.position;
      if (start != null) _drawStrokeNumber(canvas, start, selectedIndex + 1);
    }

    if (state.activeStroke.isNotEmpty) {
      final path = buildSmoothPath(state.activeStroke, artworkRect);
      if (state.tool == EditorTool.drawPath) {
        canvas.drawPath(
          path,
          Paint()
            ..color = colors.reveal.withValues(alpha: 0.24)
            ..style = PaintingStyle.stroke
            ..strokeWidth = _revealGuideWidth(null, artworkRect)
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
      final activePaint = switch (state.tool) {
        EditorTool.drawPath =>
          Paint()
            ..color = colors.reveal
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        EditorTool.revealText =>
          Paint()
            ..color = colors.reveal
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        EditorTool.maskReveal =>
          Paint()
            ..color = colors.success
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        EditorTool.maskErase =>
          Paint()
            ..color = colors.danger
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        _ => selectedPaint,
      };
      canvas.drawPath(path, activePaint);
    }
  }

  double _revealGuideWidth(double? strokeWidth, Rect artworkRect) =>
      ((strokeWidth ??
                  const ManualRevealPolicy().resolve(
                    projectRevealWidth: project.revealWidth,
                    canvasHeight: project.canvasHeight.toDouble(),
                    authoredWidth: state.manualRevealWidth,
                  )) *
              artworkRect.height /
              project.canvasHeight)
          .clamp(2.0, artworkRect.longestSide);

  void _drawEditableNodes(
    Canvas canvas,
    Rect artworkRect,
    StrokePathGeometry geometry,
  ) {
    Offset resolve(Offset point) => Offset(
      artworkRect.left + point.dx * artworkRect.width,
      artworkRect.top + point.dy * artworkRect.height,
    );

    var segmentStart = geometry.start;
    for (final segment in geometry.segments) {
      if (segment case StrokeQuadraticSegment(:final control, :final end)) {
        final guidePaint = Paint()
          ..color = colors.warning.withValues(alpha: 0.48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawLine(resolve(segmentStart), resolve(control), guidePaint);
        canvas.drawLine(resolve(control), resolve(end), guidePaint);
      }
      if (segment case StrokeCubicSegment(
        :final control1,
        :final control2,
        :final end,
      )) {
        final guidePaint = Paint()
          ..color = colors.warning.withValues(alpha: 0.48)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
        canvas.drawLine(resolve(segmentStart), resolve(control1), guidePaint);
        canvas.drawLine(resolve(control2), resolve(end), guidePaint);
      }
      segmentStart = segment.end;
    }

    for (final node in const PathNodeEditor().nodes(geometry)) {
      final selected =
          state.selectedPathNode == node.reference ||
          state.selectedPathNodes.contains(node.reference);
      final isControl =
          node.reference.kind == PathNodeKind.quadraticControl ||
          node.reference.kind == PathNodeKind.control1 ||
          node.reference.kind == PathNodeKind.control2;
      final position = resolve(node.position);
      canvas.drawCircle(
        position,
        selected
            ? 6.5
            : isControl
            ? 4.25
            : 5.25,
        Paint()
          ..color = selected
              ? colors.reveal
              : isControl
              ? colors.surface
              : colors.warning,
      );
      canvas.drawCircle(
        position,
        selected
            ? 6.5
            : isControl
            ? 4.25
            : 5.25,
        Paint()
          ..color = selected ? colors.reveal : colors.warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1.4,
      );
    }
  }

  void _drawPausePoint(Canvas canvas, Offset position, double seconds) {
    canvas.drawCircle(
      position,
      10,
      Paint()..color = colors.reveal.withValues(alpha: 0.22),
    );
    canvas.drawCircle(position, 7, Paint()..color = colors.reveal);
    final paragraph =
        (ui.ParagraphBuilder(
            ui.ParagraphStyle(textAlign: TextAlign.center, fontSize: 9),
          )..pushStyle(
            ui.TextStyle(
              color: colors.pathMarkerText,
              fontWeight: FontWeight.w800,
            ),
          ))
          ..addText('Ⅱ');
    final built = paragraph.build()
      ..layout(const ui.ParagraphConstraints(width: 14));
    canvas.drawParagraph(built, position - Offset(7, built.height / 2));
  }

  void _drawStrokeNumber(Canvas canvas, Offset position, int number) {
    BrandedPathMarkerPainter.drawNumbered(
      canvas: canvas,
      position: position,
      number: number,
      colors: _pathMarkerColors,
    );
  }

  void _drawSmartSections(Canvas canvas, Rect artworkRect) {
    if (state.smartSections.isEmpty) return;
    final available = state.smartSections.map((section) => section.id).toSet();
    final seen = <String>{};
    final order = [
      for (final id in project.timelineSectionOrder)
        if (available.contains(id) && seen.add(id)) id,
      for (final section in state.smartSections)
        if (seen.add(section.id)) section.id,
    ];
    for (var index = 0; index < state.smartSections.length; index++) {
      final section = state.smartSections[index];
      final selected = state.selectedSmartSectionId == section.id;
      final rect = Rect.fromLTRB(
        artworkRect.left + section.bounds.left * artworkRect.width,
        artworkRect.top + section.bounds.top * artworkRect.height,
        artworkRect.left + section.bounds.right * artworkRect.width,
        artworkRect.top + section.bounds.bottom * artworkRect.height,
      );
      final sequence = order.indexOf(section.id) + 1;
      if (!selected) {
        _drawStrokeNumber(canvas, rect.topLeft, sequence);
        continue;
      }
      final color = switch (section.mode) {
        SmartSectionMode.handDraw => colors.path,
        SmartSectionMode.revealText => colors.reveal,
        SmartSectionMode.ignore => colors.ignored,
      };
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(5), const Radius.circular(5)),
          Paint()..color = colors.warning.withValues(alpha: 0.12),
        );
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect.inflate(selected ? 4 : 2),
          const Radius.circular(4),
        ),
        Paint()
          ..color = selected ? colors.warning : color.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.2 : 1.3,
      );
      final guidePaint = Paint()
        ..color = color.withValues(
          alpha: section.mode == SmartSectionMode.ignore ? 0.35 : 0.8,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.0 : 1.15
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      if (section.mode == SmartSectionMode.revealText) {
        canvas.drawPath(
          buildSmoothPath(section.revealPoints, artworkRect),
          guidePaint,
        );
        _drawSmartPathStart(
          canvas,
          _normalizedToCanvas(section.revealPoints.first, artworkRect),
          1,
          selected,
        );
      } else if (section.mode == SmartSectionMode.handDraw) {
        final starts = <({int pathIndex, Offset position})>[
          for (var pathIndex = 0; pathIndex < section.paths.length; pathIndex++)
            if (section.paths[pathIndex].points.isNotEmpty)
              (
                pathIndex: pathIndex,
                position: _normalizedToCanvas(
                  section.paths[pathIndex].points.first,
                  artworkRect,
                ),
              ),
        ];
        final visibleStarts = {
          for (final index in smartPathMarkerIndices([
            for (final start in starts) start.position,
          ]))
            starts[index].pathIndex,
        };
        for (var pathIndex = 0; pathIndex < section.paths.length; pathIndex++) {
          final path = section.paths[pathIndex];
          canvas.drawPath(
            buildSmoothPath(path.points, artworkRect),
            guidePaint,
          );
          if (path.points.isNotEmpty) {
            final position = _normalizedToCanvas(
              path.points.first,
              artworkRect,
            );
            if (visibleStarts.contains(pathIndex)) {
              _drawSmartPathStart(canvas, position, pathIndex + 1, selected);
            }
          }
        }
      }
      _drawSmartSectionLabel(
        canvas,
        rect.topLeft - const Offset(0, 21),
        sequence,
        section,
        selected,
      );
    }
  }

  void _drawSceneGroups(Canvas canvas, Rect artworkRect) {
    if (project.sceneGroups.isEmpty || state.smartSections.isEmpty) {
      return;
    }
    final sectionsById = {
      for (final section in state.smartSections) section.id: section,
    };
    final groupColors = [colors.accent, colors.reveal, colors.warning];
    for (var index = 0; index < project.sceneGroups.length; index++) {
      final group = project.sceneGroups[index];
      if (state.selectedTimelineSceneId != group.id) continue;
      final sections = group.sectionIds
          .map((id) => sectionsById[id])
          .whereType<SmartPathSection>()
          .toList(growable: false);
      if (sections.isEmpty) continue;
      var normalized = sections.first.bounds;
      for (final section in sections.skip(1)) {
        normalized = normalized.expandToInclude(section.bounds);
      }
      final rect = Rect.fromLTRB(
        artworkRect.left + normalized.left * artworkRect.width,
        artworkRect.top + normalized.top * artworkRect.height,
        artworkRect.left + normalized.right * artworkRect.width,
        artworkRect.top + normalized.bottom * artworkRect.height,
      ).inflate(9);
      final color = groupColors[index % groupColors.length];
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()
          ..color = color.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      final painter = TextPainter(
        text: TextSpan(
          text: '${index + 1}  ${group.name}',
          style: TextStyle(
            color: colors.surface,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: interfaceTextDirection,
      )..layout();
      final labelRect = Rect.fromLTWH(
        rect.left,
        rect.top - painter.height - 6,
        painter.width + 12,
        painter.height + 5,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
        Paint()..color = color,
      );
      painter.paint(canvas, labelRect.topLeft + const Offset(6, 2));
    }
  }

  Offset _normalizedToCanvas(Offset point, Rect artworkRect) => Offset(
    artworkRect.left + point.dx * artworkRect.width,
    artworkRect.top + point.dy * artworkRect.height,
  );

  void _drawSmartPathStart(
    Canvas canvas,
    Offset position,
    int number,
    bool selected,
  ) {
    if (!selected) {
      BrandedPathMarkerPainter.drawDot(
        canvas: canvas,
        position: position,
        colors: _pathMarkerColors,
      );
      return;
    }
    BrandedPathMarkerPainter.drawNumbered(
      canvas: canvas,
      position: position,
      number: number,
      colors: _pathMarkerColors,
    );
  }

  void _drawSmartSectionLabel(
    Canvas canvas,
    Offset position,
    int number,
    SmartPathSection section,
    bool selected,
  ) {
    final modeLabel = switch (section.mode) {
      SmartSectionMode.handDraw => handModeLabel,
      SmartSectionMode.revealText => revealModeLabel,
      SmartSectionMode.ignore => ignoreModeLabel,
    };
    final painter = TextPainter(
      text: TextSpan(
        text: smartSectionCanvasLabel(
          number: number,
          section: section,
          modeLabel: modeLabel,
          pathsLabel: pathsLabel,
        ),
        style: TextStyle(
          color: colors.surface,
          fontSize: 10,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
      textDirection: interfaceTextDirection,
    )..layout();
    final background = Rect.fromLTWH(
      position.dx,
      position.dy,
      painter.width + 12,
      painter.height + 5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(background, const Radius.circular(4)),
      Paint()
        ..color = selected
            ? colors.warning
            : colors.surfaceElevated.withValues(alpha: 0.92),
    );
    painter.paint(canvas, position + const Offset(6, 2));
  }

  void _drawHand(
    Canvas canvas,
    TimelineSnapshot snapshot,
    Size canvasSize, {
    Offset? position,
    CameraCanvasTransform? cameraTransform,
  }) {
    final hand = state.handImage;
    if (hand == null ||
        !ImageAnimationRenderPolicy.handVisible(project, snapshot)) {
      return;
    }
    final layout = const HandDisplayPolicy().resolve(
      outputWidth: canvasSize.width,
      outputHeight: canvasSize.height,
      imageWidth: hand.width.toDouble(),
      imageHeight: hand.height.toDouble(),
      preferredHeightFraction: project.handScale,
      penTipX: project.penTip.dx,
      penTipY: project.penTip.dy,
      flipX: project.handFlipX,
    );
    final width = layout.width;
    final height = layout.height;
    final handPosition =
        position ??
        ImageAnimationRenderPolicy.penPosition(
          project,
          snapshot,
          canvasSize.height,
        );
    final handTransform = HandDisplayTransform(
      layout: layout,
      projectedPathPoint: handPosition,
      rotationRadians:
          ImageAnimationRenderPolicy.handAngle(project, snapshot) +
          project.handRotationDegrees * math.pi / 180,
      flipX: project.handFlipX,
    );
    final source = Rect.fromLTWH(
      0,
      0,
      hand.width.toDouble(),
      hand.height.toDouble(),
    );
    final destination = Rect.fromLTWH(0, 0, width, height);
    canvas.save();
    handTransform.apply(canvas);
    drawFeatheredHandImage(
      canvas: canvas,
      image: hand,
      source: source,
      destination: destination,
      opacity: snapshot.handOpacity,
      armExit: handArmExitForProject(
        presetId: project.handPresetId,
        imagePath: project.handImagePath,
      ),
    );
    canvas.restore();
    if (_showHandAlignmentDiagnostics) {
      final cursor = snapshot.cursor;
      if (cursor != null && cameraTransform != null) {
        canvas.save();
        cameraTransform.apply(canvas);
        canvas.drawPath(
          cursor.activePathGeometry,
          Paint()
            ..color = const Color(0xFFFFFF00)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 / cameraTransform.scaleX,
        );
        canvas.restore();
      }
      final footprint = handTransform.projectedFootprint;
      final footprintPath = Path()..addPolygon(footprint, true);
      canvas.drawPath(
        footprintPath,
        Paint()
          ..color = const Color(0xFFFF00FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(
        handTransform.projectedPathPoint,
        5,
        Paint()..color = const Color(0xFF00FFFF),
      );
      final diagnostic = HandAlignmentDiagnostic(
        activeWorldPathPoint: snapshot.handPosition,
        projectedPathPoint: handTransform.projectedPathPoint,
        handImageBounds: footprintPath.getBounds(),
        normalizedPenTipAnchor: project.penTip,
        scaledFlippedPenTipAnchor: handTransform.scaledPenAnchor,
        finalDisplayedPenTip: handTransform.displayedPenTip,
      );
      final label = TextPainter(
        text: TextSpan(
          text:
              'section=${cursor?.sectionId} stroke=${cursor?.strokeId} '
              'path=${cursor?.pathId} progress=${cursor?.progress.toStringAsFixed(4)} '
              'world=${diagnostic.activeWorldPathPoint} '
              'projected=${diagnostic.projectedPathPoint} '
              'bounds=${diagnostic.handImageBounds} '
              'anchor=${diagnostic.normalizedPenTipAnchor} '
              'scaled=${diagnostic.scaledFlippedPenTipAnchor} '
              'tip=${diagnostic.finalDisplayedPenTip} '
              'distance=${diagnostic.distanceInOutputPixels.toStringAsFixed(3)}px',
          style: const TextStyle(
            color: Color(0xFF00FFFF),
            backgroundColor: Color(0xCC000000),
            fontSize: 11,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: canvasSize.width - 16);
      label.paint(canvas, const Offset(8, 8));
    }
  }

  void _drawCheckerboard(Canvas canvas, Rect rect) {
    canvas.drawRect(rect, Paint()..color = colors.checkerBase);
    const cell = 18.0;
    final paint = Paint()..color = colors.checkerCell;
    for (var y = 0.0; y < rect.height; y += cell) {
      for (var x = 0.0; x < rect.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
      }
    }
  }

  void _drawEmptyState(Canvas canvas, Size size) {
    final iconPainter = TextPainter(
      text: TextSpan(
        text: emptyStateLabel,
        style: TextStyle(color: colors.textSecondary, fontSize: 18),
      ),
      textDirection: interfaceTextDirection,
    )..layout(maxWidth: size.width - 40);
    iconPainter.paint(
      canvas,
      Offset(
        (size.width - iconPainter.width) / 2,
        (size.height - iconPainter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant EditorCanvasPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.previewProgress != previewProgress ||
        oldDelegate.isPreviewing != isPreviewing ||
        oldDelegate.previewStrokeIndex != previewStrokeIndex ||
        oldDelegate.interfaceTextDirection != interfaceTextDirection ||
        oldDelegate.emptyStateLabel != emptyStateLabel ||
        oldDelegate.handModeLabel != handModeLabel ||
        oldDelegate.revealModeLabel != revealModeLabel ||
        oldDelegate.ignoreModeLabel != ignoreModeLabel ||
        oldDelegate.colors != colors;
  }
}
