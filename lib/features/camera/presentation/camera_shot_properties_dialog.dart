import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/camera/domain/policies/camera_timeline_editing_policy.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_shot_link_resolver.dart';
import 'package:handdraw_studio/features/camera/domain/services/camera_zoom_in_out_preset_planner.dart';
import 'package:handdraw_studio/features/camera/domain/services/simple_camera_view_adapter.dart';
import 'package:handdraw_studio/features/camera/presentation/camera_zoom_preset_dialog.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_canvas.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/services/unified_project_frame_resolver.dart';

Future<void> showCameraShotPropertiesDialog({
  required BuildContext context,
  required EditorCubit editor,
  required CameraEditingCubit editing,
  required CameraShot shot,
}) => showDialog<void>(
  context: context,
  builder: (_) =>
      CameraShotPropertiesDialog(editor: editor, editing: editing, shot: shot),
);

class CameraShotPropertiesDialog extends StatefulWidget {
  const CameraShotPropertiesDialog({
    super.key,
    required this.editor,
    required this.editing,
    required this.shot,
  });

  final EditorCubit editor;
  final CameraEditingCubit editing;
  final CameraShot shot;

  @override
  State<CameraShotPropertiesDialog> createState() =>
      _CameraShotPropertiesDialogState();
}

class _CameraShotPropertiesDialogState extends State<CameraShotPropertiesDialog>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _label;
  late final TextEditingController _start;
  late final TextEditingController _duration;
  late double _movementSeconds;
  late double _holdSeconds;
  late SimpleCameraMovement _movement;
  bool _saveAsDefaults = false;
  String? _error;
  late final AnimationController _previewController;

  CameraShot get shot => widget.shot;
  CameraKeyframe? get frame => shot.keyframes.lastOrNull;
  bool get isSceneOwned => shot.ownerSceneId != null;
  bool get canEdit => !shot.isLocked;
  bool get _isPreviewing => _previewController.isAnimating;

  CameraShot get _draftShot {
    if (isSceneOwned) return shot;
    final startSeconds = double.tryParse(_start.text.trim());
    final durationSeconds = double.tryParse(_duration.text.trim());
    return shot.copyWith(
      startTime: startSeconds == null || startSeconds < 0
          ? shot.startTime
          : TimelineTime.fromMicroseconds(
              (startSeconds * Duration.microsecondsPerSecond).round(),
            ),
      duration: durationSeconds == null || durationSeconds <= 0
          ? shot.duration
          : TimelineDuration.fromMicroseconds(
              (durationSeconds * Duration.microsecondsPerSecond).round(),
            ),
    );
  }

  CameraShotLink get _link {
    final scene = shot.ownerSceneId == null
        ? null
        : widget.editor.state.document.scenes
              .where((item) => item.id == shot.ownerSceneId)
              .firstOrNull;
    return const CameraShotLinkResolver().resolve(
      shot: _draftShot,
      timelineSpans: _timelineContentSpans,
      ownedSectionIds: scene?.sectionIds.map((id) => id.value).toList(),
    );
  }

  List<CameraTimelineContentSpan> get _timelineContentSpans {
    final ranges = widget.editor.timelineSectionRanges;
    return [
      for (final sectionId in widget.editor.timelineSectionOrder)
        if (ranges[sectionId] case final range?)
          CameraTimelineContentSpan(
            id: sectionId,
            name: _sectionName(sectionId),
            start: TimelineTime.fromMicroseconds(
              (range.startSeconds * Duration.microsecondsPerSecond).round(),
            ),
            end: TimelineTime.fromMicroseconds(
              (range.endSeconds * Duration.microsecondsPerSecond).round(),
            ),
          ),
    ];
  }

  String _sectionName(String sectionId) {
    for (final section in widget.editor.smartSections) {
      if (section.id == sectionId) return section.label;
    }
    for (final stroke in widget.editor.project.strokes) {
      final key = stroke.sectionId ?? 'stroke:${stroke.id}';
      if (key == sectionId) return stroke.name;
    }
    for (final section in widget.editor.state.document.sections) {
      if (section.id.value == sectionId) return section.name;
    }
    return sectionId;
  }

  List<Rect> get _linkedSectionBounds => [
    for (final sectionId in _link.sectionIds)
      ?widget.editor.timelineSectionBounds(sectionId),
  ];

  String _text(String en, String ar) =>
      Directionality.of(context) == TextDirection.rtl ? ar : en;

  @override
  void initState() {
    super.initState();
    _label = TextEditingController(text: shot.label ?? '');
    _start = TextEditingController(text: _seconds(shot.startTime.microseconds));
    _duration = TextEditingController(
      text: _seconds(shot.duration.microseconds),
    );
    final transition = frame?.incomingTransition ?? const CameraTransition();
    _movementSeconds =
        transition.duration.microseconds / Duration.microsecondsPerSecond;
    _holdSeconds = math.max(
      .1,
      (shot.duration.microseconds - transition.duration.microseconds) /
          Duration.microsecondsPerSecond,
    );
    _movement = switch (transition.type) {
      CameraTransitionType.cut => SimpleCameraMovement.cut,
      CameraTransitionType.move when transition.easing == CameraEasing.linear =>
        SimpleCameraMovement.linear,
      _ => SimpleCameraMovement.ease,
    };
    _previewController =
        AnimationController(
            vsync: this,
            duration: Duration(
              microseconds: math.max(1, shot.duration.microseconds),
            ),
          )
          ..addListener(_refreshPreview)
          ..addStatusListener((_) => _refreshPreview());
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  String _seconds(int microseconds) =>
      (microseconds / Duration.microsecondsPerSecond).toStringAsFixed(2);

  @override
  void dispose() {
    _previewController
      ..removeListener(_refreshPreview)
      ..dispose();
    _label.dispose();
    _start.dispose();
    _duration.dispose();
    super.dispose();
  }

  void _togglePreview() {
    if (_previewController.isAnimating) {
      _previewController.stop();
      return;
    }
    if (_previewController.isCompleted) _previewController.value = 0;
    _previewController.forward();
  }

  ResolvedProjectFrame _resolvedPreviewFrame() {
    final timeline = widget.editor.compileTimeline();
    final durationUs = shot.duration.microseconds;
    // Shot ends are exclusive. Sampling the exact endpoint could resolve the
    // next camera clip instead of the selected clip's final visible frame.
    final maximumElapsedUs = math.max(0, durationUs - 1);
    final elapsedUs = math.min(
      maximumElapsedUs,
      (durationUs * _previewController.value).round(),
    );
    final absoluteTime = TimelineTime.fromMicroseconds(
      shot.startTime.microseconds + elapsedUs,
    ).clampTo(timeline.duration);
    return const UnifiedProjectFrameResolver().resolveForPreview(
      timeline,
      absoluteTime,
    );
  }

  void _editFrame(CameraKeyframe selected) {
    widget.editing.selectKeyframe(shot.id, selected.id);
    widget.editing.restoreEditorView(selected.view);
    widget.editing.setCanvasMode(CameraCanvasMode.editCamera);
    Navigator.pop(context);
  }

  bool _save() {
    final startSeconds = double.tryParse(_start.text.trim());
    final durationSeconds = double.tryParse(_duration.text.trim());
    if (startSeconds == null ||
        durationSeconds == null ||
        startSeconds < 0 ||
        durationSeconds * Duration.microsecondsPerSecond <
            CameraTimelineEditingPolicy.minimumShotDuration.microseconds) {
      setState(
        () => _error = _text('Enter valid timing', 'أدخل توقيتًا صحيحًا'),
      );
      return false;
    }
    final requestedDuration = TimelineDuration.fromMicroseconds(
      (durationSeconds * Duration.microsecondsPerSecond).round(),
    );
    final effectiveMovementSeconds = _movement == SimpleCameraMovement.cut
        ? 0.0
        : _movementSeconds;
    _holdSeconds = math.max(.1, durationSeconds - effectiveMovementSeconds);
    var updated = widget.editor.updateCameraShotInspector(
      shotId: shot.id,
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
      duration: isSceneOwned ? shot.duration : requestedDuration,
      locked: shot.isLocked,
    );
    if (!updated) return false;
    if (!isSceneOwned) {
      final requestedStart = TimelineTime.fromMicroseconds(
        (startSeconds * Duration.microsecondsPerSecond).round(),
      );
      if (requestedStart != shot.startTime) {
        updated = widget.editor.moveCameraShots({shot.id: requestedStart});
      }
      if (!updated) return false;
      updated = widget.editor.updateSimpleCameraViewTiming(
        shotId: shot.id,
        movement: _movement,
        movementDuration: TimelineDuration.fromMicroseconds(
          ((_movement == SimpleCameraMovement.cut ? 0 : _movementSeconds) *
                  Duration.microsecondsPerSecond)
              .round(),
        ),
        holdDuration: TimelineDuration.fromMicroseconds(
          (_holdSeconds * Duration.microsecondsPerSecond).round(),
        ),
      );
      if (updated && _saveAsDefaults) {
        widget.editing.setShotDefaults(
          CameraShotDefaults(
            movement: _movement,
            movementDuration: Duration(
              microseconds: (_movement == SimpleCameraMovement.cut
                  ? 0
                  : (_movementSeconds * Duration.microsecondsPerSecond)
                        .round()),
            ),
            holdDuration: Duration(
              microseconds: (_holdSeconds * Duration.microsecondsPerSecond)
                  .round(),
            ),
          ),
        );
      }
    }
    return updated;
  }

  void _syncDurationFromTiming() {
    final move = _movement == SimpleCameraMovement.cut ? 0 : _movementSeconds;
    _duration.text = (move + _holdSeconds).toStringAsFixed(2);
  }

  Future<void> _applyZoomPreset() async {
    final settings = await showDialog<CameraZoomPresetSettings>(
      context: context,
      builder: (_) => CameraZoomPresetDialog(totalDuration: shot.duration),
    );
    if (settings == null || !mounted) return;
    final previousIds =
        widget.editor.state.document.cameraTrack?.shots
            .map((item) => item.id)
            .toSet() ??
        const <CameraShotId>{};
    final focus = frame?.view ?? widget.editing.state.editorView;
    final applied = widget.editor.applyCameraZoomInOutPreset(
      sourceShotId: shot.id,
      startTime: shot.startTime,
      totalDuration: shot.duration,
      focusView: focus,
      strength: settings.strength,
      zoomInDuration: settings.zoomInDuration,
      zoomOutDuration: settings.zoomOutDuration,
      wideLabel: _text('Wide', 'مشهد كامل'),
      zoomInLabel: _text('Zoom In', 'تقريب'),
      zoomOutLabel: _text('Zoom Out', 'إبعاد'),
    );
    if (!applied || !mounted) return;
    final created =
        widget.editor.state.document.cameraTrack?.shots
            .where((item) => !previousIds.contains(item.id))
            .toList()
          ?..sort((a, b) => a.startTime.compareTo(b.startTime));
    if (created != null && created.length >= 2) {
      final close = created[1];
      widget.editing.selectKeyframe(close.id, close.keyframes.last.id);
      widget.editing.restoreEditorView(close.keyframes.last.view);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final view = frame?.view ?? const CameraView.identity();
    final canvas = Size(
      widget.editor.project.canvasWidth.toDouble(),
      widget.editor.project.canvasHeight.toDouble(),
    );
    final outputAspect = canvas.width / canvas.height;
    final viewportHeight = view.normalizedViewportHeightFor(
      projectAspectRatio: outputAspect,
      outputAspectRatio: outputAspect,
    );
    return Dialog(
      key: const ValueKey('camera-shot-properties-dialog'),
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 680),
        child: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.videocam_outlined, color: colors.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _text('Camera shot properties', 'خصائص لقطة الكاميرا'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: _text('Close', 'إغلاق'),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    text: _text('Frame', 'الإطار'),
                    icon: const Icon(Icons.crop_free),
                  ),
                  Tab(
                    text: _text('Timing & motion', 'الحركة والتوقيت'),
                    icon: const Icon(Icons.motion_photos_on_outlined),
                  ),
                  Tab(
                    text: _text('Zoom', 'التقريب'),
                    icon: const Icon(Icons.zoom_out_map),
                  ),
                  Tab(
                    text: _text('Link', 'الارتباط'),
                    icon: const Icon(Icons.link),
                  ),
                  Tab(
                    text: _text('Preview', 'المعاينة'),
                    icon: const Icon(Icons.play_circle_outline),
                  ),
                ],
              ),
              Divider(height: 1, color: colors.border),
              Expanded(
                child: TabBarView(
                  children: [
                    _frameTab(view, viewportHeight, canvas),
                    _timingTab(),
                    _zoomTab(),
                    _linkTab(),
                    _previewTab(),
                  ],
                ),
              ),
              Divider(height: 1, color: colors.border),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    if (_error != null)
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(color: colors.danger),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(_text('Cancel', 'إلغاء')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const ValueKey('camera-shot-properties-save'),
                      onPressed: canEdit
                          ? () {
                              if (_save()) Navigator.pop(context);
                            }
                          : null,
                      icon: const Icon(Icons.check),
                      label: Text(_text('Save', 'حفظ')),
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

  Widget _frameTab(CameraView view, double viewportHeight, Size canvas) =>
      _tabPadding(
        ListView(
          children: [
            _CameraShotPreview(
              image: widget.editor.drawingImage,
              view: view,
              aspectRatio: canvas.width / canvas.height,
              projectSize: canvas,
              artworkDestination: widget.editor.project.artworkDestination,
              visibleArtworkBounds: _linkedSectionBounds,
              height: 230,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metric(
                  _text('Center X', 'المركز X'),
                  view.centerX.toStringAsFixed(3),
                ),
                _metric(
                  _text('Center Y', 'المركز Y'),
                  view.centerY.toStringAsFixed(3),
                ),
                _metric(
                  _text('Width', 'العرض'),
                  '${(view.viewportWidth * canvas.width).round()} px',
                ),
                _metric(
                  _text('Height', 'الارتفاع'),
                  '${(viewportHeight * canvas.height).round()} px',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('camera-properties-edit-start-frame'),
                  onPressed: !canEdit || shot.keyframes.isEmpty
                      ? null
                      : () => _editFrame(shot.keyframes.first),
                  icon: const Icon(Icons.first_page),
                  label: Text(_text('Edit start frame', 'تعديل إطار البداية')),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('camera-properties-edit-end-frame'),
                  onPressed: !canEdit || shot.keyframes.isEmpty
                      ? null
                      : () => _editFrame(shot.keyframes.last),
                  icon: const Icon(Icons.last_page),
                  label: Text(_text('Edit end frame', 'تعديل إطار النهاية')),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _timingTab() => _tabPadding(
    ListView(
      children: [
        TextField(
          key: const ValueKey('camera-properties-label'),
          controller: _label,
          enabled: canEdit,
          decoration: InputDecoration(
            labelText: _text('Shot name', 'اسم اللقطة'),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<SimpleCameraMovement>(
          key: const ValueKey('camera-properties-movement'),
          initialValue: _movement,
          decoration: InputDecoration(
            labelText: _text('Movement', 'نوع الحركة'),
          ),
          items: [
            DropdownMenuItem(
              value: SimpleCameraMovement.cut,
              child: Text(_text('Cut', 'قطع')),
            ),
            DropdownMenuItem(
              value: SimpleCameraMovement.linear,
              child: Text(_text('Linear', 'خطي')),
            ),
            DropdownMenuItem(
              value: SimpleCameraMovement.ease,
              child: Text(_text('Smooth', 'ناعم')),
            ),
          ],
          onChanged: canEdit && !isSceneOwned
              ? (value) => setState(() {
                  _movement = value ?? _movement;
                  if (_movement != SimpleCameraMovement.cut &&
                      _movementSeconds == 0) {
                    _movementSeconds = .6;
                  }
                  _syncDurationFromTiming();
                })
              : null,
        ),
        const SizedBox(height: 16),
        _secondsSlider(
          key: const ValueKey('camera-properties-movement-duration'),
          label: _text('Movement duration', 'مدة الحركة'),
          value: _movement == SimpleCameraMovement.cut ? 0 : _movementSeconds,
          maximum: math.max(
            1,
            shot.duration.microseconds / Duration.microsecondsPerSecond,
          ),
          enabled:
              canEdit && !isSceneOwned && _movement != SimpleCameraMovement.cut,
          onChanged: (value) => setState(() {
            _movementSeconds = value;
            _syncDurationFromTiming();
          }),
        ),
        _secondsSlider(
          key: const ValueKey('camera-properties-hold-duration'),
          label: _text('Hold duration', 'مدة التوقف'),
          value: _holdSeconds,
          maximum: math.max(
            1,
            shot.duration.microseconds / Duration.microsecondsPerSecond,
          ),
          enabled: canEdit && !isSceneOwned,
          onChanged: (value) => setState(() {
            _holdSeconds = value;
            _syncDurationFromTiming();
          }),
        ),
        CheckboxListTile(
          key: const ValueKey('camera-properties-save-defaults'),
          contentPadding: EdgeInsets.zero,
          value: _saveAsDefaults,
          onChanged: canEdit && !isSceneOwned
              ? (value) => setState(() => _saveAsDefaults = value ?? false)
              : null,
          title: Text(
            _text(
              'Use these timing values for new camera shots',
              'استخدم قيم التوقيت هذه للقطات الكاميرا الجديدة',
            ),
          ),
        ),
      ],
    ),
  );

  Widget _zoomTab() => _tabPadding(
    ListView(
      children: [
        Icon(Icons.zoom_out_map, size: 48, color: context.studioColors.accent),
        const SizedBox(height: 12),
        Text(
          _text(
            'Create a professional Zoom In then Out movement from this shot. The generated camera blocks keep the same total duration.',
            'أنشئ حركة تقريب ثم إبعاد احترافية انطلاقًا من هذه اللقطة، مع الحفاظ على المدة الإجمالية نفسها في بلوكات الكاميرا الناتجة.',
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Center(
          child: FilledButton.tonalIcon(
            key: const ValueKey('camera-properties-zoom-preset'),
            onPressed:
                canEdit &&
                    !isSceneOwned &&
                    shot.duration.microseconds >=
                        CameraZoomInOutPresetPlanner
                            .minimumTotalDuration
                            .microseconds
                ? _applyZoomPreset
                : null,
            icon: const Icon(Icons.auto_awesome_motion),
            label: Text(_text('Zoom In then Out…', 'تقريب ثم إبعاد…')),
          ),
        ),
      ],
    ),
  );

  Widget _linkTab() => _tabPadding(
    ListView(
      children: [
        _infoRow(
          Icons.movie_outlined,
          _text('Linked scene', 'المشهد المرتبط'),
          _link.displayName(
            isArabic: Directionality.of(context) == TextDirection.rtl,
          ),
        ),
        _infoRow(
          Icons.schedule,
          _text('Start', 'البداية'),
          '${_seconds(_draftShot.startTime.microseconds)} s',
        ),
        _infoRow(
          Icons.flag_outlined,
          _text('End', 'النهاية'),
          '${_seconds(_draftShot.endTime.microseconds)} s',
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('camera-properties-start'),
          controller: _start,
          enabled: canEdit && !isSceneOwned,
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _text('Start time (seconds)', 'وقت البداية (ثانية)'),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('camera-properties-duration'),
          controller: _duration,
          enabled: canEdit && !isSceneOwned,
          textDirection: TextDirection.ltr,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: _text(
              'Total duration (seconds)',
              'المدة الكلية (ثانية)',
            ),
          ),
        ),
        if (isSceneOwned) ...[
          const SizedBox(height: 14),
          Text(
            _text(
              'This shot follows its scene boundaries. Change the scene timing to move or resize it.',
              'هذه اللقطة تتبع حدود المشهد. غيّر توقيت المشهد لنقلها أو تعديل مدتها.',
            ),
            style: TextStyle(color: context.studioColors.textSecondary),
          ),
        ],
      ],
    ),
  );

  Widget _previewTab() {
    final resolved = _resolvedPreviewFrame();
    final elapsed = shot.duration.microseconds * _previewController.value;
    return _tabPadding(
      Column(
        children: [
          Expanded(
            child: _ResolvedCameraShotPlayback(
              editor: widget.editor,
              frame: resolved,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              IconButton.filledTonal(
                key: const ValueKey('camera-properties-preview'),
                tooltip: _isPreviewing
                    ? _text('Pause preview', 'إيقاف المعاينة مؤقتًا')
                    : _text('Preview this shot', 'معاينة هذه اللقطة'),
                onPressed: _togglePreview,
                icon: Icon(_isPreviewing ? Icons.pause : Icons.play_arrow),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Slider(
                  key: const ValueKey('camera-properties-preview-progress'),
                  value: _previewController.value,
                  onChanged: (value) {
                    _previewController.stop();
                    _previewController.value = value;
                  },
                ),
              ),
              SizedBox(
                width: 100,
                child: Text(
                  '${_seconds(elapsed.round())} / '
                  '${_seconds(shot.duration.microseconds)} s',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontFeatures: [ui.FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _link.displayName(
              isArabic: Directionality.of(context) == TextDirection.rtl,
            ),
            key: const ValueKey('camera-properties-preview-link-name'),
            style: TextStyle(color: context.studioColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _tabPadding(Widget child) =>
      Padding(padding: const EdgeInsets.all(20), child: child);

  Widget _metric(String label, String value) => Container(
    width: 160,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.studioColors.surfaceAlt,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.studioColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.studioColors.textSecondary),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _secondsSlider({
    required Key key,
    required String label,
    required double value,
    required double maximum,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) => Row(
    key: key,
    children: [
      SizedBox(width: 150, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(0, maximum),
          min: 0,
          max: maximum,
          onChanged: enabled ? onChanged : null,
        ),
      ),
      SizedBox(
        width: 62,
        child: Text(
          '${value.toStringAsFixed(1)} s',
          textDirection: TextDirection.ltr,
        ),
      ),
    ],
  );

  Widget _infoRow(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(icon, color: context.studioColors.accent),
        const SizedBox(width: 10),
        SizedBox(width: 130, child: Text(label)),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _CameraShotPreview extends StatelessWidget {
  const _CameraShotPreview({
    required this.image,
    required this.view,
    required this.aspectRatio,
    required this.projectSize,
    required this.artworkDestination,
    this.visibleArtworkBounds = const [],
    this.height,
  });

  final ui.Image? image;
  final CameraView view;
  final double aspectRatio;
  final Size projectSize;
  final Rect? artworkDestination;
  final List<Rect> visibleArtworkBounds;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: context.studioColors.appBackground,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.studioColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: AspectRatio(
      aspectRatio: aspectRatio,
      child: image == null
          ? Center(
              child: Icon(
                Icons.videocam_outlined,
                size: 40,
                color: context.studioColors.textMuted,
              ),
            )
          : CustomPaint(
              painter: CameraShotThumbnailPainter(
                image: image!,
                view: view,
                projectSize: projectSize,
                artworkDestination: artworkDestination,
                visibleArtworkBounds: visibleArtworkBounds,
              ),
              child: const SizedBox.expand(),
            ),
    ),
  );
}

/// Renders the dialog transport through the same resolved frame and painter
/// used by the main Viewer and MOV output.
class _ResolvedCameraShotPlayback extends StatelessWidget {
  const _ResolvedCameraShotPlayback({
    required this.editor,
    required this.frame,
  });

  final EditorCubit editor;
  final ResolvedProjectFrame frame;

  @override
  Widget build(BuildContext context) {
    final project = editor.project;
    final drawing = frame.drawing;
    final drawingProgress = drawing == null || drawing.duration.isZero
        ? 0.0
        : (drawing.localTime.microseconds / drawing.duration.microseconds)
              .clamp(0.0, 1.0);
    return Container(
      key: const ValueKey('camera-properties-resolved-preview'),
      decoration: BoxDecoration(
        color: context.studioColors.appBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.studioColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(
        child: AspectRatio(
          aspectRatio: project.canvasWidth / project.canvasHeight,
          child: CustomPaint(
            key: const ValueKey('camera-properties-resolved-preview-painter'),
            painter: EditorCanvasPainter(
              state: editor.state,
              project: project,
              previewProgress: drawingProgress,
              isPreviewing: true,
              cameraOutputPreview: true,
              resolvedFrame: frame,
              interfaceTextDirection: Directionality.of(context),
              emptyStateLabel: '',
              handModeLabel: '',
              revealModeLabel: '',
              ignoreModeLabel: '',
              pathsLabel: '',
              colors: context.studioColors,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class CameraShotThumbnailPainter extends CustomPainter {
  const CameraShotThumbnailPainter({
    required this.image,
    required this.view,
    required this.projectSize,
    required this.artworkDestination,
    this.visibleArtworkBounds = const [],
  });

  final ui.Image image;
  final CameraView view;
  final Size projectSize;
  final Rect? artworkDestination;
  final List<Rect> visibleArtworkBounds;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF071224),
    );
    final cameraRect = Rect.fromCenter(
      center: Offset(
        view.centerX * projectSize.width,
        view.centerY * projectSize.height,
      ),
      width: view.viewportWidth.clamp(.02, 4.0) * projectSize.width,
      height: view.viewportWidth.clamp(.02, 4.0) * projectSize.height,
    );
    final artwork =
        artworkDestination ??
        Alignment.center.inscribe(
          applyBoxFit(
            BoxFit.contain,
            Size(image.width.toDouble(), image.height.toDouble()),
            projectSize,
          ).destination,
          Offset.zero & projectSize,
        );
    final regions = visibleArtworkBounds.isEmpty
        ? <Rect>[artwork]
        : [
            for (final bounds in visibleArtworkBounds)
              Rect.fromLTRB(
                artwork.left + bounds.left * artwork.width,
                artwork.top + bounds.top * artwork.height,
                artwork.left + bounds.right * artwork.width,
                artwork.top + bounds.bottom * artwork.height,
              ),
          ];
    for (final region in regions) {
      _paintRegion(canvas, size, cameraRect, artwork, region);
    }
  }

  void _paintRegion(
    Canvas canvas,
    Size size,
    Rect cameraRect,
    Rect artwork,
    Rect region,
  ) {
    final visibleArtwork = cameraRect.intersect(artwork).intersect(region);
    if (visibleArtwork.isEmpty) return;
    final source = Rect.fromLTRB(
      (visibleArtwork.left - artwork.left) / artwork.width * image.width,
      (visibleArtwork.top - artwork.top) / artwork.height * image.height,
      (visibleArtwork.right - artwork.left) / artwork.width * image.width,
      (visibleArtwork.bottom - artwork.top) / artwork.height * image.height,
    );
    final destination = Rect.fromLTRB(
      (visibleArtwork.left - cameraRect.left) / cameraRect.width * size.width,
      (visibleArtwork.top - cameraRect.top) / cameraRect.height * size.height,
      (visibleArtwork.right - cameraRect.left) / cameraRect.width * size.width,
      (visibleArtwork.bottom - cameraRect.top) /
          cameraRect.height *
          size.height,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant CameraShotThumbnailPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.view != view ||
      oldDelegate.projectSize != projectSize ||
      oldDelegate.artworkDestination != artworkDestination ||
      !_rectListsEqual(oldDelegate.visibleArtworkBounds, visibleArtworkBounds);

  bool _rectListsEqual(List<Rect> a, List<Rect> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
