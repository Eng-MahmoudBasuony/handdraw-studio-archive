import 'dart:async';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:io';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/editor/presentation/pages/editor_screen.dart';
import 'package:handdraw_studio/features/scene_composer/application/scene_composer_cubit.dart';
import 'package:handdraw_studio/features/scene_composer/application/scene_project_builder.dart';
import 'package:handdraw_studio/features/scene_composer/domain/scene_design.dart';
import 'package:handdraw_studio/features/scene_composer/infrastructure/scene_library.dart';
import 'scene_design_painter.dart';

Future<void> showSceneComposer(BuildContext context) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => const SceneComposerDialog(),
);

class SceneComposerDialog extends StatefulWidget {
  const SceneComposerDialog({super.key, this.controller, this.connect = true});
  final SceneComposerCubit? controller;
  final bool connect;
  @override
  State<SceneComposerDialog> createState() => _SceneComposerDialogState();
}

class _SceneComposerDialogState extends State<SceneComposerDialog> {
  late final controller =
      widget.controller ??
      SceneComposerCubit(
        CodexAssistantCubit.local(allowDevelopment: false),
        SceneLibrary.local(),
      );
  final prompt = TextEditingController();
  final search = TextEditingController();
  String category = '';
  bool applying = false;
  String localMessage = '';
  String t(String en, String ar) =>
      Directionality.of(context) == TextDirection.rtl ? ar : en;
  @override
  void initState() {
    super.initState();
    unawaited(controller.load());
    if (widget.connect) unawaited(controller.assistant.connect());
  }

  @override
  void dispose() {
    prompt.dispose();
    search.dispose();
    if (widget.controller == null) {
      unawaited(controller.close());
      unawaited(controller.assistant.close());
    }
    super.dispose();
  }

  Future<void> apply() async {
    final design = controller.state.design;
    if (design == null || applying) return;
    setState(() {
      applying = true;
      localMessage = '';
    });
    try {
      final editor = await const SceneProjectBuilder().build(design);
      if (!mounted) {
        await editor.close();
        return;
      }
      if (!await controller.save()) {
        await editor.close();
        return;
      }
      if (!mounted) {
        await editor.close();
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final path = await editor.saveProject();
                          if (path != null && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                        icon: const Icon(Icons.save_outlined),
                        label: Text(
                          t(
                            'Save and return to designer',
                            'حفظ والعودة للمصمم',
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(design.title, textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
                Expanded(child: EditorScreen(cubit: editor)),
              ],
            ),
          ),
        ),
      );
      await editor.close();
    } catch (error) {
      if (mounted) setState(() => localMessage = error.toString());
    } finally {
      if (mounted) setState(() => applying = false);
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<SceneComposerCubit, SceneComposerState>(
    bloc: controller,
    builder: (context, state) {
      final design = state.design;
      final busy = state.busy || applying;
      final theme = Theme.of(context);
      return Dialog(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 1160,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('Create a scene', 'أنشئ مشهد'),
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: t('Close', 'إغلاق'),
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  Text(
                    t(
                      'Describe an idea. Keep every element, text and drawing order editable.',
                      'اكتب الفكرة، وعدّل العناصر والنصوص وترتيب الرسم قبل التنفيذ.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('scene-prompt'),
                    controller: prompt,
                    maxLength: 2000,
                    minLines: 2,
                    maxLines: 3,
                    enabled: !busy,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: t(
                        'A scene explaining Flutter package updates…',
                        'مشهد يشرح تحديث مكتبات Flutter…',
                      ),
                    ),
                  ),
                  BlocBuilder<CodexAssistantCubit, CodexAssistantState>(
                    bloc: controller.assistant,
                    builder: (context, account) => Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          key: const ValueKey('scene-generate'),
                          onPressed: busy || account.busy
                              ? null
                              : () => controller.generate(prompt.text),
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(t('Generate scene', 'توليد المشهد')),
                        ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => controller.show(SceneDesign.example()),
                          child: Text(
                            t(
                              'Free Flutter example',
                              'مثال Flutter بدون استهلاك',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: account.busy
                              ? null
                              : () => controller.assistant.login(),
                          child: Text(
                            account.account?.isChatGpt == true
                                ? t('Account connected', 'الحساب مربوط')
                                : t('Connect Codex account', 'ربط حساب Codex'),
                          ),
                        ),
                        if (account.loginUrl != null)
                          TextButton(
                            onPressed: () => Process.run('/usr/bin/open', [
                              account.loginUrl!,
                            ]),
                            child: Text(
                              t('Complete login', 'إكمال تسجيل الدخول'),
                            ),
                          ),
                        if (account.models.isNotEmpty)
                          DropdownButton<String>(
                            value: account.model,
                            items: [
                              for (final m in account.models)
                                DropdownMenuItem(
                                  value: m['model'] as String,
                                  child: Text(
                                    m['displayName'] as String? ??
                                        m['model'] as String,
                                  ),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    if (v != null) {
                                      controller.assistant.selectModel(v);
                                    }
                                  },
                          ),
                        Text(
                          '${account.inputTokens + account.outputTokens} tokens',
                        ),
                      ],
                    ),
                  ),
                  if (busy) const LinearProgressIndicator(),
                  if (state.busy)
                    TextButton(
                      onPressed: controller.assistant.cancel,
                      child: Text(t('Cancel generation', 'إلغاء التوليد')),
                    ),
                  if (localMessage.isNotEmpty || state.message.isNotEmpty)
                    Text(
                      localMessage.isNotEmpty ? localMessage : state.message,
                    ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 440,
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final preview = Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: AppPalette.light.surface,
                                      border: Border.all(
                                        color: theme.colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: design == null
                                        ? Center(
                                            child: Text(
                                              t(
                                                'Your scene appears here',
                                                'المشهد هيظهر هنا',
                                              ),
                                            ),
                                          )
                                        : CustomPaint(
                                            key: const ValueKey(
                                              'scene-preview',
                                            ),
                                            painter: SceneDesignPainter(
                                              design,
                                              selected: state.selected,
                                              selectionColor:
                                                  theme.colorScheme.primary,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            if (design != null)
                              Flexible(
                                flex: 2,
                                child: SingleChildScrollView(
                                  child: _properties(state, busy),
                                ),
                              ),
                          ],
                        );
                        final library = _library(state, busy);
                        return box.maxWidth < 760
                            ? Column(
                                children: [
                                  Expanded(child: preview),
                                  SizedBox(height: 155, child: library),
                                ],
                              )
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: preview),
                                  const SizedBox(width: 16),
                                  SizedBox(width: 300, child: library),
                                ],
                              );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    t(
                      'Vector illustrations and editable text • Elements must not overlap in this first version.',
                      'رسومات متجهة ونصوص قابلة للتعديل • باعد بين العناصر في النسخة الأولى.',
                    ),
                    style: theme.textTheme.bodySmall,
                  ),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy || design == null
                            ? null
                            : () => controller.save(),
                        child: Text(
                          t('Save template + elements', 'حفظ القالب والعناصر'),
                        ),
                      ),
                      FilledButton.icon(
                        key: const ValueKey('scene-apply'),
                        onPressed: busy || design == null ? null : apply,
                        icon: const Icon(Icons.movie_creation_outlined),
                        label: Text(t('Open as a new scene', 'فتح كمشهد جديد')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _properties(SceneComposerState state, bool busy) {
    final e = state.design!.elements[state.selected];
    void bounds(double? x, double? y, double? w, double? h) {
      final b = e.bounds;
      final width = w ?? b.width, height = h ?? b.height;
      controller.edit(
        e.copyWith(
          bounds: Rect.fromLTWH(
            (x ?? b.left).clamp(0, 1 - width),
            (y ?? b.top).clamp(0, 1 - height),
            width,
            height,
          ),
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final (i, item) in state.design!.elements.indexed)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text('${i + 1}. ${item.name}'),
                    selected: i == state.selected,
                    onSelected: busy ? null : (_) => controller.select(i),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey((
                  'scene-name',
                  state.designRevision,
                  e.instanceId,
                )),
                initialValue: e.name,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: t('Element name', 'اسم العنصر'),
                ),
                onChanged: (v) => controller.edit(e.copyWith(name: v)),
              ),
            ),
            IconButton(
              onPressed: busy ? null : () => controller.move(-1),
              tooltip: t('Draw earlier', 'ارسمه قبل'),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              onPressed: busy ? null : () => controller.move(1),
              tooltip: t('Draw later', 'ارسمه بعد'),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              onPressed: busy ? null : controller.remove,
              tooltip: t('Remove from scene', 'إزالة من المشهد'),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey(('category', state.designRevision, e.instanceId)),
                initialValue: e.category,
                enabled: !busy,
                maxLength: 40,
                decoration: InputDecoration(
                  labelText: t('Category', 'التصنيف'),
                  counterText: '',
                ),
                onChanged: (value) =>
                    controller.edit(e.copyWith(category: value)),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 110,
              child: TextFormField(
                key: ValueKey(('seconds', state.designRevision, e.instanceId)),
                initialValue: e.seconds.toString(),
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: t('Seconds', 'المدة بالثواني'),
                ),
                onChanged: (value) {
                  final seconds = double.tryParse(value);
                  if (seconds != null && seconds >= .2 && seconds <= 20) {
                    controller.edit(e.copyWith(seconds: seconds));
                  }
                },
              ),
            ),
          ],
        ),
        if (e.isText)
          TextFormField(
            key: ValueKey(('scene-text', state.designRevision, e.instanceId)),
            initialValue: e.text,
            enabled: !busy,
            decoration: InputDecoration(labelText: t('Text', 'النص')),
            onChanged: (v) => controller.edit(e.copyWith(text: v)),
          ),
        Row(
          children: [
            for (final field in ['X', 'Y', 'W', 'H'])
              Expanded(
                child: Column(
                  children: [
                    Text(field),
                    Slider(
                      value: switch (field) {
                        'X' => e.bounds.left,
                        'Y' => e.bounds.top,
                        'W' => e.bounds.width,
                        _ => e.bounds.height,
                      },
                      min: (field == 'W' || field == 'H') ? 0.02 : 0,
                      max: 1,
                      onChanged: busy
                          ? null
                          : (v) => switch (field) {
                              'X' => bounds(v, null, null, null),
                              'Y' => bounds(null, v, null, null),
                              'W' => bounds(null, null, v, null),
                              _ => bounds(null, null, null, v),
                            },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _library(SceneComposerState state, bool busy) {
    final categories = state.assets.map((e) => e.category).toSet().toList()
      ..sort();
    final filtered = state.assets.where(
      (e) =>
          (category.isEmpty || e.category == category) &&
          ('${e.name} ${e.category} ${e.text}').toLowerCase().contains(
            search.text.toLowerCase(),
          ),
    );
    return ListView(
      children: [
        Text(
          t('Element library', 'مكتبة العناصر'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        TextField(
          controller: search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: t('Search', 'بحث'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        DropdownButton<String>(
          isExpanded: true,
          value: categories.contains(category) ? category : '',
          items: [
            DropdownMenuItem(
              value: '',
              child: Text(t('All categories', 'كل التصنيفات')),
            ),
            for (final c in categories)
              DropdownMenuItem(value: c, child: Text(c)),
          ],
          onChanged: (v) => setState(() => category = v ?? ''),
        ),
        for (final e in filtered)
          ListTile(
            leading: SizedBox(
              width: 48,
              height: 40,
              child: ColoredBox(
                color: AppPalette.light.surface,
                child: CustomPaint(
                  painter: SceneDesignPainter(
                    SceneDesign(
                      title: e.name,
                      elements: [
                        e.copyWith(bounds: const Rect.fromLTWH(0, 0, 1, 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(e.category),
            trailing: const Icon(Icons.add),
            onTap: busy ? null : () => controller.add(e),
          ),
        if (state.assets.isEmpty)
          Text(
            t(
              'Save a design to start your library.',
              'احفظ تصميمًا لإضافة عناصره للمكتبة.',
            ),
          ),
        if (state.templates.isNotEmpty)
          Text(t('Saved scenes', 'المشاهد المحفوظة')),
        for (final d in state.templates)
          ListTile(
            title: Text(d.title),
            leading: const Icon(Icons.dashboard_outlined),
            onTap: busy ? null : () => controller.show(d),
          ),
      ],
    );
  }
}
