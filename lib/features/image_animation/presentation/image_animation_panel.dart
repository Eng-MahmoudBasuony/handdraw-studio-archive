import 'package:handdraw_studio/features/scene_composer/presentation/scene_composer_dialog.dart';
import 'package:handdraw_studio/features/codex_assistant/presentation/codex_assistant_dialog.dart';
import 'package:handdraw_studio/features/scene_split/presentation/smart_scene_split_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';

/// Controls the canonical editor document. No private canvas, player or export.
class ImageAnimationPanel extends StatelessWidget {
  const ImageAnimationPanel({
    super.key,
    required this.cubit,
    required this.onImportImage,
    required this.isPreviewing,
  });
  final EditorCubit cubit;
  final VoidCallback onImportImage;
  final bool isPreviewing;
  @override
  Widget build(BuildContext context) => BlocBuilder<EditorCubit, EditorState>(
    bloc: cubit,
    builder: (context, state) {
      String t(String en, String ar) =>
          Localizations.localeOf(context).languageCode == 'ar' ? ar : en;
      final project = cubit.project;
      final effect =
          ['reveal', 'penReveal'].contains(project.imageAnimationEffect)
          ? project.imageAnimationEffect
          : 'drawPaint';
      final busy =
          state.isAnalyzingSmartPaths ||
          state.isDrawingImporting ||
          isPreviewing;
      final selected = state.selectedStrokeIndex;
      final hasSelection =
          selected != null &&
          selected >= 0 &&
          selected < project.strokes.length;
      Future<void> generate(String effect) async {
        if (project.strokes.isNotEmpty) {
          final accepted = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(
                t('Regenerate this section?', 'إعادة رسم هذا القسم؟'),
              ),
              content: Text(
                t(
                  'Replaces its paths. Other sections and project settings stay intact. Undo is available.',
                  'سيستبدل مسارات القسم الحالي مع الاحتفاظ بباقي الأقسام وإعدادات المشروع. يمكنك التراجع.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(t('Cancel', 'إلغاء')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(t('Regenerate', 'إعادة التوليد')),
                ),
              ],
            ),
          );
          if (accepted != true) return;
        }
        await cubit.prepareImageAnimation(effect: effect);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t('Animate image', 'تحريك الصورة'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('scene-composer'),
            onPressed: busy ? null : () => showSceneComposer(context),
            icon: const Icon(Icons.dashboard_customize_outlined),
            label: Text(t('Create scene + library', 'أنشئ مشهد + المكتبة')),
          ),
          if (Theme.of(context).platform == TargetPlatform.macOS)
            OutlinedButton.icon(
              key: const ValueKey('animation-codex'),
              onPressed: busy
                  ? null
                  : () => showCodexAssistantDialog(context, cubit),
              icon: const Icon(Icons.auto_awesome),
              label: Text(t('Draw with Codex', 'ارسم مع Codex')),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('animation-image'),
            onPressed: busy ? null : onImportImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(
              cubit.hasDrawing
                  ? t('Change image', 'تغيير الصورة')
                  : t('Choose image', 'اختيار صورة'),
            ),
          ),
          const SizedBox(height: 12),
          Text(t('Effect', 'نوع التأثير')),
          DropdownButton<String>(
            key: const ValueKey('animation-effect'),
            isExpanded: true,
            value: effect,
            items: [
              DropdownMenuItem(
                value: 'drawPaint',
                child: Text(t('Draw & paint', 'رسم وتلوين')),
              ),
              DropdownMenuItem(
                value: 'reveal',
                child: Text(t('Reveal image', 'كشف الصورة')),
              ),
              DropdownMenuItem(
                value: 'penReveal',
                child: Text(t('Single pen reveal', 'كشف بضربة قلم')),
              ),
            ],
            onChanged: busy
                ? null
                : (value) {
                    if (value == null) return;
                    if (cubit.hasDrawing) {
                      generate(value);
                    } else {
                      cubit.setImageAnimationEffect(value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<bool>(
            key: ValueKey('path-mode-${state.tool == EditorTool.drawPath}'),
            initialValue: state.tool == EditorTool.drawPath,
            decoration: InputDecoration(
              labelText: t('Paths', 'تحديد المسارات'),
            ),
            items: [
              DropdownMenuItem(
                value: false,
                child: Text(t('Automatic', 'تلقائي')),
              ),
              DropdownMenuItem(
                value: true,
                child: Text(t('Draw my own', 'أرسمها بنفسي')),
              ),
            ],
            onChanged: busy || !cubit.hasDrawing
                ? null
                : (manual) {
                    if (manual == true &&
                        project.imageAnimationEffect == 'legacy') {
                      cubit.setImageAnimationEffect('drawPaint');
                    }
                    cubit.setImagePathEditing(true);
                    cubit.setTool(
                      manual == true ? EditorTool.drawPath : EditorTool.select,
                    );
                  },
          ),
          if (state.tool == EditorTool.drawPath) ...[
            OutlinedButton.icon(
              key: const ValueKey('animation-select-parts'),
              onPressed: busy || !cubit.hasDrawing
                  ? null
                  : () => showSmartSceneSplitDialog(
                      context,
                      cubit,
                      manualImageParts: true,
                    ),
              icon: const Icon(Icons.gesture),
              label: Text(t('Choose image parts', 'تحديد أجزاء الصورة')),
            ),
            Text(
              t(
                'Circle each part to give it its own timeline block. This replaces the current section; Undo restores it.',
                'حدّد كل جزء بدائرة ليظهر في بلوك مستقل على التايملاين. سيستبدل القسم الحالي، ويمكنك التراجع.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
          ],
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(t('Show hand', 'إظهار الإيد')),
            value: project.showDrawingHand,
            onChanged: busy ? null : cubit.setShowDrawingHand,
          ),
          _AnimationDurationField(
            seconds: cubit.imageAnimationDurationSeconds,
            enabled: !busy,
            label: t('Scene duration (seconds)', 'مدة المشهد (ثواني)'),
            invalidMessage: t(
              'Enter 1–300 seconds',
              'أدخل مدة من 1 إلى 300 ثانية',
            ),
            anchoredMessage: t(
              'Edit audio timing anchors before changing duration.',
              'عدّل ارتباطات التوقيت بالصوت قبل تغيير المدة.',
            ),
            onChanged: cubit.setImageAnimationDuration,
          ),
          const SizedBox(height: 12),
          if (cubit.hasDrawing && project.strokes.isEmpty)
            FilledButton(
              onPressed: busy ? null : () => generate(effect),
              child: Text(t('Prepare drawing', 'تجهيز الرسم')),
            ),
          if (state.isAnalyzingSmartPaths) ...[
            const LinearProgressIndicator(),
            TextButton(
              onPressed: cubit.isImageAnimationAnalyzing
                  ? cubit.cancelImageAnimation
                  : null,
              child: Text(t('Cancel', 'إلغاء')),
            ),
          ],
          OutlinedButton.icon(
            key: const ValueKey('animation-edit'),
            onPressed: busy || !cubit.hasDrawing
                ? null
                : () {
                    cubit.setImagePathEditing(!state.editingImagePaths);
                    cubit.setTool(EditorTool.select);
                  },
            icon: Icon(
              state.editingImagePaths ? Icons.check : Icons.edit_outlined,
            ),
            label: Text(
              state.editingImagePaths
                  ? t('Done', 'تم التعديل')
                  : t('Edit strokes', 'تعديل المسارات'),
            ),
          ),
          if (state.editingImagePaths) ...[
            Text(
              t(
                'Each press and lift is a separate stroke.',
                'كل ضغطة ورفعة ضربة مستقلة.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              children: [
                IconButton(
                  tooltip: t('Reverse', 'عكس الاتجاه'),
                  onPressed: busy || !hasSelection
                      ? null
                      : () => cubit.reverseStroke(selected),
                  icon: const Icon(Icons.swap_horiz),
                ),
                IconButton(
                  tooltip: t('Delete', 'حذف'),
                  onPressed: busy || !hasSelection
                      ? null
                      : () => cubit.deleteStroke(selected),
                  icon: const Icon(Icons.delete_outline),
                ),
                IconButton(
                  tooltip: t('Earlier', 'تقديم'),
                  onPressed: busy || !hasSelection
                      ? null
                      : () => cubit.moveStroke(selected, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: t('Later', 'تأخير'),
                  onPressed: busy || !hasSelection
                      ? null
                      : () => cubit.moveStroke(selected, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
                PopupMenuButton<String>(
                  tooltip: t('Path options', 'خيارات المسارات'),
                  enabled: !busy,
                  onSelected: (v) {
                    if (v == 'regenerate') {
                      generate(effect);
                    } else {
                      cubit.orderImageStrokes(v == 'regions');
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'regenerate',
                      child: Text(
                        t('Regenerate paths', 'إعادة توليد المسارات'),
                      ),
                    ),
                    if (effect == 'drawPaint') ...[
                      PopupMenuItem(
                        value: 'lines',
                        child: Text(
                          t('All lines, then paint', 'كل الخطوط ثم التلوين'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'regions',
                        child: Text(t('Complete each part', 'إكمال كل جزء')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (hasSelection && effect == 'drawPaint')
              DropdownButton<bool>(
                value: project.strokes[selected].isPaintStroke,
                items: [
                  DropdownMenuItem(
                    value: false,
                    child: Text(t('Lines', 'خطوط')),
                  ),
                  DropdownMenuItem(
                    value: true,
                    child: Text(t('Painting', 'تلوين')),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) cubit.setStrokePainting(selected, v);
                      },
              ),
            SizedBox(
              height: 240,
              child: ListView.builder(
                itemCount: project.strokes.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  selected: selected == i,
                  leading: Icon(
                    project.strokes[i].reversed ? Icons.west : Icons.east,
                    size: 16,
                  ),
                  title: Text(
                    '${i + 1} · ${project.strokes[i].isPaintStroke ? t('Paint', 'تلوين') : t('Line', 'خط')}',
                  ),
                  onTap: busy ? null : () => cubit.selectStroke(i),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            t(
              'Use the canvas player to preview. Background, camera and export use this same project.',
              'شغّل المعاينة أسفل الكانفز. الخلفية والكاميرا والتصدير يستخدمون نفس المشروع.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _AnimationDurationField extends StatefulWidget {
  const _AnimationDurationField({
    required this.seconds,
    required this.enabled,
    required this.label,
    required this.invalidMessage,
    required this.anchoredMessage,
    required this.onChanged,
  });
  final double seconds;
  final bool enabled;
  final String label;
  final String invalidMessage;
  final String anchoredMessage;
  final bool Function(double) onChanged;
  @override
  State<_AnimationDurationField> createState() =>
      _AnimationDurationFieldState();
}

class _AnimationDurationFieldState extends State<_AnimationDurationField> {
  late final TextEditingController controller = TextEditingController(
    text: widget.seconds.toStringAsFixed(1),
  );
  final focus = FocusNode();
  String? error;
  @override
  void didUpdateWidget(covariant _AnimationDurationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.seconds - widget.seconds).abs() > .00001) {
      // Keep the user's exact text/caret when the update acknowledges that edit.
      final typed = double.tryParse(controller.text);
      if (typed == null || (typed - widget.seconds).abs() > .001) {
        controller.text = widget.seconds.toStringAsFixed(1);
        error = null;
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    key: const ValueKey('animation-duration'),
    controller: controller,
    focusNode: focus,
    enabled: widget.enabled,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: widget.label, errorText: error),
    onChanged: (text) {
      final value = double.tryParse(text);
      final valid =
          value != null && value.isFinite && value >= 1 && value <= 300;
      final applied = valid && widget.onChanged(value);
      setState(
        () => error = applied
            ? null
            : valid
            ? widget.anchoredMessage
            : widget.invalidMessage,
      );
    },
    onFieldSubmitted: (_) {
      if (error == null) focus.unfocus();
    },
  );
}
