import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/branding/app_brand_logo.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

String videoQualityTier(String qualityLabel) {
  final verticalPixels = int.tryParse(
    RegExp(r'\d+').firstMatch(qualityLabel)?.group(0) ?? '',
  );
  if (verticalPixels == null) return '';
  if (verticalPixels >= 4320) return '8K UHD';
  if (verticalPixels >= 2160) return '4K UHD';
  if (verticalPixels >= 1440) return 'QHD';
  if (verticalPixels >= 1080) return 'Full HD';
  if (verticalPixels >= 720) return 'HD';
  return 'SD';
}

/// Familiar video-player controls that stay outside the rendered project.
///
/// The chrome intentionally uses HandDraw's cyan and compact timing treatment
/// instead of imitating a third-party player brand.
class CanvasPlaybackOverlay extends StatelessWidget {
  const CanvasPlaybackOverlay({
    super.key,
    required this.canPreview,
    required this.isPreviewing,
    required this.isPreviewPaused,
    required this.positionSeconds,
    required this.durationSeconds,
    required this.hasAudio,
    required this.volume,
    required this.qualityLabel,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onSeek,
    required this.onToggleMute,
    required this.onVolumeChanged,
  });

  final bool canPreview;
  final bool isPreviewing;
  final bool isPreviewPaused;
  final double positionSeconds;
  final double durationSeconds;
  final bool hasAudio;
  final double volume;
  final String qualityLabel;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final ValueChanged<double> onSeek;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChanged;

  IconData get _volumeIcon {
    if (!hasAudio || volume <= 0) return Icons.volume_off_rounded;
    if (volume < .45) return Icons.volume_mute_rounded;
    if (volume < .8) return Icons.volume_down_rounded;
    return Icons.volume_up_rounded;
  }

  String _time(double seconds) {
    final safe = seconds.isFinite ? seconds.clamp(0, 359999.0).round() : 0;
    final minutes = safe ~/ 60;
    final remaining = safe % 60;
    return '$minutes:${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final l10n = context.l10n;
    final playAction = isPreviewing
        ? (isPreviewPaused ? onResume : onPause)
        : onPlay;
    final playEnabled = isPreviewing || canPreview;
    final progress = durationSeconds <= 0
        ? 0.0
        : (positionSeconds / durationSeconds).clamp(0.0, 1.0);
    final playLabel = isPreviewing
        ? (isPreviewPaused ? l10n.resume : l10n.pause)
        : l10n.preview;
    final qualityTier = videoQualityTier(qualityLabel);

    return Stack(
      key: const ValueKey('canvas-playback-overlay'),
      fit: StackFit.expand,
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Material(
            key: const ValueKey('canvas-player-controls'),
            color: colors.appBackground.withValues(alpha: .88),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.symmetric(horizontal: 8),
              child: SizedBox(
                height: 52,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final showVolume = constraints.maxWidth >= 620;
                    final showQuality = constraints.maxWidth >= 470;
                    final showBrandMark = constraints.maxWidth >= 400;
                    final showStop = constraints.maxWidth >= 340;
                    const compactButtonConstraints = BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    );
                    return Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        IconButton(
                          key: const ValueKey('canvas-preview-toggle'),
                          tooltip: playLabel,
                          onPressed: playEnabled ? playAction : null,
                          constraints: compactButtonConstraints,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            isPreviewing && !isPreviewPaused
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                        ),
                        if (isPreviewing && showStop)
                          IconButton(
                            key: const ValueKey('canvas-preview-stop'),
                            tooltip: l10n.stopPreview,
                            onPressed: onStop,
                            constraints: compactButtonConstraints,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(Icons.stop_rounded),
                          ),
                        IconButton(
                          key: const ValueKey('canvas-preview-mute'),
                          tooltip: !hasAudio
                              ? l10n.noAudioAvailable
                              : volume <= 0
                              ? l10n.unmute
                              : l10n.mute,
                          onPressed: hasAudio ? onToggleMute : null,
                          constraints: compactButtonConstraints,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(_volumeIcon),
                        ),
                        if (showVolume)
                          SizedBox(
                            width: 92,
                            child: SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 2,
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5,
                                  disabledThumbRadius: 4,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 12,
                                ),
                                activeTrackColor: colors.textPrimary,
                                inactiveTrackColor: colors.textPrimary
                                    .withValues(alpha: .24),
                                thumbColor: colors.textPrimary,
                              ),
                              child: Slider(
                                key: const ValueKey('canvas-preview-volume'),
                                value: volume.clamp(0.0, 1.0),
                                onChanged: hasAudio ? onVolumeChanged : null,
                              ),
                            ),
                          ),
                        Text(
                          '${_time(positionSeconds)} / ${_time(durationSeconds)}',
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6,
                                disabledThumbRadius: 4,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                              activeTrackColor: colors.mediaProgress,
                              thumbColor: colors.mediaProgress,
                              inactiveTrackColor: colors.textPrimary.withValues(
                                alpha: .22,
                              ),
                              disabledActiveTrackColor: colors.mediaProgress
                                  .withValues(alpha: .7),
                            ),
                            child: Slider(
                              key: const ValueKey('canvas-preview-progress'),
                              value: progress,
                              onChanged: canPreview && durationSeconds > 0
                                  ? (value) => onSeek(value * durationSeconds)
                                  : null,
                            ),
                          ),
                        ),
                        if (showQuality) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message:
                                '${l10n.videoQuality}: $qualityLabel · $qualityTier',
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: colors.accentContainer.withValues(
                                  alpha: .96,
                                ),
                                border: Border.all(color: colors.accent),
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: colors.accent.withValues(alpha: .42),
                                    blurRadius: 9,
                                    spreadRadius: .5,
                                  ),
                                ],
                              ),
                              child: Padding(
                                key: const ValueKey('canvas-video-quality'),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      qualityLabel,
                                      textDirection: TextDirection.ltr,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: colors.textPrimary,
                                            fontWeight: FontWeight.w900,
                                            height: 1,
                                          ),
                                    ),
                                    if (qualityTier.isNotEmpty)
                                      Text(
                                        qualityTier,
                                        textDirection: TextDirection.ltr,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: colors.accentSoft,
                                              fontSize: 8,
                                              fontWeight: FontWeight.w800,
                                              height: 1.15,
                                            ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (showBrandMark)
                          const Padding(
                            padding: EdgeInsetsDirectional.only(end: 4),
                            child: AppBrandLogo(
                              key: ValueKey('canvas-player-brand-logo'),
                              size: 26,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
