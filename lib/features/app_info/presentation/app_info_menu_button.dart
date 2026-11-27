import 'package:handdraw_studio/features/cache_management/presentation/cache_cleanup_dialog.dart';
import 'package:flutter/material.dart';

import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/features/app_info/presentation/about_dialog.dart';
import 'package:handdraw_studio/features/app_info/presentation/release_notes_dialog.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

enum AppInfoMenuAction { whatsNew, about, clearCache }

Future<void> handleAppInfoAction(
  BuildContext context,
  AppInfoMenuAction action,
) async {
  switch (action) {
    case AppInfoMenuAction.whatsNew:
      await showReleaseNotesDialog(context);
    case AppInfoMenuAction.clearCache:
      await showCacheCleanupDialog(context);
    case AppInfoMenuAction.about:
      await showStudioAboutDialog(context);
  }
}

class AppInfoMenuButton extends StatelessWidget {
  const AppInfoMenuButton({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<AppInfoMenuAction>(
    key: const ValueKey('app-info-menu'),
    tooltip: context.l10n.appInformation,
    icon: const Icon(Icons.more_horiz_rounded),
    onSelected: (action) => handleAppInfoAction(context, action),
    itemBuilder: (context) => [
      PopupMenuItem(
        value: AppInfoMenuAction.clearCache,
        child: Text(
          Localizations.localeOf(context).languageCode == 'ar'
              ? 'مسح الكاش'
              : 'Clear cache',
        ),
      ),
      PopupMenuItem(
        value: AppInfoMenuAction.whatsNew,
        child: _MenuRow(
          icon: StudioIconData.whatsNew,
          label: context.l10n.whatsNew,
        ),
      ),
      PopupMenuItem(
        value: AppInfoMenuAction.about,
        child: _MenuRow(
          icon: StudioIconData.about,
          label: context.l10n.aboutApp,
        ),
      ),
    ],
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final StudioIconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      StudioIcon(icon, size: 18),
      const SizedBox(width: 10),
      Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
    ],
  );
}
