import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/layout/editor_layout_spec.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/canvas_viewport_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_canvas_overlay.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/canvas_playback_overlay.dart';

class EditorWorkspace extends StatelessWidget {
  const EditorWorkspace({
    super.key,
    required this.cubit,
    required this.layout,
    required this.previewProgress,
    required this.isPreviewing,
    required this.isPlaybackActive,
    required this.interactionLocked,
    required this.onSmartSectionSelected,
    this.previewStrokeIndex,
    this.renderSnapshot,
    this.resolvedFrame,
    this.resolvedFrameListenable,
    this.cameraEditing,
    this.playheadTime = TimelineTime.zero,
    this.onPreviewCameraShot,
    this.canPreview = false,
    this.isPreviewPaused = false,
    this.previewPositionSeconds = 0,
    this.previewDurationSeconds = 0,
    this.onPlayPreview,
    this.onPausePreview,
    this.onResumePreview,
    this.onStopPreview,
    this.onSeekPreview,
    this.hasPreviewAudio = false,
    this.previewVolume = 1,
    this.onTogglePreviewMute,
    this.onPreviewVolumeChanged,
    this.isFocusMode = false,
    this.onToggleFocusMode,
  });

  final EditorCubit cubit;
  final EditorLayoutSpec layout;
  final double previewProgress;

  /// Whether a resolved frame is currently shown on the canvas.
  final bool isPreviewing;

  /// Whether the master playback clock is actively running or paused.
  /// A timeline or camera selection can show a resolved frame without being
  /// playback, so player chrome must not infer this from [isPreviewing].
  final bool isPlaybackActive;
  final bool interactionLocked;
  final VoidCallback onSmartSectionSelected;
  final int? previewStrokeIndex;
  final EditorRenderSnapshot? renderSnapshot;
  final ResolvedProjectFrame? resolvedFrame;
  final ValueListenable<ResolvedProjectFrame?>? resolvedFrameListenable;
  final CameraEditingCubit? cameraEditing;
  final TimelineTime playheadTime;
  final ValueChanged<CameraShot>? onPreviewCameraShot;
  final bool canPreview;
  final bool isPreviewPaused;
  final double previewPositionSeconds;
  final double previewDurationSeconds;
  final VoidCallback? onPlayPreview;
  final VoidCallback? onPausePreview;
  final VoidCallback? onResumePreview;
  final VoidCallback? onStopPreview;
  final ValueChanged<double>? onSeekPreview;
  final bool hasPreviewAudio;
  final double previewVolume;
  final VoidCallback? onTogglePreviewMute;
  final ValueChanged<double>? onPreviewVolumeChanged;
  final bool isFocusMode;
  final VoidCallback? onToggleFocusMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final renderProject = renderSnapshot?.project ?? cubit.project;
    final qualityDimension =
        renderProject.canvasWidth < renderProject.canvasHeight
        ? renderProject.canvasWidth
        : renderProject.canvasHeight;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.45),
          radius: 1.15,
          colors: [
            Color.lerp(colors.workspace, colors.selectedSurface, 0.26)!,
            colors.workspace,
          ],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: layout.workspacePadding,
            child: Column(
              children: [
                if (cameraEditing != null) ...[
                  BlocBuilder<CameraEditingCubit, CameraEditingState>(
                    bloc: cameraEditing,
                    buildWhen: (previous, current) =>
                        previous.canvasMode != current.canvasMode,
                    builder: (context, state) =>
                        state.canvasMode == CameraCanvasMode.editCamera
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: layout.canvasMaxWidth,
                              ),
                              child: CameraViewControlBar(
                                editor: cubit,
                                editing: cameraEditing!,
                                readOnly: interactionLocked,
                                playheadTime: playheadTime,
                                onPreviewShot: onPreviewCameraShot ?? (_) {},
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: layout.canvasMaxWidth,
                      ),
                      child: AspectRatio(
                        key: const ValueKey('project-video-aspect-ratio'),
                        aspectRatio:
                            renderProject.canvasWidth /
                            renderProject.canvasHeight,
                        child: CanvasViewportFrame(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              EditorCanvas(
                                key: ValueKey(cubit.state.canvasRevision),
                                cubit: cubit,
                                renderSnapshot: renderSnapshot,
                                resolvedFrame: resolvedFrame,
                                resolvedFrameListenable:
                                    resolvedFrameListenable,
                                cameraEditing: cameraEditing,
                                previewProgress: previewProgress,
                                isPreviewing: isPreviewing,
                                interactionLocked: interactionLocked,
                                previewStrokeIndex: previewStrokeIndex,
                                onSmartSectionSelected: onSmartSectionSelected,
                              ),
                              CanvasPlaybackOverlay(
                                canPreview: canPreview,
                                isPreviewing: isPlaybackActive,
                                isPreviewPaused: isPreviewPaused,
                                positionSeconds: previewPositionSeconds,
                                durationSeconds: previewDurationSeconds,
                                hasAudio: hasPreviewAudio,
                                volume: previewVolume,
                                qualityLabel: '${qualityDimension}p',
                                onPlay: onPlayPreview ?? () {},
                                onPause: onPausePreview ?? () {},
                                onResume: onResumePreview ?? () {},
                                onStop: onStopPreview ?? () {},
                                onSeek: onSeekPreview ?? (_) {},
                                onToggleMute: onTogglePreviewMute ?? () {},
                                onVolumeChanged:
                                    onPreviewVolumeChanged ?? (_) {},
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (onToggleFocusMode != null)
            PositionedDirectional(
              top: 6,
              end: 6,
              child: IconButton.filledTonal(
                key: const ValueKey('canvas-focus-mode-toggle'),
                tooltip: isFocusMode ? 'Exit canvas focus' : 'Focus canvas',
                onPressed: onToggleFocusMode,
                icon: Icon(
                  isFocusMode
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
