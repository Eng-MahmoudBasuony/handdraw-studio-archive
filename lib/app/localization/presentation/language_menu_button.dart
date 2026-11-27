import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/localization/application/app_locale_cubit.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class LanguageMenuButton extends StatelessWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final localeCubit = _maybeLocaleCubit(context, listen: true);
    if (localeCubit == null) return const SizedBox.shrink();
    final selected = localeCubit.state;
    return PopupMenuButton<AppLocalePreference>(
      key: const ValueKey('language-menu'),
      tooltip: l10n.language,
      icon: const Icon(Icons.language_rounded),
      initialValue: selected,
      onSelected: localeCubit.select,
      itemBuilder: (context) => [
        _item(
          preference: AppLocalePreference.system,
          label: l10n.languageSystem,
          selected: selected,
        ),
        _item(
          preference: AppLocalePreference.english,
          label: l10n.languageEnglish,
          selected: selected,
        ),
        _item(
          preference: AppLocalePreference.arabic,
          label: l10n.languageArabic,
          selected: selected,
        ),
      ],
    );
  }

  AppLocaleCubit? _maybeLocaleCubit(
    BuildContext context, {
    required bool listen,
  }) {
    try {
      return listen
          ? context.watch<AppLocaleCubit>()
          : context.read<AppLocaleCubit>();
    } catch (_) {
      // EditorScreen is reusable in widget hosts that do not own app settings.
      return null;
    }
  }

  PopupMenuItem<AppLocalePreference> _item({
    required AppLocalePreference preference,
    required String label,
    required AppLocalePreference selected,
  }) {
    return PopupMenuItem(
      value: preference,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: preference == selected
                ? const Icon(Icons.check_rounded, size: 18)
                : null,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
