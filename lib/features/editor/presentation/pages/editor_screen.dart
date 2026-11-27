import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'package:handdraw_studio/features/app_info/presentation/about_dialog.dart';
import 'package:handdraw_studio/features/app_info/presentation/release_notes_dialog.dart';
import 'package:handdraw_studio/features/app_menu/presentation/studio_platform_menu_bar.dart';
import 'package:handdraw_studio/features/drawing_engine/domain/motion_timeline.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_audio_service.dart';
import 'package:handdraw_studio/features/writing_sound/application/writing_sound_preview_controller.dart';
import 'package:handdraw_studio/features/writing_sound/infrastructure/writing_sound_preview_service.dart';
import 'package:handdraw_studio/features/export/infrastructure/video_export_service.dart';
import 'package:handdraw_studio/features/export/application/export_status_cubit.dart';
import 'package:handdraw_studio/features/export/domain/video_export_cancellation.dart';
import 'package:handdraw_studio/features/export/infrastructure/export_result_action_service.dart';
import 'package:handdraw_studio/features/export/presentation/export_status_overlay.dart';
import 'package:handdraw_studio/features/project/domain/models/export_settings.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';
import 'package:handdraw_studio/features/playback/domain/playback_clock.dart';
import 'package:handdraw_studio/features/editor/infrastructure/flutter_playback_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/resolved_project_frame.dart';
import 'package:handdraw_studio/features/timeline/domain/models/compiled_timeline.dart';
import 'package:handdraw_studio/features/timeline/domain/models/timeline_time.dart';
import 'package:handdraw_studio/features/timeline/domain/models/frame_rate.dart';
import 'package:handdraw_studio/features/timeline/domain/services/frame_sampling_policy.dart';
import 'package:handdraw_studio/features/timeline/domain/services/unified_project_frame_resolver.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/application/new_project_request.dart';
import 'package:handdraw_studio/features/editor/application/session/editor_asset_staging.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/editor/presentation/layout/editor_layout_spec.dart';
import 'package:handdraw_studio/features/editor/presentation/inspector/application/inspector_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_inspector.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_status_bar.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_timeline_dock.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_toolbar.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/editor_workspace.dart';
import 'package:handdraw_studio/features/hand_library/presentation/hand_library_dialog.dart';
import 'package:handdraw_studio/features/voice_guide/presentation/voice_guide_bar.dart';
import 'package:handdraw_studio/features/voice_guide/infrastructure/voice_guide_service.dart';
import 'package:handdraw_studio/features/editor/presentation/widgets/hand_calibration_dialog.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/camera/application/camera_editor_view_commit_service.dart';
import 'package:handdraw_studio/features/camera/domain/models/project_camera.dart';
import 'package:handdraw_studio/features/auto_director/presentation/auto_director_dialog.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_application_service.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, this.cubit, this.writingAudioService});

  final EditorCubit? cubit;
  final WritingAudioService? writingAudioService;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

enum _DirtyProjectDecision { save, discard, cancel }

class _DirtyProjectDialog extends StatelessWidget {
  const _DirtyProjectDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('dirty-project-dialog'),
    title: Text(_b(context, 'Unsaved changes', 'تغييرات غير محفوظة')),
    content: Text(
      _b(
        context,
        'Save the current project before creating a new one?',
        'هل تريد حفظ المشروع الحالي قبل إنشاء مشروع جديد؟',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, _DirtyProjectDecision.cancel),
        child: Text(_b(context, 'Cancel', 'إلغاء')),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _DirtyProjectDecision.discard),
        child: Text(_b(context, "Don't Save", 'عدم الحفظ')),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _DirtyProjectDecision.save),
        child: Text(_b(context, 'Save', 'حفظ')),
      ),
    ],
  );
}

enum _NewProjectPreset { landscape, portrait, square, custom }

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController(text: 'Untitled Project');
  final _width = TextEditingController(text: '1920');
  final _height = TextEditingController(text: '1080');
  _NewProjectPreset _preset = _NewProjectPreset.landscape;
  int _fps = 30;
  NewProjectBackground _background = NewProjectBackground.transparent;
  ArtworkImportIntent _intent = ArtworkImportIntent.fullScene;

  @override
  void dispose() {
    _title.dispose();
    _width.dispose();
    _height.dispose();
    super.dispose();
  }

  void _selectPreset(_NewProjectPreset value) {
    setState(() {
      _preset = value;
      switch (value) {
        case _NewProjectPreset.landscape:
          _width.text = '1920';
          _height.text = '1080';
        case _NewProjectPreset.portrait:
          _width.text = '1080';
          _height.text = '1920';
        case _NewProjectPreset.square:
          _width.text = '1080';
          _height.text = '1080';
        case _NewProjectPreset.custom:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('new-project-dialog'),
    title: Text(_b(context, 'New Project', 'مشروع جديد')),
    content: SizedBox(
      width: 460,
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const ValueKey('new-project-title'),
                controller: _title,
                decoration: InputDecoration(
                  labelText: _b(context, 'Name', 'الاسم'),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? _b(context, 'Name is required', 'الاسم مطلوب')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<_NewProjectPreset>(
                key: const ValueKey('new-project-preset'),
                initialValue: _preset,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _b(context, 'Format preset', 'المقاس الجاهز'),
                ),
                items: const [
                  DropdownMenuItem(
                    value: _NewProjectPreset.landscape,
                    child: Text('1080p Landscape — 1920×1080'),
                  ),
                  DropdownMenuItem(
                    value: _NewProjectPreset.portrait,
                    child: Text('1080p Portrait — 1080×1920'),
                  ),
                  DropdownMenuItem(
                    value: _NewProjectPreset.square,
                    child: Text('Square — 1080×1080'),
                  ),
                  DropdownMenuItem(
                    value: _NewProjectPreset.custom,
                    child: Text('Custom'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) _selectPreset(value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _dimensionField(_width, 'Width')),
                  const SizedBox(width: 12),
                  Expanded(child: _dimensionField(_height, 'Height')),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const ValueKey('new-project-fps'),
                initialValue: _fps,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Frame rate'),
                items: const [24, 25, 30, 50, 60]
                    .map(
                      (fps) =>
                          DropdownMenuItem(value: fps, child: Text('$fps fps')),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _fps = value ?? 30),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<NewProjectBackground>(
                key: const ValueKey('new-project-background'),
                initialValue: _background,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _b(context, 'Background', 'الخلفية'),
                ),
                items: [
                  DropdownMenuItem(
                    value: NewProjectBackground.transparent,
                    child: Text(_b(context, 'Transparent', 'شفافة')),
                  ),
                  DropdownMenuItem(
                    value: NewProjectBackground.color,
                    child: Text(_b(context, 'Color', 'لون')),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _background = value ?? NewProjectBackground.transparent,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ArtworkImportIntent>(
                key: const ValueKey('new-project-import-intent'),
                initialValue: _intent,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _b(
                    context,
                    'Default import intent',
                    'نوع الاستيراد الافتراضي',
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: ArtworkImportIntent.fullScene,
                    child: Text('Full Scene'),
                  ),
                  DropdownMenuItem(
                    value: ArtworkImportIntent.element,
                    child: Text('Element'),
                  ),
                ],
                onChanged: (value) => setState(
                  () => _intent = value ?? ArtworkImportIntent.fullScene,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(_b(context, 'Cancel', 'إلغاء')),
      ),
      FilledButton(
        key: const ValueKey('create-new-project'),
        onPressed: () {
          if (!(_form.currentState?.validate() ?? false)) return;
          Navigator.pop(
            context,
            NewProjectRequest(
              title: _title.text,
              width: int.parse(_width.text),
              height: int.parse(_height.text),
              frameRate: FrameRate(numerator: _fps),
              background: _background,
              defaultImportIntent: _intent,
            ),
          );
        },
        child: Text(_b(context, 'Create', 'إنشاء')),
      ),
    ],
  );

  Widget _dimensionField(TextEditingController controller, String label) =>
      TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() => _preset = _NewProjectPreset.custom),
        validator: (value) {
          final number = int.tryParse(value ?? '');
          return number == null || number < 64 || number > 16384
              ? '64–16384'
              : null;
        },
      );
}

String _b(BuildContext context, String english, String arabic) =>
    Directionality.of(context) == TextDirection.rtl ? arabic : english;

class _EditorScreenState extends State<EditorScreen>
    with SingleTickerProviderStateMixin {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final VideoExportService exportService = const VideoExportService();
  final ExportResultActionService exportResultActions =
      const DesktopExportResultActionService();
  final ExportStatusCubit exportStatusCubit = ExportStatusCubit();
  late final WritingAudioService writingAudioService;
  final InspectorCubit inspectorCubit = InspectorCubit();
  final CameraEditingCubit cameraEditingCubit = CameraEditingCubit();
  late final WritingSoundPreviewController writingSoundPreviewController;

  late final EditorCubit cubit;
  late final AnimationController isolatedStrokePlayback;
  PlaybackClock? previewClock;
  ResolvedProjectFrame? currentResolvedFrame;
  final previewFrame = ValueNotifier<ResolvedProjectFrame?>(null);
  int _lastPreviewUiUpdateUs = -100000;
  int? _lastPreviewVisualFrameIndex;
  CompiledTimeline? _idleTimeline;
  int? _idleTimelineRevision;
  late final bool ownsCubit;
  bool isPreviewing = false;
  bool isPreviewPaused = false;
  bool isExporting = false;
  bool isTimelineFrameVisible = false;
  bool _inspectorCollapsed = false;
  bool _canvasFocusMode = false;
  double _timelineHeight = 240;
  int previewGeneration = 0;
  double pendingPreviewPosition = 0;
  double currentPreviewPositionSeconds = 0;
  double? drawingTrackPreviewPositionSeconds;
  double? voiceTrackPreviewPositionSeconds;
  double previewVolume = 1;
  double _lastAudiblePreviewVolume = 1;
  double? timingEditAnchorProgress;
  int? previewingStrokeIndex;
  EditorRenderSnapshot? previewSnapshot;
  CompiledTimeline? previewTimelineOverride;
  TimelineTime? previewCameraShotEnd;
  CameraCanvasMode _canvasModeBeforePreview = CameraCanvasMode.browse;
  AutoDirectorPlan? pendingAutoDirectorPlan;

  double get _previewProgress {
    final duration = _previewDuration;
    if (duration <= 0) return 0;
    return (currentPreviewPositionSeconds / duration).clamp(0.0, 1.0);
  }

  double get _drawingProgress {
    final drawing = currentResolvedFrame?.drawing;
    if (drawing == null || drawing.duration.isZero) return 0;
    return (drawing.localTime.microseconds / drawing.duration.microseconds)
        .clamp(0.0, 1.0);
  }

  bool get _hasPreviewAudio =>
      cubit.project.writingSoundEnabled ||
      (cubit.voiceGuide != null &&
          !cubit.isVoiceGuideMissing &&
          _voiceTrackEnabled);

  double get _drawingTrackPositionSeconds =>
      drawingTrackPreviewPositionSeconds ?? currentPreviewPositionSeconds;

  double get _voiceTrackPositionSeconds =>
      voiceTrackPreviewPositionSeconds ?? currentPreviewPositionSeconds;

  bool get _voiceTrackEnabled {
    final guide = cubit.state.document.voiceGuide;
    if (guide == null) return false;
    for (final track in cubit.state.document.audioTracks) {
      if (track.id == guide.audioTrackId) return !track.muted;
    }
    return false;
  }

  double exportProgress = 0;
  String exportStage = '';
  VideoExportCancellationToken? exportCancellationToken;

  @override
  void initState() {
    super.initState();
    ownsCubit = widget.cubit == null;
    cubit = widget.cubit ?? EditorCubit();
    writingAudioService = widget.writingAudioService ?? WritingAudioService();
    writingSoundPreviewController = WritingSoundPreviewController(
      player: WritingSoundPreviewService(),
    );
    isolatedStrokePlayback = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..addListener(() => setState(() {}));
    cameraEditingCubit.setCanvasMode(CameraCanvasMode.browse);
    if (ownsCubit) unawaited(cubit.initializeHandLibrary());
  }

  @override
  void dispose() {
    _disposePreviewClock();
    unawaited(writingAudioService.stop());
    writingSoundPreviewController.dispose();
    previewFrame.dispose();
    exportStatusCubit.close();
    inspectorCubit.close();
    cameraEditingCubit.close();
    isolatedStrokePlayback.dispose();
    unawaited(previewSnapshot?.release());
    previewSnapshot = null;
    previewTimelineOverride = null;
    if (ownsCubit) cubit.close();
    super.dispose();
  }

  void _stopPreview() {
    previewGeneration++;
    _disposePreviewClock();
    unawaited(writingAudioService.stop());
    isolatedStrokePlayback.stop();
    isolatedStrokePlayback.reset();
    final snapshot = previewSnapshot;
    previewSnapshot = null;
    previewTimelineOverride = null;
    previewCameraShotEnd = null;
    _lastPreviewVisualFrameIndex = null;
    cameraEditingCubit.setCanvasMode(_canvasModeBeforePreview);
    setState(() {
      currentPreviewPositionSeconds = 0;
      drawingTrackPreviewPositionSeconds = null;
      voiceTrackPreviewPositionSeconds = null;
      currentResolvedFrame = null;
      previewFrame.value = null;
      isPreviewing = false;
      isPreviewPaused = false;
      isTimelineFrameVisible = false;
      previewingStrokeIndex = null;
    });
    if (snapshot != null) _releaseSnapshotAfterCanvasSwitch(snapshot);
  }

  void _releaseSnapshotAfterCanvasSwitch(EditorRenderSnapshot snapshot) {
    if (!mounted) {
      unawaited(snapshot.release());
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(snapshot.release());
    });
  }

  void _cancelActiveEditOrStopPreview() {
    if (isPreviewing || isTimelineFrameVisible) {
      _stopPreview();
      return;
    }
    cubit.cancelPathNodeEdit();
  }

  void _previewStroke(int index) => unawaited(_startStrokePreview(index));

  Future<void> _startStrokePreview(int index) async {
    if (index < 0 || index >= cubit.project.strokes.length) return;
    final generation = ++previewGeneration;
    final snapshot = await cubit.acquireRenderSnapshot(
      kind: StagedAssetReferenceKind.preview,
    );
    if (!mounted || generation != previewGeneration) {
      await snapshot.release();
      return;
    }
    final previousSnapshot = previewSnapshot;
    previewSnapshot = snapshot;
    unawaited(writingAudioService.stop());
    final authoredDurationSeconds = projectTimelineStrokeDrawingDuration(
      snapshot.project,
      index,
    );
    final previewDuration = Duration(
      microseconds: math.max(
        50000,
        (authoredDurationSeconds * Duration.microsecondsPerSecond).round(),
      ),
    );
    isolatedStrokePlayback
      ..stop()
      ..duration = previewDuration;
    cubit.selectStroke(index);
    setState(() {
      isPreviewing = false;
      isPreviewPaused = false;
      isTimelineFrameVisible = true;
      previewingStrokeIndex = index;
    });
    if (previousSnapshot != null) {
      _releaseSnapshotAfterCanvasSwitch(previousSnapshot);
    }
    unawaited(
      isolatedStrokePlayback.forward(from: 0).then((_) async {
        if (!mounted ||
            generation != previewGeneration ||
            previewingStrokeIndex != index) {
          return;
        }
        previewSnapshot = null;
        setState(() {
          isTimelineFrameVisible = false;
          previewingStrokeIndex = null;
        });
        _releaseSnapshotAfterCanvasSwitch(snapshot);
      }),
    );
  }

  void _pausePreview() {
    unawaited(writingAudioService.pause());
    previewClock?.pause();
    setState(() => isPreviewPaused = true);
  }

  void _resumePreview() {
    final time = TimelineTime.fromMicroseconds(
      (currentPreviewPositionSeconds * Duration.microsecondsPerSecond).round(),
    );
    currentResolvedFrame = const UnifiedProjectFrameResolver()
        .resolveForPreview(_timelineForControls, time);
    previewFrame.value = currentResolvedFrame;
    setState(() {
      isPreviewPaused = false;
      drawingTrackPreviewPositionSeconds = null;
      voiceTrackPreviewPositionSeconds = null;
    });
    unawaited(writingAudioService.resume());
    previewClock?.play();
  }

  void _undoShortcut() {
    if (isPreviewing || isExporting || !cubit.canUndo) return;
    cubit.undoStroke();
  }

  void _redoShortcut() {
    if (isPreviewing || isExporting || !cubit.canRedo) return;
    cubit.redoStroke();
  }

  Future<void> _clearCanvas() async {
    if (isExporting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.clearCanvas),
        content: const Text(
          'This removes the current artwork, animation paths, sections, and '
          'camera edits. Your selected hand and general settings stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirm-clear-canvas'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.clearCanvas),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (isPreviewing) _stopPreview();
    final cleared = cubit.clearCanvas();
    if (!cleared) {
      _showMessage(context.l10n.canvasAlreadyClear);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.canvasCleared),
        action: SnackBarAction(
          label: context.l10n.undo,
          onPressed: cubit.restoreClearedCanvas,
        ),
      ),
    );
  }

  Future<void> _newProject() async {
    if (isExporting) return;
    if (cubit.isDirty) {
      final decision = await showDialog<_DirtyProjectDecision>(
        context: context,
        builder: (context) => const _DirtyProjectDialog(),
      );
      if (!mounted ||
          decision == null ||
          decision == _DirtyProjectDecision.cancel) {
        return;
      }
      if (decision == _DirtyProjectDecision.save) {
        final saved = await cubit.saveProject(copy: _editorFilePickerCopy());
        if (!mounted || saved == null) return;
      }
    }
    final request = await showDialog<NewProjectRequest>(
      context: context,
      builder: (context) => const _NewProjectDialog(),
    );
    if (!mounted || request == null) return;
    if (isPreviewing) _stopPreview();
    final created = await cubit.createNewProject(request);
    if (!mounted || created) return;
    _showMessage('Could not create the new project.');
  }

  Future<void> _importDrawing() async {
    if (isExporting || cubit.state.isDrawingImporting) return;
    if (isPreviewing) _stopPreview();
    final result = await cubit.importDrawing(copy: _editorFilePickerCopy());
    if (!mounted || result != DrawingImportResult.imported) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  Future<void> _openHandLibrary() async {
    if (isExporting) return;
    if (isPreviewing) _stopPreview();
    final action = await showDialog<HandLibraryAction>(
      context: context,
      builder: (context) => HandLibraryDialog(cubit: cubit),
    );
    if (!mounted || action != HandLibraryAction.calibrate) return;
    await _calibrateHand();
  }

  Future<void> _openProject() async {
    if (isExporting) return;
    if (isPreviewing) _stopPreview();
    await cubit.openProject(copy: _editorFilePickerCopy());
  }

  Future<void> _saveProject() async {
    try {
      final path = await cubit.saveProject(copy: _editorFilePickerCopy());
      if (path != null && mounted) _showMessage(context.l10n.savedTo(path));
    } catch (error) {
      if (mounted) {
        _showMessage(
          '${Localizations.localeOf(context).languageCode == 'ar' ? 'تعذر حفظ المشروع' : 'Could not save project'}: $error',
        );
      }
    }
  }

  Future<void> _calibrateHand() async {
    final hand = cubit.handImage;
    if (hand == null) return;
    final point = await showDialog<Offset>(
      context: context,
      builder: (context) => HandCalibrationDialog(
        image: hand,
        initialPenTip: cubit.calibrationPenTip,
        flipX: cubit.calibrationHandFlipX,
      ),
    );
    if (point != null) await cubit.setPenTip(point);
  }

  void _resetSettings() {
    if (isPreviewing || isExporting) return;
    cubit.resetDefaultSettings();
    _showMessage(context.l10n.settingsReset);
  }

  CompiledTimeline get _timelineForControls {
    final snapshot = previewSnapshot;
    if (snapshot != null) return snapshot.timeline;
    final revision = cubit.state.documentRevision.value;
    if (_idleTimelineRevision != revision || _idleTimeline == null) {
      _idleTimeline = cubit.compileTimeline();
      _idleTimelineRevision = revision;
    }
    return _idleTimeline!;
  }

  double get _previewDuration =>
      _timelineForControls.duration.microseconds /
      Duration.microsecondsPerSecond;

  void _playPreview() {
    if (!cubit.canPreview && cubit.voiceGuide == null) {
      _showMessage(context.l10n.importDrawingOrVoice);
      return;
    }
    if (!const CameraEditorViewCommitService().commitIfDirty(
      editor: cubit,
      editing: cameraEditingCubit,
    )) {
      return;
    }
    previewCameraShotEnd = null;
    unawaited(_startPreview(fromSeconds: 0));
  }

  void _previewCameraShot(CameraShot shot) {
    previewCameraShotEnd = shot.endTime;
    unawaited(
      _startPreview(
        fromSeconds:
            shot.startTime.microseconds / Duration.microsecondsPerSecond,
      ),
    );
  }

  Future<void> _startPreview({
    required double fromSeconds,
    CompiledTimeline? timelineOverride,
  }) async {
    final generation = ++previewGeneration;
    previewingStrokeIndex = null;
    if (cameraEditingCubit.state.canvasMode != CameraCanvasMode.previewCamera) {
      _canvasModeBeforePreview = cameraEditingCubit.state.canvasMode;
    }
    cameraEditingCubit.setCanvasMode(CameraCanvasMode.previewCamera);
    late final EditorRenderSnapshot snapshot;
    try {
      snapshot = await cubit.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.preview,
      );
    } catch (error) {
      if (mounted && generation == previewGeneration) {
        cameraEditingCubit.setCanvasMode(_canvasModeBeforePreview);
        _showMessage('${context.l10n.preview}: $error');
      }
      return;
    }
    if (!mounted || generation != previewGeneration) {
      await snapshot.release();
      return;
    }
    final activeTimeline = timelineOverride ?? snapshot.timeline;
    final duration =
        activeTimeline.duration.microseconds / Duration.microsecondsPerSecond;
    if (duration <= 0) {
      await snapshot.release();
      if (mounted && generation == previewGeneration) {
        cameraEditingCubit.setCanvasMode(_canvasModeBeforePreview);
      }
      return;
    }
    if (writingSoundPreviewController.isBusy) {
      await writingSoundPreviewController.stop();
    }
    if (!mounted || generation != previewGeneration) {
      await snapshot.release();
      return;
    }
    final previousSnapshot = previewSnapshot;
    previewSnapshot = snapshot;
    previewTimelineOverride = timelineOverride;
    pendingPreviewPosition = fromSeconds;
    currentPreviewPositionSeconds = fromSeconds;
    drawingTrackPreviewPositionSeconds = null;
    voiceTrackPreviewPositionSeconds = null;
    _disposePreviewClock();
    final ticker = FlutterPlaybackTickerAdapter();
    final clock = PlaybackClock(
      duration: activeTimeline.duration,
      timeSource: ticker,
      tickScheduler: ticker,
    );
    previewClock = clock;
    _lastPreviewVisualFrameIndex = null;
    // The new run starts its own chrome sampling window, including a replay
    // from zero after the previous run ended at the scene duration.
    _lastPreviewUiUpdateUs = -100000;
    clock.addListener(_onPreviewClock);
    clock.seek(
      TimelineTime.fromMicroseconds(
        (fromSeconds * Duration.microsecondsPerSecond).round(),
      ),
    );
    currentResolvedFrame = const UnifiedProjectFrameResolver()
        .resolveForPreview(activeTimeline, clock.currentTime);
    setState(() {
      isPreviewing = true;
      isPreviewPaused = false;
      isTimelineFrameVisible = cubit.canPreview;
    });
    if (previousSnapshot != null) {
      _releaseSnapshotAfterCanvasSwitch(previousSnapshot);
    }
    clock.play();
    try {
      writingAudioService.configureTimeline(activeTimeline);
      await writingAudioService.play(
        snapshot.project,
        voiceGuide: cubit.isVoiceGuideMissing || !_voiceTrackEnabled
            ? null
            : snapshot.project.voiceGuide,
        positionSeconds: fromSeconds,
        previewDurationSeconds: duration,
        volume: previewVolume,
      );
    } catch (error) {
      if (mounted && generation == previewGeneration) {
        _showMessage('${context.l10n.audio}: $error');
      }
    }
    if (!mounted || !isPreviewing || generation != previewGeneration) {
      await writingAudioService.stop();
      return;
    }
    await writingAudioService.seek(
      clock.currentTime.microseconds / Duration.microsecondsPerSecond,
    );
    if (isPreviewPaused) {
      await writingAudioService.pause();
      return;
    }
  }

  void _previewAutoDirectorPlan(AutoDirectorPlan plan) {
    final timeline = AutoDirectorApplicationService().compilePreviewTimeline(
      plan: plan,
      currentDocument: cubit.state.document,
      currentTimeline: cubit.compileTimeline(),
      currentGraph: cubit.compileSemanticGraph(),
      documentRevision: cubit.state.documentRevision.value,
    );
    Navigator.of(context).pop();
    unawaited(_startPreview(fromSeconds: 0, timelineOverride: timeline));
  }

  void _onPreviewClock(PlaybackClockState state) {
    final snapshot = previewSnapshot;
    if (!mounted || snapshot == null) return;
    final timeline = previewTimelineOverride ?? snapshot.timeline;
    const sampling = FrameSamplingPolicy();
    final frameRate = FrameRate(numerator: snapshot.project.frameRate);
    if (state.status == PlaybackStatus.ended) {
      // Video-frame sampling stops one frame interval before the mathematical
      // end. Resolve the exact terminal state once playback ends so the UI
      // honors the final hand-visibility setting instead of freezing the last
      // in-motion sample while the chrome already reads 100%.
      final resolved = const UnifiedProjectFrameResolver().resolveForPreview(
        timeline,
        TimelineTime.fromMicroseconds(timeline.duration.microseconds),
      );
      _lastPreviewVisualFrameIndex = null;
      currentResolvedFrame = resolved;
      previewFrame.value = resolved;
    } else {
      final visualFrameIndex = sampling.frameIndexForTime(
        time: state.currentTime,
        duration: timeline.duration,
        frameRate: frameRate,
      );
      if (visualFrameIndex != null &&
          visualFrameIndex != _lastPreviewVisualFrameIndex) {
        final sampledTime = sampling.timeForFrame(
          index: visualFrameIndex,
          duration: timeline.duration,
          frameRate: frameRate,
        );
        final resolved = const UnifiedProjectFrameResolver().resolveForPreview(
          timeline,
          sampledTime,
        );
        _lastPreviewVisualFrameIndex = visualFrameIndex;
        currentResolvedFrame = resolved;
        previewFrame.value = resolved;
      }
    }
    currentPreviewPositionSeconds =
        state.currentTime.microseconds / Duration.microsecondsPerSecond;
    _followCameraAt(state.currentTime);
    final shotEnd = previewCameraShotEnd;
    if (shotEnd != null && state.currentTime.compareTo(shotEnd) >= 0) {
      previewCameraShotEnd = null;
      _stopPreview();
      return;
    }
    final shouldRefreshChrome =
        state.status == PlaybackStatus.ended ||
        state.currentTime.microseconds - _lastPreviewUiUpdateUs >= 100000;
    if (shouldRefreshChrome) {
      _lastPreviewUiUpdateUs = state.currentTime.microseconds;
      setState(() {
        if (state.status == PlaybackStatus.ended) {
          isPreviewing = false;
          isPreviewPaused = false;
          cameraEditingCubit.setCanvasMode(_canvasModeBeforePreview);
        }
      });
    }
  }

  void _followCameraAt(TimelineTime time) {
    if (!cameraEditingCubit.state.followPlayhead) return;
    final track = cubit.state.document.cameraTrack;
    if (track == null) return;
    for (final shot in track.shots) {
      if (time.compareTo(shot.startTime) < 0 ||
          time.compareTo(shot.endTime) >= 0) {
        continue;
      }
      final localUs = time.microseconds - shot.startTime.microseconds;
      final frame = shot.keyframes.lastWhere(
        (item) => item.offset.microseconds <= localUs,
        orElse: () => shot.keyframes.first,
      );
      if (cameraEditingCubit.state.selectedKeyframeId != frame.id) {
        cameraEditingCubit.selectKeyframe(shot.id, frame.id);
      }
      return;
    }
  }

  void _disposePreviewClock() {
    final clock = previewClock;
    previewClock = null;
    clock?.removeListener(_onPreviewClock);
    clock?.dispose();
    _lastPreviewVisualFrameIndex = null;
  }

  Future<void> _seekPreview(double seconds) async {
    final duration = _previewDuration;
    if (duration <= 0) return;
    final position = seconds.clamp(0.0, duration);
    final timeline = _timelineForControls;
    pendingPreviewPosition = position;
    _lastPreviewVisualFrameIndex = null;
    previewClock?.seek(
      TimelineTime.fromMicroseconds(
        (position * Duration.microsecondsPerSecond).round(),
      ),
    );
    currentResolvedFrame = const UnifiedProjectFrameResolver()
        .resolveForPreview(
          timeline,
          TimelineTime.fromMicroseconds(
            (position * Duration.microsecondsPerSecond).round(),
          ),
        );
    previewFrame.value = currentResolvedFrame;
    setState(() {
      currentPreviewPositionSeconds = position;
      drawingTrackPreviewPositionSeconds = null;
      voiceTrackPreviewPositionSeconds = null;
      isTimelineFrameVisible = cubit.canPreview;
    });
    if (isPreviewing) await writingAudioService.seek(position);
  }

  void _seekDrawingTrack(double seconds) {
    final duration = _previewDuration;
    if (duration <= 0) return;
    if (isPreviewing && !isPreviewPaused) _pausePreview();
    final position = seconds.clamp(0.0, duration);
    final time = TimelineTime.fromMicroseconds(
      (position * Duration.microsecondsPerSecond).round(),
    );
    currentResolvedFrame = const UnifiedProjectFrameResolver()
        .resolveForPreview(_timelineForControls, time);
    previewFrame.value = currentResolvedFrame;
    setState(() {
      drawingTrackPreviewPositionSeconds = position;
      isTimelineFrameVisible = cubit.canPreview;
    });
  }

  void _seekVoiceTrack(double seconds) {
    final duration = _previewDuration;
    if (duration <= 0) return;
    if (isPreviewing && !isPreviewPaused) _pausePreview();
    setState(() {
      voiceTrackPreviewPositionSeconds = seconds.clamp(0.0, duration);
    });
  }

  void _setPreviewVolume(double value) {
    final resolved = value.clamp(0.0, 1.0);
    if (resolved > 0) _lastAudiblePreviewVolume = resolved;
    setState(() => previewVolume = resolved);
    unawaited(writingAudioService.setVolume(resolved));
  }

  void _togglePreviewMute() {
    _setPreviewVolume(
      previewVolume > 0 ? 0 : _lastAudiblePreviewVolume.clamp(.05, 1.0),
    );
  }

  void _beginTimelineTimingChange() {
    if (timingEditAnchorProgress != null) return;
    final duration = _previewDuration;
    timingEditAnchorProgress = duration <= 0
        ? 0
        : (currentPreviewPositionSeconds / duration).clamp(0.0, 1.0);
  }

  void _syncTimelineAfterTimingMutation() {
    final duration = _previewDuration;
    final progress = timingEditAnchorProgress;
    if (progress == null ||
        (!isPreviewing &&
            !isTimelineFrameVisible &&
            currentPreviewPositionSeconds <= 0)) {
      return;
    }
    final position = duration * progress;
    pendingPreviewPosition = position;
    setState(() {
      currentPreviewPositionSeconds = position;
    });
  }

  void _endTimelineTimingChange() {
    _syncTimelineAfterTimingMutation();
    timingEditAnchorProgress = null;
    if (!isPreviewing) return;
    unawaited(_restartPreviewClockAfterTimingChange());
  }

  Future<void> _restartPreviewClockAfterTimingChange() async {
    final generation = ++previewGeneration;
    final position = currentPreviewPositionSeconds;
    final duration = _previewDuration;
    final timeline = previewSnapshot?.timeline;
    if (timeline != null) writingAudioService.configureTimeline(timeline);
    await writingAudioService.play(
      previewSnapshot?.project ?? cubit.project,
      voiceGuide: cubit.isVoiceGuideMissing || !_voiceTrackEnabled
          ? null
          : cubit.voiceGuide,
      positionSeconds: position,
      previewDurationSeconds: duration,
      volume: previewVolume,
    );
    if (!mounted || !isPreviewing || generation != previewGeneration) return;
    if (isPreviewPaused) {
      await writingAudioService.pause();
    } else {
      previewClock?.play();
    }
  }

  void _toggleVoiceTrackEnabled() {
    final enabled = !_voiceTrackEnabled;
    if (!cubit.setVoiceGuideMuted(!enabled)) return;
    setState(() {});
    if (isPreviewing) unawaited(_reloadMasterPreviewAudio());
  }

  Future<void> _reloadMasterPreviewAudio() async {
    final snapshot = previewSnapshot;
    if (snapshot == null || !isPreviewing) return;
    writingAudioService.configureTimeline(
      previewTimelineOverride ?? snapshot.timeline,
    );
    await writingAudioService.play(
      snapshot.project,
      voiceGuide: cubit.isVoiceGuideMissing || !_voiceTrackEnabled
          ? null
          : snapshot.project.voiceGuide,
      positionSeconds: currentPreviewPositionSeconds,
      previewDurationSeconds: _previewDuration,
      volume: previewVolume,
    );
    if (!mounted || !isPreviewing) return;
    if (isPreviewPaused) await writingAudioService.pause();
  }

  Future<void> _importVoiceGuide() async {
    if (isPreviewing) _stopPreview();
    await cubit.importVoiceGuide(copy: _voiceGuidePickerCopy());
    if (!mounted || cubit.voiceGuide == null) return;
    _showMessage(context.l10n.voiceGuideReady);
  }

  Future<void> _exportVideo() async {
    if (!cubit.canPreview) {
      _showMessage(context.l10n.importDrawingAndStroke);
      return;
    }
    _stopPreview();
    if (!const CameraEditorViewCommitService().commitIfDirty(
      editor: cubit,
      editing: cameraEditingCubit,
    )) {
      return;
    }
    final cancellationToken = VideoExportCancellationToken();
    final pickerCopy = VideoExportPickerCopy(
      quickTimeMovie: context.l10n.quickTimeMovie,
      exportMovie: context.l10n.exportMovie,
    );
    exportCancellationToken = cancellationToken;
    exportStatusCubit.start(context.l10n.preparingExport);
    setState(() {
      isExporting = true;
      exportProgress = 0;
      exportStage = context.l10n.preparingExport;
    });
    EditorRenderSnapshot? snapshot;
    try {
      snapshot = await cubit.acquireRenderSnapshot(
        kind: StagedAssetReferenceKind.export,
      );
      final drawing = snapshot.drawing;
      if (drawing == null) throw StateError('Export drawing is unavailable.');
      final path = await exportService.exportProRes4444(
        project: snapshot.project,
        timeline: snapshot.timeline,
        frameRate: snapshot.documentState.document.frameRate,
        transparent:
            ExportPreset.byId(
              snapshot.documentState.document.exportConfiguration.presetId,
            )?.requiresAlpha ??
            true,
        drawing: drawing,
        drawingRevealBase: snapshot.drawingRevealBase,
        svgRevealLayers: snapshot.svgRevealLayers,
        hand: snapshot.hand,
        copy: pickerCopy,
        onProgress: (update) {
          if (!mounted) return;
          final stage = _localizedExportStage(update);
          exportStatusCubit.update(
            progress: update.progress,
            stage: stage,
            canCancel:
                update.stage != VideoExportStage.encodingProRes &&
                update.stage != VideoExportStage.complete,
          );
          setState(() {
            exportProgress = update.progress;
            exportStage = stage;
          });
        },
        cancellationToken: cancellationToken,
      );
      if (path != null && mounted) {
        final file = File(path);
        final size = await file.exists() ? await file.length() : 0;
        if (!mounted) return;
        exportStatusCubit.succeed(
          path: path,
          fileSizeBytes: size,
          durationSeconds:
              snapshot.timeline.duration.microseconds /
              Duration.microsecondsPerSecond,
        );
      } else if (mounted) {
        exportStatusCubit.dismiss();
      }
    } on VideoExportCancelledException {
      if (mounted) exportStatusCubit.dismiss();
    } catch (error) {
      if (mounted) exportStatusCubit.fail('$error');
    } finally {
      await snapshot?.release();
      if (identical(exportCancellationToken, cancellationToken)) {
        exportCancellationToken = null;
      }
      if (mounted) setState(() => isExporting = false);
    }
  }

  void _cancelExport() {
    exportStatusCubit.update(
      progress: exportProgress,
      stage: context.l10n.exportCanceled,
      canCancel: false,
    );
    exportCancellationToken?.cancel();
  }

  Future<void> _runExportResultAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) _showMessage(context.l10n.exportFailed('$error'));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _localizedExportStage(VideoExportProgress update) {
    final l10n = context.l10n;
    return switch (update.stage) {
      VideoExportStage.renderingFrame => l10n.renderingFrame(
        update.currentFrame ?? 0,
        update.totalFrames ?? 0,
      ),
      VideoExportStage.generatingWritingSound => l10n.generatingWritingSound,
      VideoExportStage.encodingProRes => l10n.encodingProRes,
      VideoExportStage.complete => l10n.exportComplete,
    };
  }

  EditorFilePickerCopy _editorFilePickerCopy() {
    final l10n = context.l10n;
    return EditorFilePickerCopy(
      chooseDrawing: l10n.chooseDrawing,
      chooseHand: l10n.chooseHand,
      images: l10n.images,
      project: l10n.handDrawProject,
      saveProject: l10n.saveProject,
      openProject: l10n.openProject,
    );
  }

  VoiceGuidePickerCopy _voiceGuidePickerCopy() {
    final l10n = context.l10n;
    return VoiceGuidePickerCopy(
      recordings: l10n.voiceRecordings,
      importVoice: l10n.importVoice,
    );
  }

  void _addCameraShotFromToolbar() {
    if ((!cubit.hasDrawing && cubit.state.document.scenes.isEmpty) ||
        isPreviewing) {
      return;
    }
    final previousShotIds = {
      for (final shot
          in cubit.state.document.cameraTrack?.shots ?? const <CameraShot>[])
        shot.id,
    };
    final playhead = TimelineTime.fromMicroseconds(
      (currentPreviewPositionSeconds * Duration.microsecondsPerSecond).round(),
    );
    final defaults = cameraEditingCubit.state.shotDefaults;
    if (!cubit.addCameraShotAtWithView(
      playhead,
      cameraEditingCubit.state.editorView,
      movement: defaults.movement,
      movementDuration: TimelineDuration.fromDuration(
        defaults.movementDuration,
      ),
      holdDuration: TimelineDuration.fromDuration(defaults.holdDuration),
    )) {
      return;
    }
    final created = cubit.state.document.cameraTrack?.shots
        .where((shot) => !previousShotIds.contains(shot.id))
        .firstOrNull;
    if (created == null || created.keyframes.isEmpty) return;
    final view = created.keyframes.last.view;
    cameraEditingCubit.selectKeyframe(created.id, created.keyframes.last.id);
    cameraEditingCubit.restoreEditorView(view);
  }

  EditorToolbarActions _toolbarActions({required bool opensStartDrawer}) =>
      EditorToolbarActions(
        onAnimateImage: _openImageAnimation,
        onNew: _newProject,
        onOpen: _openProject,
        onSave: _saveProject,
        onClear: _clearCanvas,
        onImportDrawing: _importDrawing,
        onImportHand: _openHandLibrary,
        onCalibrateHand: _calibrateHand,
        onAddCameraShot: _addCameraShotFromToolbar,
        onToolChanged: cubit.setTool,
        onUndo: cubit.undoStroke,
        onRedo: cubit.redoStroke,
        onImportVoice: _importVoiceGuide,
        onPlay: _playPreview,
        onPause: _pausePreview,
        onResume: _resumePreview,
        onStop: _stopPreview,
        onExport: _exportVideo,
        onOpenInspector: () => opensStartDrawer
            ? scaffoldKey.currentState?.openDrawer()
            : scaffoldKey.currentState?.openEndDrawer(),
      );

  StudioMenuActions _menuActions({required bool opensStartDrawer}) =>
      StudioMenuActions(
        onAbout: () => unawaited(showStudioAboutDialog(context)),
        onWhatsNew: () => unawaited(showReleaseNotesDialog(context)),
        onLicenses: () => showLicensePage(
          context: context,
          applicationName: context.l10n.appTitle,
          applicationVersion: AppBuildInfo.displayVersion,
        ),
        onNew: _newProject,
        onOpen: () => unawaited(_openProject()),
        onSave: () => unawaited(_saveProject()),
        onImportDrawing: () => unawaited(_importDrawing()),
        onImportHand: () => unawaited(_openHandLibrary()),
        onImportVoice: () => unawaited(_importVoiceGuide()),
        onCalibrateHand: () => unawaited(_calibrateHand()),
        onResetSettings: _resetSettings,
        onExport: () => unawaited(_exportVideo()),
        onUndo: _undoShortcut,
        onRedo: _redoShortcut,
        onClearCanvas: _clearCanvas,
        onPreview: _playPreview,
        onPauseOrResume: isPreviewPaused ? _resumePreview : _pausePreview,
        onStop: _stopPreview,
        onAnimateImage: _openImageAnimation,
        onOpenInspector: () => opensStartDrawer
            ? scaffoldKey.currentState?.openDrawer()
            : scaffoldKey.currentState?.openEndDrawer(),
      );

  Widget _buildInspector({VoidCallback? onClose}) => EditorInspector(
    key: const ValueKey('editor-inspector'),
    cubit: cubit,
    onImportImage: () => unawaited(_importAnimatedDrawing()),
    inspectorCubit: inspectorCubit,
    isPreviewing: isPreviewing && !isPreviewPaused,
    writingSoundPreviewEnabled: !isPreviewing,
    voicePlayheadSeconds: currentPreviewPositionSeconds,
    onDrawingSpeedChanged: (value) {
      _beginTimelineTimingChange();
      cubit.setDrawingSpeed(value);
      _syncTimelineAfterTimingMutation();
    },
    onPenTravelSpeedChanged: (value) {
      _beginTimelineTimingChange();
      cubit.setPenTravelSpeed(value);
      _syncTimelineAfterTimingMutation();
    },
    onTimingChangeStart: _beginTimelineTimingChange,
    onTimingChangeEnd: _endTimelineTimingChange,
    onResetSettings: _resetSettings,
    writingSoundPreviewController: writingSoundPreviewController,
    onOpenHandLibrary: _openHandLibrary,
    onCalibrateHand: _calibrateHand,
    onImportVoiceGuide: _importVoiceGuide,
    onRemoveVoiceGuide: cubit.removeVoiceGuide,
    cameraEditing: cameraEditingCubit,
    onPreviewCameraShot: _previewCameraShot,
    onClose: onClose,
  );

  void _openImageAnimation() {
    cubit.openImageAnimationControls();
    if (isPreviewing) _stopPreview();
    final layout = EditorLayoutSpec.fromConstraints(
      BoxConstraints.tight(MediaQuery.sizeOf(context)),
    );
    _showAnimationInspector(
      isInspectorDocked: !layout.isNarrow,
      opensStartDrawer: Directionality.of(context) == TextDirection.rtl,
    );
  }

  Future<void> _importAnimatedDrawing() async {
    final revision = cubit.state.canvasRevision;
    await _importDrawing();
    if (!mounted ||
        revision == cubit.state.canvasRevision ||
        !cubit.hasDrawing) {
      return;
    }
    await cubit.prepareImageAnimation();
  }

  void _showAnimationInspector({
    required bool isInspectorDocked,
    required bool opensStartDrawer,
  }) {
    inspectorCubit.select(InspectorTab.animation);
    if (isInspectorDocked) {
      if (_inspectorCollapsed) setState(() => _inspectorCollapsed = false);
      return;
    }
    final scaffold = scaffoldKey.currentState;
    if (opensStartDrawer) {
      scaffold?.openDrawer();
    } else {
      scaffold?.openEndDrawer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: cubit,
      child: MultiBlocListener(
        listeners: [
          BlocListener<EditorCubit, EditorState>(
            bloc: cubit,
            listenWhen: (previous, current) =>
                previous.documentRevision != current.documentRevision ||
                previous.canvasRevision != current.canvasRevision,
            listener: (_, _) {
              // A completed preview intentionally leaves its final frame
              // visible. Once the project or canvas changes, that frame no
              // longer belongs to the current content and must be discarded.
              // Otherwise a replacement image is painted through the stale
              // preview mask and can appear blank after undo -> clear -> import.
              if (!isPreviewing && isTimelineFrameVisible) {
                _stopPreview();
              }
            },
          ),
          BlocListener<EditorCubit, EditorState>(
            bloc: cubit,
            listenWhen: (previous, current) =>
                previous.selectedSmartSectionId !=
                    current.selectedSmartSectionId &&
                current.selectedSmartSectionId != null,
            listener: (_, _) => inspectorCubit.select(InspectorTab.animation),
          ),
          BlocListener<CameraEditingCubit, CameraEditingState>(
            bloc: cameraEditingCubit,
            listenWhen: (previous, current) =>
                previous.selectedShotIds.isNotEmpty &&
                current.selectedShotIds.isEmpty,
            listener: (_, _) {
              if (!_canvasFocusMode && !_inspectorCollapsed) {
                setState(() => _inspectorCollapsed = true);
              }
            },
          ),
        ],
        child: BlocBuilder<EditorCubit, EditorState>(
          bloc: cubit,
          builder: (context, state) {
            final renderProject = (isPreviewing || isTimelineFrameVisible)
                ? previewSnapshot?.project ?? cubit.project
                : cubit.project;
            return LayoutBuilder(
              builder: (context, constraints) {
                final layout = EditorLayoutSpec.fromConstraints(constraints);
                final isRtl = Directionality.of(context) == TextDirection.rtl;
                final inspectorDrawer = layout.isNarrow
                    ? Drawer(
                        key: const ValueKey('editor-inspector-drawer'),
                        width: layout.inspectorDrawerWidth,
                        child: SafeArea(
                          child: Builder(
                            builder: (drawerContext) => _buildInspector(
                              onClose: () =>
                                  Navigator.of(drawerContext).maybePop(),
                            ),
                          ),
                        ),
                      )
                    : null;
                return StudioPlatformMenuBar(
                  actions: _menuActions(opensStartDrawer: isRtl),
                  isBusy: isExporting || state.isDrawingImporting,
                  isPreviewing: isPreviewing,
                  isPreviewPaused: isPreviewPaused,
                  canPreview: state.canPreview,
                  hasCanvasContent: state.hasCanvasContent,
                  hasDrawing: state.hasDrawing,
                  hasHand: state.hasHand,
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          _cancelActiveEditOrStopPreview,
                      const SingleActivator(
                        LogicalKeyboardKey.keyZ,
                        meta: true,
                      ): _undoShortcut,
                      const SingleActivator(
                        LogicalKeyboardKey.keyZ,
                        meta: true,
                        shift: true,
                      ): _redoShortcut,
                    },
                    child: Focus(
                      autofocus: true,
                      child: Scaffold(
                        key: scaffoldKey,
                        drawer: isRtl ? inspectorDrawer : null,
                        endDrawer: isRtl ? null : inspectorDrawer,
                        body: Stack(
                          children: [
                            AbsorbPointer(
                              absorbing: isExporting,
                              child: SafeArea(
                                child: Column(
                                  key: ValueKey(
                                    'editor-layout-${layout.tier.name}',
                                  ),
                                  children: [
                                    EditorToolbar(
                                      cubit: cubit,
                                      layout: layout,
                                      actions: _toolbarActions(
                                        opensStartDrawer: isRtl,
                                      ),
                                      isPreviewing: isPreviewing,
                                      isPreviewPaused: isPreviewPaused,
                                      isExporting: isExporting,
                                      exportProgress: exportProgress,
                                    ),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: Row(
                                        // Canvas/inspector topology is intentionally
                                        // stable; content inside the inspector is RTL.
                                        textDirection: TextDirection.ltr,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  child: EditorWorkspace(
                                                    cubit: cubit,
                                                    renderSnapshot:
                                                        isPreviewing ||
                                                            isTimelineFrameVisible
                                                        ? previewSnapshot
                                                        : null,
                                                    resolvedFrame:
                                                        currentResolvedFrame,
                                                    resolvedFrameListenable:
                                                        previewFrame,
                                                    layout: layout,
                                                    previewProgress:
                                                        previewingStrokeIndex ==
                                                            null
                                                        ? _drawingProgress
                                                        : isolatedStrokePlayback
                                                              .value,
                                                    previewStrokeIndex:
                                                        previewingStrokeIndex,
                                                    isPreviewing:
                                                        isPreviewing ||
                                                        isTimelineFrameVisible,
                                                    isPlaybackActive:
                                                        isPreviewing,
                                                    interactionLocked:
                                                        isPreviewing &&
                                                        !isPreviewPaused,
                                                    onSmartSectionSelected: () =>
                                                        _showAnimationInspector(
                                                          isInspectorDocked:
                                                              layout
                                                                  .docksInspector,
                                                          opensStartDrawer:
                                                              isRtl,
                                                        ),
                                                    cameraEditing:
                                                        cameraEditingCubit,
                                                    playheadTime:
                                                        currentResolvedFrame
                                                            ?.time ??
                                                        TimelineTime.zero,
                                                    onPreviewCameraShot:
                                                        _previewCameraShot,
                                                    canPreview:
                                                        cubit.canPreview ||
                                                        cubit.voiceGuide !=
                                                            null,
                                                    isPreviewPaused:
                                                        isPreviewPaused,
                                                    previewPositionSeconds:
                                                        currentPreviewPositionSeconds,
                                                    previewDurationSeconds:
                                                        _previewDuration,
                                                    onPlayPreview: _playPreview,
                                                    onPausePreview:
                                                        _pausePreview,
                                                    onResumePreview:
                                                        _resumePreview,
                                                    onStopPreview: _stopPreview,
                                                    onSeekPreview: (seconds) =>
                                                        unawaited(
                                                          _seekPreview(seconds),
                                                        ),
                                                    hasPreviewAudio:
                                                        _hasPreviewAudio,
                                                    previewVolume:
                                                        previewVolume,
                                                    onTogglePreviewMute:
                                                        _togglePreviewMute,
                                                    onPreviewVolumeChanged:
                                                        _setPreviewVolume,
                                                    isFocusMode:
                                                        _canvasFocusMode,
                                                    onToggleFocusMode: () =>
                                                        setState(
                                                          () => _canvasFocusMode =
                                                              !_canvasFocusMode,
                                                        ),
                                                  ),
                                                ),
                                                if (!_canvasFocusMode)
                                                  MouseRegion(
                                                    cursor: SystemMouseCursors
                                                        .resizeUpDown,
                                                    child: GestureDetector(
                                                      key: const ValueKey(
                                                        'timeline-resize-handle',
                                                      ),
                                                      behavior: HitTestBehavior
                                                          .opaque,
                                                      onVerticalDragUpdate:
                                                          (details) => setState(
                                                            () => _timelineHeight =
                                                                (_timelineHeight -
                                                                        details
                                                                            .delta
                                                                            .dy)
                                                                    .clamp(
                                                                      240.0,
                                                                      460.0,
                                                                    ),
                                                          ),
                                                      child: Container(
                                                        height: 8,
                                                        alignment:
                                                            Alignment.center,
                                                        color: context
                                                            .studioColors
                                                            .surface,
                                                        child: Container(
                                                          width: 48,
                                                          height: 3,
                                                          decoration: BoxDecoration(
                                                            color: context
                                                                .studioColors
                                                                .border,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  3,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                if (!_canvasFocusMode)
                                                  EditorTimelineDock(
                                                    height:
                                                        _timelineHeight +
                                                        (renderProject
                                                                    .voiceGuide ==
                                                                null
                                                            ? 0
                                                            : 78),
                                                    cubit: cubit,
                                                    cameraEditing:
                                                        cameraEditingCubit,
                                                    onAutoCamera: () =>
                                                        showAutoDirectorDialog(
                                                          context: context,
                                                          editor: cubit,
                                                          cameraEditing:
                                                              cameraEditingCubit,
                                                          onPreviewPlan:
                                                              _previewAutoDirectorPlan,
                                                          onPendingPlanChanged:
                                                              (
                                                                plan,
                                                              ) => setState(
                                                                () =>
                                                                    pendingAutoDirectorPlan =
                                                                        plan,
                                                              ),
                                                        ),
                                                    onRegenerateCameraRange:
                                                        (
                                                          interval,
                                                        ) => showAutoDirectorDialog(
                                                          context: context,
                                                          editor: cubit,
                                                          cameraEditing:
                                                              cameraEditingCubit,
                                                          onPreviewPlan:
                                                              _previewAutoDirectorPlan,
                                                          initialScope:
                                                              AutoDirectorScope.affectedRange(
                                                                interval,
                                                              ),
                                                          onPendingPlanChanged:
                                                              (
                                                                plan,
                                                              ) => setState(
                                                                () =>
                                                                    pendingAutoDirectorPlan =
                                                                        plan,
                                                              ),
                                                        ),
                                                    pendingCameraPlan:
                                                        pendingAutoDirectorPlan,
                                                    onPreviewCameraShot:
                                                        _previewCameraShot,
                                                    playheadTime:
                                                        TimelineTime.fromMicroseconds(
                                                          (currentPreviewPositionSeconds *
                                                                  Duration
                                                                      .microsecondsPerSecond)
                                                              .round(),
                                                        ),
                                                    drawingPlayheadTime:
                                                        TimelineTime.fromMicroseconds(
                                                          (_drawingTrackPositionSeconds *
                                                                  Duration
                                                                      .microsecondsPerSecond)
                                                              .round(),
                                                        ),
                                                    previewProgress:
                                                        _drawingProgress,
                                                    isPreviewing: isPreviewing,
                                                    onSeek: (progress) {
                                                      final timelineDuration =
                                                          (previewSnapshot
                                                                  ?.timeline
                                                                  .duration
                                                                  .microseconds ??
                                                              _timelineForControls
                                                                  .duration
                                                                  .microseconds) /
                                                          Duration
                                                              .microsecondsPerSecond;
                                                      unawaited(
                                                        _seekPreview(
                                                          timelineDuration *
                                                              progress,
                                                        ),
                                                      );
                                                    },
                                                    onDrawingSeek: (progress) {
                                                      final timelineDuration =
                                                          (previewSnapshot
                                                                  ?.timeline
                                                                  .duration
                                                                  .microseconds ??
                                                              _timelineForControls
                                                                  .duration
                                                                  .microseconds) /
                                                          Duration
                                                              .microsecondsPerSecond;
                                                      _seekDrawingTrack(
                                                        timelineDuration *
                                                            progress,
                                                      );
                                                    },
                                                    onPreviewStroke:
                                                        _previewStroke,
                                                    onTimingChangeStart:
                                                        _beginTimelineTimingChange,
                                                    onTimingChangeEnd:
                                                        _endTimelineTimingChange,
                                                    audioLaneBuilder:
                                                        renderProject
                                                                .voiceGuide ==
                                                            null
                                                        ? null
                                                        : (
                                                            context,
                                                            geometry,
                                                          ) => VoiceGuideBar(
                                                            guide: renderProject
                                                                .voiceGuide!,
                                                            project:
                                                                renderProject,
                                                            positionSeconds:
                                                                _voiceTrackPositionSeconds,
                                                            isPlaying:
                                                                isPreviewing,
                                                            isPaused:
                                                                isPreviewPaused,
                                                            isMissing: state
                                                                .isVoiceGuideMissing,
                                                            selectedSectionKey:
                                                                state
                                                                    .selectedTimingSectionKey,
                                                            onPlayPause:
                                                                _toggleVoiceTrackEnabled,
                                                            onSeek:
                                                                _seekVoiceTrack,
                                                            onReplace:
                                                                _importVoiceGuide,
                                                            onLocate: () async {
                                                              if (isPreviewing) {
                                                                _stopPreview();
                                                              }
                                                              await cubit
                                                                  .locateVoiceGuide(
                                                                    copy:
                                                                        _voiceGuidePickerCopy(),
                                                                  );
                                                            },
                                                            onRemove: () {
                                                              if (isPreviewing) {
                                                                _stopPreview();
                                                              }
                                                              cubit
                                                                  .removeVoiceGuide();
                                                            },
                                                            onSelectSection: cubit
                                                                .selectTimingSection,
                                                            timelineMode: true,
                                                            timelineDurationSeconds:
                                                                geometry
                                                                    .timelineDurationSeconds,
                                                            trackStartSeconds:
                                                                geometry
                                                                    .trackStartSeconds,
                                                            trackEnabled:
                                                                _voiceTrackEnabled,
                                                            onToggleTrackEnabled:
                                                                _toggleVoiceTrackEnabled,
                                                          ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (layout.docksInspector &&
                                              !_canvasFocusMode) ...[
                                            const VerticalDivider(width: 1),
                                            if (_inspectorCollapsed)
                                              SizedBox(
                                                key: const ValueKey(
                                                  'editor-inspector-collapsed',
                                                ),
                                                width: 42,
                                                child: Align(
                                                  alignment:
                                                      Alignment.topCenter,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                          top: 8,
                                                        ),
                                                    child: InspectorEdgeToggleButton(
                                                      key: const ValueKey(
                                                        'open-collapsed-inspector',
                                                      ),
                                                      tooltip: context
                                                          .l10n
                                                          .openInspector,
                                                      onPressed: () => setState(
                                                        () =>
                                                            _inspectorCollapsed =
                                                                false,
                                                      ),
                                                      expanded: false,
                                                    ),
                                                  ),
                                                ),
                                              )
                                            else
                                              SizedBox(
                                                key: const ValueKey(
                                                  'editor-inspector-docked',
                                                ),
                                                width: layout.inspectorWidth,
                                                child: _buildInspector(
                                                  onClose: () => setState(
                                                    () => _inspectorCollapsed =
                                                        true,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    EditorStatusBar(
                                      cubit: cubit,
                                      layout: layout,
                                      isPreviewing: isPreviewing,
                                      isPreviewPaused: isPreviewPaused,
                                      previewProgress: _previewProgress,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            BlocProvider.value(
                              value: exportStatusCubit,
                              child: ExportStatusOverlay(
                                compact: layout.isNarrow,
                                topInset: layout.toolbarHeight,
                                onCancel: _cancelExport,
                                onReveal: (path) => unawaited(
                                  _runExportResultAction(
                                    () => exportResultActions.reveal(path),
                                  ),
                                ),
                                onOpen: (path) => unawaited(
                                  _runExportResultAction(
                                    () => exportResultActions.open(path),
                                  ),
                                ),
                                onCopyPath: (path) => unawaited(
                                  _runExportResultAction(() async {
                                    await exportResultActions.copyPath(path);
                                    exportStatusCubit.markPathCopied();
                                  }),
                                ),
                                onRetry: () => unawaited(_exportVideo()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
