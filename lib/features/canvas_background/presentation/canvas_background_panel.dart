import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/canvas_background/domain/canvas_background.dart';
import 'package:handdraw_studio/features/canvas_background/presentation/canvas_background_renderer.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class CanvasBackgroundPanel extends StatelessWidget {
  const CanvasBackgroundPanel({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final CanvasBackground value;
  final ValueChanged<CanvasBackground>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.studioColors;
    final enabled = onChanged != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.canvasBackgroundDescription,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _modeChip(
              context,
              key: 'canvas-background-none',
              label: l10n.backgroundNone,
              icon: Icons.layers_clear_rounded,
              selected: value.mode == CanvasBackgroundMode.transparent,
              enabled: enabled,
              onTap: () =>
                  onChanged?.call(const CanvasBackground.transparent()),
            ),
            _modeChip(
              context,
              key: 'canvas-background-white',
              label: l10n.backgroundWhite,
              icon: Icons.light_mode_outlined,
              selected:
                  value.mode == CanvasBackgroundMode.solid &&
                  value.colorValue == 0xFFFFFFFF,
              enabled: enabled,
              onTap: () =>
                  onChanged?.call(const CanvasBackground.solid(0xFFFFFFFF)),
            ),
            _modeChip(
              context,
              key: 'canvas-background-black',
              label: l10n.backgroundBlack,
              icon: Icons.dark_mode_outlined,
              selected:
                  value.mode == CanvasBackgroundMode.solid &&
                  value.colorValue == 0xFF000000,
              enabled: enabled,
              onTap: () =>
                  onChanged?.call(const CanvasBackground.solid(0xFF000000)),
            ),
            _modeChip(
              context,
              key: 'canvas-background-custom',
              label: l10n.backgroundCustom,
              icon: Icons.colorize_rounded,
              selected:
                  value.mode == CanvasBackgroundMode.solid &&
                  value.colorValue != 0xFFFFFFFF &&
                  value.colorValue != 0xFF000000,
              enabled: enabled,
              onTap: () => _pickCustomColor(context),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          l10n.backgroundPresets,
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            const columns = 5;
            final size =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final preset in CanvasBackgroundPreset.values)
                  _BackgroundPresetSwatch(
                    size: size,
                    preset: preset,
                    label: _presetLabel(context, preset),
                    selected:
                        value.mode == CanvasBackgroundMode.preset &&
                        value.preset == preset,
                    enabled: enabled,
                    onTap: () =>
                        onChanged?.call(CanvasBackground.preset(preset)),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.movie_filter_outlined, size: 14, color: colors.accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _selectionLabel(context),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _modeChip(
    BuildContext context, {
    required String key,
    required String label,
    required IconData icon,
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) => ChoiceChip(
    key: ValueKey(key),
    avatar: Icon(icon, size: 15),
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    onSelected: enabled ? (_) => onTap() : null,
  );

  Future<void> _pickCustomColor(BuildContext context) async {
    if (onChanged == null) return;
    final initial = value.mode == CanvasBackgroundMode.solid
        ? Color(value.colorValue)
        : const Color(0xFF2D7DD2);
    final result = await showDialog<Color>(
      context: context,
      builder: (context) => _CanvasColorDialog(initial: initial),
    );
    if (result != null) {
      onChanged?.call(CanvasBackground.solid(result.toARGB32()));
    }
  }

  String _selectionLabel(BuildContext context) {
    final l10n = context.l10n;
    return switch (value.mode) {
      CanvasBackgroundMode.transparent => l10n.backgroundNone,
      CanvasBackgroundMode.solid when value.colorValue == 0xFFFFFFFF =>
        l10n.backgroundWhite,
      CanvasBackgroundMode.solid when value.colorValue == 0xFF000000 =>
        l10n.backgroundBlack,
      CanvasBackgroundMode.solid =>
        '${l10n.backgroundCustom} · #${value.colorValue.toRadixString(16).substring(2).toUpperCase()}',
      CanvasBackgroundMode.preset => _presetLabel(context, value.preset!),
    };
  }

  String _presetLabel(BuildContext context, CanvasBackgroundPreset preset) {
    final l10n = context.l10n;
    return switch (preset) {
      CanvasBackgroundPreset.notebook => l10n.backgroundNotebook,
      CanvasBackgroundPreset.graph => l10n.backgroundGraph,
      CanvasBackgroundPreset.cream => l10n.backgroundCream,
      CanvasBackgroundPreset.chalkboard => l10n.backgroundChalkboard,
      CanvasBackgroundPreset.softGradient => l10n.backgroundSoftGradient,
      CanvasBackgroundPreset.warmWhite => l10n.backgroundWarmWhite,
      CanvasBackgroundPreset.blueprint => l10n.backgroundBlueprint,
      CanvasBackgroundPreset.kraft => l10n.backgroundKraft,
      CanvasBackgroundPreset.dark => l10n.backgroundDark,
      CanvasBackgroundPreset.linen => l10n.backgroundLinen,
    };
  }
}

class _BackgroundPresetSwatch extends StatelessWidget {
  const _BackgroundPresetSwatch({
    required this.size,
    required this.preset,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final double size;
  final CanvasBackgroundPreset preset;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      enabled: enabled,
      child: Tooltip(
        message: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('canvas-background-${preset.name}'),
            onTap: enabled ? onTap : null,
            borderRadius: BorderRadius.circular(9),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: size,
              height: size * 0.78,
              padding: EdgeInsets.all(selected ? 2 : 1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? colors.accent : colors.border,
                  width: selected ? 2 : 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: colors.accent.withValues(alpha: 0.18),
                          blurRadius: 7,
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(
                      painter: _BackgroundSwatchPainter(
                        CanvasBackground.preset(preset),
                      ),
                    ),
                    if (selected)
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          margin: const EdgeInsets.all(3),
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.accent,
                          ),
                          child: Icon(
                            Icons.check_rounded,
                            size: 10,
                            color: colors.surface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BackgroundSwatchPainter extends CustomPainter {
  const _BackgroundSwatchPainter(this.background);

  final CanvasBackground background;

  @override
  void paint(Canvas canvas, Size size) => const CanvasBackgroundRenderer()
      .paint(canvas: canvas, rect: Offset.zero & size, background: background);

  @override
  bool shouldRepaint(_BackgroundSwatchPainter oldDelegate) =>
      oldDelegate.background != background;
}

class _CanvasColorDialog extends StatefulWidget {
  const _CanvasColorDialog({required this.initial});

  final Color initial;

  @override
  State<_CanvasColorDialog> createState() => _CanvasColorDialogState();
}

class _CanvasColorDialogState extends State<_CanvasColorDialog> {
  late int red;
  late int green;
  late int blue;
  late final TextEditingController hexController;

  Color get color => Color.fromARGB(255, red, green, blue);

  @override
  void initState() {
    super.initState();
    red = (widget.initial.r * 255).round();
    green = (widget.initial.g * 255).round();
    blue = (widget.initial.b * 255).round();
    hexController = TextEditingController(text: _hex(color));
  }

  @override
  void dispose() {
    hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return AlertDialog(
      title: Text(context.l10n.customBackgroundColor),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              height: 72,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              key: const ValueKey('canvas-background-hex'),
              controller: hexController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: context.l10n.hexColor,
                prefixText: '#',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _updateFromHex,
            ),
            const SizedBox(height: 10),
            _channel('R', red, (value) => red = value),
            _channel('G', green, (value) => green = value),
            _channel('B', blue, (value) => blue = value),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          key: const ValueKey('apply-canvas-background-color'),
          onPressed: () => Navigator.of(context).pop(color),
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(context.l10n.apply),
        ),
      ],
    );
  }

  Widget _channel(String label, int value, ValueChanged<int> assign) => Row(
    children: [
      SizedBox(width: 18, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.toDouble(),
          min: 0,
          max: 255,
          divisions: 255,
          label: '$value',
          onChanged: (next) {
            setState(() {
              assign(next.round());
              hexController.text = _hex(color);
            });
          },
        ),
      ),
      SizedBox(width: 32, child: Text('$value')),
    ],
  );

  void _updateFromHex(String raw) {
    final normalized = raw.replaceAll('#', '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(normalized)) return;
    final value = int.parse(normalized, radix: 16);
    setState(() {
      red = (value >> 16) & 0xFF;
      green = (value >> 8) & 0xFF;
      blue = value & 0xFF;
    });
  }

  String _hex(Color value) => value
      .toARGB32()
      .toRadixString(16)
      .padLeft(8, '0')
      .substring(2)
      .toUpperCase();
}
