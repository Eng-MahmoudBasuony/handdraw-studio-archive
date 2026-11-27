import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/theme/application/app_theme_cubit.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class ThemeMenuButton extends StatelessWidget {
  const ThemeMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = maybeThemeCubit(context, listen: true);
    if (cubit == null) return const SizedBox.shrink();
    final selected = cubit.state;
    final l10n = context.l10n;
    return PopupMenuButton<AppThemePreference>(
      key: const ValueKey('theme-menu'),
      tooltip: l10n.theme,
      icon: Icon(_iconFor(selected)),
      initialValue: selected,
      onSelected: cubit.select,
      itemBuilder: (context) => [
        _item(AppThemePreference.system, l10n.themeSystem, selected),
        _item(AppThemePreference.light, l10n.themeLight, selected),
        _item(AppThemePreference.dark, l10n.themeDark, selected),
      ],
    );
  }

  static AppThemeCubit? maybeThemeCubit(
    BuildContext context, {
    required bool listen,
  }) {
    try {
      return listen
          ? context.watch<AppThemeCubit>()
          : context.read<AppThemeCubit>();
    } catch (_) {
      // EditorScreen can be reused without application-level settings.
      return null;
    }
  }

  IconData _iconFor(AppThemePreference preference) => switch (preference) {
    AppThemePreference.system => Icons.brightness_auto_rounded,
    AppThemePreference.light => Icons.light_mode_rounded,
    AppThemePreference.dark => Icons.dark_mode_rounded,
  };

  PopupMenuItem<AppThemePreference> _item(
    AppThemePreference value,
    String label,
    AppThemePreference selected,
  ) => PopupMenuItem(
    value: value,
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: value == selected
              ? const Icon(Icons.check_rounded, size: 18)
              : null,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    ),
  );
}
