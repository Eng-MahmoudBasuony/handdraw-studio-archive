import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/scene_split/application/scene_split_cubit.dart';
import 'package:handdraw_studio/features/scene_split/domain/models/scene_region.dart';

String _text(BuildContext context, String en, String ar) =>
    Directionality.of(context) == TextDirection.rtl ? ar : en;

Future<void> showSmartSceneSplitDialog(
  BuildContext context,
  EditorCubit editor, {
  bool manualImageParts = false,
}) async {
  final image = editor.state.drawingImage;
  final encoded = _decode(editor.state.drawingAnalysisEncoded);
  if (image == null || encoded == null) return;
  final split = SceneSplitCubit(encoded);
  final overlay = Overlay.of(context, rootOverlay: true);
  final themes = InheritedTheme.capture(from: context, to: overlay.context);
  final completion = Completer<List<SceneRegion>?>();
  late final OverlayEntry entry;
  void complete(List<SceneRegion>? regions) {
    if (!completion.isCompleted) completion.complete(regions);
  }

  entry = OverlayEntry(
    builder: (_) {
      final modal = CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              complete(null),
        },
        child: FocusScope(
          autofocus: true,
          child: Stack(
            key: const ValueKey('smart-scene-split-overlay'),
            fit: StackFit.expand,
            children: [
              const ModalBarrier(dismissible: false, color: Colors.black54),
              SafeArea(
                child: themes.wrap(
                  BlocProvider.value(
                    value: split,
                    child: _SmartSceneSplitDialog(
                      image: image,
                      manualImageParts: manualImageParts,
                      onClose: complete,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // Flutter 3.44's macOS AccessibilityBridge can crash while removing a
      // modal semantics subtree above a dense editor timeline. Keeping this
      // visual overlay out of semantics leaves the editor tree structurally
      // unchanged during insertion/removal. Other platforms retain the normal
      // modal semantics while the engine issue is macOS-specific.
      return defaultTargetPlatform == TargetPlatform.macOS
          ? ExcludeSemantics(child: modal)
          : Semantics(container: true, explicitChildNodes: true, child: modal);
    },
  );
  List<SceneRegion>? confirmed;
  overlay.insert(entry);
  try {
    confirmed = await completion.future;
  } finally {
    entry.remove();
    entry.dispose();
    await split.close();
  }
  if (confirmed == null ||
      confirmed.isEmpty ||
      !context.mounted ||
      editor.isClosed) {
    return;
  }
  WidgetsBinding.instance.scheduleFrame();
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted || editor.isClosed) return;
  if (manualImageParts) {
    await editor.prepareImageAnimation(regions: confirmed);
  } else {
    await editor.applyOrderedSceneReveals(confirmed);
  }
}

Uint8List? _decode(String? encoded) {
  if (encoded == null || encoded.isEmpty) return null;
  try {
    final comma = encoded.indexOf(',');
    return base64Decode(comma >= 0 ? encoded.substring(comma + 1) : encoded);
  } on FormatException {
    return null;
  }
}

class _SmartSceneSplitDialog extends StatefulWidget {
  const _SmartSceneSplitDialog({
    required this.image,
    required this.onClose,
    this.manualImageParts = false,
  });

  final bool manualImageParts;

  final ui.Image image;
  final ValueChanged<List<SceneRegion>?> onClose;

  @override
  State<_SmartSceneSplitDialog> createState() => _SmartSceneSplitDialogState();
}

class _SmartSceneSplitDialogState extends State<_SmartSceneSplitDialog> {
  final ScrollController _regionScrollController = ScrollController();

  SceneSplitCubit get split => context.read<SceneSplitCubit>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.manualImageParts) {
        split.clearForManualLasso();
      } else {
        split.suggest();
      }
    });
  }

  @override
  void dispose() {
    _regionScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<SceneSplitCubit, SceneSplitState>(
        builder: (context, state) {
          final busy = state.isSuggesting;
          return Dialog(
            key: const ValueKey('smart-scene-split-dialog'),
            insetPadding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820),
              child: Column(
                children: [
                  _header(context, state, busy),
                  Divider(height: 1, color: context.studioColors.border),
                  _tools(context, state, busy),
                  Expanded(child: _regionEditorSummary(context, state, busy)),
                  if (state.message case final message?)
                    Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        16,
                        2,
                        16,
                        8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 15,
                            color: context.studioColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _localizedMessage(context, message),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.studioColors.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );

  Widget _regionEditorSummary(
    BuildContext context,
    SceneSplitState state,
    bool busy,
  ) => Semantics(
    key: const ValueKey('smart-scene-content-summary'),
    container: true,
    label: _text(
      context,
      '${state.regions.length} scene regions',
      '${state.regions.length} منطقة مشهد',
    ),
    hint: _text(
      context,
      'Use the accessible toolbar to suggest, select, draw, merge, split, or delete regions.',
      'استخدم شريط الأدوات لاكتشاف المناطق أو تحديدها أو رسمها أو دمجها أو فصلها أو حذفها.',
    ),
    child: ExcludeSemantics(
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _SceneRegionCanvas(
                image: widget.image,
                state: state,
                onTap: (point, additive) {
                  final hit = state.regions.lastWhere(
                    (region) => region.contains(point),
                    orElse: () =>
                        SceneRegion(id: '', name: '', polygon: const []),
                  );
                  if (hit.id.isNotEmpty) {
                    split.select(hit.id, additive: additive);
                  }
                },
                onGestureStart: split.beginGesture,
                onGestureUpdate: split.updateGesture,
                onGestureEnd: split.endGesture,
              ),
            ),
          ),
          _regionStrip(context, state, busy),
        ],
      ),
    ),
  );

  Widget _header(BuildContext context, SceneSplitState state, bool busy) {
    final cancelLabel = _text(context, 'Cancel', 'إلغاء');
    final confirmLabel = _text(
      context,
      'Create ${state.regions.length} scenes',
      'إنشاء ${state.regions.length} مشهد',
    );
    void cancel() {
      widget.onClose(null);
    }

    final confirm = busy || state.regions.isEmpty ? null : _confirm;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 10, 12),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_mosaic, color: context.studioColors.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.manualImageParts
                      ? _text(
                          context,
                          'Choose image parts',
                          'تحديد أجزاء الصورة',
                        )
                      : _text(
                          context,
                          'Smart Scene Split',
                          'التقسيم الذكي للمشاهد',
                        ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  _text(
                    context,
                    widget.manualImageParts
                        ? 'Circle each part, then arrange its drawing order below.'
                        : 'Define what belongs together before Auto Path.',
                    widget.manualImageParts
                        ? 'ارسم دائرة حول كل جزء، ثم رتّب الأجزاء بالأسفل حسب ترتيب الرسم.'
                        : 'حدّد الأجزاء التي تنتمي معًا قبل تشغيل المسارات التلقائية.',
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: context.studioColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          Semantics(
            label: cancelLabel,
            container: true,
            button: true,
            enabled: true,
            onTap: cancel,
            excludeSemantics: true,
            child: TextButton(onPressed: cancel, child: Text(cancelLabel)),
          ),
          const SizedBox(width: 6),
          Semantics(
            key: const ValueKey('confirm-smart-scene-split-semantics'),
            label: confirmLabel,
            container: true,
            button: true,
            enabled: confirm != null,
            onTap: confirm,
            excludeSemantics: true,
            child: FilledButton.icon(
              key: const ValueKey('confirm-smart-scene-split'),
              onPressed: confirm,
              icon: const Icon(Icons.check, size: 17),
              label: Text(confirmLabel),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tools(BuildContext context, SceneSplitState state, bool busy) {
    final compact = MediaQuery.sizeOf(context).width < 800;
    Widget action({
      required Key key,
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool selected = false,
    }) => Tooltip(
      message: label,
      child: compact
          ? IconButton.filledTonal(
              key: key,
              onPressed: onPressed,
              isSelected: selected,
              icon: Icon(icon, size: 18),
            )
          : TextButton.icon(
              key: key,
              onPressed: onPressed,
              style: selected
                  ? TextButton.styleFrom(
                      backgroundColor: context.studioColors.accent.withValues(
                        alpha: 0.18,
                      ),
                    )
                  : null,
              icon: Icon(icon, size: 17),
              label: Text(label),
            ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          action(
            key: const ValueKey('suggest-scene-regions'),
            icon: Icons.auto_awesome,
            label: _text(context, 'Suggest', 'اقتراح تلقائي'),
            onPressed: busy ? null : split.suggest,
          ),
          action(
            key: const ValueKey('clear-scene-regions-for-lasso'),
            icon: Icons.layers_clear_outlined,
            label: _text(context, 'Start manually', 'ابدأ يدويًا'),
            onPressed: split.clearForManualLasso,
          ),
          action(
            key: const ValueKey('select-scene-region'),
            icon: Icons.near_me_outlined,
            label: _text(context, 'Select', 'تحديد'),
            selected: state.tool == SceneSplitTool.select,
            onPressed: busy ? null : () => split.setTool(SceneSplitTool.select),
          ),
          action(
            key: const ValueKey('lasso-scene-region'),
            icon: Icons.gesture,
            label: _text(context, 'Lasso', 'لاسو'),
            selected: state.tool == SceneSplitTool.lasso,
            onPressed: busy ? null : () => split.setTool(SceneSplitTool.lasso),
          ),
          action(
            key: const ValueKey('merge-scene-regions'),
            icon: Icons.join_inner,
            label: _text(context, 'Merge', 'دمج'),
            onPressed: busy || state.selectedIds.length < 2
                ? null
                : split.mergeSelected,
          ),
          action(
            key: const ValueKey('split-scene-region'),
            icon: Icons.content_cut,
            label: _text(context, 'Split', 'فصل'),
            selected: state.tool == SceneSplitTool.split,
            onPressed: busy || state.selectedIds.length != 1
                ? null
                : () => split.setTool(SceneSplitTool.split),
          ),
          action(
            key: const ValueKey('delete-scene-region'),
            icon: Icons.delete_outline,
            label: _text(context, 'Delete', 'حذف'),
            onPressed: busy || state.selectedIds.isEmpty
                ? null
                : split.removeSelected,
          ),
          action(
            key: const ValueKey('undo-scene-split-edit'),
            icon: Icons.undo,
            label: _text(context, 'Undo', 'تراجع'),
            onPressed: busy || !state.canUndo ? null : split.undo,
          ),
        ],
      ),
    );
  }

  Widget _regionStrip(BuildContext context, SceneSplitState state, bool busy) =>
      Container(
        height: 112,
        decoration: BoxDecoration(
          color: context.studioColors.surfaceAlt,
          border: Border(top: BorderSide(color: context.studioColors.border)),
        ),
        child: state.regions.isEmpty
            ? Center(
                child: Text(
                  state.isSuggesting
                      ? _text(
                          context,
                          'Finding logical regions…',
                          'جارٍ اكتشاف المناطق المنطقية…',
                        )
                      : _text(
                          context,
                          'Use Suggest or draw a Lasso region.',
                          'استخدم الاقتراح أو ارسم منطقة باللاسو.',
                        ),
                  style: TextStyle(color: context.studioColors.textMuted),
                ),
              )
            : Listener(
                key: const ValueKey('smart-scene-region-strip'),
                onPointerSignal: _handleRegionPointerSignal,
                child: Scrollbar(
                  key: const ValueKey('smart-scene-region-scrollbar'),
                  controller: _regionScrollController,
                  thumbVisibility: true,
                  interactive: true,
                  scrollbarOrientation: ScrollbarOrientation.bottom,
                  child: ReorderableListView.builder(
                    scrollController: _regionScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
                    buildDefaultDragHandles: false,
                    itemCount: state.regions.length,
                    // ignore: deprecated_member_use
                    onReorder: busy ? (_, _) {} : split.reorder,
                    itemBuilder: (context, index) {
                      final region = state.regions[index];
                      final selected = state.selectedIds.contains(region.id);
                      return InkWell(
                        key: ValueKey('scene-region-card-${region.id}'),
                        onTap: busy ? null : () => split.select(region.id),
                        child: AnimatedContainer(
                          width: 142,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          padding: const EdgeInsets.all(8),
                          duration: const Duration(milliseconds: 120),
                          decoration: BoxDecoration(
                            color: selected
                                ? context.studioColors.accent.withValues(
                                    alpha: 0.16,
                                  )
                                : context.studioColors.surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: selected
                                  ? context.studioColors.accent
                                  : context.studioColors.border,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: context.studioColors.accent,
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _text(
                                    context,
                                    'Scene ${index + 1}',
                                    'مشهد ${index + 1}',
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(7),
                                  child: Icon(Icons.drag_indicator, size: 18),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
      );

  void _handleRegionPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_regionScrollController.hasClients) {
      return;
    }
    final horizontal = event.scrollDelta.dx;
    final vertical = event.scrollDelta.dy;
    final delta = horizontal.abs() > vertical.abs() ? horizontal : vertical;
    if (delta == 0) return;
    _regionScrollController.position.pointerScroll(delta);
  }

  void _confirm() {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final regions = List<SceneRegion>.unmodifiable([
      for (var index = 0; index < split.state.regions.length; index++)
        split.state.regions[index].copyWith(
          name: rtl ? 'مشهد ${index + 1}' : 'Scene ${index + 1}',
        ),
    ]);
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onClose(regions);
  }
}

class _SceneRegionCanvas extends StatelessWidget {
  const _SceneRegionCanvas({
    required this.image,
    required this.state,
    required this.onTap,
    required this.onGestureStart,
    required this.onGestureUpdate,
    required this.onGestureEnd,
  });

  final ui.Image image;
  final SceneSplitState state;
  final void Function(Offset point, bool additive) onTap;
  final ValueChanged<Offset> onGestureStart;
  final ValueChanged<Offset> onGestureUpdate;
  final VoidCallback onGestureEnd;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: image.width / image.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          Offset normalized(Offset local) => Offset(
            (local.dx / constraints.maxWidth).clamp(0.0, 1.0),
            (local.dy / constraints.maxHeight).clamp(0.0, 1.0),
          );
          return Focus(
            autofocus: true,
            onKeyEvent: (_, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final cubit = context.read<SceneSplitCubit>();
              if (event.logicalKey == LogicalKeyboardKey.delete ||
                  event.logicalKey == LogicalKeyboardKey.backspace) {
                cubit.removeSelected();
                return KeyEventResult.handled;
              }
              if ((HardwareKeyboard.instance.isMetaPressed ||
                      HardwareKeyboard.instance.isControlPressed) &&
                  event.logicalKey == LogicalKeyboardKey.keyZ) {
                cubit.undo();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: GestureDetector(
              key: const ValueKey('smart-scene-split-canvas'),
              behavior: HitTestBehavior.opaque,
              onTapUp: state.tool == SceneSplitTool.select
                  ? (details) => onTap(
                      normalized(details.localPosition),
                      HardwareKeyboard.instance.isShiftPressed ||
                          HardwareKeyboard.instance.isMetaPressed ||
                          HardwareKeyboard.instance.isControlPressed,
                    )
                  : null,
              onPanStart: state.tool == SceneSplitTool.select
                  ? null
                  : (details) =>
                        onGestureStart(normalized(details.localPosition)),
              onPanUpdate: state.tool == SceneSplitTool.select
                  ? null
                  : (details) =>
                        onGestureUpdate(normalized(details.localPosition)),
              onPanEnd: state.tool == SceneSplitTool.select
                  ? null
                  : (_) => onGestureEnd(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RawImage(
                      image: image,
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.high,
                    ),
                    ColoredBox(color: Colors.black.withValues(alpha: 0.16)),
                    CustomPaint(
                      painter: _SceneRegionPainter(
                        regions: state.regions,
                        selectedIds: state.selectedIds,
                        activeGesture: state.activeGesture,
                        accent: context.studioColors.accent,
                        warning: context.studioColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _SceneRegionPainter extends CustomPainter {
  const _SceneRegionPainter({
    required this.regions,
    required this.selectedIds,
    required this.activeGesture,
    required this.accent,
    required this.warning,
  });

  final List<SceneRegion> regions;
  final Set<String> selectedIds;
  final List<Offset> activeGesture;
  final Color accent;
  final Color warning;

  @override
  void paint(Canvas canvas, Size size) {
    Offset map(Offset point) =>
        Offset(point.dx * size.width, point.dy * size.height);
    for (var index = 0; index < regions.length; index++) {
      final region = regions[index];
      final selected = selectedIds.contains(region.id);
      final path = Path();
      final shapes = region.fragments.isEmpty
          ? [region.polygon]
          : [for (final fragment in region.fragments) rectPolygon(fragment)];
      for (final polygon in shapes) {
        if (polygon.isEmpty) continue;
        path.moveTo(map(polygon.first).dx, map(polygon.first).dy);
        for (final point in polygon.skip(1)) {
          final mapped = map(point);
          path.lineTo(mapped.dx, mapped.dy);
        }
        path.close();
      }
      final color = selected ? warning : accent;
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: selected ? 0.24 : 0.13),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.6 : 1.4,
      );
      final center = map(region.bounds.topLeft) + const Offset(14, 14);
      canvas.drawCircle(center, 13, Paint()..color = color);
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, center - Offset(label.width / 2, label.height / 2));
    }
    if (activeGesture.length >= 2) {
      final path = Path()
        ..moveTo(map(activeGesture.first).dx, map(activeGesture.first).dy);
      for (final point in activeGesture.skip(1)) {
        final mapped = map(point);
        path.lineTo(mapped.dx, mapped.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = warning
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SceneRegionPainter oldDelegate) =>
      oldDelegate.regions != regions ||
      oldDelegate.selectedIds != selectedIds ||
      oldDelegate.activeGesture != activeGesture;
}

String _localizedMessage(BuildContext context, String message) {
  if (Directionality.of(context) != TextDirection.rtl) return message;
  if (message.contains('No transparent groups')) {
    return 'لم يتم العثور على مجموعات شفافة. استخدم اللاسو لتحديد المشاهد يدويًا.';
  }
  if (message.contains('Suggestions cleared')) {
    return 'تم مسح الاقتراحات. ارسم المشاهد يدويًا باستخدام اللاسو.';
  }
  if (message.contains('suggestions failed')) {
    return 'تعذر إنشاء الاقتراحات. يمكنك المتابعة باستخدام اللاسو.';
  }
  if (message.contains('closed area')) {
    return 'ارسم مساحة مغلقة حول المشهد.';
  }
  if (message.contains('Select one region')) {
    return 'حدد منطقة واحدة ثم ارسم خطًا يمر خلالها.';
  }
  if (message.contains('must cross') || message.contains('must divide')) {
    return 'يجب أن يقسم خط الفصل القناع المحدد إلى جزأين.';
  }
  if (message.contains('suggested')) return 'تم اقتراح مناطق المشاهد تلقائيًا.';
  if (message.contains('Manual scene')) return 'تمت إضافة مشهد يدوي.';
  if (message.contains('merged')) return 'تم دمج المناطق المحددة.';
  if (message.contains('split into')) return 'تم فصل المنطقة إلى مشهدين.';
  if (message.contains('removed')) return 'تم حذف المناطق المحددة.';
  if (message.contains('undone')) return 'تم التراجع عن آخر تعديل.';
  return message;
}
