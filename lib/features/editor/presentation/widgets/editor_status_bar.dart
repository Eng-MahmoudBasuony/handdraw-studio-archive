import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/localization/presentation/editor_status_localizer.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/layout/editor_layout_spec.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class EditorStatusBar extends StatelessWidget {
  const EditorStatusBar({
    super.key,
    required this.cubit,
    required this.layout,
    required this.isPreviewing,
    required this.isPreviewPaused,
    required this.previewProgress,
  });

  final EditorCubit cubit;
  final EditorLayoutSpec layout;
  final bool isPreviewing;
  final bool isPreviewPaused;
  final double previewProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final progress = (previewProgress * 100).round();
    final colors = context.studioColors;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: colors.toolbar,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(
            isPreviewing ? Icons.play_circle_fill : Icons.info_outline,
            size: 15,
            color: isPreviewing ? colors.success : colors.textMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isPreviewing
                  ? isPreviewPaused
                        ? l10n.pausedProgress(progress)
                        : l10n.previewProgress(progress)
                  : l10n.localizeEditorStatus(cubit.statusMessage),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Tooltip(
            message: cubit.isDirty
                ? l10n.unsavedChanges
                : cubit.state.document.title,
            child: Semantics(
              label: cubit.isDirty
                  ? '${cubit.state.document.title}, ${l10n.unsavedChanges}'
                  : cubit.state.document.title,
              child: Text(
                cubit.isDirty
                    ? '${cubit.state.document.title} •'
                    : cubit.state.document.title,
                key: const ValueKey('editor-project-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cubit.isDirty ? colors.warning : colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (layout.showsStatusDetails) ...[
            const SizedBox(width: 12),
            Text(
              '${cubit.project.canvasWidth}×${cubit.project.canvasHeight}  •  ${cubit.project.frameRate} ${l10n.fps}',
              style: TextStyle(fontSize: 12, color: colors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
