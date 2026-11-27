import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_ui_cubit.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_ui_state.dart';
import 'package:handdraw_studio/features/auto_director/application/auto_director_application_service.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_models.dart';
import 'package:handdraw_studio/features/auto_director/domain/models/auto_director_presets.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_cubit.dart';
import 'package:handdraw_studio/features/camera/application/camera_editing_state.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/project/domain/identity/project_ids.dart';

Future<void> showAutoDirectorDialog({
  required BuildContext context,
  required EditorCubit editor,
  required CameraEditingCubit cameraEditing,
  required ValueChanged<AutoDirectorPlan> onPreviewPlan,
  AutoDirectorScope? initialScope,
  ValueChanged<AutoDirectorPlan?>? onPendingPlanChanged,
  AutoDirectorApplicationService? service,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => AutoDirectorDialog(
    editor: editor,
    cameraEditing: cameraEditing,
    onPreviewPlan: onPreviewPlan,
    initialScope: initialScope,
    onPendingPlanChanged: onPendingPlanChanged,
    service: service,
  ),
);

class AutoDirectorDialog extends StatefulWidget {
  const AutoDirectorDialog({
    super.key,
    required this.editor,
    required this.cameraEditing,
    required this.onPreviewPlan,
    this.initialScope,
    this.onPendingPlanChanged,
    this.service,
  });

  final EditorCubit editor;
  final CameraEditingCubit cameraEditing;
  final ValueChanged<AutoDirectorPlan> onPreviewPlan;
  final AutoDirectorScope? initialScope;
  final ValueChanged<AutoDirectorPlan?>? onPendingPlanChanged;
  final AutoDirectorApplicationService? service;

  @override
  State<AutoDirectorDialog> createState() => _AutoDirectorDialogState();
}

class _AutoDirectorDialogState extends State<AutoDirectorDialog> {
  late final AutoDirectorUiCubit director = AutoDirectorUiCubit(
    initialSettings: widget.editor.state.document.autoDirectorSettings,
    service: widget.service,
  );
  StreamSubscription<EditorState>? documentChanges;
  StreamSubscription<AutoDirectorUiState>? planChanges;
  late int observedRevision = widget.editor.state.documentRevision.value;

  bool get rtl => Directionality.of(context) == TextDirection.rtl;
  String t(String en, String ar) => rtl ? ar : en;

  @override
  void initState() {
    super.initState();
    if (widget.initialScope != null) director.setScope(widget.initialScope!);
    documentChanges = widget.editor.stream.listen((state) {
      if (state.documentRevision.value != observedRevision) {
        director.markStale();
      }
    });
    planChanges = director.stream.listen(
      (state) => widget.onPendingPlanChanged?.call(state.plan),
    );
  }

  @override
  void dispose() {
    documentChanges?.cancel();
    planChanges?.cancel();
    director.close();
    super.dispose();
  }

  void close() {
    if (director.state.isGenerating) director.cancel();
    widget.onPendingPlanChanged?.call(null);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: director,
    child: BlocBuilder<AutoDirectorUiCubit, AutoDirectorUiState>(
      builder: (context, state) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): _CloseIntent(),
        },
        child: Actions(
          actions: {
            _CloseIntent: CallbackAction<_CloseIntent>(
              onInvoke: (_) => close(),
            ),
          },
          child: FocusScope(
            autofocus: true,
            child: AlertDialog(
              key: const ValueKey('auto-director-dialog'),
              title: Row(
                children: [
                  const Icon(Icons.auto_awesome_motion),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t('Auto Camera', 'كاميرا تلقائية'))),
                  IconButton(
                    tooltip: t('Close', 'إغلاق'),
                    onPressed: close,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              content: SizedBox(width: 680, height: 600, child: _auto(state)),
              actions: _actions(state),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _auto(AutoDirectorUiState state) => ListView(
    children: [
      Text(
        t(
          'Choose a style, generate a temporary plan, then review it before applying.',
          'اختر نمطًا، وأنشئ خطة مؤقتة، ثم راجعها قبل التطبيق.',
        ),
      ),
      if (MediaQuery.disableAnimationsOf(context))
        Card(
          child: ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: Text(t('Reduce Motion is enabled', 'تقليل الحركة مفعّل')),
            subtitle: Text(
              t(
                'No Motion is recommended. Project settings were not changed.',
                'يوصى بنمط بلا حركة. لم يتم تغيير إعدادات المشروع.',
              ),
            ),
            trailing: TextButton(
              onPressed: () =>
                  director.selectPreset(AutoDirectorPresetId.noMotion),
              child: Text(t('Use No Motion', 'استخدم بلا حركة')),
            ),
          ),
        ),
      const SizedBox(height: 8),
      _presetPicker(state),
      const SizedBox(height: 12),
      ExpansionTile(
        key: const ValueKey('auto-director-scope-options'),
        tilePadding: EdgeInsets.zero,
        title: Text(t('Scope (optional)', 'النطاق (اختياري)')),
        subtitle: Text(t('Entire Project', 'المشروع بالكامل')),
        children: [_scopePicker(state)],
      ),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('auto-director-advanced-link'),
          onPressed: director.toggleAdvanced,
          icon: const Icon(Icons.tune),
          label: Text(t('Advanced settings', 'إعدادات متقدمة')),
        ),
      ),
      if (state.advancedVisible) _advanced(state),
      const SizedBox(height: 12),
      if (state.isGenerating) _progress(state),
      if (state.phase == AutoDirectorUiPhase.stale)
        _message(
          Icons.sync_problem,
          t('Project changed — Regenerate', 'تغيّر المشروع — أعد الإنشاء'),
        ),
      if (state.phase == AutoDirectorUiPhase.failed) _generationError(state),
      if (state.plan case final plan?) _review(state, plan),
    ],
  );

  Widget _presetPicker(AutoDirectorUiState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t('Choose a style', 'اختر النمط')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final id in AutoDirectorPresetId.values)
            if (id != AutoDirectorPresetId.custom)
              SizedBox(
                width: 205,
                child: Card(
                  color: state.settings.presetId == id
                      ? Theme.of(context).colorScheme.secondaryContainer
                      : null,
                  child: InkWell(
                    key: ValueKey('auto-director-preset-${id.name}'),
                    onTap: state.isGenerating
                        ? null
                        : () => director.selectPreset(id),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _presetName(id),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _presetDescription(id),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
        ],
      ),
    ],
  );

  Widget _scopePicker(AutoDirectorUiState state) {
    final editorState = widget.editor.state;
    final selectedSections = editorState.selectedTimelineSectionIds;
    final sceneId = editorState.selectedTimelineSceneId;
    final kind = state.scope?.kind ?? AutoDirectorScopeKind.entireProject;
    return DropdownButtonFormField<AutoDirectorScopeKind>(
      key: const ValueKey('auto-director-scope'),
      initialValue: kind,
      decoration: InputDecoration(
        labelText: t('Generate scope', 'نطاق الإنشاء'),
        helperText: _scopeUnavailableReason(kind),
      ),
      items: [
        DropdownMenuItem(
          value: AutoDirectorScopeKind.entireProject,
          child: Text(t('Entire Project', 'المشروع بالكامل')),
        ),
        DropdownMenuItem(
          value: AutoDirectorScopeKind.scene,
          enabled: sceneId != null,
          child: Text(t('Current Scene', 'المشهد الحالي')),
        ),
        DropdownMenuItem(
          value: AutoDirectorScopeKind.selectedSections,
          enabled: selectedSections.isNotEmpty,
          child: Text(t('Selected Sections', 'الأقسام المحددة')),
        ),
        DropdownMenuItem(
          value: AutoDirectorScopeKind.selectedTimeRange,
          enabled: false,
          child: Text(t('Selected Time Range', 'النطاق الزمني المحدد')),
        ),
        DropdownMenuItem(
          value: AutoDirectorScopeKind.affectedRange,
          enabled: state.scope?.kind == AutoDirectorScopeKind.affectedRange,
          child: Text(t('Regenerate Affected', 'إعادة إنشاء المتأثر')),
        ),
      ],
      onChanged: state.isGenerating
          ? null
          : (value) {
              if (value == null) return;
              switch (value) {
                case AutoDirectorScopeKind.entireProject:
                  director.setScope(AutoDirectorScope.entireProject());
                case AutoDirectorScopeKind.scene:
                  if (sceneId != null) {
                    director.setScope(
                      AutoDirectorScope.scene(SceneId(sceneId)),
                    );
                  }
                case AutoDirectorScopeKind.selectedSections:
                  if (selectedSections.isNotEmpty) {
                    director.setScope(
                      AutoDirectorScope.selectedSections(
                        selectedSections.map(SectionId.new).toSet(),
                      ),
                    );
                  }
                case AutoDirectorScopeKind.affectedRange:
                  break;
                case AutoDirectorScopeKind.selectedTimeRange:
                  break;
              }
            },
    );
  }

  String? _scopeUnavailableReason(AutoDirectorScopeKind kind) => switch (kind) {
    AutoDirectorScopeKind.scene
        when widget.editor.state.selectedTimelineSceneId == null =>
      t('Select a scene first.', 'حدد مشهدًا أولًا.'),
    AutoDirectorScopeKind.selectedSections
        when widget.editor.state.selectedTimelineSectionIds.isEmpty =>
      t(
        'Select one or more sections first.',
        'حدد قسمًا واحدًا أو أكثر أولًا.',
      ),
    AutoDirectorScopeKind.selectedTimeRange => t(
      'Select a time range in the timeline first.',
      'حدد نطاقًا زمنيًا في الخط الزمني أولًا.',
    ),
    AutoDirectorScopeKind.affectedRange when stateScopeIsNotAffected => t(
      'Use Regenerate this range from a Camera clip.',
      'استخدم إعادة إنشاء هذا النطاق من مقطع كاميرا.',
    ),
    _ => null,
  };

  bool get stateScopeIsNotAffected =>
      director.state.scope?.kind != AutoDirectorScopeKind.affectedRange;

  Widget _progress(AutoDirectorUiState state) => Semantics(
    liveRegion: false,
    label: '${_phaseName(state.phase)} ${(state.progress * 100).round()}%',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LinearProgressIndicator(value: state.progress),
        const SizedBox(height: 6),
        Text(_phaseName(state.phase)),
      ],
    ),
  );

  Widget _review(AutoDirectorUiState state, AutoDirectorPlan plan) {
    final metrics = plan.qualityMetrics;
    final largeJumps = plan.proposedShots
        .where(
          (shot) => shot.reasonCodes.contains(DirectorReasonCode.largeJumpCut),
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        SegmentedButton<AutoDirectorPlanView>(
          segments: [
            ButtonSegment(
              value: AutoDirectorPlanView.current,
              label: Text(t('Current Camera', 'الكاميرا الحالية')),
            ),
            ButtonSegment(
              value: AutoDirectorPlanView.proposed,
              label: Text(t('Proposed Camera', 'الكاميرا المقترحة')),
            ),
          ],
          selected: {state.planView},
          onSelectionChanged: (value) => director.showPlan(value.first),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _metric(t('Shots', 'اللقطات'), metrics.shotCount),
            _metric(t('Move', 'حركة'), metrics.moveCount),
            _metric(t('Cut', 'قطع'), metrics.cutCount),
            _metric(t('Fade', 'تلاشي'), metrics.fadeCount),
            _metric(
              t('Uncovered', 'غير مغطى'),
              metrics.uncoveredAttentionEvents,
            ),
            _metric(
              t('Readability', 'القراءة'),
              metrics.textReadabilityWarnings,
            ),
            _metric(t('Occlusion', 'الحجب'), metrics.handOcclusionWarnings),
            _metric(t('Large jumps', 'قفزات كبيرة'), largeJumps),
          ],
        ),
        if (metrics.uncoveredAttentionEvents > 0)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(
                    t(
                      'Manual or Locked shots leave content uncovered.',
                      'تترك اللقطات اليدوية أو المقفلة محتوى غير مغطى.',
                    ),
                  ),
                  subtitle: Text(
                    t(
                      'Protected shots are never overridden.',
                      'لن يتم تجاوز اللقطات المحمية.',
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () {},
                      child: Text(
                        t('Keep protected shots', 'الاحتفاظ باللقطات المحمية'),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        widget.cameraEditing.setCanvasMode(
                          CameraCanvasMode.editCamera,
                        );
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        t('Unlock / Edit manually', 'فتح القفل / تعديل يدوي'),
                      ),
                    ),
                    TextButton(
                      onPressed: close,
                      child: Text(t('Cancel', 'إلغاء')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Semantics(
          label: t('Proposed camera ghost clips', 'مقاطع الكاميرا المقترحة'),
          child: SizedBox(
            height: 54,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.planView == AutoDirectorPlanView.proposed
                  ? plan.proposedShots.length
                  : (widget.editor.state.document.cameraTrack?.shots.length ??
                        0),
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, index) => Chip(
                avatar: Icon(
                  state.planView == AutoDirectorPlanView.proposed
                      ? Icons.auto_awesome
                      : Icons.videocam,
                  size: 16,
                ),
                label: Text('${t('Shot', 'لقطة')} ${index + 1}'),
              ),
            ),
          ),
        ),
        if (state.planView == AutoDirectorPlanView.proposed)
          Semantics(
            label: t(
              'Proposed camera frames on canvas',
              'إطارات الكاميرا المقترحة على اللوحة',
            ),
            image: true,
            child: SizedBox(
              height: 120,
              child: CustomPaint(
                painter: _ProposedFramesPainter(
                  plan,
                  Theme.of(context).colorScheme,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ExpansionTile(
          title: Text(t('Advanced plan details', 'تفاصيل الخطة المتقدمة')),
          children: [
            for (final shot in plan.proposedShots)
              ListTile(
                dense: true,
                title: Text(
                  shot.reasonCodes.map((value) => value.name).join(', '),
                ),
                subtitle: Text(
                  '${shot.targetRegionIds.join(', ')} · score ${shot.score.total.toStringAsFixed(2)}',
                  textDirection: TextDirection.ltr,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _advanced(AutoDirectorUiState state) {
    final overrides = state.settings.customOverrides;
    void update({
      DirectorMotionAmount? motion,
      DirectorFraming? framing,
      double? textEmphasis,
      Duration? minimumHold,
      DirectorTransitionPreference? transition,
      bool? movementDuringDrawing,
      DirectorOverviewFrequency? overview,
      bool? handSafe,
    }) => director.setCustomOverrides(
      AutoDirectorCustomOverrides(
        motionAmount: motion ?? overrides.motionAmount,
        framing: framing ?? overrides.framing,
        textEmphasis: textEmphasis ?? overrides.textEmphasis,
        minimumHold: minimumHold ?? overrides.minimumHold,
        transitionPreference: transition ?? overrides.transitionPreference,
        allowMovementDuringDrawing:
            movementDuringDrawing ?? overrides.allowMovementDuringDrawing,
        overviewFrequency: overview ?? overrides.overviewFrequency,
        handSafeFraming: handSafe ?? overrides.handSafeFraming,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t('Director controls', 'إعدادات المخرج')),
        DropdownButtonFormField<DirectorMotionAmount>(
          initialValue: overrides.motionAmount ?? DirectorMotionAmount.minimal,
          decoration: InputDecoration(
            labelText: t('Motion amount', 'مقدار الحركة'),
          ),
          items: [
            for (final value in DirectorMotionAmount.values)
              DropdownMenuItem(value: value, child: Text(value.name)),
          ],
          onChanged: (value) => update(motion: value),
        ),
        DropdownButtonFormField<DirectorFraming>(
          initialValue: overrides.framing ?? DirectorFraming.balanced,
          decoration: InputDecoration(labelText: t('Framing', 'التأطير')),
          items: [
            for (final value in DirectorFraming.values)
              DropdownMenuItem(value: value, child: Text(value.name)),
          ],
          onChanged: (value) => update(framing: value),
        ),
        ListTile(
          title: Text(t('Text emphasis', 'تأكيد النص')),
          subtitle: Slider(
            value: overrides.textEmphasis ?? .8,
            divisions: 10,
            label: '${((overrides.textEmphasis ?? .8) * 100).round()}%',
            onChanged: (value) => update(textEmphasis: value),
          ),
        ),
        ListTile(
          title: Text(t('Minimum hold', 'الحد الأدنى للثبات')),
          subtitle: Slider(
            min: .4,
            max: 2.5,
            divisions: 21,
            value: (overrides.minimumHold?.inMilliseconds ?? 1000) / 1000,
            label:
                '${((overrides.minimumHold?.inMilliseconds ?? 1000) / 1000).toStringAsFixed(1)}s',
            onChanged: (value) => update(
              minimumHold: Duration(milliseconds: (value * 1000).round()),
            ),
          ),
        ),
        DropdownButtonFormField<DirectorTransitionPreference>(
          initialValue:
              overrides.transitionPreference ??
              DirectorTransitionPreference.balanced,
          decoration: InputDecoration(
            labelText: t('Prefer transition', 'تفضيل الانتقال'),
          ),
          items: [
            for (final value in DirectorTransitionPreference.values)
              DropdownMenuItem(value: value, child: Text(value.name)),
          ],
          onChanged: (value) => update(transition: value),
        ),
        DropdownButtonFormField<DirectorOverviewFrequency>(
          initialValue:
              overrides.overviewFrequency ??
              DirectorOverviewFrequency.groupsOnly,
          decoration: InputDecoration(
            labelText: t('Overview frequency', 'تكرار العرض العام'),
          ),
          items: [
            for (final value in DirectorOverviewFrequency.values)
              DropdownMenuItem(value: value, child: Text(value.name)),
          ],
          onChanged: (value) => update(overview: value),
        ),
        SwitchListTile(
          title: Text(
            t('Allow movement during drawing', 'السماح بالحركة أثناء الرسم'),
          ),
          value: overrides.allowMovementDuringDrawing ?? false,
          onChanged: (value) => update(movementDuringDrawing: value),
        ),
        SwitchListTile(
          title: Text(t('Hand-safe framing', 'تأطير آمن لليد')),
          value: overrides.handSafeFraming ?? true,
          onChanged: (value) => update(handSafe: value),
        ),
        const Divider(),
        Text(
          t(
            'Shots, keyframes, transitions, timing, easing, authorship and locks remain available in the Camera track and inspector.',
            'تظل اللقطات والإطارات والانتقالات والتوقيت والتسارع والملكية والأقفال متاحة في مسار الكاميرا وخصائصها.',
          ),
        ),
        FilledButton.tonalIcon(
          onPressed: () {
            widget.cameraEditing.setCanvasMode(CameraCanvasMode.editCamera);
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.video_settings),
          label: Text(
            t('Open Camera Track editing', 'فتح تحرير مسار الكاميرا'),
          ),
        ),
      ],
    );
  }

  List<Widget> _actions(AutoDirectorUiState state) => [
    TextButton(onPressed: close, child: Text(t('Cancel', 'إلغاء'))),
    if (state.isGenerating)
      FilledButton.tonal(
        onPressed: director.cancel,
        child: Text(t('Stop generation', 'إيقاف الإنشاء')),
      )
    else if (state.plan == null || state.phase == AutoDirectorUiPhase.stale)
      FilledButton.icon(
        key: const ValueKey('auto-director-generate'),
        onPressed: _generate,
        icon: const Icon(Icons.auto_awesome),
        label: Text(
          state.phase == AutoDirectorUiPhase.stale
              ? t('Regenerate', 'إعادة الإنشاء')
              : t('Generate & Preview', 'إنشاء ومعاينة'),
        ),
      )
    else ...[
      OutlinedButton.icon(
        key: const ValueKey('auto-director-preview'),
        onPressed: () {
          director.showPlan(AutoDirectorPlanView.proposed);
          widget.onPreviewPlan(state.plan!);
        },
        icon: const Icon(Icons.play_arrow),
        label: Text(t('Preview', 'معاينة')),
      ),
      FilledButton.icon(
        key: const ValueKey('auto-director-apply'),
        onPressed: state.phase == AutoDirectorUiPhase.ready
            ? () async {
                final settings = state.settings;
                final applied = await director.apply(
                  (plan) => widget.editor.applyAutoDirectorPlan(
                    plan,
                    settings: settings,
                  ),
                );
                if (!mounted || !applied) return;
                observedRevision = widget.editor.state.documentRevision.value;
                Navigator.of(context).pop();
              }
            : null,
        icon: const Icon(Icons.check),
        label: Text(t('Apply', 'تطبيق')),
      ),
    ],
  ];

  Widget _metric(String label, Object value) =>
      Chip(label: Text('$label: $value'));
  Widget _message(IconData icon, String text) => Card(
    child: ListTile(leading: Icon(icon), title: Text(text)),
  );

  Future<void> _generate() => director.generate(
    timeline: widget.editor.compileTimeline(),
    graph: widget.editor.compileSemanticGraph(),
    cameraTrack: widget.editor.state.document.cameraTrack,
  );

  Widget _generationError(AutoDirectorUiState state) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: Text(
              t(
                'Could not create the camera plan.',
                'تعذر إنشاء خطة الكاميرا.',
              ),
            ),
            subtitle: Text(
              t(
                'The project was not changed. Try again.',
                'لم يتم تغيير المشروع. حاول مرة أخرى.',
              ),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            children: [
              TextButton(
                key: const ValueKey('auto-director-error-cancel'),
                onPressed: close,
                child: Text(t('Cancel', 'إلغاء')),
              ),
              if (state.technicalDetails case final details?)
                TextButton.icon(
                  key: const ValueKey('auto-director-copy-details'),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: details)),
                  icon: const Icon(Icons.copy),
                  label: Text(t('Copy details', 'نسخ التفاصيل')),
                ),
              FilledButton(
                key: const ValueKey('auto-director-retry'),
                onPressed: _generate,
                child: Text(t('Retry', 'إعادة المحاولة')),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  String _presetName(AutoDirectorPresetId id) => switch (id) {
    AutoDirectorPresetId.educationalCalm => t(
      'Educational Calm',
      'تعليمي هادئ',
    ),
    AutoDirectorPresetId.classicWhiteboard => t(
      'Classic Whiteboard',
      'سبورة كلاسيكية',
    ),
    AutoDirectorPresetId.dynamicExplainer => t(
      'Dynamic Explainer',
      'شرح ديناميكي',
    ),
    AutoDirectorPresetId.presentation => t('Presentation', 'عرض تقديمي'),
    AutoDirectorPresetId.noMotion => t('No Motion', 'بلا حركة'),
    AutoDirectorPresetId.custom => t('Custom', 'مخصص'),
  };

  String _presetDescription(AutoDirectorPresetId id) => switch (id) {
    AutoDirectorPresetId.educationalCalm => t(
      'Recommended · steady and easy to follow.',
      'موصى به · ثابت وسهل المتابعة.',
    ),
    AutoDirectorPresetId.classicWhiteboard => t(
      'Natural framing for board drawing.',
      'تأطير طبيعي لرسم السبورة.',
    ),
    AutoDirectorPresetId.dynamicExplainer => t(
      'More movement for energetic explanations.',
      'حركة أكثر للشرح الحيوي.',
    ),
    AutoDirectorPresetId.presentation => t(
      'Clear scene-to-scene presentation cuts.',
      'انتقالات واضحة بين مشاهد العرض.',
    ),
    AutoDirectorPresetId.noMotion => t(
      'Static framing with no camera movement.',
      'تأطير ثابت دون حركة كاميرا.',
    ),
    AutoDirectorPresetId.custom => t('Custom settings.', 'إعدادات مخصصة.'),
  };

  String _phaseName(AutoDirectorUiPhase phase) => switch (phase) {
    AutoDirectorUiPhase.preparing => t('Preparing', 'تجهيز'),
    AutoDirectorUiPhase.analyzing => t('Analyzing', 'تحليل'),
    AutoDirectorUiPhase.generatingCandidates => t(
      'Generating candidates',
      'إنشاء البدائل',
    ),
    AutoDirectorUiPhase.optimizing => t('Optimizing', 'تحسين'),
    AutoDirectorUiPhase.validating => t('Validating', 'تحقق'),
    AutoDirectorUiPhase.applying => t('Applying', 'تطبيق'),
    _ => phase.name,
  };
}

final class _CloseIntent extends Intent {
  const _CloseIntent();
}

final class _ProposedFramesPainter extends CustomPainter {
  const _ProposedFramesPainter(this.plan, this.colors);
  final AutoDirectorPlan plan;
  final ColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = colors.surfaceContainer,
    );
    final scaleX = size.width;
    final scaleY = size.height;
    for (var index = 0; index < plan.proposedShots.length; index++) {
      final view = plan.proposedShots[index].keyframes.last.view;
      final width = (view.viewportWidth * scaleX).clamp(12, scaleX).toDouble();
      final height = (width * 9 / 16).clamp(8, scaleY).toDouble();
      final rect = Rect.fromCenter(
        center: Offset(view.centerX * scaleX, view.centerY * scaleY),
        width: width,
        height: height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = colors.primary.withValues(alpha: .75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = index == 0 ? 2.5 : 1.2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProposedFramesPainter oldDelegate) =>
      oldDelegate.plan != plan || oldDelegate.colors != colors;
}
