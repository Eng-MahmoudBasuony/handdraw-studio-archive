import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/localization/presentation/localized_domain_labels.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/infrastructure/editor_file_service.dart';
import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

enum HandLibraryAction { calibrate }

class HandLibraryDialog extends StatelessWidget {
  const HandLibraryDialog({super.key, required this.cubit});

  final EditorCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 680),
        child: BlocBuilder<EditorCubit, EditorState>(
          bloc: cubit,
          builder: (context, state) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Header(isLoading: state.isHandLibraryLoading),
                const Divider(height: 1),
                Flexible(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 650 ? 3 : 2;
                      return GridView.builder(
                        padding: const EdgeInsets.all(20),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                          childAspectRatio: columns == 3 ? 1.25 : 1.1,
                        ),
                        itemCount: state.handPresets.length,
                        itemBuilder: (context, index) {
                          final preset = state.handPresets[index];
                          return _HandPresetCard(
                            preset: preset,
                            selected: preset.id == state.selectedHandPresetId,
                            enabled: !state.isHandLibraryLoading,
                            onPressed: () => cubit.selectHandPreset(preset.id),
                          );
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                _HandVideoSizeControl(
                  value: state.document.handConfiguration.scale,
                  defaultValue:
                      state.selectedHandPreset?.defaultScale ??
                      BuiltInHands.defaultPreset.defaultScale,
                  enabled: state.hasHand && !state.isHandLibraryLoading,
                  onChanged: cubit.setHandScale,
                  onChangeEnd: cubit.commitHandPreferences,
                ),
                const Divider(height: 1),
                _Footer(
                  canCalibrate: state.hasHand && !state.isHandLibraryLoading,
                  isLoading: state.isHandLibraryLoading,
                  onImport: () async {
                    final l10n = context.l10n;
                    final imported = await cubit.importHand(
                      copy: EditorFilePickerCopy(
                        chooseDrawing: l10n.chooseDrawing,
                        chooseHand: l10n.chooseHand,
                        images: l10n.images,
                        project: l10n.handDrawProject,
                        saveProject: l10n.saveProject,
                        openProject: l10n.openProject,
                      ),
                    );
                    if (!context.mounted || !imported) return;
                    Navigator.pop(context, HandLibraryAction.calibrate);
                  },
                  onCalibrate: () =>
                      Navigator.pop(context, HandLibraryAction.calibrate),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HandVideoSizeControl extends StatelessWidget {
  const _HandVideoSizeControl({
    required this.value,
    required this.defaultValue,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double defaultValue;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final safeValue = value.clamp(.06, .90).toDouble();
    final canReset = enabled && (safeValue - defaultValue).abs() > .0001;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 14, 10),
      child: Row(
        children: [
          Icon(
            Icons.aspect_ratio_rounded,
            size: 19,
            color: context.studioColors.accentSoft,
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.handVideoSize,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.handVideoSizeDescription,
                  style: TextStyle(
                    color: context.studioColors.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(
              key: const ValueKey('hand-library-video-size'),
              value: safeValue,
              min: .06,
              max: .90,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? (_) => onChangeEnd() : null,
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              '${(safeValue * 100).round()}%',
              key: const ValueKey('hand-library-video-size-value'),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('hand-library-video-size-reset'),
            tooltip: l10n.resetHandVideoSize,
            onPressed: canReset ? () => onChanged(defaultValue) : null,
            icon: const Icon(Icons.restart_alt_rounded, size: 19),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 12, 16),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: context.studioColors.accentContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.pan_tool_alt_outlined,
              color: context.studioColors.accentSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.handLibrary,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.handLibraryDescription,
                  style: TextStyle(
                    color: context.studioColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: l10n.close,
            onPressed: isLoading ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _HandPresetCard extends StatelessWidget {
  const _HandPresetCard({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.onPressed,
  });

  final HandPreset preset;
  final bool selected;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: selected
          ? context.studioColors.selectedSurface
          : context.studioColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? context.studioColors.accent
              : context.studioColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const _Checkerboard(),
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Transform.flip(
                      flipX: preset.flipX,
                      child: _HandThumbnail(preset: preset),
                    ),
                  ),
                  if (selected)
                    PositionedDirectional(
                      end: 9,
                      top: 9,
                      child: CircleAvatar(
                        radius: 11,
                        backgroundColor: context.studioColors.accent,
                        child: Icon(
                          Icons.check,
                          size: 15,
                          color: context.studioColors.surface,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.localizedName(l10n),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.studioColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      preset.isBundled ? l10n.defaultBadge : l10n.customBadge,
                      style: TextStyle(
                        color: context.studioColors.textSecondary,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
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
  }
}

class _HandThumbnail extends StatelessWidget {
  const _HandThumbnail({required this.preset});

  final HandPreset preset;

  @override
  Widget build(BuildContext context) {
    final path = preset.imageLocation;
    if (path == null) return const Icon(Icons.broken_image_outlined);
    if (preset.isBundled) {
      return Image.asset(
        path,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      );
    }
    return Image.file(
      File(path),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
    );
  }
}

class _Checkerboard extends StatelessWidget {
  const _Checkerboard();

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return CustomPaint(
      painter: _CheckerboardPainter(
        baseColor: colors.checkerBase,
        cellColor: colors.checkerCell,
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({
    required this.baseColor,
    required this.cellColor,
  });

  final Color baseColor;
  final Color cellColor;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = baseColor);
    const cell = 12.0;
    final paint = Paint()..color = cellColor;
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) =>
      oldDelegate.baseColor != baseColor || oldDelegate.cellColor != cellColor;
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.canCalibrate,
    required this.isLoading,
    required this.onImport,
    required this.onCalibrate,
  });

  final bool canCalibrate;
  final bool isLoading;
  final VoidCallback onImport;
  final VoidCallback onCalibrate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: isLoading ? null : onImport,
            icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
            label: Text(l10n.importCustomHand),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: canCalibrate ? onCalibrate : null,
            icon: const Icon(Icons.gps_fixed, size: 17),
            label: Text(l10n.calibratePenTip),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: isLoading ? null : () => Navigator.pop(context),
            child: Text(l10n.done),
          ),
        ],
      ),
    );
  }
}
