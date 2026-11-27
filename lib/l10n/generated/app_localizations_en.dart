// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'HandDraw Studio';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get newAction => 'New';

  @override
  String get openAction => 'Open';

  @override
  String get saveAction => 'Save';

  @override
  String get clearCanvas => 'Clear Canvas';

  @override
  String get newProject => 'New project';

  @override
  String get openProject => 'Open project';

  @override
  String get saveProject => 'Save project';

  @override
  String get unsavedChanges => 'Unsaved changes';

  @override
  String get chooseDrawing => 'Choose Drawing';

  @override
  String get chooseHand => 'Choose Hand';

  @override
  String get images => 'Images';

  @override
  String get handDrawProject => 'HandDraw project';

  @override
  String get voiceRecordings => 'Voice recordings';

  @override
  String get quickTimeMovie => 'QuickTime Movie';

  @override
  String get exportMovie => 'Export Movie';

  @override
  String get projectActions => 'Project actions';

  @override
  String get appInformation => 'App information';

  @override
  String get aboutApp => 'About HandDraw Studio';

  @override
  String get whatsNew => 'What’s New';

  @override
  String get releaseNotesDescription =>
      'Explore the features, improvements, and fixes included in every HandDraw Studio release.';

  @override
  String get releaseNotesLoadFailed => 'Release notes could not be loaded.';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get currentVersion => 'CURRENT';

  @override
  String get releaseNew => 'NEW';

  @override
  String get releaseImproved => 'IMPROVED';

  @override
  String get releaseFixed => 'FIXED';

  @override
  String get aboutTheApp => 'About the app';

  @override
  String get aboutDescription =>
      'HandDraw Studio transforms images, text, and illustrations into precise hand-drawn animations ready for professional editing.';

  @override
  String get creator => 'Creator';

  @override
  String get systemInformation => 'System information';

  @override
  String get legalAndCredits => 'Legal & credits';

  @override
  String get soundCreditsDescription =>
      'Bundled writing recordings retain their original source names in the project credits. Package licenses are available below.';

  @override
  String get openSourceLicenses => 'Open-source licenses';

  @override
  String copyrightNotice(int year) {
    return '© $year Mahmoud Basuony. All rights reserved.';
  }

  @override
  String versionBuild(String version, String build) {
    return 'Version $version • Build $build';
  }

  @override
  String get version => 'Version';

  @override
  String get build => 'Build';

  @override
  String get platform => 'Platform';

  @override
  String get exportFormat => 'Export format';

  @override
  String get defaultCanvas => 'Default canvas';

  @override
  String get copySystemInfo => 'Copy system info';

  @override
  String get systemInfoCopied => 'System information copied.';

  @override
  String get undoStroke => 'Undo stroke (⌘Z)';

  @override
  String get redoStroke => 'Redo stroke (⌘⇧Z)';

  @override
  String get openInspector => 'Open inspector';

  @override
  String get closeInspector => 'Close inspector';

  @override
  String get importVoice => 'Import Voice';

  @override
  String get voiceGuide => 'Voice Guide';

  @override
  String get resume => 'Resume';

  @override
  String get pause => 'Pause';

  @override
  String get stopPreview => 'Stop preview';

  @override
  String get preview => 'Preview';

  @override
  String get exportMov => 'Export MOV';

  @override
  String get drawing => 'Drawing';

  @override
  String get sourceFile => 'Source file';

  @override
  String get hands => 'Hands';

  @override
  String get hand => 'Hand';

  @override
  String get penTip => 'Pen Tip';

  @override
  String get analyzing => 'Analyzing…';

  @override
  String get analysisRecognizingText => 'Recognizing text';

  @override
  String get analysisReadingPixels => 'Reading image pixels';

  @override
  String get analysisPreparingRaster => 'Preparing image detail';

  @override
  String get analysisTracingText => 'Tracing text paths';

  @override
  String get analysisFindingShapes => 'Finding artwork regions';

  @override
  String get analysisTracingShapes => 'Tracing artwork paths';

  @override
  String get analysisValidatingPaths => 'Checking path coverage';

  @override
  String get analysisFinalizing => 'Finalizing paths';

  @override
  String analysisElapsedRemaining(String elapsed, String remaining) {
    return '$elapsed elapsed • about $remaining left';
  }

  @override
  String analysisElapsedEstimating(String elapsed) {
    return '$elapsed elapsed • estimating time left';
  }

  @override
  String get autoPath => 'Auto Path';

  @override
  String get autoPathUnavailableForBackgroundTitle =>
      'Auto Path isn’t suitable for this image';

  @override
  String get autoPathUnavailableForBackgroundDescription =>
      'This looks like a colored or full-background image. Auto Path would trace the background and produce a poor result. Use Auto Reveal to uncover the original image naturally without changing transparent images or SVG behavior.';

  @override
  String get useAutoReveal => 'Use Auto Reveal';

  @override
  String get autoReveal => 'Auto Reveal';

  @override
  String get select => 'Select';

  @override
  String get drawPath => 'Draw Path';

  @override
  String get manualDrawReveal => 'Draw & Reveal';

  @override
  String get manualDrawRevealDescription =>
      'Draw the hand path directly. The same ordered stroke reveals the original artwork in Preview and MOV.';

  @override
  String get manualRevealWidth => 'Reveal brush';

  @override
  String get revealText => 'Reveal Text';

  @override
  String get maskReveal => 'Mask Reveal';

  @override
  String get maskErase => 'Mask Erase';

  @override
  String get addCameraShot => 'Add Camera';

  @override
  String get project => 'PROJECT';

  @override
  String get resetSettings => 'Reset settings';

  @override
  String get notSelected => 'Not selected';

  @override
  String get detectingPaths => 'Detecting text, artwork, and center paths…';

  @override
  String get timingReveal => 'TIMING & REVEAL';

  @override
  String get timingUnavailableDescription =>
      'Add at least one path to edit timing and reveal settings.';

  @override
  String get baseDuration => 'Base duration';

  @override
  String get globalDrawingSpeed => 'Overall drawing speed';

  @override
  String get drawingTime => 'Drawing time';

  @override
  String get penTravelSpeed => 'Pen travel speed';

  @override
  String get penTravelTime => 'Pen travel time';

  @override
  String get fitToDuration => 'Fit to duration';

  @override
  String get fitToDurationTitle => 'Fit drawing to duration';

  @override
  String get fitToDurationDescription =>
      'Choose the exact final duration. Only drawing speed is adjusted; pen travel, pauses, voice cues, and holds stay unchanged.';

  @override
  String get targetDuration => 'Target duration (seconds)';

  @override
  String fitDurationRange(String minimum, String maximum) {
    return 'Available with the current fixed timing: ${minimum}s–${maximum}s';
  }

  @override
  String get fitDurationImpossible =>
      'This duration cannot be reached without changing fixed pauses, pen travel, or holds.';

  @override
  String get apply => 'Apply';

  @override
  String get autoTiming => 'Auto timing';

  @override
  String autoTimingValue(String wait, String hold) {
    return '${wait}s wait  •  ${hold}s hold';
  }

  @override
  String get sections => 'Sections';

  @override
  String sectionsDetected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections detected automatically',
      one: '1 section detected automatically',
      zero: 'No sections detected automatically',
    );
    return '$_temp0';
  }

  @override
  String get outputDuration => 'Output duration';

  @override
  String get revealWidth => 'Reveal width';

  @override
  String get handSection => 'HAND';

  @override
  String get handUnavailableDescription =>
      'Choose a hand to adjust its size, rotation, and direction.';

  @override
  String get size => 'Size';

  @override
  String get rotationOffset => 'Rotation offset';

  @override
  String get writingSound => 'WRITING SOUND';

  @override
  String get writingSoundUnavailableDescription =>
      'Add at least one path to use synchronized writing sound.';

  @override
  String get startupSound => 'STARTUP SOUND';

  @override
  String get playStartupSound => 'Play startup sound';

  @override
  String get startupSoundDescription =>
      'A gentle branded cue plays once when the app opens and fades naturally.';

  @override
  String get includeWritingSound => 'Include writing sound';

  @override
  String get writingSoundOnDescription => 'Synced in Preview and exported MOV';

  @override
  String get writingSoundOffDescription => 'Off — exported MOV stays silent';

  @override
  String get soundType => 'Sound type';

  @override
  String get previewSelectedSound => 'Preview selected sound';

  @override
  String get playingSoundPreview => 'Playing sample…';

  @override
  String get stopSoundPreview => 'Stop sound preview';

  @override
  String get soundPreviewFailed => 'Could not play this sample';

  @override
  String get volume => 'Volume';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get noAudioAvailable => 'No audio in this project';

  @override
  String get videoQuality => 'Video quality';

  @override
  String get strokes => 'STROKES';

  @override
  String get emptyStrokesHelp =>
      'Choose Draw Path for the hand, or Reveal Text for a smooth reveal without the hand.';

  @override
  String get autoPathSections => 'AUTO PATH SECTIONS';

  @override
  String get autoPathApplied => 'Applied';

  @override
  String get autoPathAppliedDescription =>
      'Auto Path is already applied. The generated result is ready to arrange, preview, and export.';

  @override
  String get autoPathPaths => 'Paths';

  @override
  String get autoPathHandDraw => 'Hand draw';

  @override
  String get autoPathNativeVectors => 'Native vectors';

  @override
  String get autoPathTimelineReady =>
      'Ready in the Smart Timeline • Preview and MOV use the same paths';

  @override
  String autoPathResultSemantics(int sections, int paths) {
    return 'Auto Path applied with $sections sections and $paths paths';
  }

  @override
  String get autoPathReview => 'AUTO PATH REVIEW';

  @override
  String get experimental => 'Experimental';

  @override
  String get suspectedFrameDescription =>
      'A high-confidence canvas frame was excluded from the preview. Restore it if the border is intentional, then apply the paths.';

  @override
  String suspectedFrameCount(Object count) {
    return '$count suspected frame candidates are ready for review';
  }

  @override
  String get restoreFrame => 'Restore';

  @override
  String get excludeFrame => 'Exclude';

  @override
  String get scenePlanner => 'Smart Timeline';

  @override
  String get scenePlannerHelp =>
      'Drag sections to set the real drawing order. Select related items to group them into a movable scene.';

  @override
  String get drawSceneGroup => 'Select on Canvas (optional)';

  @override
  String get finishSceneGroup => 'Draw an enclosure on the canvas';

  @override
  String get resetSceneGroups => 'Reset Groups';

  @override
  String sceneSectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections',
      one: '1 section',
    );
    return '$_temp0';
  }

  @override
  String get autoArrangeTimeline => 'Auto Arrange';

  @override
  String groupSelectedTimeline(int count) {
    return 'Group Selected ($count)';
  }

  @override
  String get timelineDragHelp =>
      'Drag scenes or items. Open a scene to reorder its contents.';

  @override
  String get cancel => 'Cancel';

  @override
  String get textKind => 'Text';

  @override
  String get artworkKind => 'Artwork';

  @override
  String get ignore => 'Ignore';

  @override
  String get reveal => 'Reveal';

  @override
  String get advancedTiming => 'Advanced Timing';

  @override
  String get advancedTimingDescription =>
      'Independent drawing, travel, pauses, and per-section speed';

  @override
  String sectionsCustomized(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections customized',
      one: '1 section customized',
    );
    return '$_temp0';
  }

  @override
  String get pauseBefore => 'Pause before';

  @override
  String get pauseAfter => 'Pause after';

  @override
  String get pauseAtSectionStart => 'Pause at section start';

  @override
  String get pauseAtSectionEnd => 'Pause at section end';

  @override
  String get handEntranceAnimation => 'Hand entrance animation';

  @override
  String get handExitAnimation => 'Hand exit animation';

  @override
  String get noAnimation => 'None';

  @override
  String get fadeIn => 'Fade in';

  @override
  String get moveIn => 'Move in';

  @override
  String get slingshot => 'Slingshot';

  @override
  String get fadeOut => 'Fade out';

  @override
  String get moveOut => 'Move out';

  @override
  String get disappear => 'Disappear';

  @override
  String get handAnimationDuration => 'Hand animation duration';

  @override
  String get timingOn => 'On';

  @override
  String get timingOff => 'Off';

  @override
  String get drawingSpeed => 'Drawing speed';

  @override
  String get keepHandVisible => 'Keep hand visible while paused';

  @override
  String get keepHandVisibleAfterDrawing => 'Keep hand visible after drawing';

  @override
  String get keepHandVisibleAfterDrawingDescription =>
      'Keep the hand at the final pen position until the section or video ends.';

  @override
  String get pauseSoundDescription =>
      'The writing sound remains silent during every pause.';

  @override
  String get resetSection => 'Reset section';

  @override
  String get voiceCue => 'Voice cue';

  @override
  String get notLinked => 'Not linked';

  @override
  String startSectionHere(String time) {
    return 'Start Section Here  •  $time';
  }

  @override
  String get fineTune => 'Fine tune';

  @override
  String get clearVoiceCue => 'Clear Voice Cue';

  @override
  String cueConflict(String seconds) {
    return 'The previous section ends ${seconds}s after this cue. Move the cue later or shorten earlier timing.';
  }

  @override
  String get revealOnly => 'reveal only';

  @override
  String get reversed => 'reversed';

  @override
  String get moveUp => 'Move up';

  @override
  String get moveDown => 'Move down';

  @override
  String get strokeActions => 'Stroke actions';

  @override
  String get reverseDirection => 'Reverse direction';

  @override
  String get showHandOnStroke => 'Show hand on this stroke';

  @override
  String get revealWithoutHand => 'Reveal without hand';

  @override
  String get deleteStroke => 'Delete stroke';

  @override
  String get dragToReorder => 'Drag to reorder paths';

  @override
  String get previewThisStroke => 'Preview this path';

  @override
  String get addPausePoint => 'Add pause point';

  @override
  String get pausePoints => 'Pause points';

  @override
  String pausePoint(Object duration, Object progress) {
    return 'Pause at $progress% · ${duration}s';
  }

  @override
  String get pausePosition => 'Position on path';

  @override
  String get pauseDuration => 'Pause duration';

  @override
  String get keepHandAtPause => 'Keep hand visible';

  @override
  String get editPausePoint => 'Edit pause point';

  @override
  String get deletePausePoint => 'Delete pause point';

  @override
  String get appearanceMethod => 'Appearance method';

  @override
  String get withHand => 'Draw with hand';

  @override
  String get withoutHand => 'Reveal without hand';

  @override
  String get moveUpTooltip => 'Move one position earlier';

  @override
  String get moveDownTooltip => 'Move one position later';

  @override
  String get clickExactPenTip => 'Click the exact pen tip';

  @override
  String get useThisPoint => 'Use this point';

  @override
  String get handLibrary => 'Hand Library';

  @override
  String get handLibraryDescription =>
      'Every hand keeps its own calibrated pen tip.';

  @override
  String get handVideoSize => 'Hand size in video';

  @override
  String get handVideoSizeDescription => 'Same size in Preview and MOV';

  @override
  String get resetHandVideoSize => 'Reset to this hand\'s default size';

  @override
  String get handMarkerRight => 'Marker — Right';

  @override
  String get handMarkerLeft => 'Marker — Left';

  @override
  String get handMarkerCompact => 'Marker — Compact';

  @override
  String get handDarkMarkerRight => 'Dark Marker — Right';

  @override
  String get handFineLinerRight => 'Fine Liner — Right';

  @override
  String get handBlueMarkerRight => 'Blue Marker — Right';

  @override
  String get handFrontBlackMarkerRight => 'Front Black Marker — Right';

  @override
  String get handTechnicalPenWheat => 'Technical Pen — Wheat';

  @override
  String get close => 'Close';

  @override
  String get defaultBadge => 'DEFAULT';

  @override
  String get customBadge => 'CUSTOM';

  @override
  String get importCustomHand => 'Import Custom Hand';

  @override
  String get calibratePenTip => 'Calibrate Pen Tip';

  @override
  String get done => 'Done';

  @override
  String get pauseVoicePreview => 'Pause Voice Guide preview';

  @override
  String get playVoiceWithAnimation => 'Play Voice Guide with the animation';

  @override
  String get voiceGuideTooltip =>
      'Voice Guide is used for preview and synchronization only. It is never exported.';

  @override
  String get voiceFileMissing => 'File missing — locate to preview';

  @override
  String get voicePreviewOnly => 'Preview & sync only • not exported';

  @override
  String get dragToScrub => 'Drag to scrub • markers are section cues';

  @override
  String get voiceGuideActions => 'Voice Guide actions';

  @override
  String get locateVoiceGuide => 'Locate Voice Guide';

  @override
  String get replaceVoiceGuide => 'Replace Voice Guide';

  @override
  String get removeVoiceGuide => 'Remove Voice Guide';

  @override
  String get locate => 'Locate';

  @override
  String pausedProgress(int progress) {
    return 'Paused $progress%';
  }

  @override
  String previewProgress(int progress) {
    return 'Preview $progress%';
  }

  @override
  String get fps => 'fps';

  @override
  String get canvasAlreadyClear => 'The canvas is already clear.';

  @override
  String get canvasCleared =>
      'Canvas cleared. Hand and global settings were kept.';

  @override
  String get undo => 'UNDO';

  @override
  String get replaceAnimationPaths => 'Replace animation paths?';

  @override
  String get replaceAnimationPathsDescription =>
      'Auto Reveal creates a clean animation for the whole image. Background images use smart edge detection to reveal the outline first, then the original colors; uncertain results safely fall back to diagonal hand sweeps. It will replace the current stroke list.';

  @override
  String get replaceAndReveal => 'Replace & Reveal';

  @override
  String savedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String get settingsReset =>
      'Settings reset to defaults. Canvas content was kept.';

  @override
  String get importDrawingOrVoice => 'Import a drawing or a Voice Guide first.';

  @override
  String get voiceGuideReady =>
      'Voice Guide ready. It will not be included in Export MOV.';

  @override
  String get importDrawingAndStroke =>
      'Import a drawing and create at least one stroke first.';

  @override
  String get preparingExport => 'Preparing export';

  @override
  String renderingFrame(int current, int total) {
    return 'Rendering frame $current of $total';
  }

  @override
  String get generatingWritingSound => 'Generating synchronized writing sound';

  @override
  String get encodingProRes => 'Encoding Apple ProRes 4444';

  @override
  String get exportComplete => 'Export complete';

  @override
  String exportedTo(String path) {
    return 'ProRes 4444 exported to $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get importDrawingToBegin => 'Import a drawing to begin';

  @override
  String get importDrawingToStart => 'Import a drawing to start';

  @override
  String get pencilOnPaper => 'Pencil on Paper';

  @override
  String get markerOnPaper => 'Marker on Paper';

  @override
  String get technicalPen => 'Technical Pen';

  @override
  String get realPaperSoft => 'Real Paper — Soft';

  @override
  String get realPaperPencil => 'Real Paper — Pencil';

  @override
  String get realPaperNatural => 'Real Paper — Natural';

  @override
  String get realPaperQuick => 'Real Paper — Quick';

  @override
  String get statusHandLibraryReady => 'Hand library ready';

  @override
  String statusCouldNotLoadHandLibrary(Object error) {
    return 'Could not load the hand library: $error';
  }

  @override
  String get statusDrawingImported =>
      'Drawing imported. Draw the first stroke.';

  @override
  String get statusDrawingImporting => 'Importing drawing…';

  @override
  String statusCouldNotImportDrawing(String error) {
    return 'Could not import drawing: $error';
  }

  @override
  String get statusCustomHandSaved =>
      'Custom hand saved. Calibrate the pen tip once.';

  @override
  String statusCouldNotImportHand(Object error) {
    return 'Could not import hand: $error';
  }

  @override
  String statusHandSelected(Object name) {
    return '$name selected';
  }

  @override
  String statusCouldNotSelectHand(Object error) {
    return 'Could not select hand: $error';
  }

  @override
  String get statusSmoothRevealAdded => 'Smooth text reveal added';

  @override
  String statusStrokesReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count strokes ready',
      one: '1 stroke ready',
    );
    return '$_temp0';
  }

  @override
  String get statusTimingUndone => 'Timing or Voice Guide change undone';

  @override
  String get statusLastStrokeRemoved => 'Last stroke removed';

  @override
  String get statusAutoBatchRemoved => 'Auto Path batch removed';

  @override
  String get statusTimingRestored => 'Timing or Voice Guide change restored';

  @override
  String get statusStrokeRestored => 'Stroke restored';

  @override
  String get statusStrokeDeleted => 'Stroke deleted';

  @override
  String get statusDirectionReversed => 'Stroke direction reversed';

  @override
  String get statusChangedToHand => 'Stroke changed to hand drawing';

  @override
  String get statusChangedToReveal => 'Stroke changed to reveal only';

  @override
  String get statusImportBeforeAutoPath =>
      'Import a drawing before using Auto Path.';

  @override
  String get statusDetectingSmartPaths =>
      'Detecting text, shapes, and pen paths…';

  @override
  String get statusNoClearSection => 'Auto Path did not find a clear section.';

  @override
  String statusSectionsReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sections detected. Choose Hand or Reveal Text, then Apply.',
      one: '1 section detected. Choose Hand or Reveal Text, then Apply.',
    );
    return '$_temp0';
  }

  @override
  String statusAutoPathFailed(Object error) {
    return 'Auto Path failed: $error';
  }

  @override
  String get statusImportBeforeAutoReveal =>
      'Import a drawing before using Auto Reveal.';

  @override
  String get statusBuildingReveal =>
      'Building a smooth reveal for the entire artwork…';

  @override
  String get statusAutoRevealDirectional =>
      'Auto Reveal ready using a full-artwork directional wipe.';

  @override
  String get statusAutoRevealSweep =>
      'Auto Reveal ready with a continuous side-to-side hand sweep.';

  @override
  String statusSmartRegionReveal(String algorithm) {
    return 'Smart Region Reveal is ready using $algorithm detail analysis.';
  }

  @override
  String statusAutoRevealReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sections',
      one: '1 section',
    );
    return 'Auto Reveal ready: $_temp0 in visual order.';
  }

  @override
  String get statusAutoRevealFallback =>
      'Auto Reveal ready with the safe full-artwork fallback.';

  @override
  String statusAutomaticPathsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count automatic paths added',
      one: '1 automatic path added',
    );
    return '$_temp0. Preview is ready.';
  }

  @override
  String statusOrderedSceneReveals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ordered scene reveals are ready',
      one: '1 ordered scene reveal is ready',
    );
    return '$_temp0, with one broad hand path each.';
  }

  @override
  String get statusSuggestionsCleared => 'Auto Path suggestions cleared.';

  @override
  String get statusPenCalibrated => 'Pen tip calibrated and saved';

  @override
  String statusPenSaveFailed(Object error) {
    return 'Pen tip set, but save failed: $error';
  }

  @override
  String get statusCanvasRestored => 'Canvas content restored.';

  @override
  String statusVoiceImported(Object name) {
    return '$name imported as a preview-only Voice Guide.';
  }

  @override
  String statusVoiceImportFailed(Object error) {
    return 'Could not import the Voice Guide: $error';
  }

  @override
  String get statusVoiceRemoved => 'Voice Guide and its section cues removed.';

  @override
  String get statusCueImpossible =>
      'This section cannot start at the selected time because the previous section ends later.';

  @override
  String statusCueLinked(Object seconds) {
    return 'Voice cue linked at ${seconds}s.';
  }

  @override
  String get statusCueCleared => 'Voice cue cleared.';

  @override
  String get statusSectionTimingReset => 'Section timing reset';

  @override
  String get statusAdvancedTimingUpdated => 'Advanced timing updated';

  @override
  String get statusProjectSaved => 'Project saved';

  @override
  String get statusProjectOpenedMissingDrawing =>
      'Project opened, but the drawing file is missing';

  @override
  String get statusProjectOpened => 'Project opened';

  @override
  String get statusVoiceMissing =>
      'Voice Guide is missing. Locate or remove it to continue syncing.';

  @override
  String get statusNewProject => 'New project. Selected hand was kept.';

  @override
  String get theme => 'Appearance';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get resolution => 'Resolution';

  @override
  String get customWidth => 'Width';

  @override
  String get customHeight => 'Height';

  @override
  String get pixelsUnit => 'px';

  @override
  String customResolutionRange(int min, int max) {
    return 'Enter a value from $min to $max px';
  }

  @override
  String get applyResolution => 'Apply size';

  @override
  String get frameRate => 'Frame rate';

  @override
  String get background => 'Background';

  @override
  String get canvasBackground => 'Canvas background';

  @override
  String get canvasBackgroundDescription =>
      'Choose the surface behind every scene. It is saved with the project and included in Preview and MOV.';

  @override
  String get backgroundNone => 'None';

  @override
  String get backgroundWhite => 'White';

  @override
  String get backgroundBlack => 'Black';

  @override
  String get backgroundCustom => 'Custom';

  @override
  String get backgroundPresets => 'Surfaces';

  @override
  String get backgroundNotebook => 'Notebook';

  @override
  String get backgroundGraph => 'Graph paper';

  @override
  String get backgroundCream => 'Cream paper';

  @override
  String get backgroundChalkboard => 'Chalkboard';

  @override
  String get backgroundSoftGradient => 'Soft gradient';

  @override
  String get backgroundWarmWhite => 'Warm white';

  @override
  String get backgroundBlueprint => 'Blueprint';

  @override
  String get backgroundKraft => 'Kraft paper';

  @override
  String get backgroundDark => 'Dark';

  @override
  String get backgroundLinen => 'Linen';

  @override
  String get customBackgroundColor => 'Custom background color';

  @override
  String get hexColor => 'Hex color';

  @override
  String get transparent => 'Transparent';

  @override
  String get startDelay => 'Start delay';

  @override
  String get endHold => 'End hold';

  @override
  String get animation => 'Animation';

  @override
  String get audio => 'Audio';

  @override
  String get fileMenu => 'File';

  @override
  String get projectMenu => 'Project';

  @override
  String get editMenu => 'Edit';

  @override
  String get viewMenu => 'View';

  @override
  String get windowMenu => 'Window';

  @override
  String get helpMenu => 'Help';

  @override
  String get importMenu => 'Import';

  @override
  String get toolsMenu => 'Tools';

  @override
  String get exportingMovie => 'Exporting movie';

  @override
  String get exportSucceeded => 'Export completed';

  @override
  String get exportFailedTitle => 'Export failed';

  @override
  String get cancelExport => 'Cancel Export';

  @override
  String get exportCanceled => 'Export canceled';

  @override
  String get finishingExport => 'Finishing export…';

  @override
  String get revealInFinder => 'Reveal in Finder';

  @override
  String get openMovie => 'Open Movie';

  @override
  String get copyPath => 'Copy Path';

  @override
  String get pathCopied => 'Path copied';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get tryAgain => 'Try Again';

  @override
  String exportOutputDetails(String size, String duration) {
    return 'Apple ProRes 4444 • Alpha • $size • $duration';
  }

  @override
  String get exportSafeNotice =>
      'Your project is saved separately and was not changed.';

  @override
  String get licenses => 'Licenses';

  @override
  String get stop => 'Stop';

  @override
  String get selectToolMenu => 'Select Tool';

  @override
  String get drawPathToolMenu => 'Draw Path Tool';

  @override
  String get revealTextToolMenu => 'Reveal Text Tool';

  @override
  String get addNode => 'Add Node';

  @override
  String get deleteNode => 'Delete Node';

  @override
  String get smoothNode => 'Convert to Smooth';

  @override
  String get cornerNode => 'Convert to Corner';

  @override
  String get splitPath => 'Split Path Here';

  @override
  String get joinNextPath => 'Join with Next Path';

  @override
  String get setStartNode => 'Set as Start Node';

  @override
  String get hidePath => 'Hide Animation Path';

  @override
  String get showPath => 'Show Animation Path';

  @override
  String get resetMask => 'Reset Reveal Mask';

  @override
  String get maskBrushSize => 'Mask Brush Size';

  @override
  String get maskFeather => 'Mask Feather';

  @override
  String get showMaskOverlay => 'Show Mask Overlay';

  @override
  String get compareBeforeMask => 'Preview Before Mask';

  @override
  String get exportPreset => 'Export Preset';

  @override
  String get exportUnavailableDescription =>
      'Import a drawing and add at least one path to configure export.';

  @override
  String get presetYoutube4k => 'YouTube / Course 4K';

  @override
  String get presetFinalCut4k => 'Final Cut Overlay 4K';

  @override
  String get presetVerticalLesson => 'Vertical Lesson';

  @override
  String get presetSquareLesson => 'Square Lesson';

  @override
  String get presetPresentationHd => 'Presentation 1080p';

  @override
  String get presetCustom => 'Custom';

  @override
  String get exportQuality => 'Export Quality';

  @override
  String get exportFullQuality => 'Full Resolution';

  @override
  String get exportProxyQuality => 'Half-resolution Proxy';

  @override
  String get alphaMode => 'Alpha Interpretation';

  @override
  String get alphaPremultiplied => 'Premultiplied Alpha';

  @override
  String get alphaStraight => 'Straight Alpha';

  @override
  String get clipMaskToLayer => 'Clip Mask to Layer';

  @override
  String get snapNodes => 'Snap Nodes to Precision Grid';

  @override
  String get timelineSectionProperties => 'Section timing';

  @override
  String get timelineSectionTimingDescription =>
      'These exact durations drive the timeline, Preview, and MOV export.';

  @override
  String sectionDrawingSpeedDescription(String duration) {
    return 'This section will draw in $duration s. Speed and duration stay synchronized.';
  }

  @override
  String get animateDuration => 'Animate';

  @override
  String get transitionDuration => 'Transition';

  @override
  String totalSectionDuration(String duration) {
    return 'Total: $duration s';
  }

  @override
  String get deleteTimelineSectionTitle => 'Delete timeline section?';

  @override
  String deleteTimelineSectionDescription(String name) {
    return 'Remove “$name” and its animation from the timeline? This does not delete the imported source file.';
  }

  @override
  String get zoomIn => 'Zoom in';

  @override
  String get zoomOut => 'Zoom out';

  @override
  String get importBehavior => 'Import behavior';

  @override
  String get fullScene => 'Full scene';

  @override
  String get fullSceneDescription =>
      'Preserve the complete image and its placement';

  @override
  String get singleElement => 'Element';

  @override
  String get singleElementDescription =>
      'Focus placement on the visible content';

  @override
  String get artworkFit => 'Artwork fit';

  @override
  String get fitEntireImage => 'Fit entire image';

  @override
  String get fitVisibleContent => 'Fit visible content';

  @override
  String get originalSize => 'Original size';

  @override
  String get fillCanvas => 'Fill canvas';

  @override
  String get fillCanvasWarning =>
      'This option fills the canvas and may crop part of the artwork.';

  @override
  String get positionAndSize => 'Position and size';

  @override
  String get positionAndSizeDescription => 'Exact canvas coordinates';

  @override
  String get centerHorizontal => 'Center horizontally';

  @override
  String get centerVertical => 'Center vertically';

  @override
  String get resetPlacement => 'Reset placement';
}
