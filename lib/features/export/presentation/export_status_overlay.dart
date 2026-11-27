import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/export/application/export_status_cubit.dart';
import 'package:handdraw_studio/features/export/application/export_status_state.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class ExportStatusOverlay extends StatelessWidget {
  const ExportStatusOverlay({
    super.key,
    required this.compact,
    required this.topInset,
    required this.onCancel,
    required this.onReveal,
    required this.onOpen,
    required this.onCopyPath,
    required this.onRetry,
  });

  final bool compact;
  final double topInset;
  final VoidCallback onCancel;
  final ValueChanged<String> onReveal;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onCopyPath;
  final VoidCallback onRetry;

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<ExportStatusCubit, ExportStatusState>(
    builder: (context, state) {
      return PositionedDirectional(
        top: compact ? null : topInset + 12,
        bottom: compact ? 42 : null,
        start: compact ? 12 : null,
        end: 12,
        child: IgnorePointer(
          ignoring: !state.isVisible,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.08),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: state.isVisible
                ? ConstrainedBox(
                    key: const ValueKey('export-status-card'),
                    constraints: BoxConstraints(
                      minWidth: compact ? 0 : 360,
                      maxWidth: compact ? 520 : 410,
                    ),
                    child: MouseRegion(
                      onEnter: (_) =>
                          context.read<ExportStatusCubit>().pauseAutoDismiss(),
                      onExit: (_) =>
                          context.read<ExportStatusCubit>().resumeAutoDismiss(),
                      child: _ExportStatusCard(
                        state: state,
                        onCancel: onCancel,
                        onReveal: onReveal,
                        onOpen: onOpen,
                        onCopyPath: onCopyPath,
                        onRetry: onRetry,
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('export-status-idle')),
          ),
        ),
      );
    },
  );
}

class _ExportStatusCard extends StatelessWidget {
  const _ExportStatusCard({
    required this.state,
    required this.onCancel,
    required this.onReveal,
    required this.onOpen,
    required this.onCopyPath,
    required this.onRetry,
  });

  final ExportStatusState state;
  final VoidCallback onCancel;
  final ValueChanged<String> onReveal;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onCopyPath;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final accent = switch (state.phase) {
      ExportStatusPhase.success => colors.success,
      ExportStatusPhase.failure => colors.danger,
      _ => colors.accent,
    };
    return Material(
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: 0.36),
      color: colors.surfaceElevated,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: accent.withValues(alpha: 0.62)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: switch (state.phase) {
            ExportStatusPhase.rendering => _RenderingContent(
              state: state,
              onCancel: onCancel,
            ),
            ExportStatusPhase.success => _SuccessContent(
              state: state,
              onReveal: onReveal,
              onOpen: onOpen,
              onCopyPath: onCopyPath,
            ),
            ExportStatusPhase.failure => _FailureContent(
              state: state,
              onRetry: onRetry,
            ),
            ExportStatusPhase.idle => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({
    required this.icon,
    required this.title,
    this.color,
    this.dismissible = true,
  });

  final IconData icon;
  final String title;
  final Color? color;
  final bool dismissible;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 22, color: color ?? context.studioColors.accent),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      if (dismissible)
        IconButton(
          key: const ValueKey('export-dismiss'),
          tooltip: context.l10n.dismiss,
          visualDensity: VisualDensity.compact,
          onPressed: context.read<ExportStatusCubit>().dismiss,
          icon: const Icon(Icons.close, size: 18),
        ),
    ],
  );
}

class _RenderingContent extends StatelessWidget {
  const _RenderingContent({required this.state, required this.onCancel});

  final ExportStatusState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final percent = (state.progress * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusHeader(
          icon: Icons.movie_creation_outlined,
          title: context.l10n.exportingMovie,
          dismissible: false,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                state.canCancel ? state.stage : context.l10n.finishingExport,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.studioColors.textSecondary),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$percent%',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LinearProgressIndicator(
          key: const ValueKey('export-progress'),
          value: state.progress,
          minHeight: 7,
          borderRadius: BorderRadius.circular(20),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const ValueKey('export-cancel'),
            onPressed: state.canCancel ? onCancel : null,
            child: Text(context.l10n.cancelExport),
          ),
        ),
      ],
    );
  }
}

class _SuccessContent extends StatelessWidget {
  const _SuccessContent({
    required this.state,
    required this.onReveal,
    required this.onOpen,
    required this.onCopyPath,
  });

  final ExportStatusState state;
  final ValueChanged<String> onReveal;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onCopyPath;

  @override
  Widget build(BuildContext context) {
    final path = state.outputPath!;
    final name = File(path).uri.pathSegments.last;
    final size = _formatBytes(state.fileSizeBytes ?? 0);
    final duration = '${(state.durationSeconds ?? 0).toStringAsFixed(2)}s';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusHeader(
          icon: Icons.check_circle_rounded,
          title: context.l10n.exportSucceeded,
          color: context.studioColors.success,
        ),
        const SizedBox(height: 8),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(
          context.l10n.exportOutputDetails(size, duration),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: context.studioColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('export-copy-path'),
              onPressed: () => onCopyPath(path),
              icon: Icon(
                state.pathCopied ? Icons.check : Icons.copy_outlined,
                size: 17,
              ),
              label: Text(
                state.pathCopied
                    ? context.l10n.pathCopied
                    : context.l10n.copyPath,
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('export-open'),
              onPressed: () => onOpen(path),
              icon: const Icon(Icons.open_in_new, size: 17),
              label: Text(context.l10n.openMovie),
            ),
            FilledButton.icon(
              key: const ValueKey('export-reveal-finder'),
              onPressed: () => onReveal(path),
              icon: const Icon(Icons.folder_open, size: 17),
              label: Text(context.l10n.revealInFinder),
            ),
          ],
        ),
      ],
    );
  }
}

class _FailureContent extends StatelessWidget {
  const _FailureContent({required this.state, required this.onRetry});

  final ExportStatusState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _StatusHeader(
        icon: Icons.error_rounded,
        title: context.l10n.exportFailedTitle,
        color: context.studioColors.danger,
      ),
      const SizedBox(height: 8),
      Text(
        state.errorMessage ?? context.l10n.exportFailedTitle,
        maxLines: 4,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.studioColors.textSecondary),
      ),
      const SizedBox(height: 10),
      Text(
        context.l10n.exportSafeNotice,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerEnd,
        child: FilledButton.icon(
          key: const ValueKey('export-retry'),
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 17),
          label: Text(context.l10n.tryAgain),
        ),
      ),
    ],
  );
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
