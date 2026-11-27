import 'dart:async';

import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/localization/presentation/localized_domain_labels.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_preview_controller.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class WritingSoundPreviewControl extends StatelessWidget {
  const WritingSoundPreviewControl({
    super.key,
    required this.controller,
    required this.preset,
    required this.volume,
    required this.enabled,
  });

  final WritingSoundPreviewController controller;
  final WritingSoundPreset preset;
  final double volume;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final l10n = context.l10n;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final isLoading =
            controller.status == WritingSoundPreviewStatus.loading;
        final isPlaying =
            controller.status == WritingSoundPreviewStatus.playing;
        final failed = controller.status == WritingSoundPreviewStatus.failed;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 7),
          decoration: BoxDecoration(
            color: isPlaying ? colors.accentContainer : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPlaying ? colors.accent : colors.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Tooltip(
                    message: isPlaying
                        ? l10n.stopSoundPreview
                        : l10n.previewSelectedSound,
                    child: IconButton.filled(
                      key: const ValueKey('writing-sound-preview-button'),
                      onPressed: enabled && !isLoading
                          ? () => unawaited(
                              controller.toggle(preset: preset, volume: volume),
                            )
                          : null,
                      icon: isLoading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : isPlaying
                          ? const Icon(Icons.stop_rounded, size: 20)
                          : const StudioIcon(StudioIconData.preview, size: 19),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPlaying
                              ? l10n.playingSoundPreview
                              : l10n.previewSelectedSound,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          failed
                              ? l10n.soundPreviewFailed
                              : preset.localizedLabel(l10n),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: failed
                                    ? colors.danger
                                    : colors.textMuted,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(volume * 100).round()}%',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  key: const ValueKey('writing-sound-preview-progress'),
                  value: isLoading ? null : controller.progress,
                  minHeight: 3,
                  backgroundColor: colors.border.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
