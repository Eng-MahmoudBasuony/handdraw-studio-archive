import 'package:handdraw_smart_path/handdraw_smart_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/branding/app_brand_logo.dart';
import 'package:handdraw_studio/app/icons/studio_icon.dart';
import 'package:handdraw_studio/app/localization/application/app_locale_cubit.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/localization/presentation/language_menu_button.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/app/theme/palette/app_palette.dart';
import 'package:handdraw_studio/app/theme/presentation/theme_menu_button.dart';
import 'package:handdraw_studio/features/editor/application/editor_cubit.dart';
import 'package:handdraw_studio/features/editor/application/editor_state.dart';
import 'package:handdraw_studio/features/editor/presentation/layout/editor_layout_spec.dart';
import 'package:handdraw_studio/features/app_info/presentation/app_info_menu_button.dart';
import 'package:handdraw_studio/l10n/l10n.dart';

class EditorToolbarActions {
  const EditorToolbarActions({
    required this.onNew,
    required this.onAnimateImage,
    required this.onOpen,
    required this.onSave,
    required this.onClear,
    required this.onImportDrawing,
    required this.onImportHand,
    required this.onCalibrateHand,
    required this.onAddCameraShot,
    required this.onToolChanged,
    required this.onUndo,
    required this.onRedo,
    required this.onImportVoice,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onExport,
    this.onOpenInspector,
  });

  final VoidCallback onNew;
  final VoidCallback onAnimateImage;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onClear;
  final VoidCallback onImportDrawing;
  final VoidCallback onImportHand;
  final VoidCallback onCalibrateHand;
  final VoidCallback onAddCameraShot;
  final ValueChanged<EditorTool> onToolChanged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onImportVoice;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onExport;
  final VoidCallback? onOpenInspector;
}

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    super.key,
    required this.cubit,
    required this.layout,
    required this.actions,
    required this.isPreviewing,
    required this.isPreviewPaused,
    this.isExporting = false,
    this.exportProgress = 0,
  });

  final EditorCubit cubit;
  final EditorLayoutSpec layout;
  final EditorToolbarActions actions;
  final bool isPreviewing;
  final bool isPreviewPaused;
  final bool isExporting;
  final double exportProgress;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final primary = _PrimaryToolbarRow(
      cubit: cubit,
      layout: layout,
      actions: actions,
      isPreviewing: isPreviewing,
      isPreviewPaused: isPreviewPaused,
      isExporting: isExporting,
      exportProgress: exportProgress,
      trailingTools: layout.isWide
          ? Expanded(
              child: _EditorToolsRow(
                cubit: cubit,
                layout: layout,
                actions: actions,
                isPreviewing: isPreviewing,
              ),
            )
          : null,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.toolbar,
            Color.lerp(colors.toolbar, colors.selectedSurface, 0.34)!,
          ],
        ),
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SizedBox(
        key: ValueKey(
          layout.usesTwoRowToolbar
              ? 'editor-toolbar-two-row'
              : 'editor-toolbar-one-row',
        ),
        height: layout.toolbarHeight,
        child: Column(
          children: [
            SizedBox(height: 61, child: primary),
            if (layout.usesTwoRowToolbar) ...[
              const Divider(height: 1),
              Expanded(
                child: _EditorToolsRow(
                  cubit: cubit,
                  layout: layout,
                  actions: actions,
                  isPreviewing: isPreviewing,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrimaryToolbarRow extends StatelessWidget {
  const _PrimaryToolbarRow({
    required this.cubit,
    required this.layout,
    required this.actions,
    required this.isPreviewing,
    required this.isPreviewPaused,
    required this.trailingTools,
    required this.isExporting,
    required this.exportProgress,
  });

  final EditorCubit cubit;
  final EditorLayoutSpec layout;
  final EditorToolbarActions actions;
  final bool isPreviewing;
  final bool isPreviewPaused;
  final Widget? trailingTools;
  final bool isExporting;
  final double exportProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canExport = cubit.canPreview && !isExporting;
    final compactActions =
        !layout.isWide ||
        (layout.isWide && layout.viewportWidth < 2000) ||
        (cubit.voiceGuide != null && layout.viewportWidth < 1450);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          AppBrandLogo(
            key: const ValueKey('editor-brand-logo'),
            size: layout.isNarrow ? 50 : 58,
          ),
          if (layout.showsBrandLabel) ...[
            const SizedBox(width: 8),
            Text(
              key: const ValueKey('editor-brand-label'),
              l10n.appTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            SizedBox(width: layout.isWide ? 16 : 8),
          ] else
            const SizedBox(width: 4),
          if (layout.usesFileMenu)
            _FileActionsMenu(cubit: cubit, actions: actions)
          else ...[
            _ToolbarGroup(
              children: [
                _ToolbarAction(
                  icon: StudioIconData.newProject,
                  label: l10n.newAction,
                  compact: compactActions,
                  onPressed: actions.onNew,
                ),
                _ToolbarAction(
                  icon: StudioIconData.openProject,
                  label: l10n.openAction,
                  compact: compactActions,
                  onPressed: actions.onOpen,
                ),
                _ToolbarAction(
                  icon: StudioIconData.saveProject,
                  label: l10n.saveAction,
                  compact: compactActions,
                  onPressed: actions.onSave,
                ),
              ],
            ),
            const SizedBox(width: 6),
            _CanvasActionsMenu(cubit: cubit, actions: actions),
          ],
          if (trailingTools != null) ...[
            const SizedBox(width: 8),
            trailingTools!,
          ] else
            const Spacer(),
          IconButton(
            key: const ValueKey('editor-undo'),
            tooltip: l10n.undoStroke,
            onPressed: cubit.canUndo ? actions.onUndo : null,
            icon: const StudioIcon(StudioIconData.undo, size: 19),
          ),
          IconButton(
            key: const ValueKey('editor-redo'),
            tooltip: l10n.redoStroke,
            onPressed: cubit.canRedo ? actions.onRedo : null,
            icon: const StudioIcon(StudioIconData.redo, size: 19),
          ),
          if (layout.isNarrow)
            IconButton(
              key: const ValueKey('open-inspector'),
              tooltip: l10n.openInspector,
              onPressed: actions.onOpenInspector,
              icon: const StudioIcon(StudioIconData.inspector, size: 19),
            ),
          const SizedBox(width: 4),
          if (!layout.isNarrow) ...[
            const LanguageMenuButton(),
            const ThemeMenuButton(),
          ],
          if (layout.isWide) const AppInfoMenuButton(),
          if (!layout.isNarrow)
            _ToolbarAction(
              icon: StudioIconData.voice,
              label: cubit.voiceGuide == null
                  ? l10n.importVoice
                  : l10n.voiceGuide,
              compact: true,
              onPressed: cubit.isVoiceGuideLoading || isPreviewing
                  ? null
                  : actions.onImportVoice,
            ),
          if (layout.showsBrandLabel)
            OutlinedButton.icon(
              key: const ValueKey('editor-export'),
              onPressed: canExport ? actions.onExport : null,
              icon: isExporting
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const StudioIcon(StudioIconData.exportMovie, size: 18),
              label: Text(
                isExporting
                    ? '${(exportProgress * 100).round()}%'
                    : l10n.exportMov,
              ),
            )
          else
            IconButton.outlined(
              key: const ValueKey('editor-export'),
              tooltip: l10n.exportMov,
              onPressed: canExport ? actions.onExport : null,
              icon: isExporting
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const StudioIcon(StudioIconData.exportMovie, size: 18),
            ),
        ],
      ),
    );
  }
}

class _FileActionsMenu extends StatelessWidget {
  const _FileActionsMenu({required this.cubit, required this.actions});

  final EditorCubit cubit;
  final EditorToolbarActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.projectActions,
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) {
        switch (value) {
          case 'new':
            actions.onNew();
            return;
          case 'open':
            actions.onOpen();
            return;
          case 'save':
            actions.onSave();
            return;
          case 'clear':
            actions.onClear();
            return;
          case 'language-system':
            _selectLocale(context, AppLocalePreference.system);
            return;
          case 'language-en':
            _selectLocale(context, AppLocalePreference.english);
            return;
          case 'language-ar':
            _selectLocale(context, AppLocalePreference.arabic);
            return;
          case 'theme-system':
            _selectTheme(context, AppThemePreference.system);
            return;
          case 'theme-light':
            _selectTheme(context, AppThemePreference.light);
            return;
          case 'theme-dark':
            _selectTheme(context, AppThemePreference.dark);
            return;
          case 'whats-new':
            handleAppInfoAction(context, AppInfoMenuAction.whatsNew);
            return;
          case 'clear-cache':
            handleAppInfoAction(context, AppInfoMenuAction.clearCache);
            return;
          case 'about':
            handleAppInfoAction(context, AppInfoMenuAction.about);
            return;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(value: 'new', child: Text(l10n.newProject)),
        PopupMenuItem(value: 'open', child: Text(l10n.openProject)),
        PopupMenuItem(value: 'save', child: Text(l10n.saveProject)),
        PopupMenuItem(
          value: 'clear',
          enabled: cubit.hasCanvasContent,
          child: Text(l10n.clearCanvas),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'language-system',
          child: Text('${l10n.language}: ${l10n.languageSystem}'),
        ),
        PopupMenuItem(value: 'language-en', child: Text(l10n.languageEnglish)),
        PopupMenuItem(value: 'language-ar', child: Text(l10n.languageArabic)),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'theme-system',
          child: Text('${l10n.theme}: ${l10n.themeSystem}'),
        ),
        PopupMenuItem(value: 'theme-light', child: Text(l10n.themeLight)),
        PopupMenuItem(value: 'theme-dark', child: Text(l10n.themeDark)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'whats-new', child: Text(l10n.whatsNew)),
        PopupMenuItem(
          value: 'clear-cache',
          child: Text(
            Localizations.localeOf(context).languageCode == 'ar'
                ? 'مسح الكاش'
                : 'Clear cache',
          ),
        ),
        PopupMenuItem(value: 'about', child: Text(l10n.aboutApp)),
      ],
    );
  }

  void _selectLocale(BuildContext context, AppLocalePreference preference) {
    try {
      context.read<AppLocaleCubit>().select(preference);
    } catch (_) {
      // The standalone editor can be embedded without application settings.
    }
  }

  void _selectTheme(BuildContext context, AppThemePreference preference) {
    ThemeMenuButton.maybeThemeCubit(context, listen: false)?.select(preference);
  }
}

class _CanvasActionsMenu extends StatelessWidget {
  const _CanvasActionsMenu({required this.cubit, required this.actions});

  final EditorCubit cubit;
  final EditorToolbarActions actions;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: context.l10n.clearCanvas,
    icon: const StudioIcon(StudioIconData.clearCanvas, size: 18),
    enabled: cubit.hasCanvasContent,
    onSelected: (_) => actions.onClear(),
    itemBuilder: (context) => [
      PopupMenuItem(value: 'clear', child: Text(context.l10n.clearCanvas)),
    ],
  );
}

class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.studioColors.surfaceAlt.withValues(alpha: 0.58),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: context.studioColors.border),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: children),
  );
}

class _EditorToolsRow extends StatelessWidget {
  const _EditorToolsRow({
    required this.cubit,
    required this.layout,
    required this.actions,
    required this.isPreviewing,
  });

  final EditorCubit cubit;
  final EditorLayoutSpec layout;
  final EditorToolbarActions actions;
  final bool isPreviewing;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: layout.isWide ? 0 : 10),
      child: Row(
        children: [
          FilledButton.icon(
            key: const ValueKey('animate-image'),
            onPressed: isPreviewing ? null : actions.onAnimateImage,
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: Text(arabic ? 'تحريك الصورة' : 'Animate image'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            tooltip: arabic ? 'الصورة والإيد' : 'Image & hand',
            icon: const Icon(Icons.tune_rounded, size: 20),
            onSelected: (value) {
              switch (value) {
                case 'drawing':
                  actions.onImportDrawing();
                case 'hand':
                  actions.onImportHand();
                case 'pen':
                  actions.onCalibrateHand();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'drawing', child: Text(l10n.drawing)),
              PopupMenuItem(value: 'hand', child: Text(l10n.hands)),
              PopupMenuItem(
                value: 'pen',
                enabled: cubit.hasHand,
                child: Text(l10n.penTip),
              ),
            ],
          ),
          if (cubit.isAnalyzingSmartPaths) ...[
            const SizedBox(width: 8),
            Flexible(
              child: _SmartPathAnalysisProgress(
                progress: cubit.state.smartPathProgress,
                elapsed: cubit.state.smartPathAnalysisElapsed,
                compact: layout.isNarrow || layout.viewportWidth < 1500,
              ),
            ),
            if (cubit.isAnalyzingSmartScenes)
              IconButton(
                key: const ValueKey('cancel-smart-scene-analysis'),
                tooltip: l10n.cancel,
                onPressed: cubit.cancelSmartSceneAnalysis,
                icon: const Icon(Icons.close),
              ),
          ],
          const Spacer(),
          const SizedBox(width: 6),
          Tooltip(
            message: l10n.addCameraShot,
            child: FilledButton(
              key: const ValueKey('toolbar-add-camera-shot'),
              onPressed:
                  (cubit.hasDrawing ||
                          cubit.state.document.scenes.isNotEmpty) &&
                      !isPreviewing
                  ? actions.onAddCameraShot
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size(40, 40),
                padding: EdgeInsets.symmetric(
                  horizontal: layout.showsToolLabels ? 12 : 10,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_a_photo_outlined, size: 17),
                  if (layout.showsToolLabels) ...[
                    const SizedBox(width: 7),
                    Text(l10n.addCameraShot),
                  ],
                ],
              ),
            ),
          ),
          if (!layout.isWide && !layout.usesFileMenu) ...[
            const SizedBox(width: 6),
            const AppInfoMenuButton(),
          ],
        ],
      ),
    );
  }
}

class _SmartPathAnalysisProgress extends StatelessWidget {
  const _SmartPathAnalysisProgress({
    required this.progress,
    required this.elapsed,
    required this.compact,
  });

  final SmartPathProgress? progress;
  final Duration elapsed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.studioColors;
    final fraction = progress?.fraction.clamp(0.0, 1.0) ?? 0.0;
    final percent = (fraction * 100).round();
    final progressStage = progress?.stage;
    final stage = _stageLabel(context, progressStage);
    final elapsedText = _shortDuration(elapsed);
    final hasStableLinearEstimate =
        progressStage != SmartPathProgressStage.validatingPaths &&
        progressStage != SmartPathProgressStage.finalizing;
    final canEstimate =
        hasStableLinearEstimate && elapsed.inSeconds >= 1 && fraction >= 0.12;
    final remaining = canEstimate
        ? Duration(
            milliseconds: (elapsed.inMilliseconds * (1 - fraction) / fraction)
                .round(),
          )
        : null;
    final timing = remaining == null
        ? context.l10n.analysisElapsedEstimating(elapsedText)
        : context.l10n.analysisElapsedRemaining(
            elapsedText,
            _shortDuration(remaining),
          );

    return Semantics(
      key: const ValueKey('smart-path-analysis-progress'),
      label: stage,
      value: '$percent% — $timing',
      liveRegion: true,
      child: Container(
        width: compact ? 190 : 236,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 2 : 6,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceAlt.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 10 : null,
                      height: compact ? 1 : null,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$percent%',
                  key: const ValueKey('smart-path-analysis-percent'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 10 : null,
                    height: compact ? 1 : null,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 1 : 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: compact ? 3 : 4,
                backgroundColor: colors.border.withValues(alpha: 0.55),
              ),
            ),
            SizedBox(height: compact ? 1 : 3),
            Text(
              timing,
              key: const ValueKey('smart-path-analysis-timing'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: compact ? 9 : null,
                height: compact ? 1 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _stageLabel(
    BuildContext context,
    SmartPathProgressStage? stage,
  ) => switch (stage) {
    SmartPathProgressStage.recognizingText =>
      context.l10n.analysisRecognizingText,
    SmartPathProgressStage.readingPixels => context.l10n.analysisReadingPixels,
    SmartPathProgressStage.preparingRaster =>
      context.l10n.analysisPreparingRaster,
    SmartPathProgressStage.tracingText => context.l10n.analysisTracingText,
    SmartPathProgressStage.findingShapes => context.l10n.analysisFindingShapes,
    SmartPathProgressStage.tracingShapes => context.l10n.analysisTracingShapes,
    SmartPathProgressStage.validatingPaths =>
      context.l10n.analysisValidatingPaths,
    SmartPathProgressStage.finalizing => context.l10n.analysisFinalizing,
    null => context.l10n.analyzing,
  };

  String _shortDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 5999);
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
  }
}

class _ToolbarAction extends StatelessWidget {
  const _ToolbarAction({
    required this.icon,
    required this.label,
    required this.compact,
    this.onPressed,
  });

  final StudioIconData icon;
  final String label;
  final bool compact;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tooltip = label;
    final child = compact
        ? IconButton(
            tooltip: tooltip,
            onPressed: onPressed,
            icon: StudioIcon(icon, size: 18),
          )
        : TextButton.icon(
            onPressed: onPressed,
            icon: StudioIcon(icon, size: 17),
            label: Text(label),
          );
    return child;
  }
}
