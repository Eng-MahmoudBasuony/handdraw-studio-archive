import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/application/camera_editor_view_commit_service.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_content_visibility_service.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';

enum _CameraResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

Rect _cameraFrameRect(CameraView value, Size size) => Rect.fromCenter(
  center: Offset(value.centerX * size.width, value.centerY * size.height),
  width: value.viewportWidth * size.width,
  height: value.viewportWidth * size.height,
);

/// An editable camera frame drawn over the fixed, uncropped editor scene.
class CameraCanvasOverlay extends StatefulWidget {
  const CameraCanvasOverlay({
    super.key,
    required this.editor,
    required this.editing,
    required this.readOnly,
    this.onTransientUpdate,
  });

  final EditorCubit editor;
  final CameraEditingCubit editing;
  final bool readOnly;
  final VoidCallback? onTransientUpdate;

  @override
  State<CameraCanvasOverlay> createState() => _CameraCanvasOverlayState();
}

class _CameraCanvasOverlayState extends State<CameraCanvasOverlay> {
  CameraView? _gestureStartView;
  Offset _gestureStartFocal = Offset.zero;
  CameraView? _resizeStartView;
  Offset _resizeDelta = Offset.zero;
  int? _middlePanPointer;

  ({CameraShot shot, CameraKeyframe frame})? _selected(
    CameraEditingState state,
  ) {
    final id = state.primaryShotId;
    if (id == null) return null;
    final shot = widget.editor.state.document.cameraTrack?.shots
        .where((item) => item.id == id)
        .firstOrNull;
    if (shot == null || shot.keyframes.isEmpty) return null;
    final selectedFrame = state.selectedKeyframeId == null
        ? null
        : shot.keyframes
              .where((frame) => frame.id == state.selectedKeyframeId)
              .firstOrNull;
    return (shot: shot, frame: selectedFrame ?? shot.keyframes.last);
  }

  void _beginViewGesture(ScaleStartDetails details) {
    _gestureStartView = widget.editing.state.editorView;
    _gestureStartFocal = details.localFocalPoint;
  }

  void _updateViewGesture(ScaleUpdateDetails details, Size size) {
    final start = _gestureStartView;
    if (start == null || size.isEmpty) return;
    if (details.pointerCount <= 1) {
      final delta = details.localFocalPoint - _gestureStartFocal;
      widget.editing.setEditorView(
        CameraView(
          centerX: start.centerX + delta.dx / size.width,
          centerY: start.centerY + delta.dy / size.height,
          viewportWidth: start.viewportWidth,
        ),
      );
      widget.onTransientUpdate?.call();
      return;
    }
    final width = (start.viewportWidth / details.scale).clamp(.02, 20.0);
    final worldAtFocal = Offset(
      start.centerX +
          (_gestureStartFocal.dx / size.width - .5) * start.viewportWidth,
      start.centerY +
          (_gestureStartFocal.dy / size.height - .5) * start.viewportWidth,
    );
    widget.editing.setEditorView(
      CameraView(
        centerX:
            worldAtFocal.dx -
            (details.localFocalPoint.dx / size.width - .5) * width,
        centerY:
            worldAtFocal.dy -
            (details.localFocalPoint.dy / size.height - .5) * width,
        viewportWidth: width,
      ),
    );
    widget.onTransientUpdate?.call();
  }

  void _beginResize(DragStartDetails details) {
    _resizeStartView = widget.editing.state.editorView;
    _resizeDelta = Offset.zero;
  }

  void _updateResize(
    _CameraResizeHandle handle,
    DragUpdateDetails details,
    Size size,
  ) {
    final start = _resizeStartView;
    if (start == null || size.isEmpty) return;
    _resizeDelta += details.delta;
    final horizontal = switch (handle) {
      _CameraResizeHandle.topLeft ||
      _CameraResizeHandle.bottomLeft ||
      _CameraResizeHandle.left => -_resizeDelta.dx / size.width,
      _CameraResizeHandle.topRight ||
      _CameraResizeHandle.bottomRight ||
      _CameraResizeHandle.right => _resizeDelta.dx / size.width,
      _ => 0.0,
    };
    final vertical = switch (handle) {
      _CameraResizeHandle.topLeft ||
      _CameraResizeHandle.top ||
      _CameraResizeHandle.topRight => -_resizeDelta.dy / size.height,
      _CameraResizeHandle.bottomLeft ||
      _CameraResizeHandle.bottom ||
      _CameraResizeHandle.bottomRight => _resizeDelta.dy / size.height,
      _ => 0.0,
    };
    final widthDelta = horizontal.abs() >= vertical.abs()
        ? horizontal
        : vertical;
    final width = (start.viewportWidth + widthDelta).clamp(.02, 20.0);
    final widthChange = width - start.viewportWidth;
    final movesLeft = switch (handle) {
      _CameraResizeHandle.topLeft ||
      _CameraResizeHandle.bottomLeft ||
      _CameraResizeHandle.left => true,
      _ => false,
    };
    final movesRight = switch (handle) {
      _CameraResizeHandle.topRight ||
      _CameraResizeHandle.bottomRight ||
      _CameraResizeHandle.right => true,
      _ => false,
    };
    final movesTop = switch (handle) {
      _CameraResizeHandle.topLeft ||
      _CameraResizeHandle.top ||
      _CameraResizeHandle.topRight => true,
      _ => false,
    };
    final movesBottom = switch (handle) {
      _CameraResizeHandle.bottomLeft ||
      _CameraResizeHandle.bottom ||
      _CameraResizeHandle.bottomRight => true,
      _ => false,
    };
    widget.editing.setEditorView(
      CameraView(
        centerX:
            start.centerX +
            (movesRight ? widthChange / 2 : 0) -
            (movesLeft ? widthChange / 2 : 0),
        centerY:
            start.centerY +
            (movesBottom ? widthChange / 2 : 0) -
            (movesTop ? widthChange / 2 : 0),
        viewportWidth: width,
      ),
    );
    widget.onTransientUpdate?.call();
  }

  void _endResize(DragEndDetails details) {
    _resizeStartView = null;
    _resizeDelta = Offset.zero;
  }

  void _panBy(Offset delta, Size size) {
    if (size.isEmpty) return;
    final source = widget.editing.state.editorView;
    widget.editing.setEditorView(
      CameraView(
        centerX: source.centerX + delta.dx / size.width,
        centerY: source.centerY + delta.dy / size.height,
        viewportWidth: source.viewportWidth,
      ),
    );
    widget.onTransientUpdate?.call();
  }

  void _beginTrackpad(PointerPanZoomStartEvent event) {
    _gestureStartView = widget.editing.state.editorView;
    _gestureStartFocal = event.localPosition;
  }

  void _updateTrackpad(PointerPanZoomUpdateEvent event, Size size) {
    final start = _gestureStartView;
    if (start == null || size.isEmpty) return;
    _updateViewGesture(
      ScaleUpdateDetails(
        scale: event.scale,
        focalPoint: event.position + event.pan,
        localFocalPoint: event.localPosition + event.pan,
      ),
      size,
    );
  }

  void _zoomAt(PointerScrollEvent event, Size size) {
    if (size.isEmpty) return;
    final source = widget.editing.state.editorView;
    final factor = math.exp(event.scrollDelta.dy * .0015);
    final width = (source.viewportWidth * factor).clamp(.02, 20.0);
    final focal = event.localPosition;
    final worldAtFocal = Offset(
      source.centerX + (focal.dx / size.width - .5) * source.viewportWidth,
      source.centerY + (focal.dy / size.height - .5) * source.viewportWidth,
    );
    widget.editing.setEditorView(
      CameraView(
        centerX: worldAtFocal.dx - (focal.dx / size.width - .5) * width,
        centerY: worldAtFocal.dy - (focal.dy / size.height - .5) * width,
        viewportWidth: width,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CameraEditingCubit, CameraEditingState>(
        bloc: widget.editing,
        builder: (context, state) {
          if (state.canvasMode == CameraCanvasMode.previewCamera) {
            return const SizedBox.shrink(
              key: ValueKey('camera-output-preview-overlay-hidden'),
            );
          }
          final selected = _selected(state);
          final shots = widget.editor.state.document.cameraTrack?.shots;
          final composing =
              state.canvasMode == CameraCanvasMode.editCamera &&
              (selected != null || shots == null || shots.isEmpty);
          final interactive =
              composing &&
              !widget.readOnly &&
              (selected == null || !selected.shot.isLocked);
          return LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (interactive)
                    Listener(
                      key: const ValueKey('camera-editor-view-gesture-surface'),
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (event) {
                        if ((event.buttons & kMiddleMouseButton) != 0) {
                          _middlePanPointer = event.pointer;
                        }
                      },
                      onPointerMove: (event) {
                        if (_middlePanPointer == event.pointer) {
                          _panBy(event.delta, size);
                        }
                      },
                      onPointerUp: (event) {
                        if (_middlePanPointer == event.pointer) {
                          _middlePanPointer = null;
                        }
                      },
                      onPointerCancel: (event) {
                        if (_middlePanPointer == event.pointer) {
                          _middlePanPointer = null;
                        }
                      },
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) _zoomAt(event, size);
                      },
                      onPointerPanZoomStart: _beginTrackpad,
                      onPointerPanZoomUpdate: (event) =>
                          _updateTrackpad(event, size),
                      onPointerPanZoomEnd: (_) => _gestureStartView = null,
                      child: selected == null
                          ? const SizedBox.expand()
                          : GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onScaleStart: _beginViewGesture,
                              onScaleUpdate: (details) =>
                                  _updateViewGesture(details, size),
                              onScaleEnd: (_) => _gestureStartView = null,
                              child: const SizedBox.expand(),
                            ),
                    ),
                  IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('camera-editable-output-frame'),
                      painter: _CameraFrameOverlayPainter(
                        view: state.editorView,
                        ghostView: switch (selected) {
                          final value? =>
                            value.shot.keyframes
                                .where((frame) => frame.id != value.frame.id)
                                .firstOrNull
                                ?.view,
                          null => null,
                        },
                        label: selected == null
                            ? null
                            : _frameLabel(
                                context,
                                selected.shot,
                                selected.frame,
                                state.editorView,
                              ),
                        labelTextDirection: Directionality.of(context),
                        accent: context.studioColors.accent,
                        scrim: context.studioColors.appBackground,
                        textColor: context.studioColors.appBackground,
                        composing: composing,
                        compositionGrid: state.compositionGrid,
                      ),
                    ),
                  ),
                  if (interactive && selected != null)
                    for (final handle in _CameraResizeHandle.values)
                      _CameraResizeHandleWidget(
                        handle: handle,
                        frame: _cameraFrameRect(state.editorView, size),
                        onStart: _beginResize,
                        onUpdate: (details) =>
                            _updateResize(handle, details, size),
                        onEnd: _endResize,
                      ),
                ],
              );
            },
          );
        },
      );

  String _frameLabel(
    BuildContext context,
    CameraShot shot,
    CameraKeyframe frame,
    CameraView editorView,
  ) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final index = shot.keyframes.indexWhere((item) => item.id == frame.id);
    final name = switch (index) {
      0 => isArabic ? 'بداية' : 'Start',
      1 when shot.ownerSceneId != null => isArabic ? 'تركيز' : 'Focus',
      _ => isArabic ? 'نهاية' : 'End',
    };
    final outputLabel = isArabic ? 'الظاهر في الفيديو' : 'VIDEO OUTPUT';
    return '$name · ${(100 / editorView.viewportWidth).round()}% · $outputLabel';
  }
}

class _CameraResizeHandleWidget extends StatelessWidget {
  const _CameraResizeHandleWidget({
    required this.handle,
    required this.frame,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final _CameraResizeHandle handle;
  final Rect frame;
  final GestureDragStartCallback onStart;
  final GestureDragUpdateCallback onUpdate;
  final GestureDragEndCallback onEnd;

  Offset get _position => switch (handle) {
    _CameraResizeHandle.topLeft => frame.topLeft,
    _CameraResizeHandle.top => frame.topCenter,
    _CameraResizeHandle.topRight => frame.topRight,
    _CameraResizeHandle.right => frame.centerRight,
    _CameraResizeHandle.bottomRight => frame.bottomRight,
    _CameraResizeHandle.bottom => frame.bottomCenter,
    _CameraResizeHandle.bottomLeft => frame.bottomLeft,
    _CameraResizeHandle.left => frame.centerLeft,
  };

  MouseCursor get _cursor => switch (handle) {
    _CameraResizeHandle.top ||
    _CameraResizeHandle.bottom => SystemMouseCursors.resizeUpDown,
    _CameraResizeHandle.left ||
    _CameraResizeHandle.right => SystemMouseCursors.resizeLeftRight,
    _CameraResizeHandle.topLeft ||
    _CameraResizeHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
    _CameraResizeHandle.topRight ||
    _CameraResizeHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
  };

  @override
  Widget build(BuildContext context) {
    const hitSize = 24.0;
    final position = _position;
    return Positioned(
      left: position.dx - hitSize / 2,
      top: position.dy - hitSize / 2,
      width: hitSize,
      height: hitSize,
      child: MouseRegion(
        cursor: _cursor,
        child: GestureDetector(
          key: ValueKey('camera-resize-${handle.name}'),
          behavior: HitTestBehavior.opaque,
          onPanStart: onStart,
          onPanUpdate: onUpdate,
          onPanEnd: onEnd,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

final class _CameraFrameOverlayPainter extends CustomPainter {
  const _CameraFrameOverlayPainter({
    required this.view,
    required this.ghostView,
    required this.label,
    required this.labelTextDirection,
    required this.accent,
    required this.scrim,
    required this.textColor,
    required this.composing,
    required this.compositionGrid,
  });

  final CameraView view;
  final CameraView? ghostView;
  final String? label;
  final TextDirection labelTextDirection;
  final Color accent;
  final Color scrim;
  final Color textColor;
  final bool composing;
  final CameraCompositionGrid compositionGrid;

  Rect _decorationRect(Rect frame, Size size, double inset) {
    const tolerance = .01;
    return Rect.fromLTRB(
      frame.left >= -tolerance && frame.left < inset ? inset : frame.left,
      frame.top >= -tolerance && frame.top < inset ? inset : frame.top,
      frame.right <= size.width + tolerance && frame.right > size.width - inset
          ? size.width - inset
          : frame.right,
      frame.bottom <= size.height + tolerance &&
              frame.bottom > size.height - inset
          ? size.height - inset
          : frame.bottom,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!composing || size.isEmpty) return;
    final frame = _cameraFrameRect(view, size);
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(outside, Paint()..color = scrim.withValues(alpha: .48));
    if (ghostView case final ghost?) {
      _drawDashedRect(
        canvas,
        _decorationRect(_cameraFrameRect(ghost, size), size, 1),
      );
    }
    _drawCompositionGrid(canvas, frame);
    const handle = 7.0;
    final decorationFrame = _decorationRect(frame, size, handle / 2);
    canvas.drawRect(
      decorationFrame,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (final point in [
      decorationFrame.topLeft,
      decorationFrame.topCenter,
      decorationFrame.topRight,
      decorationFrame.centerRight,
      decorationFrame.bottomRight,
      decorationFrame.bottomCenter,
      decorationFrame.bottomLeft,
      decorationFrame.centerLeft,
    ]) {
      canvas.drawRect(
        Rect.fromCenter(center: point, width: handle, height: handle),
        Paint()..color = accent,
      );
    }
    final value = label;
    if (value == null) return;
    final text = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: labelTextDirection,
    )..layout(maxWidth: math.max(0, size.width - 14));
    final labelWidth = math.min(text.width + 14, size.width);
    final labelLeft = decorationFrame.left
        .clamp(0.0, math.max(0.0, size.width - labelWidth))
        .toDouble();
    final labelRect = Rect.fromLTWH(
      labelLeft,
      decorationFrame.top >= text.height + 8
          ? decorationFrame.top - text.height - 8
          : decorationFrame.top,
      text.width + 14,
      text.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(labelRect, const Radius.circular(4)),
      Paint()..color = accent,
    );
    text.paint(canvas, Offset(labelRect.left + 7, labelRect.top + 4));
  }

  void _drawCompositionGrid(Canvas canvas, Rect frame) {
    final divisions = switch (compositionGrid) {
      CameraCompositionGrid.quarters => 2,
      CameraCompositionGrid.ruleOfThirds => 3,
    };
    final paint = Paint()
      ..color = accent.withValues(alpha: .48)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var index = 1; index < divisions; index++) {
      final fraction = index / divisions;
      final x = frame.left + frame.width * fraction;
      final y = frame.top + frame.height * fraction;
      canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), paint);
      canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), paint);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = accent.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    const dash = 7.0;
    const gap = 5.0;
    void line(Offset a, Offset b) {
      final distance = (b - a).distance;
      if (distance == 0) return;
      final direction = (b - a) / distance;
      for (var cursor = 0.0; cursor < distance; cursor += dash + gap) {
        canvas.drawLine(
          a + direction * cursor,
          a + direction * math.min(cursor + dash, distance),
          paint,
        );
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant _CameraFrameOverlayPainter oldDelegate) =>
      oldDelegate.view != view ||
      oldDelegate.ghostView != ghostView ||
      oldDelegate.label != label ||
      oldDelegate.labelTextDirection != labelTextDirection ||
      oldDelegate.accent != accent ||
      oldDelegate.scrim != scrim ||
      oldDelegate.composing != composing ||
      oldDelegate.compositionGrid != compositionGrid;
}

/// Camera commands live beside the workspace, never over exported content.
class CameraViewControlBar extends StatelessWidget {
  const CameraViewControlBar({
    super.key,
    required this.editor,
    required this.editing,
    required this.readOnly,
    required this.playheadTime,
    required this.onPreviewShot,
  });

  final EditorCubit editor;
  final CameraEditingCubit editing;
  final bool readOnly;
  final TimelineTime playheadTime;
  final ValueChanged<CameraShot> onPreviewShot;

  String _text(BuildContext context, String english, String arabic) =>
      Localizations.localeOf(context).languageCode == 'ar' ? arabic : english;

  ({CameraShot shot, CameraKeyframe frame})? _selected(
    CameraEditingState state,
  ) {
    final id = state.primaryShotId;
    if (id == null) return null;
    final shot = editor.state.document.cameraTrack?.shots
        .where((item) => item.id == id)
        .firstOrNull;
    if (shot == null || shot.keyframes.isEmpty) return null;
    final selectedFrame = state.selectedKeyframeId == null
        ? null
        : shot.keyframes
              .where((frame) => frame.id == state.selectedKeyframeId)
              .firstOrNull;
    return (shot: shot, frame: selectedFrame ?? shot.keyframes.last);
  }

  void _addCurrentView() {
    final previous =
        editor.state.document.cameraTrack?.shots
            .map((shot) => shot.id)
            .toSet() ??
        const <CameraShotId>{};
    final defaults = editing.state.shotDefaults;
    if (!editor.addCameraShotAtWithView(
      playheadTime,
      editing.state.editorView,
      movement: defaults.movement,
      movementDuration: TimelineDuration.fromDuration(
        defaults.movementDuration,
      ),
      holdDuration: TimelineDuration.fromDuration(defaults.holdDuration),
    )) {
      return;
    }
    final shot = editor.state.document.cameraTrack?.shots
        .where((candidate) => !previous.contains(candidate.id))
        .firstOrNull;
    if (shot == null || shot.keyframes.isEmpty) return;
    editing.selectKeyframe(shot.id, shot.keyframes.last.id);
    editing.restoreEditorView(shot.keyframes.last.view);
  }

  bool _updateCurrentView(({CameraShot shot, CameraKeyframe frame}) selected) {
    return const CameraEditorViewCommitService().commitIfDirty(
      editor: editor,
      editing: editing,
    );
  }

  Future<void> _previewSelected(
    BuildContext context,
    ({CameraShot shot, CameraKeyframe frame}) selected,
  ) async {
    if (editing.state.isEditorViewDirty && !_updateCurrentView(selected)) {
      return;
    }
    final coverage = const CameraContentVisibilityService().evaluate(
      document: editor.state.document,
      view: editing.state.editorView,
    );
    if (coverage == CameraContentCoverage.outside ||
        coverage == CameraContentCoverage.partiallyVisible) {
      final outside = coverage == CameraContentCoverage.outside;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          key: const ValueKey('camera-content-warning-dialog'),
          title: Text(
            outside
                ? _text(
                    dialogContext,
                    'Camera is outside the content',
                    'الكاميرا خارج المحتوى',
                  )
                : _text(
                    dialogContext,
                    'Some content is outside the camera',
                    'بعض المحتوى خارج الكاميرا',
                  ),
          ),
          content: Text(
            outside
                ? _text(
                    dialogContext,
                    'This camera view does not contain the artwork. The preview and exported video will show only the project background.',
                    'إطار الكاميرا لا يحتوي على الرسم. ستعرض المعاينة والفيديو المصدّر خلفية المشروع فقط.',
                  )
                : _text(
                    dialogContext,
                    'Part of the artwork is outside the camera and will not appear in the preview or exported video.',
                    'جزء من الرسم خارج إطار الكاميرا ولن يظهر في المعاينة أو الفيديو المصدّر.',
                  ),
          ),
          actions: [
            TextButton(
              key: const ValueKey('camera-content-warning-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_text(dialogContext, 'Cancel', 'إلغاء')),
            ),
            FilledButton(
              key: const ValueKey('camera-content-warning-continue'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_text(dialogContext, 'Continue', 'متابعة')),
            ),
          ],
        ),
      );
      if (proceed != true || !context.mounted) return;
    }
    final updatedShot = editor.state.document.cameraTrack?.shots
        .where((shot) => shot.id == selected.shot.id)
        .firstOrNull;
    if (updatedShot != null) onPreviewShot(updatedShot);
  }

  void _delete(({CameraShot shot, CameraKeyframe frame}) selected) {
    if (!editor.deleteCameraShots({selected.shot.id})) return;
    editing.clear();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<CameraEditingCubit, CameraEditingState>(
        bloc: editing,
        builder: (context, state) {
          if (state.canvasMode != CameraCanvasMode.editCamera) {
            return const SizedBox.shrink(
              key: ValueKey('camera-view-controls-hidden'),
            );
          }
          final selected = _selected(state);
          final shots = editor.state.document.cameraTrack?.shots;
          final composing = selected != null || shots == null || shots.isEmpty;
          final colors = context.studioColors;
          return Material(
            key: const ValueKey('camera-view-control-dock'),
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 50,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Tooltip(
                      message: _text(
                        context,
                        'Add Camera Shot',
                        'إضافة لقطة كاميرا',
                      ),
                      child: FilledButton.icon(
                        key: const ValueKey('camera-add-current-view'),
                        onPressed:
                            readOnly ||
                                !composing ||
                                selected?.shot.ownerSceneId != null
                            ? null
                            : _addCurrentView,
                        icon: const Icon(Icons.add, size: 17),
                        label: Text(_text(context, 'Add', 'إضافة')),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: _text(
                        context,
                        'Camera composition grid',
                        'شبكة تقسيم الكاميرا',
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 9),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<CameraCompositionGrid>(
                              key: const ValueKey('camera-composition-grid'),
                              value: state.compositionGrid,
                              borderRadius: BorderRadius.circular(10),
                              icon: const Icon(Icons.arrow_drop_down, size: 18),
                              selectedItemBuilder: (context) => [
                                _gridChoice(context, '2×2'),
                                _gridChoice(context, '3×3'),
                              ],
                              items: [
                                DropdownMenuItem(
                                  value: CameraCompositionGrid.quarters,
                                  child: Text(
                                    _text(
                                      context,
                                      '2×2 · Quarters',
                                      '2×2 · أربعة أرباع',
                                    ),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: CameraCompositionGrid.ruleOfThirds,
                                  child: Text(
                                    _text(
                                      context,
                                      '3×3 · Rule of Thirds',
                                      '3×3 · قاعدة الأثلاث',
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: readOnly
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        editing.setCompositionGrid(value);
                                      }
                                    },
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      key: const ValueKey('camera-update-current-view'),
                      onPressed:
                          selected == null ||
                              selected.shot.isLocked ||
                              readOnly ||
                              !state.isEditorViewDirty
                          ? null
                          : () => _updateCurrentView(selected),
                      icon: const Icon(Icons.sync, size: 16),
                      label: Text(_text(context, 'Update', 'تحديث اللقطة')),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      key: const ValueKey('camera-delete-current-view'),
                      onPressed:
                          selected == null || selected.shot.isLocked || readOnly
                          ? null
                          : () => _delete(selected),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(_text(context, 'Delete', 'حذف اللقطة')),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.tonalIcon(
                      key: const ValueKey('camera-preview-current-view'),
                      onPressed: selected == null
                          ? null
                          : () => _previewSelected(context, selected),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(
                        _text(context, 'Preview Camera', 'معاينة اللقطة'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _gridChoice(BuildContext context, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.grid_4x4, size: 16),
      const SizedBox(width: 5),
      Text(label),
    ],
  );
}
