import 'package:handdraw_studio/l10n/generated/app_localizations.dart';

extension LocalizedEditorStatus on AppLocalizations {
  String localizeEditorStatus(String raw) {
    final warningIndex = raw.indexOf(' • ');
    final message = warningIndex < 0 ? raw : raw.substring(0, warningIndex);
    final warning = warningIndex < 0 ? '' : raw.substring(warningIndex);

    final localized = switch (message) {
      'Import a drawing to begin' => importDrawingToBegin,
      'Hand library ready' => statusHandLibraryReady,
      'Drawing imported. Draw the first stroke.' => statusDrawingImported,
      'Importing drawing…' => statusDrawingImporting,
      'Custom hand saved. Calibrate the pen tip once.' => statusCustomHandSaved,
      'Smooth text reveal added' => statusSmoothRevealAdded,
      'Timing or Voice Guide change undone' => statusTimingUndone,
      'Last stroke removed' => statusLastStrokeRemoved,
      'Auto Path batch removed' => statusAutoBatchRemoved,
      'Timing or Voice Guide change restored' => statusTimingRestored,
      'Stroke restored' => statusStrokeRestored,
      'Stroke deleted' => statusStrokeDeleted,
      'Stroke direction reversed' => statusDirectionReversed,
      'Stroke changed to hand drawing' => statusChangedToHand,
      'Stroke changed to reveal only' => statusChangedToReveal,
      'Import a drawing before using Auto Path.' => statusImportBeforeAutoPath,
      'Detecting text, shapes, and pen paths…' => statusDetectingSmartPaths,
      'Auto Path did not find a clear section.' => statusNoClearSection,
      'Import a drawing before using Auto Reveal.' =>
        statusImportBeforeAutoReveal,
      'Building a smooth reveal for the entire artwork…' =>
        statusBuildingReveal,
      'Auto Reveal ready using a full-artwork directional wipe.' =>
        statusAutoRevealDirectional,
      'Auto Reveal ready with a continuous side-to-side hand sweep.' =>
        statusAutoRevealSweep,
      'Auto Reveal ready with the safe full-artwork fallback.' =>
        statusAutoRevealFallback,
      'Auto Path suggestions cleared.' => statusSuggestionsCleared,
      'Pen tip calibrated and saved' => statusPenCalibrated,
      'Canvas is already clear.' => canvasAlreadyClear,
      'Canvas cleared. Hand and global settings were kept.' => canvasCleared,
      'Canvas content restored.' => statusCanvasRestored,
      'Settings reset to defaults. Canvas content was kept.' => settingsReset,
      'Voice Guide and its section cues removed.' => statusVoiceRemoved,
      'This section cannot start at the selected time because the previous section ends later.' =>
        statusCueImpossible,
      'Voice cue cleared.' => statusCueCleared,
      'Section timing reset' => statusSectionTimingReset,
      'Advanced timing updated' => statusAdvancedTimingUpdated,
      'Project saved' => statusProjectSaved,
      'Project opened, but the drawing file is missing' =>
        statusProjectOpenedMissingDrawing,
      'Project opened' => statusProjectOpened,
      'Voice Guide is missing. Locate or remove it to continue syncing.' =>
        statusVoiceMissing,
      'New project. Selected hand was kept.' => statusNewProject,
      _ => _localizeDynamicStatus(message),
    };
    return '$localized$warning';
  }

  String _localizeDynamicStatus(String message) {
    String? tail(String prefix) =>
        message.startsWith(prefix) ? message.substring(prefix.length) : null;

    final loadHandError = tail('Could not load the hand library: ');
    if (loadHandError != null) {
      return statusCouldNotLoadHandLibrary(loadHandError);
    }
    final importHandError = tail('Could not import hand: ');
    if (importHandError != null) {
      return statusCouldNotImportHand(importHandError);
    }
    final importDrawingError = tail('Could not import drawing: ');
    if (importDrawingError != null) {
      return statusCouldNotImportDrawing(importDrawingError);
    }
    final selectHandError = tail('Could not select hand: ');
    if (selectHandError != null) {
      return statusCouldNotSelectHand(selectHandError);
    }
    final autoPathError = tail('Auto Path failed: ');
    if (autoPathError != null) {
      return statusAutoPathFailed(autoPathError);
    }
    final penError = tail('Pen tip set, but save failed: ');
    if (penError != null) {
      return statusPenSaveFailed(penError);
    }
    final voiceError = tail('Could not import the Voice Guide: ');
    if (voiceError != null) {
      return statusVoiceImportFailed(voiceError);
    }

    final strokes = RegExp(r'^(\d+) stroke\(s\) ready$').firstMatch(message);
    if (strokes != null) {
      return statusStrokesReady(int.parse(strokes.group(1)!));
    }
    final sections = RegExp(
      r'^(\d+) section\(s\) detected\. Choose Hand or Reveal Text, then Apply\.$',
    ).firstMatch(message);
    if (sections != null) {
      return statusSectionsReady(int.parse(sections.group(1)!));
    }
    final revealSections = RegExp(
      r'^Auto Reveal ready: (\d+) section\(s\) in visual order\.$',
    ).firstMatch(message);
    if (revealSections != null) {
      return statusAutoRevealReady(int.parse(revealSections.group(1)!));
    }
    final smartRegion = RegExp(
      r'^Smart Region Reveal ready with (Adaptive|Canny\+|Morph Shell) detail analysis\.$',
    ).firstMatch(message);
    if (smartRegion != null) {
      return statusSmartRegionReveal(smartRegion.group(1)!);
    }
    final paths = RegExp(
      r'^(\d+) automatic path\(s\) added\. Preview is ready\.$',
    ).firstMatch(message);
    if (paths != null) {
      return statusAutomaticPathsAdded(int.parse(paths.group(1)!));
    }
    final sceneReveals = RegExp(
      r'^(\d+) ordered scene reveal\(s\) ready with one broad hand path each\.$',
    ).firstMatch(message);
    if (sceneReveals != null) {
      return statusOrderedSceneReveals(int.parse(sceneReveals.group(1)!));
    }
    final cue = RegExp(r'^Voice cue linked at (.+)s\.$').firstMatch(message);
    if (cue != null) {
      return statusCueLinked(cue.group(1)!);
    }
    const voiceSuffix = ' imported as a preview-only Voice Guide.';
    if (message.endsWith(voiceSuffix)) {
      return statusVoiceImported(
        message.substring(0, message.length - voiceSuffix.length),
      );
    }
    const selectedSuffix = ' selected';
    if (message.endsWith(selectedSuffix)) {
      return statusHandSelected(
        message.substring(0, message.length - selectedSuffix.length),
      );
    }
    return message;
  }
}
