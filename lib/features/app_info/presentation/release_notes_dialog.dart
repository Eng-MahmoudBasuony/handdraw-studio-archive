import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/features/app_info/application/release_notes_cubit.dart';
import 'package:handdraw_studio/features/app_info/application/release_notes_state.dart';
import 'package:handdraw_studio/features/app_info/domain/release_note.dart';
import 'package:handdraw_studio/features/app_info/presentation/studio_info_dialog_frame.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

Future<void> showReleaseNotesDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => const ReleaseNotesDialog(),
);

class ReleaseNotesDialog extends StatelessWidget {
  const ReleaseNotesDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StudioInfoDialogFrame(
      title: l10n.whatsNew,
      icon: StudioIconData.whatsNew,
      maxWidth: 820,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.done),
        ),
      ],
      child: BlocBuilder<ReleaseNotesCubit, ReleaseNotesState>(
        builder: (context, state) => switch (state.status) {
          ReleaseNotesStatus.loaded => ListView(
            key: const ValueKey('release-notes-list'),
            padding: const EdgeInsets.all(22),
            children: [
              Text(
                l10n.releaseNotesDescription,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: context.studioColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              for (final release in state.releases)
                _ReleaseCard(release: release),
            ],
          ),
          ReleaseNotesStatus.failure => _ReleaseNotesFailure(
            onRetry: context.read<ReleaseNotesCubit>().load,
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _ReleaseNotesFailure extends StatelessWidget {
  const _ReleaseNotesFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.description_outlined,
            size: 36,
            color: context.studioColors.textMuted,
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.releaseNotesLoadFailed,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.l10n.tryAgain),
          ),
        ],
      ),
    ),
  );
}

class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({required this.release});

  final AppRelease release;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.studioColors;
    final locale = Localizations.localeOf(context);
    final date = DateFormat.yMMMMd(
      locale.toLanguageTag(),
    ).format(release.releaseDate);
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        key: ValueKey('release-${release.version}'),
        initiallyExpanded: release.isCurrent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        title: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 6,
          children: [
            Text(
              l10n.versionLabel(release.version),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (release.isCurrent)
              _Pill(
                label: l10n.currentVersion,
                color: colors.accent,
                foreground: Theme.of(context).colorScheme.onPrimary,
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(date, style: TextStyle(color: colors.textMuted)),
        ),
        children: [
          for (final entry in release.entries) _ReleaseEntryTile(entry: entry),
        ],
      ),
    );
  }
}

class _ReleaseEntryTile extends StatelessWidget {
  const _ReleaseEntryTile({required this.entry});

  final ReleaseNoteEntry entry;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context);
    final colors = context.studioColors;
    final metadata = _metadata(context, entry.type);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border.withValues(alpha: 0.7)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(metadata.icon, size: 18, color: metadata.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          entry.title.resolve(locale),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        _Pill(
                          label: metadata.label,
                          color: metadata.color.withValues(alpha: 0.15),
                          foreground: metadata.color,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      entry.description.resolve(locale),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _ReleaseMetadata _metadata(BuildContext context, ReleaseChangeType type) {
    final l10n = context.l10n;
    final colors = context.studioColors;
    return switch (type) {
      ReleaseChangeType.newFeature => _ReleaseMetadata(
        label: l10n.releaseNew,
        icon: Icons.add_circle_outline_rounded,
        color: colors.accent,
      ),
      ReleaseChangeType.improvement => _ReleaseMetadata(
        label: l10n.releaseImproved,
        icon: Icons.auto_awesome_rounded,
        color: colors.reveal,
      ),
      ReleaseChangeType.fix => _ReleaseMetadata(
        label: l10n.releaseFixed,
        icon: Icons.check_circle_outline_rounded,
        color: colors.success,
      ),
    };
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.foreground,
  });

  final String label;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _ReleaseMetadata {
  const _ReleaseMetadata({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}
