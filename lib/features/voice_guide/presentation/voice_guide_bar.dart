import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/voice_guide/domain/voice_guide.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class VoiceGuideBar extends StatefulWidget {
  const VoiceGuideBar({
    super.key,
    required this.guide,
    required this.project,
    required this.positionSeconds,
    required this.isPlaying,
    required this.isPaused,
    required this.isMissing,
    required this.selectedSectionKey,
    required this.onPlayPause,
    required this.onSeek,
    required this.onReplace,
    required this.onRemove,
    required this.onLocate,
    required this.onSelectSection,
    this.timelineMode = false,
    this.timelineDurationSeconds,
    this.trackStartSeconds = 0,
    this.trackEnabled = true,
    this.onToggleTrackEnabled,
  });

  final VoiceGuide guide;
  final HandDrawProject project;
  final double positionSeconds;
  final bool isPlaying;
  final bool isPaused;
  final bool isMissing;
  final String? selectedSectionKey;
  final VoidCallback onPlayPause;
  final ValueChanged<double> onSeek;
  final VoidCallback onReplace;
  final VoidCallback onRemove;
  final VoidCallback onLocate;
  final ValueChanged<String> onSelectSection;
  final bool timelineMode;
  final double? timelineDurationSeconds;
  final double trackStartSeconds;
  final bool trackEnabled;
  final VoidCallback? onToggleTrackEnabled;

  @override
  State<VoiceGuideBar> createState() => _VoiceGuideBarState();
}

class _VoiceGuideBarState extends State<VoiceGuideBar> {
  String? hoveredSectionKey;

  double _secondsAt(double dx, double width) =>
      (dx / width * widget.guide.durationSeconds).clamp(
        0.0,
        widget.guide.durationSeconds,
      );

  String? _nearestCue(double dx, double width) {
    if (width <= 0 || widget.guide.durationSeconds <= 0) return null;
    String? nearest;
    var distance = 14.0;
    for (final entry in widget.project.sectionTimings.entries) {
      final cue = entry.value.voiceCueSeconds;
      if (cue == null) continue;
      final markerX = cue / widget.guide.durationSeconds * width;
      final candidate = (markerX - dx).abs();
      if (candidate <= distance) {
        distance = candidate;
        nearest = entry.key;
      }
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = context.studioColors;
    final interfaceTextDirection = Directionality.of(context);
    final duration = widget.guide.durationSeconds;
    final position = widget.positionSeconds.clamp(0.0, duration);
    final compact = MediaQuery.sizeOf(context).width < 980;
    final sections = {
      for (final section in buildTimelineSections(widget.project.strokes))
        section.key: section,
    };
    final hoverLabel = hoveredSectionKey == null
        ? null
        : sections[hoveredSectionKey]?.label;

    if (widget.timelineMode) {
      return _buildTimelineLane(
        context,
        duration: duration,
        position: position,
        sections: sections,
      );
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        key: const ValueKey('voice-guide-bar'),
        height: 94,
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [colors.surface, colors.surfaceAlt]),
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: Row(
          // Playback stays on the left and guide actions stay on the right.
          // Localized labels continue to inherit RTL/LTR from the app.
          textDirection: TextDirection.ltr,
          children: [
            _RoundControl(
              icon: widget.isPlaying && !widget.isPaused
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              tooltip: widget.isPlaying && !widget.isPaused
                  ? l10n.pauseVoicePreview
                  : l10n.playVoiceWithAnimation,
              onPressed: widget.isMissing ? null : widget.onPlayPause,
            ),
            const SizedBox(width: 12),
            if (!compact) ...[
              SizedBox(
                width: 164,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Tooltip(
                          message: l10n.voiceGuideTooltip,
                          child: StudioIcon(
                            StudioIconData.voice,
                            color: colors.accentSoft,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            widget.guide.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.isMissing
                          ? l10n.voiceFileMissing
                          : l10n.voicePreviewOnly,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.isMissing
                            ? theme.colorScheme.error
                            : colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              // A timeline is a spatial control: zero stays on the left and
              // duration stays on the right in every interface language.
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatTime(position),
                          style: TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: colors.textPrimary,
                            fontSize: 11,
                          ),
                        ),
                        if (!compact) ...[
                          const Spacer(),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 120),
                            child: Text(
                              hoverLabel == null
                                  ? l10n.dragToScrub
                                  : '${(sections[hoveredSectionKey]?.index ?? 0) + 1}. $hoverLabel',
                              key: ValueKey(hoverLabel),
                              textDirection: interfaceTextDirection,
                              style: TextStyle(
                                fontSize: 11,
                                color: hoverLabel == null
                                    ? colors.textMuted
                                    : colors.warning,
                              ),
                            ),
                          ),
                        ] else
                          Expanded(
                            child: Text(
                              widget.guide.name,
                              textAlign: TextAlign.center,
                              textDirection: interfaceTextDirection,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          _formatTime(duration),
                          style: TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: colors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: double.infinity,
                      height: 42,
                      child: LayoutBuilder(
                        builder: (context, constraints) => MouseRegion(
                          cursor: widget.isMissing
                              ? SystemMouseCursors.forbidden
                              : SystemMouseCursors.resizeLeftRight,
                          onExit: (_) =>
                              setState(() => hoveredSectionKey = null),
                          onHover: (event) => setState(
                            () => hoveredSectionKey = _nearestCue(
                              event.localPosition.dx,
                              constraints.maxWidth,
                            ),
                          ),
                          child: Listener(
                            key: const ValueKey('voice-guide-scrubber'),
                            behavior: HitTestBehavior.opaque,
                            onPointerDown: widget.isMissing
                                ? null
                                : (event) {
                                    final cue = _nearestCue(
                                      event.localPosition.dx,
                                      constraints.maxWidth,
                                    );
                                    if (cue != null) {
                                      widget.onSelectSection(cue);
                                    }
                                    widget.onSeek(
                                      _secondsAt(
                                        event.localPosition.dx,
                                        constraints.maxWidth,
                                      ),
                                    );
                                  },
                            onPointerMove: widget.isMissing
                                ? null
                                : (event) => widget.onSeek(
                                    _secondsAt(
                                      event.localPosition.dx,
                                      constraints.maxWidth,
                                    ),
                                  ),
                            child: CustomPaint(
                              painter: _WaveformPainter(
                                waveform: widget.guide.waveform,
                                position: duration <= 0
                                    ? 0
                                    : position / duration,
                                cueFractions: {
                                  for (final entry
                                      in widget.project.sectionTimings.entries)
                                    if (entry.value.voiceCueSeconds != null &&
                                        duration > 0)
                                      entry.key:
                                          entry.value.voiceCueSeconds! /
                                          duration,
                                },
                                selectedSectionKey: widget.selectedSectionKey,
                                hoveredSectionKey: hoveredSectionKey,
                                colors: colors,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (compact)
              PopupMenuButton<String>(
                key: const ValueKey('voice-guide-actions'),
                tooltip: l10n.voiceGuideActions,
                constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
                onSelected: (value) {
                  if (value == 'locate') widget.onLocate();
                  if (value == 'replace') widget.onReplace();
                  if (value == 'remove') widget.onRemove();
                },
                itemBuilder: (context) => [
                  if (widget.isMissing)
                    _actionMenuItem(
                      value: 'locate',
                      icon: Icons.folder_open_rounded,
                      label: l10n.locateVoiceGuide,
                    )
                  else
                    _actionMenuItem(
                      value: 'replace',
                      icon: Icons.swap_horiz_rounded,
                      label: l10n.replaceVoiceGuide,
                    ),
                  _actionMenuItem(
                    key: const ValueKey('voice-guide-remove-action'),
                    value: 'remove',
                    icon: Icons.delete_outline_rounded,
                    label: l10n.removeVoiceGuide,
                    color: colors.danger,
                  ),
                  _actionMenuItem(
                    enabled: false,
                    icon: Icons.info_outline_rounded,
                    label: l10n.voicePreviewOnly,
                  ),
                ],
              )
            else if (widget.isMissing)
              FilledButton.tonalIcon(
                onPressed: widget.onLocate,
                icon: const Icon(Icons.folder_open, size: 17),
                label: Text(l10n.locate),
              )
            else
              IconButton(
                tooltip: l10n.replaceVoiceGuide,
                onPressed: widget.onReplace,
                icon: const Icon(Icons.swap_horiz_rounded),
              ),
            if (!compact)
              IconButton(
                tooltip: l10n.removeVoiceGuide,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineLane(
    BuildContext context, {
    required double duration,
    required double position,
    required Map<String, TimelineSectionDefinition> sections,
  }) {
    final l10n = context.l10n;
    final colors = context.studioColors;
    final interfaceTextDirection = Directionality.of(context);
    final start = math.max(0.0, widget.trackStartSeconds);
    final total = math.max(
      0.001,
      widget.timelineDurationSeconds ?? start + duration,
    );
    final localPosition = (position - start).clamp(0.0, duration);
    final progress = duration <= 0 ? 0.0 : localPosition / duration;

    return LayoutBuilder(
      builder: (context, constraints) {
        final left = start / total * constraints.maxWidth;
        final clipWidth = (duration / total * constraints.maxWidth)
            .clamp(0.0, math.max(0.0, constraints.maxWidth - left))
            .toDouble();
        return Semantics(
          container: true,
          label: l10n.voiceGuide,
          child: Container(
            key: const ValueKey('voice-guide-bar'),
            decoration: BoxDecoration(
              color: colors.surfaceAlt.withValues(alpha: 0.42),
              border: Border(
                top: BorderSide(color: colors.border),
                bottom: BorderSide(color: colors.border),
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  left: left,
                  top: 5,
                  bottom: 7,
                  width: clipWidth,
                  child: ClipRRect(
                    key: const ValueKey('timeline-audio-clip'),
                    borderRadius: BorderRadius.circular(7),
                    child: MouseRegion(
                      cursor: widget.isMissing
                          ? SystemMouseCursors.forbidden
                          : SystemMouseCursors.resizeLeftRight,
                      onExit: (_) => setState(() => hoveredSectionKey = null),
                      onHover: clipWidth <= 0
                          ? null
                          : (event) => setState(
                              () => hoveredSectionKey = _nearestCue(
                                event.localPosition.dx,
                                clipWidth,
                              ),
                            ),
                      child: Listener(
                        key: const ValueKey('voice-guide-scrubber'),
                        behavior: HitTestBehavior.opaque,
                        onPointerDown: widget.isMissing || clipWidth <= 0
                            ? null
                            : (event) {
                                if (_isTimelineControlHit(
                                  event.localPosition.dx,
                                  clipWidth,
                                )) {
                                  return;
                                }
                                final cue = _nearestCue(
                                  event.localPosition.dx,
                                  clipWidth,
                                );
                                if (cue != null) widget.onSelectSection(cue);
                                widget.onSeek(
                                  start +
                                      _secondsAt(
                                        event.localPosition.dx,
                                        clipWidth,
                                      ),
                                );
                              },
                        onPointerMove: widget.isMissing || clipWidth <= 0
                            ? null
                            : (event) {
                                if (_isTimelineControlHit(
                                  event.localPosition.dx,
                                  clipWidth,
                                )) {
                                  return;
                                }
                                widget.onSeek(
                                  start +
                                      _secondsAt(
                                        event.localPosition.dx,
                                        clipWidth,
                                      ),
                                );
                              },
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              key: const ValueKey('timeline-audio-waveform'),
                              painter: _WaveformPainter(
                                waveform: widget.guide.waveform,
                                position: progress,
                                cueFractions: {
                                  for (final entry
                                      in widget.project.sectionTimings.entries)
                                    if (entry.value.voiceCueSeconds != null &&
                                        duration > 0)
                                      entry.key:
                                          entry.value.voiceCueSeconds! /
                                          duration,
                                },
                                selectedSectionKey: widget.selectedSectionKey,
                                hoveredSectionKey: hoveredSectionKey,
                                colors: colors,
                              ),
                            ),
                            Positioned(
                              key: ValueKey(
                                'voice-track-position:${localPosition.toStringAsFixed(3)}',
                              ),
                              left: progress * math.max(0, clipWidth - 1),
                              top: 0,
                              bottom: 0,
                              child: const SizedBox(width: 1),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: widget.isMissing
                                      ? Theme.of(context).colorScheme.error
                                      : colors.accent.withValues(alpha: 0.66),
                                ),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Row(
                                textDirection: TextDirection.ltr,
                                children: [
                                  IconButton(
                                    key: const ValueKey(
                                      'voice-track-enabled-toggle',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    constraints: const BoxConstraints.tightFor(
                                      width: 28,
                                      height: 28,
                                    ),
                                    padding: EdgeInsets.zero,
                                    tooltip: widget.trackEnabled
                                        ? l10n.mute
                                        : l10n.unmute,
                                    onPressed: widget.isMissing
                                        ? null
                                        : widget.onToggleTrackEnabled,
                                    icon: Icon(
                                      widget.trackEnabled
                                          ? Icons.volume_up_rounded
                                          : Icons.volume_off_rounded,
                                      size: 18,
                                    ),
                                  ),
                                  if (clipWidth >= 110) ...[
                                    StudioIcon(
                                      StudioIconData.voice,
                                      color: colors.accentSoft,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  if (clipWidth >= 180)
                                    Expanded(
                                      child: Text(
                                        widget.guide.name,
                                        textDirection: interfaceTextDirection,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  if (clipWidth >= 320)
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _formatTime(localPosition),
                                          style: TextStyle(
                                            color: colors.textPrimary,
                                            fontSize: 10,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          ' / ${_formatTime(duration)}',
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                            fontSize: 10,
                                            fontFeatures: const [
                                              FontFeature.tabularFigures(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  if (clipWidth >= 110)
                                    SizedBox.square(
                                      dimension: 36,
                                      child: PopupMenuButton<String>(
                                        key: const ValueKey(
                                          'voice-guide-actions',
                                        ),
                                        tooltip: l10n.voiceGuideActions,
                                        padding: EdgeInsets.zero,
                                        iconSize: 20,
                                        constraints: const BoxConstraints(
                                          minWidth: 220,
                                          maxWidth: 280,
                                        ),
                                        onSelected: (value) {
                                          if (value == 'locate') {
                                            widget.onLocate();
                                          }
                                          if (value == 'replace') {
                                            widget.onReplace();
                                          }
                                          if (value == 'remove') {
                                            widget.onRemove();
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (widget.isMissing)
                                            _actionMenuItem(
                                              value: 'locate',
                                              icon: Icons.folder_open_rounded,
                                              label: l10n.locateVoiceGuide,
                                            )
                                          else
                                            _actionMenuItem(
                                              value: 'replace',
                                              icon: Icons.swap_horiz_rounded,
                                              label: l10n.replaceVoiceGuide,
                                            ),
                                          _actionMenuItem(
                                            key: const ValueKey(
                                              'voice-guide-remove-action',
                                            ),
                                            value: 'remove',
                                            icon: Icons.delete_outline_rounded,
                                            label: l10n.removeVoiceGuide,
                                            color: colors.danger,
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isTimelineControlHit(double x, double width) =>
      x <= 36 || (width >= 110 && x >= width - 44);

  PopupMenuItem<String> _actionMenuItem({
    Key? key,
    String? value,
    required IconData icon,
    required String label,
    Color? color,
    bool enabled = true,
  }) => PopupMenuItem<String>(
    key: key,
    value: value,
    enabled: enabled,
    height: 48,
    child: Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: color == null ? null : TextStyle(color: color),
          ),
        ),
      ],
    ),
  );
}

class _RoundControl extends StatelessWidget {
  const _RoundControl({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({
    required this.waveform,
    required this.position,
    required this.cueFractions,
    required this.selectedSectionKey,
    required this.hoveredSectionKey,
    required this.colors,
  });

  final List<double> waveform;
  final double position;
  final Map<String, double> cueFractions;
  final String? selectedSectionKey;
  final String? hoveredSectionKey;
  final StudioThemeColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final background = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(7),
    );
    canvas.drawRRect(background, Paint()..color = colors.waveformBackground);
    canvas.save();
    canvas.clipRRect(background);
    final center = size.height / 2;
    final playedWidth = position.clamp(0.0, 1.0) * size.width;
    if (playedWidth > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, playedWidth, size.height),
        Paint()..color = colors.waveformPlayed.withValues(alpha: 0.12),
      );
    }
    canvas.drawLine(
      Offset(0, center),
      Offset(size.width, center),
      Paint()
        ..color = colors.waveformIdle.withValues(alpha: 0.28)
        ..strokeWidth = 1,
    );
    final samples = waveform.isEmpty ? const [0.08] : waveform;
    final peak = samples.fold<double>(
      0,
      (current, sample) => math.max(current, sample.abs()),
    );
    final bars = math.max(1, math.min(samples.length, size.width ~/ 4));
    final barWidth = size.width / bars;
    for (var index = 0; index < bars; index++) {
      final sampleIndex = index * samples.length ~/ bars;
      final normalized = peak <= 0
          ? 0.0
          : (samples[sampleIndex].abs() / peak).clamp(0.0, 1.0);
      final amplitude = 0.16 + math.pow(normalized, 0.68).toDouble() * 0.84;
      final height = amplitude * math.max(0, size.height - 6);
      final fraction = (index + 0.5) / bars;
      final paint = Paint()
        ..color = fraction <= position
            ? colors.waveformPlayed
            : colors.waveformIdle.withValues(alpha: 0.82);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            index * barWidth + 0.6,
            center - height / 2,
            math.max(1.4, barWidth - 1.2),
            height,
          ),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
    canvas.restore();

    for (final entry in cueFractions.entries) {
      final x = entry.value.clamp(0.0, 1.0) * size.width;
      final highlighted =
          entry.key == selectedSectionKey || entry.key == hoveredSectionKey;
      final color = highlighted ? colors.warning : colors.textSecondary;
      canvas.drawLine(
        Offset(x, 1),
        Offset(x, size.height - 1),
        Paint()
          ..color = color
          ..strokeWidth = highlighted ? 2.2 : 1.2,
      );
      final marker = Path()
        ..moveTo(x - 5, 0)
        ..lineTo(x + 5, 0)
        ..lineTo(x, 6)
        ..close();
      canvas.drawPath(marker, Paint()..color = color);
    }

    final playheadX = position.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      Paint()
        ..color = colors.textPrimary
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.waveform != waveform ||
      oldDelegate.cueFractions != cueFractions ||
      oldDelegate.selectedSectionKey != selectedSectionKey ||
      oldDelegate.hoveredSectionKey != hoveredSectionKey ||
      oldDelegate.colors != colors;
}

String _formatTime(double seconds) {
  final safe = seconds.isFinite ? math.max(0.0, seconds) : 0.0;
  final minutes = safe ~/ 60;
  final remainder = safe - minutes * 60;
  return '$minutes:${remainder.toStringAsFixed(2).padLeft(5, '0')}';
}
