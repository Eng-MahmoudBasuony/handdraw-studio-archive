import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:handdraw_studio/app/branding/app_brand_logo.dart';
import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'package:handdraw_studio/features/app_info/presentation/release_notes_dialog.dart';
import 'package:handdraw_studio/features/app_info/presentation/studio_info_dialog_frame.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

enum _AboutAction { whatsNew, licenses }

Future<void> showStudioAboutDialog(BuildContext context) async {
  final action = await showDialog<_AboutAction>(
    context: context,
    builder: (_) => const StudioAboutDialog(),
  );
  if (!context.mounted || action == null) return;
  switch (action) {
    case _AboutAction.whatsNew:
      await showReleaseNotesDialog(context);
    case _AboutAction.licenses:
      showLicensePage(
        context: context,
        applicationName: context.l10n.appTitle,
        applicationVersion: AppBuildInfo.displayVersion,
        applicationIcon: const Padding(
          padding: EdgeInsets.all(12),
          child: AppBrandLogo(size: 88),
        ),
      );
  }
}

class StudioAboutDialog extends StatelessWidget {
  const StudioAboutDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StudioInfoDialogFrame(
      title: l10n.aboutApp,
      icon: StudioIconData.about,
      maxWidth: 720,
      actions: [
        OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, _AboutAction.whatsNew),
          icon: const StudioIcon(StudioIconData.whatsNew, size: 17),
          label: Text(l10n.whatsNew),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
      child: ListView(
        key: const ValueKey('about-dialog-content'),
        padding: const EdgeInsets.all(22),
        children: [
          const _BrandHero(),
          const SizedBox(height: 22),
          _AboutSection(
            title: l10n.aboutTheApp,
            icon: StudioIconData.about,
            child: Text(l10n.aboutDescription),
          ),
          const SizedBox(height: 12),
          _AboutSection(
            title: l10n.creator,
            icon: StudioIconData.penTip,
            child: const Text('Mahmoud Basuony'),
          ),
          const SizedBox(height: 12),
          _AboutSection(
            title: l10n.systemInformation,
            icon: StudioIconData.inspector,
            child: _SystemInformation(),
          ),
          const SizedBox(height: 12),
          _AboutSection(
            title: l10n.legalAndCredits,
            icon: StudioIconData.licenses,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.soundCreditsDescription),
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: () =>
                        Navigator.pop(context, _AboutAction.licenses),
                    icon: const StudioIcon(StudioIconData.licenses, size: 17),
                    label: Text(l10n.openSourceLicenses),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.copyrightNotice(AppBuildInfo.copyrightYear),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.studioColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHero extends StatelessWidget {
  const _BrandHero();

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: colors.accent.withValues(alpha: 0.20),
                blurRadius: 30,
                spreadRadius: 2,
              ),
              BoxShadow(
                color: colors.reveal.withValues(alpha: 0.16),
                blurRadius: 36,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const AppBrandLogo(size: 138),
        ),
        const SizedBox(height: 14),
        Text(
          context.l10n.appTitle,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          context.l10n.versionBuild(
            AppBuildInfo.version,
            AppBuildInfo.buildNumber,
          ),
          style: TextStyle(color: colors.textSecondary),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final StudioIconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.78)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                StudioIcon(icon, size: 18, color: colors.accent),
                const SizedBox(width: 9),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 10),
            DefaultTextStyle.merge(
              style: TextStyle(color: colors.textSecondary, height: 1.45),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemInformation extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final rows = <(String, String)>[
      (l10n.version, AppBuildInfo.version),
      (l10n.build, AppBuildInfo.buildNumber),
      (l10n.platform, _platformLabel),
      (l10n.exportFormat, 'Apple ProRes 4444'),
      (l10n.defaultCanvas, '1920×1080 • 30 fps'),
    ];
    final systemInfo = rows.map((row) => '${row.$1}: ${row.$2}').join('\n');
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(row.$1)),
                const SizedBox(width: 16),
                SelectableText(
                  row.$2,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: context.studioColors.textPrimary),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('copy-system-info'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: systemInfo));
              if (!context.mounted) return;
              ScaffoldMessenger.maybeOf(
                context,
              )?.showSnackBar(SnackBar(content: Text(l10n.systemInfoCopied)));
            },
            icon: const StudioIcon(StudioIconData.copy, size: 17),
            label: Text(l10n.copySystemInfo),
          ),
        ),
      ],
    );
  }

  String get _platformLabel => switch (defaultTargetPlatform) {
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}
