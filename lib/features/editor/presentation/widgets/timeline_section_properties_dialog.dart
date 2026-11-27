import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/section_drawing_speed_policy.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/domain/path_node_editor.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/section_hand_animation.dart';
import 'package:handdraw_studio/features/project/domain/models/stroke_pause_point.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class TimelineSectionPropertiesDialog extends StatefulWidget {
  const TimelineSectionPropertiesDialog({
    super.key,
    required this.cubit,
    required this.sectionId,
    required this.label,
    required this.preview,
    required this.animationSeconds,
    required this.speedMultiplier,
    required this.pauseSeconds,
    required this.transitionSeconds,
    required this.pauseBeforeSeconds,
    required this.pauseBeforeEnabled,
    required this.pauseAfterEnabled,
    required this.handEntranceAnimation,
    required this.handEntranceDurationSeconds,
    required this.handExitAnimation,
    required this.handExitDurationSeconds,
    required this.keepHandVisibleAfterDrawing,
    required this.allowTransition,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    this.strokeIndex,
    this.smartSection,
    this.onPreviewStroke,
  });

  final EditorCubit cubit;
  final String sectionId;
  final String label;
  final Widget preview;
  final double animationSeconds;
  final double speedMultiplier;
  final double pauseSeconds;
  final double transitionSeconds;
  final double pauseBeforeSeconds;
  final bool pauseBeforeEnabled;
  final bool pauseAfterEnabled;
  final SectionHandEntranceAnimation handEntranceAnimation;
  final double handEntranceDurationSeconds;
  final SectionHandExitAnimation handExitAnimation;
  final double handExitDurationSeconds;
  final bool keepHandVisibleAfterDrawing;
  final bool allowTransition;
  final int? strokeIndex;
  final SmartPathSection? smartSection;
  final VoidCallback? onPreviewStroke;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;

  @override
  State<TimelineSectionPropertiesDialog> createState() =>
      _TimelineSectionPropertiesDialogState();
}

class _TimelineSectionPropertiesDialogState
    extends State<TimelineSectionPropertiesDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);
  late double animationSeconds = widget.animationSeconds.clamp(0.05, 60);
  late double speedMultiplier = SectionDrawingSpeedPolicy.sanitizeSpeed(
    widget.speedMultiplier,
  );
  late final double _baselineAnimationSeconds;
  late double pauseBeforeSeconds = widget.pauseBeforeSeconds.clamp(0, 60);
  late double pauseSeconds = widget.pauseSeconds.clamp(0, 60);
  late double transitionSeconds = widget.transitionSeconds.clamp(0, 60);
  late bool pauseBeforeEnabled = widget.pauseBeforeEnabled;
  late bool pauseAfterEnabled = widget.pauseAfterEnabled;
  late SectionHandEntranceAnimation handEntranceAnimation =
      widget.handEntranceAnimation;
  late double handEntranceDurationSeconds = math.max(
    .1,
    widget.handEntranceDurationSeconds,
  );
  late SectionHandExitAnimation handExitAnimation = widget.handExitAnimation;
  late double handExitDurationSeconds = math.max(
    .1,
    widget.handExitDurationSeconds,
  );
  late bool keepHandVisibleAfterDrawing = widget.keepHandVisibleAfterDrawing;

  EditorCubit get cubit => widget.cubit;

  @override
  void initState() {
    super.initState();
    _baselineAnimationSeconds = SectionDrawingSpeedPolicy.baselineDuration(
      resolvedDurationSeconds: animationSeconds,
      speedMultiplier: speedMultiplier,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    bloc: cubit,
    builder: (context, state) {
      final stroke = _stroke;
      return AlertDialog(
        key: const ValueKey('timeline-section-properties-dialog'),
        titlePadding: const EdgeInsets.fromLTRB(22, 18, 12, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
        title: Row(
          children: [
            const Icon(Icons.tune_rounded, size: 21),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${context.l10n.timelineSectionProperties} · ${widget.label}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: context.l10n.cancel,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        content: SizedBox(
          width: 820,
          height: (MediaQuery.sizeOf(context).height - 180).clamp(320, 520),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 650;
              final editor = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TabBar(
                    controller: _tabs,
                    isScrollable: compact,
                    tabs: [
                      _tab(Icons.timelapse_rounded, context.l10n.timingReveal),
                      _tab(Icons.gesture_rounded, context.l10n.drawPath),
                      _tab(
                        Icons.auto_awesome_outlined,
                        context.l10n.appearanceMethod,
                      ),
                      _tab(Icons.layers_outlined, context.l10n.maskReveal),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _timingTab(context),
                        _pathTab(context, stroke),
                        _appearanceTab(context, stroke),
                        _maskTab(context, stroke),
                      ],
                    ),
                  ),
                ],
              );
              if (compact) return editor;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 210, child: widget.preview),
                  const SizedBox(width: 20),
                  Expanded(child: editor),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
          FilledButton.icon(
            key: const ValueKey('save-section-properties'),
            onPressed: _saveAndClose,
            icon: const Icon(Icons.check_rounded, size: 17),
            label: Text(context.l10n.saveAction),
          ),
        ],
      );
    },
  );

  Tab _tab(IconData icon, String label) => Tab(
    height: 48,
    icon: Icon(icon, size: 18),
    iconMargin: const EdgeInsets.only(bottom: 2),
    text: label,
  );

  Widget _timingTab(BuildContext context) {
    final entranceSeconds =
        handEntranceAnimation == SectionHandEntranceAnimation.none
        ? 0.0
        : handEntranceDurationSeconds;
    final exitSeconds =
        keepHandVisibleAfterDrawing ||
            handExitAnimation == SectionHandExitAnimation.none ||
            handExitAnimation == SectionHandExitAnimation.disappear
        ? 0.0
        : handExitDurationSeconds;
    final startPause = pauseBeforeEnabled ? pauseBeforeSeconds : 0.0;
    final endPause = pauseAfterEnabled ? pauseSeconds : 0.0;
    final total =
        startPause +
        entranceSeconds +
        animationSeconds +
        endPause +
        exitSeconds +
        transitionSeconds;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimingOverview(
            description: context.l10n.timelineSectionTimingDescription,
            totalLabel: context.l10n.totalSectionDuration(
              total.toStringAsFixed(2),
            ),
            speedLabel: '${_DrawingSpeedControl.formatSpeed(speedMultiplier)}×',
            pauseBeforeSeconds: startPause,
            handEntranceSeconds: entranceSeconds,
            animationSeconds: animationSeconds,
            pauseSeconds: endPause,
            handExitSeconds: exitSeconds,
            transitionSeconds: transitionSeconds,
          ),
          const SizedBox(height: 10),
          _TimingStageExpansion(
            key: const ValueKey('section-start-stage'),
            title: context.l10n.pauseAtSectionStart,
            icon: Icons.first_page_rounded,
            summary: [
              pauseBeforeEnabled
                  ? '${pauseBeforeSeconds.toStringAsFixed(2)} s'
                  : context.l10n.timingOff,
              handEntranceAnimation == SectionHandEntranceAnimation.none
                  ? context.l10n.noAnimation
                  : _entranceAnimationLabel(context, handEntranceAnimation),
            ].join(' · '),
            initiallyExpanded:
                pauseBeforeEnabled ||
                handEntranceAnimation != SectionHandEntranceAnimation.none,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('section-start-pause-toggle'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(context.l10n.pauseDuration),
                  subtitle: Text(
                    pauseBeforeEnabled
                        ? context.l10n.timingOn
                        : context.l10n.timingOff,
                  ),
                  value: pauseBeforeEnabled,
                  onChanged: (enabled) =>
                      setState(() => pauseBeforeEnabled = enabled),
                ),
                if (pauseBeforeEnabled)
                  _DurationStepper(
                    key: const ValueKey('section-start-pause-duration'),
                    icon: Icons.pause_circle_outline_rounded,
                    label: context.l10n.pauseDuration,
                    value: pauseBeforeSeconds,
                    minimum: 0,
                    precise: true,
                    onChanged: (value) =>
                        setState(() => pauseBeforeSeconds = value),
                  ),
                const Divider(height: 18),
                _CompactFieldLabel(
                  icon: Icons.login_rounded,
                  label: context.l10n.handEntranceAnimation,
                ),
                const SizedBox(height: 7),
                _AnimationPicker<SectionHandEntranceAnimation>(
                  key: const ValueKey('section-hand-entrance-picker'),
                  value: handEntranceAnimation,
                  choices: [
                    (
                      SectionHandEntranceAnimation.none,
                      Icons.block,
                      context.l10n.noAnimation,
                    ),
                    (
                      SectionHandEntranceAnimation.fadeIn,
                      Icons.blur_on_rounded,
                      context.l10n.fadeIn,
                    ),
                    (
                      SectionHandEntranceAnimation.moveIn,
                      Icons.login_rounded,
                      context.l10n.moveIn,
                    ),
                    (
                      SectionHandEntranceAnimation.slingshot,
                      Icons.keyboard_double_arrow_right_rounded,
                      context.l10n.slingshot,
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => handEntranceAnimation = value),
                ),
                if (handEntranceAnimation !=
                    SectionHandEntranceAnimation.none) ...[
                  const SizedBox(height: 10),
                  _DurationStepper(
                    key: const ValueKey('section-hand-entrance-duration'),
                    icon: Icons.timer_outlined,
                    label: context.l10n.handAnimationDuration,
                    value: handEntranceDurationSeconds,
                    minimum: .05,
                    onChanged: (value) =>
                        setState(() => handEntranceDurationSeconds = value),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          _DrawingSpeedControl(
            value: speedMultiplier,
            durationSeconds: animationSeconds,
            onChanged: _setDrawingSpeed,
            onDurationChanged: _setAnimationDuration,
          ),
          const SizedBox(height: 10),
          _TimingStageExpansion(
            key: const ValueKey('section-end-stage'),
            title: context.l10n.pauseAtSectionEnd,
            icon: Icons.last_page_rounded,
            summary: [
              pauseAfterEnabled
                  ? '${pauseSeconds.toStringAsFixed(2)} s'
                  : context.l10n.timingOff,
              keepHandVisibleAfterDrawing
                  ? context.l10n.keepHandVisibleAfterDrawing
                  : handExitAnimation == SectionHandExitAnimation.none
                  ? context.l10n.noAnimation
                  : _exitAnimationLabel(context, handExitAnimation),
            ].join(' · '),
            initiallyExpanded:
                pauseAfterEnabled ||
                keepHandVisibleAfterDrawing ||
                handExitAnimation != SectionHandExitAnimation.none ||
                transitionSeconds > 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('section-end-pause-toggle'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(context.l10n.pauseDuration),
                  subtitle: Text(
                    pauseAfterEnabled
                        ? context.l10n.timingOn
                        : context.l10n.timingOff,
                  ),
                  value: pauseAfterEnabled,
                  onChanged: (enabled) =>
                      setState(() => pauseAfterEnabled = enabled),
                ),
                if (pauseAfterEnabled)
                  _DurationStepper(
                    key: const ValueKey('section-pause-duration'),
                    icon: Icons.pause_circle_outline_rounded,
                    label: context.l10n.pauseDuration,
                    value: pauseSeconds,
                    minimum: 0,
                    precise: true,
                    onChanged: (value) => setState(() => pauseSeconds = value),
                  ),
                const Divider(height: 18),
                SwitchListTile.adaptive(
                  key: const ValueKey(
                    'section-keep-hand-visible-after-drawing',
                  ),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  title: Text(context.l10n.keepHandVisibleAfterDrawing),
                  subtitle: Text(
                    context.l10n.keepHandVisibleAfterDrawingDescription,
                  ),
                  value: keepHandVisibleAfterDrawing,
                  onChanged: (enabled) =>
                      setState(() => keepHandVisibleAfterDrawing = enabled),
                ),
                if (!keepHandVisibleAfterDrawing) ...[
                  const Divider(height: 18),
                  _CompactFieldLabel(
                    icon: Icons.logout_rounded,
                    label: context.l10n.handExitAnimation,
                  ),
                  const SizedBox(height: 7),
                  _AnimationPicker<SectionHandExitAnimation>(
                    key: const ValueKey('section-hand-exit-picker'),
                    value: handExitAnimation,
                    choices: [
                      (
                        SectionHandExitAnimation.none,
                        Icons.block,
                        context.l10n.noAnimation,
                      ),
                      (
                        SectionHandExitAnimation.fadeOut,
                        Icons.blur_off_rounded,
                        context.l10n.fadeOut,
                      ),
                      (
                        SectionHandExitAnimation.moveOut,
                        Icons.logout_rounded,
                        context.l10n.moveOut,
                      ),
                      (
                        SectionHandExitAnimation.slingshot,
                        Icons.keyboard_double_arrow_left_rounded,
                        context.l10n.slingshot,
                      ),
                      (
                        SectionHandExitAnimation.disappear,
                        Icons.hide_source_rounded,
                        context.l10n.disappear,
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => handExitAnimation = value),
                  ),
                  if (handExitAnimation != SectionHandExitAnimation.none &&
                      handExitAnimation !=
                          SectionHandExitAnimation.disappear) ...[
                    const SizedBox(height: 10),
                    _DurationStepper(
                      key: const ValueKey('section-hand-exit-duration'),
                      icon: Icons.timer_outlined,
                      label: context.l10n.handAnimationDuration,
                      value: handExitDurationSeconds,
                      minimum: .05,
                      onChanged: (value) =>
                          setState(() => handExitDurationSeconds = value),
                    ),
                  ],
                ],
                const Divider(height: 18),
                _DurationStepper(
                  key: const ValueKey('section-transition-duration'),
                  icon: Icons.arrow_circle_right_outlined,
                  label: context.l10n.transitionDuration,
                  value: transitionSeconds,
                  minimum: 0,
                  enabled: widget.allowTransition,
                  onChanged: (value) =>
                      setState(() => transitionSeconds = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  String _entranceAnimationLabel(
    BuildContext context,
    SectionHandEntranceAnimation value,
  ) => switch (value) {
    SectionHandEntranceAnimation.none => context.l10n.noAnimation,
    SectionHandEntranceAnimation.fadeIn => context.l10n.fadeIn,
    SectionHandEntranceAnimation.moveIn => context.l10n.moveIn,
    SectionHandEntranceAnimation.slingshot => context.l10n.slingshot,
  };

  String _exitAnimationLabel(
    BuildContext context,
    SectionHandExitAnimation value,
  ) => switch (value) {
    SectionHandExitAnimation.none => context.l10n.noAnimation,
    SectionHandExitAnimation.fadeOut => context.l10n.fadeOut,
    SectionHandExitAnimation.moveOut => context.l10n.moveOut,
    SectionHandExitAnimation.slingshot => context.l10n.slingshot,
    SectionHandExitAnimation.disappear => context.l10n.disappear,
  };

  Widget _pathTab(BuildContext context, DrawingStroke? stroke) {
    if (stroke == null) return _unavailable(context);
    final index = widget.strokeIndex!;
    final hasNode = cubit.selectedPathNode != null;
    final hasGeometry = stroke.geometry != null;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionCard(
            key: const ValueKey('section-preview-path'),
            icon: Icons.play_circle_outline_rounded,
            label: context.l10n.previewThisStroke,
            onPressed: widget.onPreviewStroke,
          ),
          _ActionCard(
            key: const ValueKey('section-reverse-path'),
            icon: Icons.swap_horiz_rounded,
            label: context.l10n.reverseDirection,
            selected: stroke.reversed,
            onPressed: () => cubit.reverseStroke(index),
          ),
          if (hasGeometry) ...[
            const Divider(height: 24),
            _ActionGrid(
              children: [
                _ActionCard(
                  icon: Icons.add_circle_outline_rounded,
                  label: context.l10n.addNode,
                  onPressed: hasNode ? cubit.addNodeToSelectedPath : null,
                ),
                _ActionCard(
                  icon: Icons.remove_circle_outline_rounded,
                  label: context.l10n.deleteNode,
                  onPressed: hasNode ? cubit.deleteSelectedNode : null,
                ),
                _ActionCard(
                  icon: Icons.gesture_rounded,
                  label: context.l10n.smoothNode,
                  onPressed: hasNode
                      ? () => cubit.setSelectedNodeSmooth(true)
                      : null,
                ),
                _ActionCard(
                  icon: Icons.change_history_rounded,
                  label: context.l10n.cornerNode,
                  onPressed: hasNode
                      ? () => cubit.setSelectedNodeSmooth(false)
                      : null,
                ),
                _ActionCard(
                  icon: Icons.first_page_rounded,
                  label: context.l10n.setStartNode,
                  onPressed: hasNode && stroke.geometry!.closed
                      ? cubit.setSelectedNodeAsStart
                      : null,
                ),
                _ActionCard(
                  icon: Icons.call_split_rounded,
                  label: context.l10n.splitPath,
                  onPressed:
                      cubit.selectedPathNode?.kind == PathNodeKind.endAnchor &&
                          !stroke.geometry!.closed
                      ? cubit.splitSelectedPath
                      : null,
                ),
                _ActionCard(
                  icon: Icons.merge_rounded,
                  label: context.l10n.joinNextPath,
                  onPressed:
                      index < cubit.project.strokes.length - 1 &&
                          cubit.project.strokes[index + 1].geometry != null
                      ? () => cubit.joinStrokeWithNext(index)
                      : null,
                ),
              ],
            ),
          ],
          const Divider(height: 24),
          _ActionCard(
            icon: stroke.hidden
                ? Icons.visibility_rounded
                : Icons.visibility_off_rounded,
            label: stroke.hidden
                ? context.l10n.showPath
                : context.l10n.hidePath,
            selected: stroke.hidden,
            onPressed: () => cubit.toggleStrokeHidden(index),
          ),
          _ActionCard(
            icon: Icons.layers_clear_outlined,
            label: context.l10n.resetMask,
            onPressed: stroke.vectorMaskStrokes.isEmpty
                ? null
                : () => cubit.resetStrokeMask(index),
          ),
          _ActionCard(
            key: const ValueKey('section-add-pause-point'),
            icon: Icons.pause_circle_outline_rounded,
            label: context.l10n.addPausePoint,
            onPressed: () => _editPausePoint(context, stroke),
          ),
          for (final pause in stroke.pausePoints)
            _ActionCard(
              icon: Icons.timer_outlined,
              label: context.l10n.pausePoint(
                (pause.progress * 100).round(),
                pause.durationSeconds.toStringAsFixed(1),
              ),
              onPressed: () => _editPausePoint(context, stroke, pause: pause),
            ),
        ],
      ),
    );
  }

  Widget _appearanceTab(BuildContext context, DrawingStroke? stroke) {
    final smart = widget.smartSection;
    final handSelected = stroke != null
        ? !stroke.revealOnly && !stroke.hidden
        : smart?.mode == SmartSectionMode.handDraw;
    final revealSelected = stroke != null
        ? stroke.revealOnly && !stroke.hidden
        : smart?.mode == SmartSectionMode.revealText;
    final hidden = stroke?.hidden ?? smart?.mode == SmartSectionMode.ignore;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.l10n.appearanceMethod,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _ChoiceCard(
            key: const ValueKey('section-appearance-hand'),
            icon: Icons.back_hand_outlined,
            title: context.l10n.withHand,
            selected: handSelected,
            onTap: () => _setAppearance(SmartSectionMode.handDraw),
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            key: const ValueKey('section-appearance-reveal'),
            icon: Icons.pan_tool_alt_outlined,
            title: context.l10n.withoutHand,
            selected: revealSelected,
            onTap: () => _setAppearance(SmartSectionMode.revealText),
          ),
          const SizedBox(height: 10),
          _ChoiceCard(
            key: const ValueKey('section-appearance-hidden'),
            icon: Icons.visibility_off_outlined,
            title: context.l10n.hidePath,
            selected: hidden,
            onTap: () => _setAppearance(SmartSectionMode.ignore),
          ),
        ],
      ),
    );
  }

  Widget _maskTab(BuildContext context, DrawingStroke? stroke) {
    if (stroke == null) return _unavailable(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PropertySlider(
            label: context.l10n.maskBrushSize,
            valueLabel: '${cubit.state.maskBrushWidth.round()} px',
            value: cubit.state.maskBrushWidth,
            min: 2,
            max: 400,
            onChanged: cubit.setMaskBrushWidth,
          ),
          _PropertySlider(
            label: context.l10n.maskFeather,
            valueLabel: '${cubit.state.maskFeather.round()} px',
            value: cubit.state.maskFeather,
            min: 0,
            max: 80,
            onChanged: cubit.setMaskFeather,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.showMaskOverlay),
            value: cubit.state.maskOverlayVisible,
            onChanged: cubit.setMaskOverlayVisible,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.compareBeforeMask),
            value: cubit.state.maskComparisonBefore,
            onChanged: cubit.setMaskComparisonBefore,
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.clipMaskToLayer),
            value: cubit.state.maskClipToLayer,
            onChanged: cubit.setMaskClipToLayer,
          ),
          if (stroke.geometry != null)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(context.l10n.snapNodes),
              value: cubit.state.nodeSnapEnabled,
              onChanged: cubit.setNodeSnapEnabled,
            ),
        ],
      ),
    );
  }

  Widget _unavailable(BuildContext context) => Center(
    child: Text(
      context.l10n.emptyStrokesHelp,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.studioColors.textMuted),
    ),
  );

  DrawingStroke? get _stroke {
    final index = widget.strokeIndex;
    if (index == null || index < 0 || index >= cubit.project.strokes.length) {
      return null;
    }
    return cubit.project.strokes[index];
  }

  void _setDrawingSpeed(double value) {
    final nextSpeed = SectionDrawingSpeedPolicy.sanitizeSpeed(value);
    setState(() {
      speedMultiplier = nextSpeed;
      animationSeconds = SectionDrawingSpeedPolicy.durationForSpeed(
        baselineDurationSeconds: _baselineAnimationSeconds,
        speedMultiplier: nextSpeed,
      );
    });
  }

  void _setAnimationDuration(double value) {
    final nextDuration = value.clamp(0.05, 60.0);
    setState(() {
      animationSeconds = nextDuration;
      speedMultiplier = SectionDrawingSpeedPolicy.speedForDuration(
        baselineDurationSeconds: _baselineAnimationSeconds,
        durationSeconds: nextDuration,
      );
    });
  }

  void _setAppearance(SmartSectionMode mode) {
    final index = widget.strokeIndex;
    if (index != null && index >= 0 && index < cubit.project.strokes.length) {
      if (mode == SmartSectionMode.ignore) {
        if (!cubit.project.strokes[index].hidden) {
          cubit.toggleStrokeHidden(index);
        }
        return;
      }
      if (cubit.project.strokes[index].hidden) cubit.toggleStrokeHidden(index);
      cubit.setStrokeRevealOnly(
        index,
        revealOnly: mode == SmartSectionMode.revealText,
      );
      return;
    }
    cubit.setSmartSectionMode(widget.sectionId, mode);
  }

  Future<void> _editPausePoint(
    BuildContext context,
    DrawingStroke stroke, {
    StrokePausePoint? pause,
  }) async {
    final result = await showDialog<_PausePointDialogResult>(
      context: context,
      builder: (_) => _StrokePausePointDialog(stroke: stroke, pause: pause),
    );
    if (result == null || !mounted) return;
    final index = widget.strokeIndex!;
    if (result.delete && pause != null) {
      cubit.deleteStrokePausePoint(index, pause.id);
    } else if (pause == null) {
      cubit.addStrokePausePoint(
        index,
        progress: result.progress,
        durationSeconds: result.durationSeconds,
        keepHandVisible: result.keepHandVisible,
      );
    } else {
      cubit.updateStrokePausePoint(
        index,
        pause.id,
        progress: result.progress,
        durationSeconds: result.durationSeconds,
        keepHandVisible: result.keepHandVisible,
      );
    }
  }

  void _saveAndClose() {
    widget.onTimingChangeStart();
    cubit.setTimelineSectionDurations(
      sectionId: widget.sectionId,
      animationSeconds: animationSeconds,
      speedMultiplier: speedMultiplier,
      pauseSeconds: pauseAfterEnabled ? pauseSeconds : 0,
      transitionSeconds: transitionSeconds,
      pauseBeforeSeconds: pauseBeforeEnabled ? pauseBeforeSeconds : 0,
      pauseBeforeEnabled: pauseBeforeEnabled,
      pauseAfterEnabled: pauseAfterEnabled,
      handEntranceAnimation: handEntranceAnimation,
      handEntranceDurationSeconds: handEntranceDurationSeconds,
      handExitAnimation: handExitAnimation,
      handExitDurationSeconds: handExitDurationSeconds,
      keepHandVisibleAfterDrawing: keepHandVisibleAfterDrawing,
    );
    widget.onTimingChangeEnd();
    Navigator.pop(context);
  }
}

class _DrawingSpeedControl extends StatelessWidget {
  const _DrawingSpeedControl({
    required this.value,
    required this.durationSeconds,
    required this.onChanged,
    required this.onDurationChanged,
  });

  final double value;
  final double durationSeconds;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onDurationChanged;

  @override
  Widget build(BuildContext context) {
    return _TimingStageCard(
      title: context.l10n.drawingSpeed,
      icon: Icons.speed_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 5),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final preset in SectionDrawingSpeedPolicy.presets)
                ChoiceChip(
                  key: ValueKey('section-speed-${preset}x'),
                  label: Text('${formatSpeed(preset)}×'),
                  selected: (preset - value).abs() <= 0.001,
                  onSelected: (_) => onChanged(preset),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  key: const ValueKey('section-speed-custom-slider'),
                  value: value.clamp(
                    SectionDrawingSpeedPolicy.minimum,
                    SectionDrawingSpeedPolicy.maximum,
                  ),
                  min: SectionDrawingSpeedPolicy.minimum,
                  max: SectionDrawingSpeedPolicy.maximum,
                  divisions: 75,
                  label: '${formatSpeed(value)}×',
                  onChanged: onChanged,
                ),
              ),
              SizedBox(
                width: 62,
                child: Text(
                  '${formatSpeed(value)}×',
                  key: const ValueKey('section-speed-value'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.studioColors.accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          Text(
            context.l10n.sectionDrawingSpeedDescription(
              durationSeconds.toStringAsFixed(2),
            ),
            textAlign: TextAlign.start,
            style: TextStyle(
              color: context.studioColors.textMuted,
              fontSize: 11,
            ),
          ),
          const Divider(height: 18),
          _DurationStepper(
            key: const ValueKey('section-animate-duration'),
            icon: Icons.play_circle_outline_rounded,
            label: context.l10n.animateDuration,
            value: durationSeconds,
            minimum: 0.05,
            onChanged: onDurationChanged,
          ),
        ],
      ),
    );
  }

  static String formatSpeed(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final child in children)
          SizedBox(width: (constraints.maxWidth - 8) / 2, child: child),
      ],
    ),
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(44),
        alignment: AlignmentDirectional.centerStart,
        backgroundColor: selected
            ? context.studioColors.selectedSurfaceStrong
            : null,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
  );
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.studioColors.selectedSurfaceStrong
        : context.studioColors.surfaceElevated,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? context.studioColors.accent
                : context.studioColors.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? context.studioColors.accent : null),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (selected)
              Icon(
                Icons.check_circle_rounded,
                color: context.studioColors.accent,
              ),
          ],
        ),
      ),
    ),
  );
}

class _TimingOverview extends StatelessWidget {
  const _TimingOverview({
    required this.description,
    required this.totalLabel,
    required this.speedLabel,
    required this.pauseBeforeSeconds,
    required this.handEntranceSeconds,
    required this.animationSeconds,
    required this.pauseSeconds,
    required this.handExitSeconds,
    required this.transitionSeconds,
  });

  final String description;
  final String totalLabel;
  final String speedLabel;
  final double pauseBeforeSeconds;
  final double handEntranceSeconds;
  final double animationSeconds;
  final double pauseSeconds;
  final double handExitSeconds;
  final double transitionSeconds;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.studioColors.surfaceElevated,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.studioColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.studioColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _TimingMetricChip(icon: Icons.speed_rounded, label: speedLabel),
              const SizedBox(width: 6),
              _TimingMetricChip(
                key: const ValueKey('section-total-duration'),
                icon: Icons.schedule_rounded,
                label: totalLabel,
                highlighted: true,
              ),
            ],
          ),
          const SizedBox(height: 9),
          _SectionTimingBar(
            pauseBeforeSeconds: pauseBeforeSeconds,
            handEntranceSeconds: handEntranceSeconds,
            animationSeconds: animationSeconds,
            pauseSeconds: pauseSeconds,
            handExitSeconds: handExitSeconds,
            transitionSeconds: transitionSeconds,
          ),
        ],
      ),
    ),
  );
}

class _TimingMetricChip extends StatelessWidget {
  const _TimingMetricChip({
    super.key,
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: highlighted
          ? context.studioColors.selectedSurfaceStrong
          : context.studioColors.surfaceAlt,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(
        color: highlighted
            ? context.studioColors.accent
            : context.studioColors.border,
      ),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: highlighted ? context.studioColors.accent : null,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _TimingStageExpansion extends StatelessWidget {
  const _TimingStageExpansion({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.initiallyExpanded,
    required this.child,
  });

  final String title;
  final IconData icon;
  final String summary;
  final bool initiallyExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: context.studioColors.surfaceAlt,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: context.studioColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      maintainState: true,
      dense: true,
      visualDensity: VisualDensity.compact,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      leading: Icon(icon, size: 18, color: context.studioColors.accent),
      title: Text(
        title,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        summary,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.studioColors.textMuted, fontSize: 11),
      ),
      children: [child],
    ),
  );
}

class _CompactFieldLabel extends StatelessWidget {
  const _CompactFieldLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 16, color: context.studioColors.accent),
      const SizedBox(width: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ],
  );
}

class _TimingStageCard extends StatelessWidget {
  const _TimingStageCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    color: context.studioColors.surfaceAlt,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: context.studioColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: context.studioColors.accent),
              const SizedBox(width: 7),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    ),
  );
}

class _AnimationPicker<T> extends StatelessWidget {
  const _AnimationPicker({
    super.key,
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  final T value;
  final List<(T, IconData, String)> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 520
          ? math.min(choices.length, 5)
          : constraints.maxWidth >= 360
          ? math.min(choices.length, 3)
          : 2;
      final width = (constraints.maxWidth - (columns - 1) * 6) / columns;
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final choice in choices)
            SizedBox(
              width: width,
              child: _AnimationChoiceTile(
                icon: choice.$2,
                label: choice.$3,
                selected: choice.$1 == value,
                onTap: () => onChanged(choice.$1),
              ),
            ),
        ],
      );
    },
  );
}

class _AnimationChoiceTile extends StatelessWidget {
  const _AnimationChoiceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected
        ? context.studioColors.selectedSurfaceStrong
        : context.studioColors.surfaceElevated,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? context.studioColors.accent
                : context.studioColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 17,
              color: selected ? context.studioColors.accent : null,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.minimum,
    required this.onChanged,
    this.enabled = true,
    this.precise = false,
  });

  final IconData icon;
  final String label;
  final double value;
  final double minimum;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final bool precise;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 18, color: context.studioColors.accent),
      const SizedBox(width: 7),
      Expanded(child: Text(label)),
      IconButton.outlined(
        key: ValueKey('${key.toString()}-decrease'),
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        padding: EdgeInsets.zero,
        onPressed: !enabled || value <= minimum
            ? null
            : () =>
                  onChanged(math.max(minimum, value - (precise ? 0.05 : 0.1))),
        icon: const Icon(Icons.remove, size: 16),
      ),
      SizedBox(
        width: precise ? 132 : 72,
        child: Text(
          precise ? _preciseDuration(value) : '${value.toStringAsFixed(2)} s',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontFeatures: [ui.FontFeature.tabularFigures()],
          ),
        ),
      ),
      IconButton.outlined(
        key: ValueKey('${key.toString()}-increase'),
        constraints: const BoxConstraints.tightFor(width: 30, height: 30),
        padding: EdgeInsets.zero,
        onPressed: !enabled || value >= 60
            ? null
            : () => onChanged(math.min(60, value + (precise ? 0.05 : 0.1))),
        icon: const Icon(Icons.add, size: 16),
      ),
    ],
  );
}

String _preciseDuration(double value) {
  final totalMilliseconds = (value.clamp(0, 60) * 1000).round();
  final seconds = totalMilliseconds ~/ 1000;
  final milliseconds = totalMilliseconds % 1000;
  return '$seconds s · ${milliseconds.toString().padLeft(3, '0')} ms';
}

class _SectionTimingBar extends StatelessWidget {
  const _SectionTimingBar({
    required this.pauseBeforeSeconds,
    required this.handEntranceSeconds,
    required this.animationSeconds,
    required this.pauseSeconds,
    required this.handExitSeconds,
    required this.transitionSeconds,
  });

  final double pauseBeforeSeconds;
  final double handEntranceSeconds;
  final double animationSeconds;
  final double pauseSeconds;
  final double handExitSeconds;
  final double transitionSeconds;

  @override
  Widget build(BuildContext context) {
    final total = math.max(
      0.001,
      pauseBeforeSeconds +
          handEntranceSeconds +
          animationSeconds +
          pauseSeconds +
          handExitSeconds +
          transitionSeconds,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (pauseBeforeSeconds > 0)
              Expanded(
                flex: math.max(1, (pauseBeforeSeconds / total * 1000).round()),
                child: ColoredBox(color: context.studioColors.warning),
              ),
            if (handEntranceSeconds > 0)
              Expanded(
                flex: math.max(1, (handEntranceSeconds / total * 1000).round()),
                child: ColoredBox(color: context.studioColors.accentSoft),
              ),
            if (animationSeconds > 0)
              Expanded(
                flex: math.max(1, (animationSeconds / total * 1000).round()),
                child: ColoredBox(color: context.studioColors.accent),
              ),
            if (pauseSeconds > 0)
              Expanded(
                flex: math.max(1, (pauseSeconds / total * 1000).round()),
                child: ColoredBox(color: context.studioColors.warning),
              ),
            if (handExitSeconds > 0)
              Expanded(
                flex: math.max(1, (handExitSeconds / total * 1000).round()),
                child: ColoredBox(color: context.studioColors.reveal),
              ),
            if (transitionSeconds > 0)
              Expanded(
                flex: math.max(1, (transitionSeconds / total * 1000).round()),
                child: ColoredBox(color: context.studioColors.success),
              ),
          ],
        ),
      ),
    );
  }
}

class _PropertySlider extends StatelessWidget {
  const _PropertySlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(valueLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        onChanged: onChanged,
      ),
    ],
  );
}

class _PausePointDialogResult {
  const _PausePointDialogResult({
    required this.progress,
    required this.durationSeconds,
    required this.keepHandVisible,
    this.delete = false,
  });

  final double progress;
  final double durationSeconds;
  final bool keepHandVisible;
  final bool delete;
}

class _StrokePausePointDialog extends StatefulWidget {
  const _StrokePausePointDialog({required this.stroke, this.pause});

  final DrawingStroke stroke;
  final StrokePausePoint? pause;

  @override
  State<_StrokePausePointDialog> createState() =>
      _StrokePausePointDialogState();
}

class _StrokePausePointDialogState extends State<_StrokePausePointDialog> {
  late double progress = widget.pause?.progress ?? 0.5;
  late double durationSeconds = widget.pause?.durationSeconds ?? 0.8;
  late bool keepHandVisible = widget.pause?.keepHandVisible ?? true;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.pause == null
          ? context.l10n.addPausePoint
          : context.l10n.editPausePoint,
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PathPositionPicker(
            stroke: widget.stroke,
            progress: progress,
            onChanged: (value) => setState(() => progress = value),
          ),
          const SizedBox(height: 12),
          _PropertySlider(
            label: context.l10n.pausePosition,
            valueLabel: '${(progress * 100).round()}%',
            value: progress,
            min: 0.01,
            max: 0.99,
            onChanged: (value) => setState(() => progress = value),
          ),
          _PropertySlider(
            label: context.l10n.pauseDuration,
            valueLabel: '${durationSeconds.toStringAsFixed(1)} s',
            value: durationSeconds,
            min: 0.1,
            max: 10,
            onChanged: (value) => setState(() => durationSeconds = value),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.keepHandAtPause),
            value: keepHandVisible,
            onChanged: (value) => setState(() => keepHandVisible = value),
          ),
        ],
      ),
    ),
    actions: [
      if (widget.pause != null)
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(
            context,
            _PausePointDialogResult(
              progress: progress,
              durationSeconds: durationSeconds,
              keepHandVisible: keepHandVisible,
              delete: true,
            ),
          ),
          icon: const Icon(Icons.delete_outline_rounded),
          label: Text(context.l10n.deletePausePoint),
        ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        key: const ValueKey('save-pause-point'),
        onPressed: () => Navigator.pop(
          context,
          _PausePointDialogResult(
            progress: progress,
            durationSeconds: durationSeconds,
            keepHandVisible: keepHandVisible,
          ),
        ),
        child: Text(context.l10n.apply),
      ),
    ],
  );
}

class _PathPositionPicker extends StatelessWidget {
  const _PathPositionPicker({
    required this.stroke,
    required this.progress,
    required this.onChanged,
  });

  final DrawingStroke stroke;
  final double progress;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    void update(Offset position, Size size) {
      final drawingRect = _fittedStrokeRect(stroke, size);
      final metric = buildDrawingStrokePath(
        stroke,
        drawingRect,
      ).computeMetrics().firstOrNull;
      if (metric == null || metric.length <= 0) return;
      var closestProgress = progress;
      var closestDistance = double.infinity;
      for (var sample = 0; sample <= 240; sample++) {
        final candidate = sample / 240;
        final point = metric
            .getTangentForOffset(metric.length * candidate)
            ?.position;
        if (point == null) continue;
        final distance = (point - position).distanceSquared;
        if (distance < closestDistance) {
          closestDistance = distance;
          closestProgress = candidate;
        }
      }
      onChanged(closestProgress.clamp(0.01, 0.99));
    }

    return Semantics(
      label: context.l10n.pausePosition,
      slider: true,
      value: '${(progress * 100).round()}%',
      child: SizedBox(
        height: 110,
        width: double.infinity,
        child: Builder(
          builder: (pickerContext) => GestureDetector(
            key: const ValueKey('pause-path-position-picker'),
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(
              details.localPosition,
              pickerContext.size ?? const Size(420, 110),
            ),
            onPanUpdate: (details) => update(
              details.localPosition,
              pickerContext.size ?? const Size(420, 110),
            ),
            child: CustomPaint(
              painter: _PathPositionPainter(
                stroke: stroke,
                progress: progress,
                colors: context.studioColors,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Rect _fittedStrokeRect(DrawingStroke stroke, Size size) {
  final points = stroke.orderedPoints;
  if (points.isEmpty) return Offset.zero & size;
  var bounds = Rect.fromPoints(points.first, points.first);
  for (final point in points.skip(1)) {
    bounds = bounds.expandToInclude(Rect.fromPoints(point, point));
  }
  final safeWidth = bounds.width <= 0 ? 1.0 : bounds.width;
  final safeHeight = bounds.height <= 0 ? 1.0 : bounds.height;
  final scale = math.min(
    (size.width - 32) / safeWidth,
    (size.height - 28) / safeHeight,
  );
  final drawnSize = Size(safeWidth * scale, safeHeight * scale);
  return Rect.fromLTWH(
    (size.width - drawnSize.width) / 2 - bounds.left * scale,
    (size.height - drawnSize.height) / 2 - bounds.top * scale,
    scale,
    scale,
  );
}

class _PathPositionPainter extends CustomPainter {
  const _PathPositionPainter({
    required this.stroke,
    required this.progress,
    required this.colors,
  });

  final DrawingStroke stroke;
  final double progress;
  final StudioThemeColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = _fittedStrokeRect(stroke, size);
    final path = buildDrawingStrokePath(stroke, rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)),
      Paint()..color = colors.inputFill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = colors.path.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final metric = path.computeMetrics().firstOrNull;
    final point = metric
        ?.getTangentForOffset(metric.length * progress)
        ?.position;
    if (point == null) return;
    canvas.drawCircle(
      point,
      11,
      Paint()..color = colors.reveal.withValues(alpha: 0.22),
    );
    canvas.drawCircle(point, 7, Paint()..color = colors.reveal);
  }

  @override
  bool shouldRepaint(covariant _PathPositionPainter oldDelegate) =>
      oldDelegate.stroke != stroke ||
      oldDelegate.progress != progress ||
      oldDelegate.colors != colors;
}
