import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';

class StudioInfoDialogFrame extends StatelessWidget {
  const StudioInfoDialogFrame({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    required this.actions,
    this.maxWidth = 760,
  });

  final String title;
  final StudioIconData icon;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(maxWidth, math.max(280.0, media.width - 24));
    final dialogHeight = math.min(780.0, math.max(420.0, media.height - 36));
    final colors = context.studioColors;

    return Dialog(
      insetPadding: const EdgeInsets.all(12),
      clipBehavior: Clip.antiAlias,
      backgroundColor: colors.surface,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 12, 14),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.accentContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: StudioIcon(icon, size: 20, color: colors.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: colors.border),
            Expanded(child: child),
            Divider(height: 1, color: colors.border),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: actions,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
