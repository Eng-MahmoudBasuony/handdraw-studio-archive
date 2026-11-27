import 'package:handdraw_studio/features/image_animation/domain/image_parts_failure.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_assistant_cubit.dart';
import 'package:handdraw_studio/features/codex_assistant/application/codex_image_context.dart';
import 'package:handdraw_studio/features/codex_assistant/domain/codex_drawing_plan.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/project/domain/models/project_document.dart';

Future<void> showCodexAssistantDialog(
  BuildContext context,
  EditorCubit editor,
) => showDialog<void>(
  context: context,
  builder: (_) => CodexAssistantDialog(editor: editor),
);

class CodexAssistantDialog extends StatefulWidget {
  const CodexAssistantDialog({super.key, required this.editor, this.assistant});
  final EditorCubit editor;
  final CodexAssistantCubit? assistant;
  @override
  State<CodexAssistantDialog> createState() => _CodexAssistantDialogState();
}

class _CodexAssistantDialogState extends State<CodexAssistantDialog> {
  late final CodexAssistantCubit assistant =
      widget.assistant ?? CodexAssistantCubit.local();
  final prompt = TextEditingController();
  CodexImageContext? _imageContext;
  ui.Image? _contextImage;
  ProjectDocument? _planDocument, _beforeApply, _lastApplied;
  bool _localBusy = false, _autoApply = true;
  String? _message;
  int _operation = 0;
  String t(String en, String ar) =>
      Directionality.of(context) == TextDirection.rtl ? ar : en;
  @override
  void initState() {
    super.initState();
    unawaited(assistant.connect());
  }

  @override
  void dispose() {
    _operation++;
    if (_localBusy) widget.editor.cancelImageAnimation();
    prompt.dispose();
    if (widget.assistant == null) unawaited(assistant.close());
    super.dispose();
  }

  Future<void> _generate() async {
    final image = widget.editor.drawingImage;
    if (image == null || _localBusy) return;
    setState(() {
      _localBusy = true;
      _message = null;
    });
    final operation = ++_operation;
    _planDocument = null;
    final expected = widget.editor.state.document;
    try {
      if (!identical(image, _contextImage)) {
        _imageContext = await CodexImageContext.prepare(image);
        _contextImage = image;
      }
      if (!mounted || operation != _operation) return;
      final plan = await assistant.plan(prompt.text, _imageContext!);
      if (!mounted || operation != _operation || plan == null) return;
      _planDocument = expected;
      if (_autoApply && plan.confidence >= .8) {
        await _apply(plan);
      } else {
        setState(
          () => _message = t(
            'Review the highlighted parts before applying.',
            'راجع الأجزاء المحددة قبل التنفيذ.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = t(
            'Could not prepare the image.',
            'تعذّر تجهيز الصورة.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  Future<void> _apply(
    CodexDrawingPlan plan, {
    bool dismissOnSuccess = false,
  }) async {
    final expected = _planDocument;
    if (expected == null) return;
    setState(() => _localBusy = true);
    final replacementBase = identical(expected, _lastApplied)
        ? _beforeApply
        : null;
    Object? failure;
    final applied = await widget.editor.applyCodexDrawingPlan(
      plan,
      expected,
      replacementBase: replacementBase,
      onFailure: (error) => failure = error,
    );
    if (applied) {
      _beforeApply = replacementBase ?? expected;
      _lastApplied = widget.editor.state.document;
    }
    if (!mounted) return;
    setState(() {
      _localBusy = false;
      _message = applied
          ? t(
              'Applied to the timeline. Undo is available.',
              'تم التنفيذ على التايملاين. يمكنك التراجع.',
            )
          : _applicationError(failure, expected);
      if (applied) _planDocument = null;
    });
    if (applied && dismissOnSuccess) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            t(
              '${plan.parts.length} parts added to the timeline. Press Play to preview.',
              'تمت إضافة ${plan.parts.length} أجزاء للتايملاين. اضغط تشغيل للمعاينة.',
            ),
          ),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  String _applicationError(Object? failure, ProjectDocument expected) {
    if (failure is ImagePartsFailure &&
        failure.code == 'unsupportedBackground') {
      return t(
        'Could not separate text from the background in “${failure.partName}”. Use manual image-part selection for this background. The project is unchanged and no new Codex request was sent.',
        'تعذّر فصل النص عن خلفية «${failure.partName}». استخدم تحديد أجزاء الصورة يدويًا لهذه الخلفية. المشروع لم يتغيّر ولم يُرسل طلب Codex جديد.',
      );
    }
    if (!identical(widget.editor.state.document, expected)) {
      return t(
        'The project changed after this plan. Prepare an updated plan.',
        'المشروع اتغيّر بعد تجهيز الخطة. جهّز خطة محدثة.',
      );
    }
    return t(
      'Local drawing preparation failed. The plan is kept; retry without sending to Codex again.',
      'تعذّر تجهيز الرسم محليًا. الخطة محفوظة؛ جرّب التنفيذ مرة أخرى من غير إعادة الإرسال لـCodex.',
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CodexAssistantCubit, CodexAssistantState>(
    bloc: assistant,
    builder: (context, state) {
      final busy = state.busy || _localBusy;
      final account = state.account;
      final block = account?.blockedReason;
      final drawing = widget.editor.drawingImage;
      return Dialog(
        key: const ValueKey('codex-assistant-dialog'),
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850, maxHeight: 850),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('Draw with Codex', 'ارسم مع Codex'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: t('Close', 'إغلاق'),
                      onPressed: () {
                        widget.editor.cancelImageAnimation();
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t(
                          'Uses your Codex subscription. Image understanding uses your allowance; drawing and export run locally.',
                          'يستخدم اشتراك Codex. فهم الصورة والطلب يستهلك من الباقة؛ الرسم والتصدير يتمّان محليًا.',
                        ),
                      ),
                      if (assistant.developmentEnabled) ...[
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Automatic code improvements • Full access',
                            'تحسين كود البرنامج تلقائيًا • صلاحيات كاملة',
                          ),
                        ),
                        Text(
                          t(
                            'Works in a source snapshot, then checks changes before applying. The new build requires restarting.',
                            'يعمل على نسخة من الكود ويفحص التغييرات قبل اعتمادها. تشغيل التحسين يحتاج إعادة فتح النسخة الجديدة.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (state.developmentStatus != null &&
                          state.developmentStatus != 'unchanged')
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _developmentLabel(state.developmentStatus!),
                          ),
                        ),
                      if (state.developmentPath != null)
                        SelectableText(
                          state.developmentPath!,
                          textDirection: TextDirection.ltr,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (account?.isChatGpt == true)
                            Text(
                              '${account!.email ?? 'ChatGPT'} • ${account.plan}',
                            ),
                          OutlinedButton.icon(
                            key: const ValueKey('codex-connect'),
                            onPressed: busy
                                ? null
                                : () async {
                                    await assistant.login();
                                    if (mounted) await assistant.openLogin();
                                  },
                            icon: const Icon(Icons.link),
                            label: Text(
                              t('Link Codex account', 'ربط حساب Codex'),
                            ),
                          ),
                          IconButton(
                            tooltip: t('Refresh allowance', 'تحديث المتبقي'),
                            onPressed: busy ? null : assistant.connect,
                            icon: const Icon(Icons.refresh),
                          ),
                          if (account?.isChatGpt == true)
                            TextButton(
                              onPressed: busy ? null : assistant.logout,
                              child: Text(t('Disconnect', 'فصل الحساب')),
                            ),
                        ],
                      ),
                      if (state.phase == CodexPhase.login &&
                          state.loginCode == null)
                        TextButton(
                          onPressed: assistant.openLogin,
                          child: Text(
                            t(
                              'Complete sign-in in your browser',
                              'أكمل تسجيل الدخول في المتصفح',
                            ),
                          ),
                        ),
                      if (state.loginCode != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          t(
                            'Enter this code on the official sign-in page:',
                            'أدخل الكود ده في صفحة تسجيل الدخول الرسمية:',
                          ),
                        ),
                        Row(
                          children: [
                            SelectableText(
                              state.loginCode!,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            IconButton(
                              tooltip: t('Copy code', 'نسخ الكود'),
                              onPressed: () => Clipboard.setData(
                                ClipboardData(text: state.loginCode!),
                              ),
                              icon: const Icon(Icons.copy),
                            ),
                            TextButton(
                              onPressed: assistant.openLogin,
                              child: Text(
                                t('Open sign-in', 'فتح تسجيل الدخول'),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (state.error != null ||
                          (account?.isChatGpt == true && block != null))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _errorText(state.error ?? block!),
                            style: TextStyle(
                              color: context.studioColors.warning,
                            ),
                          ),
                        ),
                      if (state.models.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: ValueKey('codex-model-${state.model}'),
                          initialValue: state.model,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: t('Model', 'النموذج'),
                          ),
                          items: [
                            for (final m in state.models)
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
                              : (value) {
                                  if (value != null) {
                                    assistant.selectModel(value);
                                  }
                                },
                        ),
                      ],
                      const SizedBox(height: 14),
                      TextField(
                        key: const ValueKey('codex-prompt'),
                        controller: prompt,
                        enabled: !busy,
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: t(
                            'What should the hand draw?',
                            'عاوز الإيد ترسم إيه؟',
                          ),
                          hintText: t(
                            'Draw the Flutter logo first, then the symbol below. Reveal the panel quickly and write each command line in order.',
                            'ارسم شعار Flutter الأول ثم الرمز اللي تحته. ارسم المربع بسرعة وبعده اكتب الأوامر سطر سطر.',
                          ),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          t(
                            'Apply automatically when the plan is clear',
                            'نفّذ تلقائيًا لما تكون الخطة واضحة',
                          ),
                        ),
                        value: _autoApply,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => _autoApply = v),
                      ),
                      Text(
                        t(
                          'Replaces the current section with ordered parts. One Undo restores it.',
                          'يستبدل القسم الحالي بأجزاء مرتّبة. تراجع واحد يرجّع الحالة السابقة.',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const ValueKey('codex-generate'),
                        onPressed:
                            busy ||
                                drawing == null ||
                                account?.isChatGpt != true
                            ? null
                            : _generate,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(
                          t('Create drawing plan', 'تجهيز خطة الرسم'),
                        ),
                      ),
                      if (busy) ...[
                        const SizedBox(height: 10),
                        const LinearProgressIndicator(),
                        TextButton(
                          onPressed: () {
                            _operation++;
                            unawaited(assistant.cancel());
                            widget.editor.cancelImageAnimation();
                          },
                          child: Text(t('Cancel', 'إلغاء')),
                        ),
                      ],
                      if (_message != null && state.plan == null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(_message!),
                        ),
                      if (state.plan case final CodexDrawingPlan plan) ...[
                        const SizedBox(height: 12),
                        Text(plan.summary),
                        if (drawing != null)
                          SizedBox(
                            height: 230,
                            child: AspectRatio(
                              aspectRatio: drawing.width / drawing.height,
                              child: CustomPaint(
                                painter: _PlanPainter(
                                  drawing,
                                  plan,
                                  context.studioColors.accent,
                                ),
                              ),
                            ),
                          ),
                        for (var i = 0; i < plan.parts.length; i++)
                          ListTile(
                            dense: true,
                            leading: Text('${i + 1}'),
                            title: Text(plan.parts[i].name),
                            subtitle: Text(
                              '${_modeLabel(plan.parts[i].mode)} • ${plan.parts[i].seconds.toStringAsFixed(1)} ${t('s', 'ث')}',
                            ),
                          ),
                        if (_localBusy) ...[
                          const LinearProgressIndicator(),
                          Text(
                            t(
                              'Preparing drawing paths locally…',
                              'جاري تجهيز مسارات الرسم محليًا…',
                            ),
                          ),
                        ],
                        if (_message != null) Text(_message!),
                        OutlinedButton(
                          key: const ValueKey('codex-apply'),
                          onPressed: busy
                              ? null
                              : _planDocument == null
                              ? () => Navigator.of(context).pop()
                              : () => _apply(plan, dismissOnSuccess: true),
                          child: Text(
                            _planDocument == null
                                ? t('Show timeline', 'عرض التايملاين')
                                : t('Apply this plan', 'تنفيذ الخطة'),
                          ),
                        ),
                      ],
                      if (state.inputTokens + state.outputTokens > 0)
                        Text(
                          t(
                            'Session tokens: ${state.inputTokens} input / ${state.outputTokens} output',
                            'توكنات الجلسة: ${state.inputTokens} إدخال / ${state.outputTokens} إخراج',
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  String _developmentLabel(String status) => switch (status) {
    'coding' => t(
      'Codex is inspecting or improving the source…',
      'Codex بيفحص الكود أو بينفّذ التحسين…',
    ),
    'preparing' => t(
      'Preparing an isolated source snapshot…',
      'تجهيز نسخة مستقلة من الكود…',
    ),
    'verifying' => t(
      'Checking code changes and building the app…',
      'فحص تغييرات الكود وبناء التطبيق…',
    ),
    'applied' => t(
      'Code improvements passed checks and were applied. Open the new build after saving your project.',
      'تحسينات الكود اجتازت الفحص واتطبّقت. افتح النسخة الجديدة بعد حفظ مشروعك.',
    ),
    'sourceChanged' => t(
      'The original source changed. Improvements were kept separately.',
      'الكود الأصلي اتغيّر. التحسينات محفوظة في نسخة منفصلة.',
    ),
    _ => t(
      'Improvements were kept separately because verification did not pass. The original code was preserved.',
      'التحسينات محفوظة منفصلة لأن الفحص لم يكتمل بنجاح. الكود الأصلي محفوظ.',
    ),
  };

  String _modeLabel(String mode) => switch (mode) {
    'write' => t('Write line', 'كتابة السطر'),
    'reveal' => t('Quick reveal', 'كشف سريع'),
    _ => t('Draw and paint', 'رسم وتلوين'),
  };
  String _errorText(String code) => switch (code) {
    'developmentUnavailable' => t(
      'The local development host is unavailable. Restart its service and reconnect.',
      'مشغّل التطوير المحلي غير متاح. أعد تشغيل خدمته والاتصال.',
    ),
    'codexMissing' => t(
      'Install the official ChatGPT/Codex desktop app or Codex CLI first.',
      'ثبّت تطبيق ChatGPT/Codex الرسمي أو Codex CLI أولًا.',
    ),
    'chatgptRequired' => t(
      'Link a ChatGPT account. API-key sessions are not accepted.',
      'اربط حساب ChatGPT. جلسات مفتاح API غير مقبولة.',
    ),
    'creditsAvailable' => t(
      'This account has additional credits. Requests are blocked because Codex cannot guarantee subscription-only billing per request.',
      'الحساب فيه رصيد إضافي. التوليد متوقف لأن Codex لا يضمن استخدام الباقة فقط لكل طلب.',
    ),
    'unsupportedPlan' => t(
      'Subscription-only mode currently supports personal Plus and Pro accounts.',
      'وضع الباقة فقط يدعم حاليًا حسابات Plus وPro الشخصية.',
    ),
    'limitReached' => t(
      'Allowance is exhausted or below the 10% reserve. Wait for renewal.',
      'الباقة خلصت أو المتبقي أقل من احتياطي ١٠٪. انتظر التجديد.',
    ),
    'limitsUnknown' => t(
      'Could not verify subscription allowance. Refresh before sending.',
      'تعذّر التأكد من المتبقي في الباقة. حدّث البيانات قبل الإرسال.',
    ),
    'modelMissing' => t(
      'No compatible image model is available.',
      'لا يوجد نموذج متاح يدعم الصور.',
    ),
    'invalidPlan' => t(
      'Codex returned an invalid plan. Nothing was changed. Refine the request.',
      'Codex رجّع خطة غير صالحة. لم يتغير المشروع؛ وضّح الطلب.',
    ),
    'loginFailed' => t(
      'Sign-in did not complete. Try linking again.',
      'تسجيل الدخول لم يكتمل. جرّب ربط الحساب مرة ثانية.',
    ),
    'timeout' => t(
      'Codex timed out. The request was interrupted.',
      'انتهت مهلة Codex وتم إيقاف الطلب.',
    ),
    _ => t(
      'Codex could not complete the request. Reconnect and try again.',
      'تعذّر إكمال طلب Codex. أعد الاتصال وحاول مرة أخرى.',
    ),
  };
}

class _PlanPainter extends CustomPainter {
  const _PlanPainter(this.image, this.plan, this.color);
  final ui.Image image;
  final CodexDrawingPlan plan;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final dest = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      dest,
      Paint()..filterQuality = FilterQuality.high,
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < plan.parts.length; i++) {
      final b = plan.parts[i].bounds;
      final rect = Rect.fromLTRB(
        dest.left + b.left * dest.width,
        dest.top + b.top * dest.height,
        dest.left + b.right * dest.width,
        dest.top + b.bottom * dest.height,
      );
      canvas.drawRect(rect, paint);
      final text = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, rect.topLeft);
    }
  }

  @override
  bool shouldRepaint(_PlanPainter old) =>
      old.image != image || old.plan != plan || old.color != color;
}
