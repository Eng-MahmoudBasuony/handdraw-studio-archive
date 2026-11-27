import 'package:handdraw_studio/features/image_animation/presentation/image_animation_panel.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_smart_path/handdraw_smart_path.dart';

import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/localization/presentation/localized_domain_labels.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/app/startup_sound/application/startup_sound_cubit.dart';
import 'package:handdraw_studio/app/startup_sound/domain/startup_sound_state.dart';
import 'package:handdraw_studio/features/writing_sound/domain/writing_sound.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_preview_controller.dart';
import 'package:handdraw_studio/features/writing_sound/presentation/writing_sound_preview_control.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/project/domain/models/drawing_project.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/editor/presentation/inspector/application/inspector_cubit.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'package:handdraw_studio/features/canvas_background/presentation/canvas_background_panel.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class EditorInspector extends StatefulWidget {
  const EditorInspector({
    super.key,
    required this.cubit,
    this.onImportImage,
    required this.inspectorCubit,
    required this.isPreviewing,
    required this.writingSoundPreviewEnabled,
    required this.voicePlayheadSeconds,
    required this.onDrawingSpeedChanged,
    required this.onPenTravelSpeedChanged,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    required this.onResetSettings,
    required this.writingSoundPreviewController,
    required this.onOpenHandLibrary,
    required this.onCalibrateHand,
    required this.onImportVoiceGuide,
    required this.onRemoveVoiceGuide,
    this.cameraEditing,
    this.onPreviewCameraShot,
    this.onClose,
  });

  final EditorCubit cubit;
  final VoidCallback? onImportImage;
  final InspectorCubit inspectorCubit;
  final bool isPreviewing;
  final bool writingSoundPreviewEnabled;
  final double voicePlayheadSeconds;
  final ValueChanged<double> onDrawingSpeedChanged;
  final ValueChanged<double> onPenTravelSpeedChanged;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;
  final VoidCallback onResetSettings;
  final WritingSoundPreviewController writingSoundPreviewController;
  final VoidCallback onOpenHandLibrary;
  final VoidCallback onCalibrateHand;
  final VoidCallback onImportVoiceGuide;
  final VoidCallback onRemoveVoiceGuide;
  final CameraEditingCubit? cameraEditing;
  final ValueChanged<CameraShot>? onPreviewCameraShot;
  final VoidCallback? onClose;

  @override
  State<EditorInspector> createState() => _EditorInspectorState();
}

class _EditorInspectorState extends State<EditorInspector> {
  final ScrollController _scrollController = ScrollController();

  EditorCubit get cubit => widget.cubit;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _fileName(String? path, String fallback) =>
      path == null ? fallback : path.split(Platform.pathSeparator).last;

  Future<void> _showFitToDuration() async {
    final l10n = context.l10n;
    final currentDuration = projectTimelineDuration(cubit.project);
    final range = fitProjectToDuration(cubit.project, currentDuration);
    var durationInput = currentDuration.toStringAsFixed(2);
    final target = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fitToDurationTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.fitToDurationDescription),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('fit-duration-field'),
                initialValue: durationInput,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.targetDuration,
                  suffixText: 's',
                ),
                onChanged: (value) => durationInput = value,
                onFieldSubmitted: (_) {
                  final value = double.tryParse(
                    durationInput.trim().replaceAll(',', '.'),
                  );
                  if (value != null) Navigator.pop(dialogContext, value);
                },
              ),
              const SizedBox(height: 10),
              Text(
                l10n.fitDurationRange(
                  range.minimumDurationSeconds.toStringAsFixed(2),
                  range.maximumDurationSeconds.toStringAsFixed(2),
                ),
                style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(
                  color: dialogContext.studioColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final value = double.tryParse(
                durationInput.trim().replaceAll(',', '.'),
              );
              if (value != null) Navigator.pop(dialogContext, value);
            },
            child: Text(l10n.apply),
          ),
        ],
      ),
    );
    if (!mounted || target == null) return;
    widget.onTimingChangeStart();
    final result = cubit.fitToDuration(target);
    if (result.isSuccess) {
      widget.onDrawingSpeedChanged(cubit.project.drawingSpeed);
      widget.onTimingChangeEnd();
      return;
    }
    widget.onTimingChangeEnd();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.fitToDurationTitle),
        content: Text(l10n.fitDurationImpossible),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.studioColors;
    final startupSoundCubit = _maybeStartupSoundCubit(context);
    final frameRates = {24, 25, 30, 50, 60, cubit.project.frameRate}.toList()
      ..sort();
    final hasTimedContent = cubit.project.strokes.isNotEmpty;
    final canEditTiming = hasTimedContent && !widget.isPreviewing;
    final canConfigureExport = cubit.canPreview && !widget.isPreviewing;
    final regularInspector = BlocBuilder<InspectorCubit, InspectorTab>(
      bloc: widget.inspectorCubit,
      builder: (context, tab) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.surface, colors.appBackground],
          ),
        ),
        child: Column(
          children: [
            _InspectorHeader(
              tab: tab,
              enabled: !widget.isPreviewing,
              onChanged: widget.inspectorCubit.select,
              onReset: widget.onResetSettings,
              onClose: widget.onClose,
            ),
            Expanded(
              child: CustomScrollView(
                key: const ValueKey('editor-inspector-scroll-view'),
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      tab == InspectorTab.animation &&
                              cubit.project.strokes.isNotEmpty
                          ? 0
                          : 16,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        if (tab == InspectorTab.project) ...[
                          _InspectorSectionCard(
                            key: const ValueKey(
                              'inspector-section-project-summary',
                            ),
                            title: l10n.drawing,
                            icon: StudioIconData.drawing,
                            child: Column(
                              children: [
                                _InfoRow(
                                  label: l10n.sourceFile,
                                  value: _fileName(
                                    cubit.project.drawingImagePath,
                                    l10n.notSelected,
                                  ),
                                ),
                                if (cubit.artworkPlacement != null) ...[
                                  const SizedBox(height: 8),
                                  _ArtworkPlacementControls(
                                    cubit: cubit,
                                    readOnly: widget.isPreviewing,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InspectorSectionCard(
                            key: const ValueKey(
                              'inspector-section-canvas-background',
                            ),
                            title: l10n.canvasBackground,
                            icon: StudioIconData.inspector,
                            child: CanvasBackgroundPanel(
                              value: cubit.state.document.canvas.background,
                              onChanged: widget.isPreviewing
                                  ? null
                                  : cubit.setCanvasBackground,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InspectorSectionCard(
                            key: const ValueKey(
                              'inspector-section-project-export',
                            ),
                            title: l10n.exportMovie,
                            icon: StudioIconData.exportMovie,
                            enabled: cubit.canPreview,
                            disabledReason: l10n.exportUnavailableDescription,
                            child: Column(
                              children: [
                                DropdownButtonFormField<ExportPresetId>(
                                  initialValue: cubit.project.exportPresetId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: l10n.exportPreset,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final id in ExportPresetId.values)
                                      DropdownMenuItem(
                                        value: id,
                                        child: Text(switch (id) {
                                          ExportPresetId.youtubeCourse4k =>
                                            l10n.presetYoutube4k,
                                          ExportPresetId.finalCutOverlay4k =>
                                            l10n.presetFinalCut4k,
                                          ExportPresetId.verticalLesson =>
                                            l10n.presetVerticalLesson,
                                          ExportPresetId.squareLesson =>
                                            l10n.presetSquareLesson,
                                          ExportPresetId.presentationHd =>
                                            l10n.presetPresentationHd,
                                          ExportPresetId.custom =>
                                            l10n.presetCustom,
                                        }),
                                      ),
                                  ],
                                  onChanged: canConfigureExport
                                      ? (value) {
                                          if (value != null) {
                                            cubit.applyExportPreset(value);
                                          }
                                        }
                                      : null,
                                ),
                                if (cubit.project.exportPresetId ==
                                    ExportPresetId.custom) ...[
                                  const SizedBox(height: 10),
                                  _CustomExportResolutionFields(
                                    width: cubit.project.canvasWidth,
                                    height: cubit.project.canvasHeight,
                                    enabled: canConfigureExport,
                                    onApply: (width, height) =>
                                        cubit.setCustomExportResolution(
                                          width: width,
                                          height: height,
                                        ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                DropdownButtonFormField<int>(
                                  initialValue: cubit.project.frameRate,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: l10n.frameRate,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    for (final rate in frameRates)
                                      DropdownMenuItem(
                                        value: rate,
                                        child: Text('$rate fps'),
                                      ),
                                  ],
                                  onChanged: canConfigureExport
                                      ? (value) {
                                          if (value != null) {
                                            cubit.setExportFrameRate(value);
                                          }
                                        }
                                      : null,
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<ExportRenderQuality>(
                                  initialValue:
                                      cubit.project.exportRenderQuality,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: l10n.exportQuality,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: ExportRenderQuality.full,
                                      child: Text(
                                        l10n.exportFullQuality,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: ExportRenderQuality.proxy,
                                      child: Text(
                                        l10n.exportProxyQuality,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: canConfigureExport
                                      ? (value) {
                                          if (value != null) {
                                            cubit.setExportRenderQuality(value);
                                          }
                                        }
                                      : null,
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<ExportAlphaMode>(
                                  initialValue: cubit.project.exportAlphaMode,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: l10n.alphaMode,
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: ExportAlphaMode.premultiplied,
                                      child: Text(
                                        l10n.alphaPremultiplied,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: ExportAlphaMode.straight,
                                      child: Text(
                                        l10n.alphaStraight,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                  onChanged: canConfigureExport
                                      ? (value) {
                                          if (value != null) {
                                            cubit.setExportAlphaMode(value);
                                          }
                                        }
                                      : null,
                                ),
                                const SizedBox(height: 10),
                                _InfoRow(
                                  label: l10n.resolution,
                                  value:
                                      '${cubit.project.canvasWidth} × ${cubit.project.canvasHeight}',
                                ),
                                _InfoRow(
                                  label: l10n.frameRate,
                                  value: '${cubit.project.frameRate} fps',
                                ),
                                _InfoRow(
                                  label: l10n.background,
                                  value: _canvasBackgroundLabel(
                                    context,
                                    cubit.state.document.canvas.background,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (tab == InspectorTab.animation) ...[
                          if (cubit.project.imageAnimationEffect != 'legacy' ||
                              cubit.state.imageAnimationControlsOpen ||
                              (!cubit.hasDrawing &&
                                  cubit.project.strokes.isEmpty &&
                                  cubit.smartSections.isEmpty))
                            ImageAnimationPanel(
                              cubit: cubit,
                              onImportImage: widget.onImportImage ?? () {},
                              isPreviewing: widget.isPreviewing,
                            ),
                          const SizedBox(height: 16),
                          if (cubit.isAnalyzingSmartPaths) ...[
                            const SizedBox(height: 18),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 8),
                            Text(
                              l10n.detectingPaths,
                              style: TextStyle(
                                color: context.studioColors.textSecondary,
                              ),
                            ),
                          ],
                          if (cubit.autoPathResult != null) ...[
                            const SizedBox(height: 18),
                            _SmartPathPanel(cubit: cubit),
                          ],
                          if (cubit.smartSections.any(
                            (section) => section.isSuspectedFrame,
                          )) ...[
                            const SizedBox(height: 18),
                            _SmartPathReviewPanel(cubit: cubit),
                          ],
                          const SizedBox(height: 12),
                          Builder(
                            builder: (context) {
                              final details = _InspectorSectionCard(
                                key: const ValueKey(
                                  'inspector-section-animation-timing',
                                ),
                                title: l10n.timingReveal,
                                icon: StudioIconData.autoPath,
                                enabled: hasTimedContent,
                                disabledReason:
                                    l10n.timingUnavailableDescription,
                                child: Column(
                                  children: [
                                    _MotionSpeedControls(
                                      cubit: cubit,
                                      project: cubit.project,
                                      compact: true,
                                      onDrawingSpeedChanged: canEditTiming
                                          ? widget.onDrawingSpeedChanged
                                          : null,
                                      onPenTravelSpeedChanged: canEditTiming
                                          ? widget.onPenTravelSpeedChanged
                                          : null,
                                      onTimingChangeStart:
                                          widget.onTimingChangeStart,
                                      onTimingChangeEnd:
                                          widget.onTimingChangeEnd,
                                      onFitToDuration: canEditTiming
                                          ? _showFitToDuration
                                          : null,
                                    ),
                                    _InfoRow(
                                      label: l10n.autoTiming,
                                      value: l10n.autoTimingValue(
                                        cubit.project.startDelaySeconds
                                            .toStringAsFixed(1),
                                        cubit.project.endHoldSeconds
                                            .toStringAsFixed(1),
                                      ),
                                    ),
                                    _InfoRow(
                                      label: l10n.sections,
                                      value: l10n.sectionsDetected(
                                        automaticSectionCount(
                                          cubit.project.strokes,
                                        ),
                                      ),
                                    ),
                                    if (cubit.project.strokes.isNotEmpty) ...[
                                      _InfoRow(
                                        label: l10n.outputDuration,
                                        value:
                                            '${projectTimelineDuration(cubit.project).toStringAsFixed(2)} s',
                                      ),
                                      const SizedBox(height: 8),
                                      _AdvancedTimingPanel(
                                        cubit: cubit,
                                        enabled: !widget.isPreviewing,
                                        voicePlayheadSeconds:
                                            widget.voicePlayheadSeconds,
                                      ),
                                    ],
                                    _LabeledSlider(
                                      label: l10n.revealWidth,
                                      valueLabel:
                                          '${cubit.project.revealWidth.round()} px',
                                      value: cubit.project.revealWidth,
                                      min: 4,
                                      max: 240,
                                      onChanged: canEditTiming
                                          ? cubit.setRevealWidth
                                          : null,
                                    ),
                                  ],
                                ),
                              );
                              if (cubit.project.imageAnimationEffect ==
                                  'legacy') {
                                return details;
                              }
                              return ExpansionTile(
                                title: Text(
                                  Localizations.localeOf(
                                            context,
                                          ).languageCode ==
                                          'ar'
                                      ? 'توقيت وإعدادات إضافية'
                                      : 'Timing and more settings',
                                ),
                                children: [details],
                              );
                            },
                          ),
                        ],
                        if (tab == InspectorTab.hand) ...[
                          _InspectorSectionCard(
                            key: const ValueKey(
                              'inspector-section-hand-settings',
                            ),
                            title: l10n.handSection,
                            icon: StudioIconData.hand,
                            child: Column(
                              children: [
                                _InfoRow(
                                  label: l10n.hand,
                                  value: cubit.hasHand
                                      ? cubit.selectedHandPreset?.localizedName(
                                              l10n,
                                            ) ??
                                            cubit.activeHandName
                                      : l10n.notSelected,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: widget.isPreviewing
                                            ? null
                                            : widget.onOpenHandLibrary,
                                        icon: const StudioIcon(
                                          StudioIconData.hand,
                                          size: 17,
                                        ),
                                        label: Text(l10n.hands),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton.outlined(
                                      tooltip: l10n.penTip,
                                      onPressed:
                                          cubit.hasHand && !widget.isPreviewing
                                          ? widget.onCalibrateHand
                                          : null,
                                      icon: const StudioIcon(
                                        StudioIconData.penTip,
                                        size: 17,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _ContextualControlGroup(
                                  enabled: cubit.hasHand,
                                  disabledReason:
                                      l10n.handUnavailableDescription,
                                  child: Column(
                                    children: [
                                      _LabeledSlider(
                                        label: l10n.size,
                                        valueLabel:
                                            '${(cubit.project.handScale * 100).round()}%',
                                        value: cubit.project.handScale,
                                        min: 0.06,
                                        max: 0.90,
                                        onChanged:
                                            cubit.hasHand &&
                                                !widget.isPreviewing
                                            ? cubit.setHandScale
                                            : null,
                                        onChangeEnd: (_) =>
                                            cubit.commitHandPreferences(),
                                      ),
                                      _LabeledSlider(
                                        label: l10n.rotationOffset,
                                        valueLabel:
                                            '${cubit.project.handRotationDegrees.round()}°',
                                        value:
                                            cubit.project.handRotationDegrees,
                                        min: -180,
                                        max: 180,
                                        onChanged:
                                            cubit.hasHand &&
                                                !widget.isPreviewing
                                            ? cubit.setHandRotation
                                            : null,
                                        onChangeEnd: (_) =>
                                            cubit.commitHandPreferences(),
                                      ),
                                      Material(
                                        type: MaterialType.transparency,
                                        child: SwitchListTile.adaptive(
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(l10n.reverseDirection),
                                          value: cubit.project.handFlipX,
                                          onChanged:
                                              cubit.hasHand &&
                                                  !widget.isPreviewing
                                              ? cubit.setHandFlipX
                                              : null,
                                        ),
                                      ),
                                      const Divider(height: 18),
                                      Material(
                                        type: MaterialType.transparency,
                                        child: SwitchListTile.adaptive(
                                          key: const ValueKey(
                                            'keep-hand-visible-after-drawing',
                                          ),
                                          contentPadding: EdgeInsets.zero,
                                          title: Text(
                                            l10n.keepHandVisibleAfterDrawing,
                                          ),
                                          subtitle: Text(
                                            l10n.keepHandVisibleAfterDrawingDescription,
                                            style: TextStyle(
                                              color: context
                                                  .studioColors
                                                  .textMuted,
                                              fontSize: 11,
                                            ),
                                          ),
                                          value:
                                              cubit.keepHandVisibleAfterDrawing,
                                          onChanged:
                                              cubit.hasHand && canEditTiming
                                              ? cubit
                                                    .setKeepHandVisibleAfterDrawing
                                              : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        if (tab == InspectorTab.audio) ...[
                          if (startupSoundCubit != null) ...[
                            BlocBuilder<StartupSoundCubit, StartupSoundState>(
                              bloc: startupSoundCubit,
                              builder: (context, startupSound) =>
                                  _InspectorSectionCard(
                                    key: const ValueKey(
                                      'inspector-section-startup-sound',
                                    ),
                                    title: l10n.startupSound,
                                    icon: StudioIconData.voice,
                                    child: Material(
                                      type: MaterialType.transparency,
                                      child: SwitchListTile.adaptive(
                                        key: const ValueKey(
                                          'startup-sound-toggle',
                                        ),
                                        contentPadding: EdgeInsets.zero,
                                        title: Text(l10n.playStartupSound),
                                        subtitle: Text(
                                          l10n.startupSoundDescription,
                                          style: TextStyle(
                                            color:
                                                context.studioColors.textMuted,
                                            fontSize: 11,
                                          ),
                                        ),
                                        value: startupSound.enabled,
                                        onChanged: startupSoundCubit.setEnabled,
                                      ),
                                    ),
                                  ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          _InspectorSectionCard(
                            key: const ValueKey(
                              'inspector-section-writing-sound',
                            ),
                            title: l10n.writingSound,
                            icon: StudioIconData.penTip,
                            enabled: hasTimedContent,
                            disabledReason:
                                l10n.writingSoundUnavailableDescription,
                            child: Column(
                              children: [
                                Material(
                                  type: MaterialType.transparency,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(l10n.includeWritingSound),
                                    subtitle: Text(
                                      cubit.project.writingSoundEnabled
                                          ? l10n.writingSoundOnDescription
                                          : l10n.writingSoundOffDescription,
                                      style: TextStyle(
                                        color: context.studioColors.textMuted,
                                        fontSize: 11,
                                      ),
                                    ),
                                    value: cubit.project.writingSoundEnabled,
                                    onChanged:
                                        hasTimedContent && !widget.isPreviewing
                                        ? cubit.setWritingSoundEnabled
                                        : null,
                                  ),
                                ),
                                if (cubit.project.writingSoundEnabled) ...[
                                  const SizedBox(height: 4),
                                  Material(
                                    type: MaterialType.transparency,
                                    child:
                                        DropdownButtonFormField<
                                          WritingSoundPreset
                                        >(
                                          initialValue:
                                              cubit.project.writingSoundPreset,
                                          isExpanded: true,
                                          decoration: InputDecoration(
                                            labelText: l10n.soundType,
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          items: [
                                            for (final preset
                                                in WritingSoundPreset.values)
                                              DropdownMenuItem(
                                                value: preset,
                                                child: Text(
                                                  preset.localizedLabel(l10n),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                          onChanged:
                                              hasTimedContent &&
                                                  !widget.isPreviewing
                                              ? (value) {
                                                  if (value != null) {
                                                    widget
                                                        .writingSoundPreviewController
                                                        .stop();
                                                    cubit.setWritingSoundPreset(
                                                      value,
                                                    );
                                                  }
                                                }
                                              : null,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                  WritingSoundPreviewControl(
                                    controller:
                                        widget.writingSoundPreviewController,
                                    preset: cubit.project.writingSoundPreset,
                                    volume: cubit.project.writingSoundVolume,
                                    enabled: widget.writingSoundPreviewEnabled,
                                  ),
                                  const SizedBox(height: 12),
                                  _LabeledSlider(
                                    label: l10n.volume,
                                    valueLabel:
                                        '${(cubit.project.writingSoundVolume * 100).round()}%',
                                    value: cubit.project.writingSoundVolume,
                                    min: 0,
                                    max: 1,
                                    onChanged:
                                        hasTimedContent && !widget.isPreviewing
                                        ? (value) {
                                            widget.writingSoundPreviewController
                                                .stop();
                                            cubit.setWritingSoundVolume(value);
                                          }
                                        : null,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          _InspectorSectionCard(
                            key: const ValueKey(
                              'inspector-section-voice-guide',
                            ),
                            title: l10n.voiceGuide,
                            icon: StudioIconData.voice,
                            child: Column(
                              children: [
                                _InfoRow(
                                  label: l10n.voiceGuide,
                                  value: cubit.voiceGuide == null
                                      ? l10n.notSelected
                                      : _fileName(
                                          cubit.voiceGuide!.path,
                                          l10n.voiceGuide,
                                        ),
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: FilledButton.tonalIcon(
                                        onPressed: widget.isPreviewing
                                            ? null
                                            : widget.onImportVoiceGuide,
                                        icon: const StudioIcon(
                                          StudioIconData.voice,
                                          size: 17,
                                        ),
                                        label: Text(
                                          cubit.voiceGuide == null
                                              ? l10n.importVoice
                                              : l10n.replaceVoiceGuide,
                                        ),
                                      ),
                                    ),
                                    if (cubit.voiceGuide != null) ...[
                                      const SizedBox(width: 8),
                                      IconButton.outlined(
                                        tooltip: l10n.removeVoiceGuide,
                                        onPressed: widget.isPreviewing
                                            ? null
                                            : widget.onRemoveVoiceGuide,
                                        icon: const Icon(Icons.close, size: 18),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    final cameraEditing = widget.cameraEditing;
    if (cameraEditing == null) return regularInspector;
    return BlocBuilder<CameraEditingCubit, CameraEditingState>(
      bloc: cameraEditing,
      builder: (context, cameraState) {
        final shotId = cameraState.primaryShotId;
        final shot = shotId == null
            ? null
            : cubit.state.document.cameraTrack?.shots
                  .where((item) => item.id == shotId)
                  .firstOrNull;
        if (shot == null || shot.ownerSceneId == null) return regularInspector;
        return _SceneCameraInspector(
          editor: cubit,
          editing: cameraEditing,
          shot: shot,
          readOnly: widget.isPreviewing,
          onPreview: widget.onPreviewCameraShot,
        );
      },
    );
  }
}

class _SceneCameraInspector extends StatelessWidget {
  const _SceneCameraInspector({
    required this.editor,
    required this.editing,
    required this.shot,
    required this.readOnly,
    this.onPreview,
  });

  final EditorCubit editor;
  final CameraEditingCubit editing;
  final CameraShot shot;
  final bool readOnly;
  final ValueChanged<CameraShot>? onPreview;

  bool _isArabic(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ar';
  String _text(BuildContext context, String en, String ar) =>
      _isArabic(context) ? ar : en;

  void _selectFrame(CameraKeyframe frame) {
    editing.selectKeyframe(shot.id, frame.id, preserveShotSelection: true);
    editing.restoreEditorView(frame.view);
    editing.setCanvasMode(CameraCanvasMode.editCamera);
  }

  void _setZoom(CameraKeyframe frame, double zoom) {
    final view = CameraView(
      centerX: frame.view.centerX,
      centerY: frame.view.centerY,
      viewportWidth: 1 / zoom,
    );
    if (!editor.setCameraKeyframeView(shot.id, frame.id, view)) return;
    editing.restoreEditorView(view);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final frames = shot.keyframes;
    if (frames.length != 3) return const SizedBox.shrink();
    final selectedId = editing.state.selectedKeyframeId;
    final selected =
        frames.where((frame) => frame.id == selectedId).firstOrNull ??
        frames.first;
    final enter = frames[1].incomingTransition.duration;
    final exit = frames[2].incomingTransition.duration;
    final totalSeconds =
        shot.duration.microseconds / Duration.microsecondsPerSecond;
    final enterSeconds = enter.microseconds / Duration.microsecondsPerSecond;
    final exitSeconds = exit.microseconds / Duration.microsecondsPerSecond;
    final holdSeconds = (totalSeconds - enterSeconds - exitSeconds).clamp(
      0.0,
      totalSeconds,
    );
    final maximumPhase = (totalSeconds / 2).clamp(.1, 10.0);
    final easing = frames[1].incomingTransition.easing;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.surface, colors.appBackground],
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.videocam_outlined, color: colors.accent, size: 19),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _text(context, 'Scene Camera', 'كاميرا المشهد'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        shot.label ?? shot.ownerSceneId!.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: colors.textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _text(context, 'Close', 'إغلاق'),
                  onPressed: editing.clear,
                  icon: const Icon(Icons.close, size: 18),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _InspectorSectionCard(
                  title: _text(context, 'Camera views', 'مناظر الكاميرا'),
                  icon: StudioIconData.inspector,
                  enabled: !readOnly && !shot.isLocked,
                  disabledReason: _text(
                    context,
                    'Pause Preview or unlock this clip to edit it.',
                    'أوقف المعاينة أو افتح قفل الكليب لتعديله.',
                  ),
                  child: Column(
                    children: [
                      SegmentedButton<CameraKeyframeId>(
                        segments: [
                          ButtonSegment(
                            value: frames[0].id,
                            label: Text(_text(context, 'Start', 'البداية')),
                          ),
                          ButtonSegment(
                            value: frames[1].id,
                            label: Text(_text(context, 'Focus', 'التركيز')),
                          ),
                          ButtonSegment(
                            value: frames[2].id,
                            label: Text(_text(context, 'End', 'النهاية')),
                          ),
                        ],
                        selected: {selected.id},
                        onSelectionChanged: (values) {
                          final id = values.first;
                          _selectFrame(
                            frames.firstWhere((frame) => frame.id == id),
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _LabeledSlider(
                        label: _text(context, 'Zoom', 'قوة الزووم'),
                        valueLabel:
                            '${(100 / selected.view.viewportWidth).round()}%',
                        value: (1 / selected.view.viewportWidth).clamp(1, 4),
                        min: 1,
                        max: 4,
                        onChanged: (value) => _setZoom(selected, value),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _text(
                          context,
                          'Drag or resize the cyan frame on the canvas. The dashed frame is the comparison view.',
                          'حرّك أو غيّر حجم الإطار السماوي فوق اللوحة. الإطار المتقطع هو منظر المقارنة.',
                        ),
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 10,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _InspectorSectionCard(
                  title: _text(context, 'Timing and motion', 'التوقيت والحركة'),
                  icon: StudioIconData.preview,
                  enabled: !readOnly && !shot.isLocked,
                  disabledReason: _text(
                    context,
                    'Camera timing is unavailable during Preview.',
                    'توقيت الكاميرا غير متاح أثناء المعاينة.',
                  ),
                  child: Column(
                    children: [
                      _LabeledSlider(
                        label: _text(context, 'Enter', 'الدخول'),
                        valueLabel: '${enterSeconds.toStringAsFixed(1)}s',
                        value: enterSeconds.clamp(0, maximumPhase),
                        min: 0,
                        max: maximumPhase,
                        onChanged: (value) => editor.updateSceneCameraTiming(
                          shotId: shot.id,
                          enterDuration: TimelineDuration.fromMicroseconds(
                            (value * Duration.microsecondsPerSecond).round(),
                          ),
                          exitDuration: exit,
                          easing: easing,
                        ),
                      ),
                      _InfoRow(
                        label: _text(context, 'Hold', 'الثبات'),
                        value: '${holdSeconds.toStringAsFixed(1)}s',
                      ),
                      _LabeledSlider(
                        label: _text(context, 'Exit', 'الخروج'),
                        valueLabel: '${exitSeconds.toStringAsFixed(1)}s',
                        value: exitSeconds.clamp(0, maximumPhase),
                        min: 0,
                        max: maximumPhase,
                        onChanged: (value) => editor.updateSceneCameraTiming(
                          shotId: shot.id,
                          enterDuration: enter,
                          exitDuration: TimelineDuration.fromMicroseconds(
                            (value * Duration.microsecondsPerSecond).round(),
                          ),
                          easing: easing,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<CameraEasing>(
                        initialValue: easing,
                        decoration: InputDecoration(
                          labelText: _text(context, 'Easing', 'النعومة'),
                        ),
                        items: [
                          for (final value in CameraEasing.values)
                            DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          editor.updateSceneCameraTiming(
                            shotId: shot.id,
                            enterDuration: enter,
                            exitDuration: exit,
                            easing: value,
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _InspectorSectionCard(
                  title: _text(
                    context,
                    'From previous scene',
                    'العلاقة بالمشهد السابق',
                  ),
                  icon: StudioIconData.preview,
                  enabled: !readOnly && !shot.isLocked,
                  disabledReason: _text(
                    context,
                    'Pause Preview to change the scene connection.',
                    'أوقف المعاينة لتغيير اتصال المشهد.',
                  ),
                  child: SegmentedButton<CameraSceneConnection>(
                    segments: [
                      ButtonSegment(
                        value: CameraSceneConnection.continuePrevious,
                        label: Text(_text(context, 'Continue', 'استمرار')),
                      ),
                      ButtonSegment(
                        value: CameraSceneConnection.cut,
                        label: Text(_text(context, 'Cut', 'قطع')),
                      ),
                      ButtonSegment(
                        value: CameraSceneConnection.transition,
                        label: Text(_text(context, 'Transition', 'انتقال')),
                      ),
                    ],
                    selected: {shot.sceneConnection},
                    onSelectionChanged: (values) =>
                        editor.setSceneCameraConnection(shot.id, values.first),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('preview-scene-camera-clip'),
                  onPressed: onPreview == null ? null : () => onPreview!(shot),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(
                    _text(
                      context,
                      'Preview this camera clip',
                      'معاينة كاميرا هذا المشهد',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

StartupSoundCubit? _maybeStartupSoundCubit(BuildContext context) {
  try {
    return context.read<StartupSoundCubit>();
  } catch (_) {
    return null;
  }
}

String _canvasBackgroundLabel(
  BuildContext context,
  CanvasBackground background,
) => switch (background.mode) {
  CanvasBackgroundMode.transparent => context.l10n.backgroundNone,
  CanvasBackgroundMode.solid when background.colorValue == 0xFFFFFFFF =>
    context.l10n.backgroundWhite,
  CanvasBackgroundMode.solid when background.colorValue == 0xFF000000 =>
    context.l10n.backgroundBlack,
  CanvasBackgroundMode.solid => context.l10n.backgroundCustom,
  CanvasBackgroundMode.preset => switch (background.preset!) {
    CanvasBackgroundPreset.notebook => context.l10n.backgroundNotebook,
    CanvasBackgroundPreset.graph => context.l10n.backgroundGraph,
    CanvasBackgroundPreset.cream => context.l10n.backgroundCream,
    CanvasBackgroundPreset.chalkboard => context.l10n.backgroundChalkboard,
    CanvasBackgroundPreset.softGradient => context.l10n.backgroundSoftGradient,
    CanvasBackgroundPreset.warmWhite => context.l10n.backgroundWarmWhite,
    CanvasBackgroundPreset.blueprint => context.l10n.backgroundBlueprint,
    CanvasBackgroundPreset.kraft => context.l10n.backgroundKraft,
    CanvasBackgroundPreset.dark => context.l10n.backgroundDark,
    CanvasBackgroundPreset.linen => context.l10n.backgroundLinen,
  },
};

class _InspectorSectionCard extends StatelessWidget {
  const _InspectorSectionCard({
    super.key,
    required this.title,
    required this.icon,
    this.child,
    this.trailing,
    this.enabled = true,
    this.disabledReason,
  });

  final String title;
  final StudioIconData icon;
  final Widget? child;
  final Widget? trailing;
  final bool enabled;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.82)),
        boxShadow: [
          BoxShadow(
            color: colors.appBackground.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceElevated.withValues(alpha: 0.64),
                  border: Border(
                    bottom: BorderSide(
                      color: colors.border.withValues(alpha: 0.62),
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(13, 10, 11, 10),
                  child: Row(
                    children: [
                      StudioIcon(icon, size: 16, color: colors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(title, style: _sectionStyle(context)),
                      ),
                      ...switch (trailing) {
                        final trailing? => [trailing],
                        null => const <Widget>[],
                      },
                    ],
                  ),
                ),
              ),
              if (child case final child?)
                Padding(
                  padding: const EdgeInsets.all(13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!enabled && disabledReason != null) ...[
                        _InspectorDisabledNotice(message: disabledReason!),
                        const SizedBox(height: 10),
                      ],
                      Semantics(
                        enabled: enabled,
                        child: IgnorePointer(
                          ignoring: !enabled,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 160),
                            opacity: enabled ? 1 : 0.42,
                            child: child,
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
  }
}

class _ContextualControlGroup extends StatelessWidget {
  const _ContextualControlGroup({
    required this.enabled,
    required this.disabledReason,
    required this.child,
  });

  final bool enabled;
  final String disabledReason;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (!enabled) ...[
        _InspectorDisabledNotice(message: disabledReason),
        const SizedBox(height: 10),
      ],
      Semantics(
        enabled: enabled,
        child: IgnorePointer(
          ignoring: !enabled,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: enabled ? 1 : 0.42,
            child: child,
          ),
        ),
      ),
    ],
  );
}

class _InspectorDisabledNotice extends StatelessWidget {
  const _InspectorDisabledNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return Container(
      key: const ValueKey('inspector-disabled-notice'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: colors.border.withValues(alpha: 0.74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: colors.textMuted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 10.5,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InspectorHeader extends StatelessWidget {
  const _InspectorHeader({
    required this.tab,
    required this.enabled,
    required this.onChanged,
    required this.onReset,
    this.onClose,
  });
  final InspectorTab tab;
  final bool enabled;
  final ValueChanged<InspectorTab> onChanged;
  final VoidCallback onReset;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: context.studioColors.surfaceElevated,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 6, 4),
            child: Row(
              children: [
                if (onClose case final closeInspector?)
                  InspectorEdgeToggleButton(
                    key: const ValueKey('close-inspector'),
                    tooltip: l10n.closeInspector,
                    onPressed: closeInspector,
                    expanded: true,
                  ),
                Expanded(
                  child: Text(switch (tab) {
                    InspectorTab.project => l10n.project,
                    InspectorTab.animation => l10n.animation,
                    InspectorTab.hand => l10n.handSection,
                    InspectorTab.audio => l10n.audio,
                  }, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                PopupMenuButton<String>(
                  tooltip: l10n.resetSettings,
                  onSelected: (_) => onReset(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'all',
                      enabled: enabled,
                      child: Text(l10n.resetSettings),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            key: const ValueKey('inspector-tabs'),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 8, 9),
            child: Row(
              children: [
                _InspectorTabButton(
                  tab: InspectorTab.project,
                  selected: tab == InspectorTab.project,
                  icon: StudioIconData.inspector,
                  label: l10n.project,
                  onPressed: onChanged,
                ),
                _InspectorTabButton(
                  tab: InspectorTab.animation,
                  selected: tab == InspectorTab.animation,
                  icon: StudioIconData.autoPath,
                  label: l10n.animation,
                  onPressed: onChanged,
                ),
                _InspectorTabButton(
                  tab: InspectorTab.hand,
                  selected: tab == InspectorTab.hand,
                  icon: StudioIconData.hand,
                  label: l10n.handSection,
                  onPressed: onChanged,
                ),
                _InspectorTabButton(
                  tab: InspectorTab.audio,
                  selected: tab == InspectorTab.audio,
                  icon: StudioIconData.voice,
                  label: l10n.audio,
                  onPressed: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A matching pair of edge controls for the docked inspector. Using the same
/// visual language in both states makes it clear that the panel is collapsed,
/// not permanently closed.
class InspectorEdgeToggleButton extends StatelessWidget {
  const InspectorEdgeToggleButton({
    super.key,
    required this.expanded,
    required this.tooltip,
    required this.onPressed,
  });

  final bool expanded;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return Semantics(
      button: true,
      label: tooltip,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: const Size.square(34),
          maximumSize: const Size.square(34),
          padding: EdgeInsets.zero,
          foregroundColor: colors.accentSoft,
          backgroundColor: colors.surfaceAlt,
          side: BorderSide(color: colors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        icon: Icon(
          expanded
              ? Icons.keyboard_double_arrow_right_rounded
              : Icons.keyboard_double_arrow_left_rounded,
          size: 20,
        ),
      ),
    );
  }
}

class _InspectorTabButton extends StatelessWidget {
  const _InspectorTabButton({
    required this.tab,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onPressed,
  });
  final InspectorTab tab;
  final bool selected;
  final StudioIconData icon;
  final String label;
  final ValueChanged<InspectorTab> onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Tooltip(
      message: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => onPressed(tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? context.studioColors.selectedSurfaceStrong
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StudioIcon(
                icon,
                size: 16,
                color: selected
                    ? context.studioColors.accentSoft
                    : context.studioColors.textMuted,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: selected
                      ? context.studioColors.textPrimary
                      : context.studioColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SmartPathPanel extends StatelessWidget {
  const _SmartPathPanel({required this.cubit});

  final EditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = cubit.autoPathResult!;
    return _InspectorSectionCard(
      key: const ValueKey('inspector-section-smart-path'),
      title: l10n.autoPathSections,
      icon: StudioIconData.autoPath,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.studioColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 14,
              color: context.studioColors.accent,
            ),
            const SizedBox(width: 4),
            Text(
              l10n.autoPathApplied,
              style: TextStyle(
                color: context.studioColors.accentSoft,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
      child: Semantics(
        liveRegion: true,
        label: l10n.autoPathResultSemantics(
          result.sectionCount,
          result.pathCount,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.autoPathAppliedDescription,
              style: TextStyle(
                color: context.studioColors.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 7.0;
                final width = (constraints.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    _AutoPathMetric(
                      width: width,
                      icon: Icons.grid_view_rounded,
                      value: result.sectionCount,
                      label: l10n.sections,
                    ),
                    _AutoPathMetric(
                      width: width,
                      icon: Icons.route_outlined,
                      value: result.pathCount,
                      label: l10n.autoPathPaths,
                    ),
                    _AutoPathMetric(
                      width: width,
                      icon: Icons.gesture_rounded,
                      value: result.handSectionCount,
                      label: l10n.autoPathHandDraw,
                    ),
                    _AutoPathMetric(
                      width: width,
                      icon: Icons.layers_outlined,
                      value: result.revealSectionCount,
                      label: l10n.reveal,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 10),
            Divider(height: 1, color: context.studioColors.border),
            const SizedBox(height: 9),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                _AutoPathDetail(
                  label: l10n.textKind,
                  value: result.textSectionCount,
                ),
                _AutoPathDetail(
                  label: l10n.artworkKind,
                  value: result.artworkSectionCount,
                ),
                if (result.nativeVectorCount > 0)
                  _AutoPathDetail(
                    label: l10n.autoPathNativeVectors,
                    value: result.nativeVectorCount,
                  ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  Icons.playlist_play_rounded,
                  size: 16,
                  color: context.studioColors.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.autoPathTimelineReady,
                    style: TextStyle(
                      color: context.studioColors.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartPathReviewPanel extends StatelessWidget {
  const _SmartPathReviewPanel({required this.cubit});

  final EditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final candidates = cubit.smartSections
        .where((section) => section.isSuspectedFrame)
        .toList(growable: false);
    return _InspectorSectionCard(
      key: const ValueKey('inspector-section-smart-path-review'),
      title: l10n.autoPathReview,
      icon: StudioIconData.autoPath,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: context.studioColors.warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          l10n.experimental,
          style: TextStyle(
            color: context.studioColors.warning,
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      child: Semantics(
        liveRegion: true,
        label: l10n.suspectedFrameCount(candidates.length),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.suspectedFrameDescription,
              style: TextStyle(
                color: context.studioColors.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            for (final candidate in candidates) ...[
              Row(
                children: [
                  Icon(
                    Icons.crop_square_rounded,
                    size: 17,
                    color: context.studioColors.warning,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${candidate.label} · ${(candidate.artifactConfidence * 100).round()}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    key: ValueKey('toggle-suspected-frame-${candidate.id}'),
                    onPressed: () => cubit.setSmartSectionMode(
                      candidate.id,
                      candidate.mode == SmartSectionMode.ignore
                          ? SmartSectionMode.handDraw
                          : SmartSectionMode.ignore,
                    ),
                    child: Text(
                      candidate.mode == SmartSectionMode.ignore
                          ? l10n.restoreFrame
                          : l10n.excludeFrame,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('discard-smart-path-review'),
                    onPressed: cubit.clearSmartPathSuggestions,
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('apply-smart-path-review'),
                    onPressed: cubit.applySmartPathSuggestions,
                    child: Text(l10n.apply),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AutoPathMetric extends StatelessWidget {
  const _AutoPathMetric({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });

  final double width;
  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
    decoration: BoxDecoration(
      color: context.studioColors.surfaceElevated,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.studioColors.border),
    ),
    child: Row(
      children: [
        Icon(icon, size: 16, color: context.studioColors.accentSoft),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  color: context.studioColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: context.studioColors.textMuted,
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AutoPathDetail extends StatelessWidget {
  const _AutoPathDetail({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: context.studioColors.accent,
          shape: BoxShape.circle,
        ),
      ),
      const SizedBox(width: 5),
      Text(
        '$label $value',
        style: TextStyle(
          color: context.studioColors.textSecondary,
          fontSize: 10.5,
        ),
      ),
    ],
  );
}

TextStyle _sectionStyle(BuildContext context) => TextStyle(
  color: context.studioColors.textMuted,
  fontSize: 11,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.1,
);

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: context.studioColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _MotionSpeedControls extends StatelessWidget {
  const _MotionSpeedControls({
    required this.cubit,
    required this.project,
    required this.onDrawingSpeedChanged,
    required this.onPenTravelSpeedChanged,
    required this.onFitToDuration,
    required this.onTimingChangeStart,
    required this.onTimingChangeEnd,
    this.compact = false,
  });

  final EditorCubit cubit;
  final HandDrawProject project;
  final ValueChanged<double>? onDrawingSpeedChanged;
  final ValueChanged<double>? onPenTravelSpeedChanged;
  final VoidCallback? onFitToDuration;
  final VoidCallback onTimingChangeStart;
  final VoidCallback onTimingChangeEnd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final speed = project.drawingSpeed;
    const presets = [0.5, 1.0, 2.0, 4.0];
    final selected = presets.where((value) => (value - speed).abs() < 0.001);
    return Column(
      children: [
        _LabeledSlider(
          label: context.l10n.globalDrawingSpeed,
          valueLabel: '${speed.toStringAsFixed(2)}×',
          value: speed,
          min: minimumProjectDrawingSpeed,
          max: maximumProjectDrawingSpeed,
          divisions: 155,
          onChanged: onDrawingSpeedChanged,
          onChangeStart: onDrawingSpeedChanged == null
              ? null
              : (_) {
                  onTimingChangeStart();
                  cubit.beginSectionTimingEdit();
                },
          onChangeEnd: onDrawingSpeedChanged == null
              ? null
              : (_) {
                  cubit.commitSectionTimingEdit();
                  onTimingChangeEnd();
                },
        ),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<double>(
            segments: const [
              ButtonSegment(value: 0.5, label: Text('0.5×')),
              ButtonSegment(value: 1, label: Text('1×')),
              ButtonSegment(value: 2, label: Text('2×')),
              ButtonSegment(value: 4, label: Text('4×')),
            ],
            selected: selected.toSet(),
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -2, vertical: -3),
            ),
            onSelectionChanged: onDrawingSpeedChanged == null
                ? null
                : (selection) {
                    if (selection.isEmpty) return;
                    onTimingChangeStart();
                    cubit.beginSectionTimingEdit();
                    onDrawingSpeedChanged!(selection.first);
                    cubit.commitSectionTimingEdit();
                    onTimingChangeEnd();
                  },
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 4),
          _InfoRow(
            label: context.l10n.drawingTime,
            value:
                '${resolveProjectTimeline(project).breakdown.drawingSeconds.toStringAsFixed(2)} s',
          ),
          const Divider(height: 22),
        ],
        _LabeledSlider(
          label: context.l10n.penTravelSpeed,
          valueLabel: '${project.penTravelSpeed.toStringAsFixed(2)}×',
          value: project.penTravelSpeed,
          min: 0.25,
          max: 3,
          divisions: 55,
          onChanged: onPenTravelSpeedChanged,
          onChangeStart: onPenTravelSpeedChanged == null
              ? null
              : (_) {
                  onTimingChangeStart();
                  cubit.beginSectionTimingEdit();
                },
          onChangeEnd: onPenTravelSpeedChanged == null
              ? null
              : (_) {
                  cubit.commitSectionTimingEdit();
                  onTimingChangeEnd();
                },
        ),
        if (!compact)
          _InfoRow(
            label: context.l10n.penTravelTime,
            value:
                '${resolveProjectTimeline(project).breakdown.penTravelSeconds.toStringAsFixed(2)} s',
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            key: const ValueKey('fit-to-duration-button'),
            onPressed: onFitToDuration,
            icon: const Icon(Icons.fit_screen_rounded, size: 18),
            label: Text(context.l10n.fitToDuration),
          ),
        ),
      ],
    );
  }
}

class _CustomExportResolutionFields extends StatefulWidget {
  const _CustomExportResolutionFields({
    required this.width,
    required this.height,
    required this.enabled,
    required this.onApply,
  });

  final int width;
  final int height;
  final bool enabled;
  final bool Function(int width, int height) onApply;

  @override
  State<_CustomExportResolutionFields> createState() =>
      _CustomExportResolutionFieldsState();
}

class _CustomExportResolutionFieldsState
    extends State<_CustomExportResolutionFields> {
  final _formKey = GlobalKey<FormState>();
  final _widthFocus = FocusNode();
  final _heightFocus = FocusNode();
  late final TextEditingController _widthController;
  late final TextEditingController _heightController;

  @override
  void initState() {
    super.initState();
    _widthController = TextEditingController(text: '${widget.width}');
    _heightController = TextEditingController(text: '${widget.height}');
  }

  @override
  void didUpdateWidget(covariant _CustomExportResolutionFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.width != widget.width && !_widthFocus.hasFocus) {
      _widthController.text = '${widget.width}';
    }
    if (oldWidget.height != widget.height && !_heightFocus.hasFocus) {
      _heightController.text = '${widget.height}';
    }
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    _widthFocus.dispose();
    _heightFocus.dispose();
    super.dispose();
  }

  int? _parse(TextEditingController controller) =>
      int.tryParse(controller.text.trim());

  bool get _hasChanges =>
      _parse(_widthController) != widget.width ||
      _parse(_heightController) != widget.height;

  String? _validate(BuildContext context, String? raw) {
    final value = int.tryParse(raw?.trim() ?? '');
    if (value == null || !ExportResolutionPolicy.isValidDimension(value)) {
      return context.l10n.customResolutionRange(
        ExportResolutionPolicy.minDimension,
        ExportResolutionPolicy.maxDimension,
      );
    }
    return null;
  }

  void _apply() {
    if (!_formKey.currentState!.validate()) return;
    final width = _parse(_widthController)!;
    final height = _parse(_heightController)!;
    if (widget.onApply(width, height)) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('custom-export-width'),
                controller: _widthController,
                focusNode: _widthFocus,
                enabled: widget.enabled,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  labelText: context.l10n.customWidth,
                  suffixText: context.l10n.pixelsUnit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) => _validate(context, value),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _apply(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                key: const ValueKey('custom-export-height'),
                controller: _heightController,
                focusNode: _heightFocus,
                enabled: widget.enabled,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: InputDecoration(
                  labelText: context.l10n.customHeight,
                  suffixText: context.l10n.pixelsUnit,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) => _validate(context, value),
                onChanged: (_) => setState(() {}),
                onFieldSubmitted: (_) => _apply(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: const ValueKey('apply-custom-export-resolution'),
          onPressed: widget.enabled && _hasChanges ? _apply : null,
          icon: const Icon(Icons.aspect_ratio_rounded, size: 17),
          label: Text(context.l10n.applyResolution),
        ),
      ],
    ),
  );
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;
  final int? divisions;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Flexible(
              child: Text(
                valueLabel,
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.studioColors.textMuted),
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeStart: onChanged == null ? null : onChangeStart,
          onChangeEnd: onChanged == null ? null : onChangeEnd,
        ),
      ],
    );
  }
}

class _AdvancedTimingPanel extends StatelessWidget {
  const _AdvancedTimingPanel({
    required this.cubit,
    required this.enabled,
    required this.voicePlayheadSeconds,
  });

  final EditorCubit cubit;
  final bool enabled;
  final double voicePlayheadSeconds;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = buildTimelineSections(cubit.project.strokes);
    final customized = sections
        .where((section) => !cubit.sectionTiming(section.key).isDefault)
        .length;
    return Material(
      type: MaterialType.transparency,
      child: ExpansionTile(
        key: const PageStorageKey('advanced-timing-panel'),
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.schedule, size: 19),
        title: Text(l10n.advancedTiming),
        subtitle: Text(
          customized == 0
              ? l10n.advancedTimingDescription
              : l10n.sectionsCustomized(customized),
          style: TextStyle(color: context.studioColors.textMuted, fontSize: 11),
        ),
        children: [
          for (final section in sections)
            _SectionTimingCard(
              cubit: cubit,
              section: section,
              enabled: enabled,
              voicePlayheadSeconds: voicePlayheadSeconds,
            ),
        ],
      ),
    );
  }
}

class _SectionTimingCard extends StatelessWidget {
  const _SectionTimingCard({
    required this.cubit,
    required this.section,
    required this.enabled,
    required this.voicePlayheadSeconds,
  });

  final EditorCubit cubit;
  final TimelineSectionDefinition section;
  final bool enabled;
  final double voicePlayheadSeconds;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final timing = cubit.sectionTiming(section.key);
    final canEdit = enabled;
    final cueResolution = resolveProjectTimeline(
      cubit.project,
    ).voiceCues[section.key];
    final resolvedPauseBefore =
        cueResolution?.resolvedPauseBeforeSeconds ?? timing.pauseBeforeSeconds;
    final hasVoiceGuide = cubit.voiceGuide != null;
    final hasCue = timing.voiceCueSeconds != null;
    final selected = cubit.selectedTimingSectionKey == section.key;
    return Card(
      margin: const EdgeInsets.only(bottom: 7),
      color: selected
          ? context.studioColors.selectedSurface
          : context.studioColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected
              ? context.studioColors.accent
              : context.studioColors.accent.withValues(alpha: 0),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ExpansionTile(
          key: PageStorageKey('section-timing-${section.key}'),
          title: Text(
            '${section.index + 1}. ${section.label}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${resolvedPauseBefore.toStringAsFixed(2)}s before • '
            '${timing.pauseAfterSeconds.toStringAsFixed(2)}s after • '
            '${timing.speedMultiplier.toStringAsFixed(2)}×',
            style: TextStyle(
              color: context.studioColors.textMuted,
              fontSize: 10,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          onExpansionChanged: (expanded) {
            if (expanded) cubit.selectTimingSection(section.key);
          },
          children: [
            if (hasVoiceGuide) ...[
              _VoiceCuePanel(
                cueSeconds: timing.voiceCueSeconds,
                playheadSeconds: voicePlayheadSeconds,
                hasConflict: cueResolution?.hasConflict ?? false,
                lateBySeconds: cueResolution?.lateBySeconds ?? 0,
                enabled: canEdit,
                onSetHere: () =>
                    cubit.setSectionVoiceCue(section.key, voicePlayheadSeconds),
                onClear: hasCue
                    ? () => cubit.clearSectionVoiceCue(section.key)
                    : null,
                onNudge: (delta) =>
                    cubit.nudgeSectionVoiceCue(section.key, delta),
              ),
              const SizedBox(height: 8),
            ],
            _LabeledSlider(
              label: l10n.pauseBefore,
              valueLabel: hasCue
                  ? '${resolvedPauseBefore.toStringAsFixed(2)} s • from Voice Cue'
                  : '${timing.pauseBeforeSeconds.toStringAsFixed(2)} s',
              value: resolvedPauseBefore.clamp(0.0, 10.0),
              min: 0,
              max: 10,
              divisions: 1000,
              onChangeStart: (_) => cubit.beginSectionTimingEdit(),
              onChanged: canEdit && !hasCue
                  ? (value) => cubit.setSectionPauseBefore(section.key, value)
                  : null,
              onChangeEnd: (_) => cubit.commitSectionTimingEdit(),
            ),
            _LabeledSlider(
              label: l10n.pauseAfter,
              valueLabel: '${timing.pauseAfterSeconds.toStringAsFixed(2)} s',
              value: timing.pauseAfterSeconds.clamp(0.0, 10.0),
              min: 0,
              max: 10,
              divisions: 1000,
              onChangeStart: (_) => cubit.beginSectionTimingEdit(),
              onChanged: canEdit
                  ? (value) => cubit.setSectionPauseAfter(section.key, value)
                  : null,
              onChangeEnd: (_) => cubit.commitSectionTimingEdit(),
            ),
            _LabeledSlider(
              label: l10n.drawingSpeed,
              valueLabel: '${timing.speedMultiplier.toStringAsFixed(2)}×',
              value: timing.speedMultiplier.clamp(0.25, 3.0),
              min: 0.25,
              max: 3,
              divisions: 11,
              onChangeStart: (_) => cubit.beginSectionTimingEdit(),
              onChanged: canEdit
                  ? (value) => cubit.setSectionSpeed(section.key, value)
                  : null,
              onChangeEnd: (_) => cubit.commitSectionTimingEdit(),
            ),
            Material(
              type: MaterialType.transparency,
              child: SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n.keepHandVisible),
                subtitle: Text(
                  l10n.pauseSoundDescription,
                  style: TextStyle(
                    color: context.studioColors.textMuted,
                    fontSize: 10,
                  ),
                ),
                value:
                    timing.pauseHandBehavior == PauseHandBehavior.keepVisible,
                onChanged: !canEdit
                    ? null
                    : (value) => cubit.setSectionPauseHandBehavior(
                        section.key,
                        value
                            ? PauseHandBehavior.keepVisible
                            : PauseHandBehavior.hide,
                      ),
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: !canEdit || timing.isDefault
                    ? null
                    : () => cubit.resetSectionTiming(section.key),
                icon: const Icon(Icons.restart_alt, size: 16),
                label: Text(l10n.resetSection),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VoiceCuePanel extends StatelessWidget {
  const _VoiceCuePanel({
    required this.cueSeconds,
    required this.playheadSeconds,
    required this.hasConflict,
    required this.lateBySeconds,
    required this.enabled,
    required this.onSetHere,
    required this.onClear,
    required this.onNudge,
  });

  final double? cueSeconds;
  final double playheadSeconds;
  final bool hasConflict;
  final double lateBySeconds;
  final bool enabled;
  final VoidCallback onSetHere;
  final VoidCallback? onClear;
  final ValueChanged<double> onNudge;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cue = cueSeconds;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: hasConflict
            ? context.studioColors.dangerContainer
            : context.studioColors.accentContainer,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: hasConflict
              ? context.studioColors.danger
              : context.studioColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                size: 17,
                color: context.studioColors.accentSoft,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.voiceCue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                cue == null ? l10n.notLinked : _cueTime(cue),
                maxLines: 1,
                style: TextStyle(
                  color: cue == null
                      ? context.studioColors.textMuted
                      : context.studioColors.warning,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const ValueKey('start-section-here-button'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 36),
            ),
            onPressed: enabled ? onSetHere : null,
            icon: const Icon(Icons.add_location_alt_outlined, size: 17),
            label: Text(l10n.startSectionHere(_cueTime(playheadSeconds))),
          ),
          if (cue != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  l10n.fineTune,
                  style: TextStyle(
                    color: context.studioColors.textMuted,
                    fontSize: 11,
                  ),
                ),
                const Spacer(),
                _NudgeButton(
                  label: '−1f',
                  onPressed: enabled ? () => onNudge(-1 / 30) : null,
                ),
                const SizedBox(width: 4),
                _NudgeButton(
                  label: '+1f',
                  onPressed: enabled ? () => onNudge(1 / 30) : null,
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: l10n.clearVoiceCue,
                  visualDensity: VisualDensity.compact,
                  onPressed: enabled ? onClear : null,
                  icon: const Icon(Icons.link_off_rounded, size: 17),
                ),
              ],
            ),
          ],
          if (hasConflict) ...[
            const SizedBox(height: 6),
            Text(
              l10n.cueConflict(lateBySeconds.toStringAsFixed(2)),
              style: TextStyle(
                color: context.studioColors.dangerSoft,
                fontSize: 10.5,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(42, 28),
      padding: const EdgeInsets.symmetric(horizontal: 7),
      visualDensity: VisualDensity.compact,
    ),
    onPressed: onPressed,
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}

class _ArtworkPlacementControls extends StatelessWidget {
  const _ArtworkPlacementControls({
    required this.cubit,
    required this.readOnly,
  });

  final EditorCubit cubit;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final placement = cubit.artworkPlacement!;
    final rect = placement.destination;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.importBehavior,
          style: TextStyle(
            color: context.studioColors.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<ArtworkImportIntent>(
            key: const ValueKey('artwork-intent-selector'),
            segments: [
              ButtonSegment(
                value: ArtworkImportIntent.fullScene,
                icon: const Icon(Icons.crop_free_rounded, size: 16),
                label: Text(l10n.fullScene),
              ),
              ButtonSegment(
                value: ArtworkImportIntent.element,
                icon: const Icon(Icons.select_all_rounded, size: 16),
                label: Text(l10n.singleElement),
              ),
            ],
            selected: {placement.importIntent},
            showSelectedIcon: false,
            style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2),
            ),
            onSelectionChanged: readOnly
                ? null
                : (selection) {
                    if (selection.isNotEmpty) {
                      cubit.setArtworkImportIntent(selection.first);
                    }
                  },
          ),
        ),
        const SizedBox(height: 5),
        Text(
          placement.importIntent == ArtworkImportIntent.fullScene
              ? l10n.fullSceneDescription
              : l10n.singleElementDescription,
          style: TextStyle(
            color: context.studioColors.textMuted,
            fontSize: 10.5,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<ArtworkPlacementMode>(
          key: ValueKey('artwork-mode-${placement.mode.name}'),
          initialValue: placement.mode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.artworkFit,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            DropdownMenuItem(
              value: ArtworkPlacementMode.fitEntire,
              child: Text(l10n.fitEntireImage),
            ),
            DropdownMenuItem(
              value: ArtworkPlacementMode.fitVisible,
              child: Text(l10n.fitVisibleContent),
            ),
            DropdownMenuItem(
              value: ArtworkPlacementMode.originalSize,
              child: Text(l10n.originalSize),
            ),
            DropdownMenuItem(
              value: ArtworkPlacementMode.fillCanvas,
              child: Text(l10n.fillCanvas),
            ),
          ],
          onChanged: readOnly
              ? null
              : (mode) async {
                  if (mode == null) return;
                  if (mode == ArtworkPlacementMode.fillCanvas) {
                    final approved = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(l10n.fillCanvas),
                        content: Text(l10n.fillCanvasWarning),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: Text(l10n.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(dialogContext, true),
                            child: Text(l10n.apply),
                          ),
                        ],
                      ),
                    );
                    if (approved != true) return;
                  }
                  cubit.applyArtworkPlacementMode(mode);
                },
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _PlacementQuickAction(
              key: const ValueKey('artwork-center-horizontal'),
              tooltip: l10n.centerHorizontal,
              icon: Icons.align_horizontal_center_rounded,
              onPressed: readOnly
                  ? null
                  : () => cubit.centerArtwork(vertical: false),
            ),
            const SizedBox(width: 6),
            _PlacementQuickAction(
              key: const ValueKey('artwork-center-vertical'),
              tooltip: l10n.centerVertical,
              icon: Icons.align_vertical_center_rounded,
              onPressed: readOnly
                  ? null
                  : () => cubit.centerArtwork(horizontal: false),
            ),
            const SizedBox(width: 6),
            _PlacementQuickAction(
              key: const ValueKey('artwork-reset-placement'),
              tooltip: l10n.resetPlacement,
              icon: Icons.restart_alt_rounded,
              onPressed: readOnly
                  ? null
                  : () => cubit.applyArtworkPlacementMode(
                      ArtworkPlacementMode.fitEntire,
                    ),
            ),
          ],
        ),
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: const ValueKey('artwork-position-details'),
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 2),
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            leading: const Icon(Icons.open_with_rounded, size: 18),
            title: Text(l10n.positionAndSize),
            subtitle: Text(
              l10n.positionAndSizeDescription,
              style: TextStyle(
                color: context.studioColors.textMuted,
                fontSize: 10,
              ),
            ),
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final fieldWidth = (constraints.maxWidth - 8) / 2;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _placementField(context, 'X', rect.left, fieldWidth, (
                        value,
                      ) {
                        final width = rect.right - rect.left;
                        return DocumentRect(
                          left: value,
                          top: rect.top,
                          right: value + width,
                          bottom: rect.bottom,
                        );
                      }),
                      _placementField(context, 'Y', rect.top, fieldWidth, (
                        value,
                      ) {
                        final height = rect.bottom - rect.top;
                        return DocumentRect(
                          left: rect.left,
                          top: value,
                          right: rect.right,
                          bottom: value + height,
                        );
                      }),
                      _placementField(
                        context,
                        'W',
                        rect.right - rect.left,
                        fieldWidth,
                        (value) {
                          final aspect =
                              (rect.right - rect.left) /
                              (rect.bottom - rect.top);
                          return DocumentRect(
                            left: rect.left,
                            top: rect.top,
                            right: rect.left + value,
                            bottom: rect.top + value / aspect,
                          );
                        },
                      ),
                      _placementField(
                        context,
                        'H',
                        rect.bottom - rect.top,
                        fieldWidth,
                        (value) {
                          final aspect =
                              (rect.right - rect.left) /
                              (rect.bottom - rect.top);
                          return DocumentRect(
                            left: rect.left,
                            top: rect.top,
                            right: rect.left + value * aspect,
                            bottom: rect.top + value,
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _placementField(
    BuildContext context,
    String label,
    double value,
    double width,
    DocumentRect Function(double value) update,
  ) => SizedBox(
    width: width,
    child: TextFormField(
      key: ValueKey('artwork-$label-${value.toStringAsFixed(2)}'),
      initialValue: value.toStringAsFixed(1),
      enabled: !readOnly,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onFieldSubmitted: (raw) {
        final parsed = double.tryParse(raw);
        if (parsed == null ||
            !parsed.isFinite ||
            (label == 'W' || label == 'H') && parsed <= 0) {
          return;
        }
        cubit.setArtworkPlacement(
          cubit.artworkPlacement!.copyWith(destination: update(parsed)),
        );
      },
    ),
  );
}

class _PlacementQuickAction extends StatelessWidget {
  const _PlacementQuickAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Tooltip(
      message: tooltip,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(32),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
        child: Icon(icon, size: 17),
      ),
    ),
  );
}

String _cueTime(double seconds) {
  final minutes = seconds ~/ 60;
  final remainder = seconds - minutes * 60;
  return '$minutes:${remainder.toStringAsFixed(2).padLeft(5, '0')}';
}
