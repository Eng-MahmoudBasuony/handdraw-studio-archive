import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/localization/application/app_locale_cubit.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/theme/application/app_theme_cubit.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/l10n/generated/app_localizations.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class StudioMenuActions {
  const StudioMenuActions({
    required this.onAbout,
    required this.onWhatsNew,
    required this.onLicenses,
    required this.onNew,
    required this.onOpen,
    required this.onSave,
    required this.onImportDrawing,
    required this.onImportHand,
    required this.onImportVoice,
    required this.onCalibrateHand,
    required this.onResetSettings,
    required this.onExport,
    required this.onUndo,
    required this.onRedo,
    required this.onClearCanvas,
    required this.onPreview,
    required this.onPauseOrResume,
    required this.onStop,
    required this.onAnimateImage,
    required this.onOpenInspector,
  });

  final VoidCallback onAbout;
  final VoidCallback onWhatsNew;
  final VoidCallback onLicenses;
  final VoidCallback onNew;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onImportDrawing;
  final VoidCallback onImportHand;
  final VoidCallback onImportVoice;
  final VoidCallback onCalibrateHand;
  final VoidCallback onResetSettings;
  final VoidCallback onExport;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClearCanvas;
  final VoidCallback onPreview;
  final VoidCallback onPauseOrResume;
  final VoidCallback onStop;
  final VoidCallback onAnimateImage;
  final VoidCallback onOpenInspector;
}

class StudioPlatformMenuBar extends StatelessWidget {
  const StudioPlatformMenuBar({
    super.key,
    required this.actions,
    required this.isBusy,
    required this.isPreviewing,
    required this.isPreviewPaused,
    required this.canPreview,
    required this.hasCanvasContent,
    required this.hasDrawing,
    required this.hasHand,
    required this.child,
  });

  final StudioMenuActions actions;
  final bool isBusy;
  final bool isPreviewing;
  final bool isPreviewPaused;
  final bool canPreview;
  final bool hasCanvasContent;
  final bool hasDrawing;
  final bool hasHand;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // PlatformMenuBar owns a process-wide native delegate. Widget tests run
    // several app instances in parallel, so they validate the menu model
    // separately and intentionally skip installing the native delegate.
    const isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');
    if (defaultTargetPlatform != TargetPlatform.macOS || isFlutterTest) {
      return child;
    }
    final l10n = context.l10n;
    final theme = _maybeReadTheme(context);
    final locale = _maybeReadLocale(context);
    VoidCallback? enabled(VoidCallback callback, [bool allowed = true]) =>
        !isBusy && allowed ? callback : null;

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: l10n.appTitle,
          menus: buildStudioApplicationMenuItems(
            aboutLabel: l10n.aboutApp,
            whatsNewLabel: l10n.whatsNew,
            licensesLabel: l10n.licenses,
            onAbout: actions.onAbout,
            onWhatsNew: actions.onWhatsNew,
            onLicenses: actions.onLicenses,
          ),
        ),
        PlatformMenu(
          label: l10n.fileMenu,
          menus: [
            PlatformMenuItem(
              label: l10n.newProject,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelected: enabled(actions.onNew),
            ),
            PlatformMenuItem(
              label: l10n.openProject,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyO,
                meta: true,
              ),
              onSelected: enabled(actions.onOpen),
            ),
            PlatformMenuItem(
              label: l10n.saveProject,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyS,
                meta: true,
              ),
              onSelected: enabled(actions.onSave),
            ),
            PlatformMenu(
              label: l10n.importMenu,
              menus: [
                PlatformMenuItem(
                  label: l10n.drawing,
                  onSelected: enabled(actions.onImportDrawing),
                ),
                PlatformMenuItem(
                  label: l10n.hands,
                  onSelected: enabled(actions.onImportHand),
                ),
                PlatformMenuItem(
                  label: l10n.importVoice,
                  onSelected: enabled(actions.onImportVoice),
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l10n.exportMov,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyE,
                    meta: true,
                  ),
                  onSelected: enabled(actions.onExport, canPreview),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.editMenu,
          menus: [
            PlatformMenuItem(
              label: l10n.undo,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
              ),
              onSelected: enabled(actions.onUndo, hasCanvasContent),
            ),
            PlatformMenuItem(
              label: l10n.redoStroke,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ),
              onSelected: enabled(actions.onRedo),
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l10n.clearCanvas,
                  onSelected: enabled(actions.onClearCanvas, hasCanvasContent),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.projectMenu,
          menus: [
            PlatformMenuItem(
              label: l10n.drawing,
              onSelected: enabled(actions.onImportDrawing),
            ),
            PlatformMenuItem(
              label: l10n.hands,
              onSelected: enabled(actions.onImportHand),
            ),
            PlatformMenuItem(
              label: l10n.penTip,
              onSelected: enabled(actions.onCalibrateHand, hasHand),
            ),
            PlatformMenuItem(
              label: l10n.importVoice,
              onSelected: enabled(actions.onImportVoice),
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l10n.clearCanvas,
                  onSelected: enabled(actions.onClearCanvas, hasCanvasContent),
                ),
                PlatformMenuItem(
                  label: l10n.resetSettings,
                  onSelected: enabled(actions.onResetSettings),
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.animation,
          menus: [
            PlatformMenuItem(
              label: l10n.preview,
              shortcut: const SingleActivator(LogicalKeyboardKey.space),
              onSelected: enabled(
                actions.onPreview,
                canPreview && !isPreviewing,
              ),
            ),
            PlatformMenuItem(
              label: isPreviewPaused ? l10n.resume : l10n.pause,
              onSelected: enabled(actions.onPauseOrResume, isPreviewing),
            ),
            PlatformMenuItem(
              label: l10n.stop,
              shortcut: const SingleActivator(LogicalKeyboardKey.escape),
              onSelected: enabled(actions.onStop, isPreviewing),
            ),
            PlatformMenuItem(
              label: Localizations.localeOf(context).languageCode == 'ar'
                  ? 'تحريك الصورة'
                  : 'Animate image',
              onSelected: enabled(actions.onAnimateImage),
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.viewMenu,
          menus: [
            PlatformMenuItem(
              label: l10n.openInspector,
              onSelected: actions.onOpenInspector,
            ),
            PlatformMenu(
              label: l10n.theme,
              menus: [
                for (final preference in AppThemePreference.values)
                  PlatformMenuItem(
                    label:
                        '${theme == preference ? '✓ ' : ''}${_themeLabel(l10n, preference)}',
                    onSelected: theme == null
                        ? null
                        : () =>
                              context.read<AppThemeCubit>().select(preference),
                  ),
              ],
            ),
            PlatformMenu(
              label: l10n.language,
              menus: [
                for (final preference in AppLocalePreference.values)
                  PlatformMenuItem(
                    label:
                        '${locale == preference ? '✓ ' : ''}${_localeLabel(l10n, preference)}',
                    onSelected: locale == null
                        ? null
                        : () =>
                              context.read<AppLocaleCubit>().select(preference),
                  ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.windowMenu,
          menus: const [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
        PlatformMenu(
          label: l10n.helpMenu,
          menus: [
            PlatformMenuItem(
              label: l10n.whatsNew,
              onSelected: actions.onWhatsNew,
            ),
            PlatformMenuItem(label: l10n.aboutApp, onSelected: actions.onAbout),
            PlatformMenuItem(
              label: l10n.licenses,
              onSelected: actions.onLicenses,
            ),
          ],
        ),
      ],
      child: child,
    );
  }

  AppThemePreference? _maybeReadTheme(BuildContext context) {
    try {
      return context.watch<AppThemeCubit>().state;
    } catch (_) {
      return null;
    }
  }

  AppLocalePreference? _maybeReadLocale(BuildContext context) {
    try {
      return context.watch<AppLocaleCubit>().state;
    } catch (_) {
      return null;
    }
  }

  String _themeLabel(AppLocalizations l10n, AppThemePreference preference) =>
      switch (preference) {
        AppThemePreference.system => l10n.themeSystem,
        AppThemePreference.light => l10n.themeLight,
        AppThemePreference.dark => l10n.themeDark,
      };

  String _localeLabel(AppLocalizations l10n, AppLocalePreference preference) =>
      switch (preference) {
        AppLocalePreference.system => l10n.languageSystem,
        AppLocalePreference.english => l10n.languageEnglish,
        AppLocalePreference.arabic => l10n.languageArabic,
      };
}

@visibleForTesting
List<PlatformMenuItem> buildStudioApplicationMenuItems({
  required String aboutLabel,
  required String whatsNewLabel,
  required String licensesLabel,
  required VoidCallback onAbout,
  required VoidCallback onWhatsNew,
  required VoidCallback onLicenses,
}) => [
  PlatformMenuItem(label: aboutLabel, onSelected: onAbout),
  PlatformMenuItem(label: whatsNewLabel, onSelected: onWhatsNew),
  PlatformMenuItem(label: licensesLabel, onSelected: onLicenses),
];
