import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'HandDraw Studio'**
  String get appTitle;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System language'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @newAction.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newAction;

  /// No description provided for @openAction.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openAction;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @clearCanvas.
  ///
  /// In en, this message translates to:
  /// **'Clear Canvas'**
  String get clearCanvas;

  /// No description provided for @newProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get newProject;

  /// No description provided for @openProject.
  ///
  /// In en, this message translates to:
  /// **'Open project'**
  String get openProject;

  /// No description provided for @saveProject.
  ///
  /// In en, this message translates to:
  /// **'Save project'**
  String get saveProject;

  /// No description provided for @unsavedChanges.
  ///
  /// In en, this message translates to:
  /// **'Unsaved changes'**
  String get unsavedChanges;

  /// No description provided for @chooseDrawing.
  ///
  /// In en, this message translates to:
  /// **'Choose Drawing'**
  String get chooseDrawing;

  /// No description provided for @chooseHand.
  ///
  /// In en, this message translates to:
  /// **'Choose Hand'**
  String get chooseHand;

  /// No description provided for @images.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get images;

  /// No description provided for @handDrawProject.
  ///
  /// In en, this message translates to:
  /// **'HandDraw project'**
  String get handDrawProject;

  /// No description provided for @voiceRecordings.
  ///
  /// In en, this message translates to:
  /// **'Voice recordings'**
  String get voiceRecordings;

  /// No description provided for @quickTimeMovie.
  ///
  /// In en, this message translates to:
  /// **'QuickTime Movie'**
  String get quickTimeMovie;

  /// No description provided for @exportMovie.
  ///
  /// In en, this message translates to:
  /// **'Export Movie'**
  String get exportMovie;

  /// No description provided for @projectActions.
  ///
  /// In en, this message translates to:
  /// **'Project actions'**
  String get projectActions;

  /// No description provided for @appInformation.
  ///
  /// In en, this message translates to:
  /// **'App information'**
  String get appInformation;

  /// No description provided for @aboutApp.
  ///
  /// In en, this message translates to:
  /// **'About HandDraw Studio'**
  String get aboutApp;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What’s New'**
  String get whatsNew;

  /// No description provided for @releaseNotesDescription.
  ///
  /// In en, this message translates to:
  /// **'Explore the features, improvements, and fixes included in every HandDraw Studio release.'**
  String get releaseNotesDescription;

  /// No description provided for @releaseNotesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Release notes could not be loaded.'**
  String get releaseNotesLoadFailed;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @currentVersion.
  ///
  /// In en, this message translates to:
  /// **'CURRENT'**
  String get currentVersion;

  /// No description provided for @releaseNew.
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get releaseNew;

  /// No description provided for @releaseImproved.
  ///
  /// In en, this message translates to:
  /// **'IMPROVED'**
  String get releaseImproved;

  /// No description provided for @releaseFixed.
  ///
  /// In en, this message translates to:
  /// **'FIXED'**
  String get releaseFixed;

  /// No description provided for @aboutTheApp.
  ///
  /// In en, this message translates to:
  /// **'About the app'**
  String get aboutTheApp;

  /// No description provided for @aboutDescription.
  ///
  /// In en, this message translates to:
  /// **'HandDraw Studio transforms images, text, and illustrations into precise hand-drawn animations ready for professional editing.'**
  String get aboutDescription;

  /// No description provided for @creator.
  ///
  /// In en, this message translates to:
  /// **'Creator'**
  String get creator;

  /// No description provided for @systemInformation.
  ///
  /// In en, this message translates to:
  /// **'System information'**
  String get systemInformation;

  /// No description provided for @legalAndCredits.
  ///
  /// In en, this message translates to:
  /// **'Legal & credits'**
  String get legalAndCredits;

  /// No description provided for @soundCreditsDescription.
  ///
  /// In en, this message translates to:
  /// **'Bundled writing recordings retain their original source names in the project credits. Package licenses are available below.'**
  String get soundCreditsDescription;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get openSourceLicenses;

  /// No description provided for @copyrightNotice.
  ///
  /// In en, this message translates to:
  /// **'© {year} Mahmoud Basuony. All rights reserved.'**
  String copyrightNotice(int year);

  /// No description provided for @versionBuild.
  ///
  /// In en, this message translates to:
  /// **'Version {version} • Build {build}'**
  String versionBuild(String version, String build);

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @build.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get build;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @exportFormat.
  ///
  /// In en, this message translates to:
  /// **'Export format'**
  String get exportFormat;

  /// No description provided for @defaultCanvas.
  ///
  /// In en, this message translates to:
  /// **'Default canvas'**
  String get defaultCanvas;

  /// No description provided for @copySystemInfo.
  ///
  /// In en, this message translates to:
  /// **'Copy system info'**
  String get copySystemInfo;

  /// No description provided for @systemInfoCopied.
  ///
  /// In en, this message translates to:
  /// **'System information copied.'**
  String get systemInfoCopied;

  /// No description provided for @undoStroke.
  ///
  /// In en, this message translates to:
  /// **'Undo stroke (⌘Z)'**
  String get undoStroke;

  /// No description provided for @redoStroke.
  ///
  /// In en, this message translates to:
  /// **'Redo stroke (⌘⇧Z)'**
  String get redoStroke;

  /// No description provided for @openInspector.
  ///
  /// In en, this message translates to:
  /// **'Open inspector'**
  String get openInspector;

  /// No description provided for @closeInspector.
  ///
  /// In en, this message translates to:
  /// **'Close inspector'**
  String get closeInspector;

  /// No description provided for @importVoice.
  ///
  /// In en, this message translates to:
  /// **'Import Voice'**
  String get importVoice;

  /// No description provided for @voiceGuide.
  ///
  /// In en, this message translates to:
  /// **'Voice Guide'**
  String get voiceGuide;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @stopPreview.
  ///
  /// In en, this message translates to:
  /// **'Stop preview'**
  String get stopPreview;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @exportMov.
  ///
  /// In en, this message translates to:
  /// **'Export MOV'**
  String get exportMov;

  /// No description provided for @drawing.
  ///
  /// In en, this message translates to:
  /// **'Drawing'**
  String get drawing;

  /// No description provided for @sourceFile.
  ///
  /// In en, this message translates to:
  /// **'Source file'**
  String get sourceFile;

  /// No description provided for @hands.
  ///
  /// In en, this message translates to:
  /// **'Hands'**
  String get hands;

  /// No description provided for @hand.
  ///
  /// In en, this message translates to:
  /// **'Hand'**
  String get hand;

  /// No description provided for @penTip.
  ///
  /// In en, this message translates to:
  /// **'Pen Tip'**
  String get penTip;

  /// No description provided for @analyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing…'**
  String get analyzing;

  /// No description provided for @analysisRecognizingText.
  ///
  /// In en, this message translates to:
  /// **'Recognizing text'**
  String get analysisRecognizingText;

  /// No description provided for @analysisReadingPixels.
  ///
  /// In en, this message translates to:
  /// **'Reading image pixels'**
  String get analysisReadingPixels;

  /// No description provided for @analysisPreparingRaster.
  ///
  /// In en, this message translates to:
  /// **'Preparing image detail'**
  String get analysisPreparingRaster;

  /// No description provided for @analysisTracingText.
  ///
  /// In en, this message translates to:
  /// **'Tracing text paths'**
  String get analysisTracingText;

  /// No description provided for @analysisFindingShapes.
  ///
  /// In en, this message translates to:
  /// **'Finding artwork regions'**
  String get analysisFindingShapes;

  /// No description provided for @analysisTracingShapes.
  ///
  /// In en, this message translates to:
  /// **'Tracing artwork paths'**
  String get analysisTracingShapes;

  /// No description provided for @analysisValidatingPaths.
  ///
  /// In en, this message translates to:
  /// **'Checking path coverage'**
  String get analysisValidatingPaths;

  /// No description provided for @analysisFinalizing.
  ///
  /// In en, this message translates to:
  /// **'Finalizing paths'**
  String get analysisFinalizing;

  /// No description provided for @analysisElapsedRemaining.
  ///
  /// In en, this message translates to:
  /// **'{elapsed} elapsed • about {remaining} left'**
  String analysisElapsedRemaining(String elapsed, String remaining);

  /// No description provided for @analysisElapsedEstimating.
  ///
  /// In en, this message translates to:
  /// **'{elapsed} elapsed • estimating time left'**
  String analysisElapsedEstimating(String elapsed);

  /// No description provided for @autoPath.
  ///
  /// In en, this message translates to:
  /// **'Auto Path'**
  String get autoPath;

  /// No description provided for @autoPathUnavailableForBackgroundTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto Path isn’t suitable for this image'**
  String get autoPathUnavailableForBackgroundTitle;

  /// No description provided for @autoPathUnavailableForBackgroundDescription.
  ///
  /// In en, this message translates to:
  /// **'This looks like a colored or full-background image. Auto Path would trace the background and produce a poor result. Use Auto Reveal to uncover the original image naturally without changing transparent images or SVG behavior.'**
  String get autoPathUnavailableForBackgroundDescription;

  /// No description provided for @useAutoReveal.
  ///
  /// In en, this message translates to:
  /// **'Use Auto Reveal'**
  String get useAutoReveal;

  /// No description provided for @autoReveal.
  ///
  /// In en, this message translates to:
  /// **'Auto Reveal'**
  String get autoReveal;

  /// No description provided for @select.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// No description provided for @drawPath.
  ///
  /// In en, this message translates to:
  /// **'Draw Path'**
  String get drawPath;

  /// No description provided for @manualDrawReveal.
  ///
  /// In en, this message translates to:
  /// **'Draw & Reveal'**
  String get manualDrawReveal;

  /// No description provided for @manualDrawRevealDescription.
  ///
  /// In en, this message translates to:
  /// **'Draw the hand path directly. The same ordered stroke reveals the original artwork in Preview and MOV.'**
  String get manualDrawRevealDescription;

  /// No description provided for @manualRevealWidth.
  ///
  /// In en, this message translates to:
  /// **'Reveal brush'**
  String get manualRevealWidth;

  /// No description provided for @revealText.
  ///
  /// In en, this message translates to:
  /// **'Reveal Text'**
  String get revealText;

  /// No description provided for @maskReveal.
  ///
  /// In en, this message translates to:
  /// **'Mask Reveal'**
  String get maskReveal;

  /// No description provided for @maskErase.
  ///
  /// In en, this message translates to:
  /// **'Mask Erase'**
  String get maskErase;

  /// No description provided for @addCameraShot.
  ///
  /// In en, this message translates to:
  /// **'Add Camera'**
  String get addCameraShot;

  /// No description provided for @project.
  ///
  /// In en, this message translates to:
  /// **'PROJECT'**
  String get project;

  /// No description provided for @resetSettings.
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get resetSettings;

  /// No description provided for @notSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get notSelected;

  /// No description provided for @detectingPaths.
  ///
  /// In en, this message translates to:
  /// **'Detecting text, artwork, and center paths…'**
  String get detectingPaths;

  /// No description provided for @timingReveal.
  ///
  /// In en, this message translates to:
  /// **'TIMING & REVEAL'**
  String get timingReveal;

  /// No description provided for @timingUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'Add at least one path to edit timing and reveal settings.'**
  String get timingUnavailableDescription;

  /// No description provided for @baseDuration.
  ///
  /// In en, this message translates to:
  /// **'Base duration'**
  String get baseDuration;

  /// No description provided for @globalDrawingSpeed.
  ///
  /// In en, this message translates to:
  /// **'Overall drawing speed'**
  String get globalDrawingSpeed;

  /// No description provided for @drawingTime.
  ///
  /// In en, this message translates to:
  /// **'Drawing time'**
  String get drawingTime;

  /// No description provided for @penTravelSpeed.
  ///
  /// In en, this message translates to:
  /// **'Pen travel speed'**
  String get penTravelSpeed;

  /// No description provided for @penTravelTime.
  ///
  /// In en, this message translates to:
  /// **'Pen travel time'**
  String get penTravelTime;

  /// No description provided for @fitToDuration.
  ///
  /// In en, this message translates to:
  /// **'Fit to duration'**
  String get fitToDuration;

  /// No description provided for @fitToDurationTitle.
  ///
  /// In en, this message translates to:
  /// **'Fit drawing to duration'**
  String get fitToDurationTitle;

  /// No description provided for @fitToDurationDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the exact final duration. Only drawing speed is adjusted; pen travel, pauses, voice cues, and holds stay unchanged.'**
  String get fitToDurationDescription;

  /// No description provided for @targetDuration.
  ///
  /// In en, this message translates to:
  /// **'Target duration (seconds)'**
  String get targetDuration;

  /// No description provided for @fitDurationRange.
  ///
  /// In en, this message translates to:
  /// **'Available with the current fixed timing: {minimum}s–{maximum}s'**
  String fitDurationRange(String minimum, String maximum);

  /// No description provided for @fitDurationImpossible.
  ///
  /// In en, this message translates to:
  /// **'This duration cannot be reached without changing fixed pauses, pen travel, or holds.'**
  String get fitDurationImpossible;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @autoTiming.
  ///
  /// In en, this message translates to:
  /// **'Auto timing'**
  String get autoTiming;

  /// No description provided for @autoTimingValue.
  ///
  /// In en, this message translates to:
  /// **'{wait}s wait  •  {hold}s hold'**
  String autoTimingValue(String wait, String hold);

  /// No description provided for @sections.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get sections;

  /// No description provided for @sectionsDetected.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No sections detected automatically} =1{1 section detected automatically} other{{count} sections detected automatically}}'**
  String sectionsDetected(int count);

  /// No description provided for @outputDuration.
  ///
  /// In en, this message translates to:
  /// **'Output duration'**
  String get outputDuration;

  /// No description provided for @revealWidth.
  ///
  /// In en, this message translates to:
  /// **'Reveal width'**
  String get revealWidth;

  /// No description provided for @handSection.
  ///
  /// In en, this message translates to:
  /// **'HAND'**
  String get handSection;

  /// No description provided for @handUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose a hand to adjust its size, rotation, and direction.'**
  String get handUnavailableDescription;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get size;

  /// No description provided for @rotationOffset.
  ///
  /// In en, this message translates to:
  /// **'Rotation offset'**
  String get rotationOffset;

  /// No description provided for @writingSound.
  ///
  /// In en, this message translates to:
  /// **'WRITING SOUND'**
  String get writingSound;

  /// No description provided for @writingSoundUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'Add at least one path to use synchronized writing sound.'**
  String get writingSoundUnavailableDescription;

  /// No description provided for @startupSound.
  ///
  /// In en, this message translates to:
  /// **'STARTUP SOUND'**
  String get startupSound;

  /// No description provided for @playStartupSound.
  ///
  /// In en, this message translates to:
  /// **'Play startup sound'**
  String get playStartupSound;

  /// No description provided for @startupSoundDescription.
  ///
  /// In en, this message translates to:
  /// **'A gentle branded cue plays once when the app opens and fades naturally.'**
  String get startupSoundDescription;

  /// No description provided for @includeWritingSound.
  ///
  /// In en, this message translates to:
  /// **'Include writing sound'**
  String get includeWritingSound;

  /// No description provided for @writingSoundOnDescription.
  ///
  /// In en, this message translates to:
  /// **'Synced in Preview and exported MOV'**
  String get writingSoundOnDescription;

  /// No description provided for @writingSoundOffDescription.
  ///
  /// In en, this message translates to:
  /// **'Off — exported MOV stays silent'**
  String get writingSoundOffDescription;

  /// No description provided for @soundType.
  ///
  /// In en, this message translates to:
  /// **'Sound type'**
  String get soundType;

  /// No description provided for @previewSelectedSound.
  ///
  /// In en, this message translates to:
  /// **'Preview selected sound'**
  String get previewSelectedSound;

  /// No description provided for @playingSoundPreview.
  ///
  /// In en, this message translates to:
  /// **'Playing sample…'**
  String get playingSoundPreview;

  /// No description provided for @stopSoundPreview.
  ///
  /// In en, this message translates to:
  /// **'Stop sound preview'**
  String get stopSoundPreview;

  /// No description provided for @soundPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not play this sample'**
  String get soundPreviewFailed;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @noAudioAvailable.
  ///
  /// In en, this message translates to:
  /// **'No audio in this project'**
  String get noAudioAvailable;

  /// No description provided for @videoQuality.
  ///
  /// In en, this message translates to:
  /// **'Video quality'**
  String get videoQuality;

  /// No description provided for @strokes.
  ///
  /// In en, this message translates to:
  /// **'STROKES'**
  String get strokes;

  /// No description provided for @emptyStrokesHelp.
  ///
  /// In en, this message translates to:
  /// **'Choose Draw Path for the hand, or Reveal Text for a smooth reveal without the hand.'**
  String get emptyStrokesHelp;

  /// No description provided for @autoPathSections.
  ///
  /// In en, this message translates to:
  /// **'AUTO PATH SECTIONS'**
  String get autoPathSections;

  /// No description provided for @autoPathApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get autoPathApplied;

  /// No description provided for @autoPathAppliedDescription.
  ///
  /// In en, this message translates to:
  /// **'Auto Path is already applied. The generated result is ready to arrange, preview, and export.'**
  String get autoPathAppliedDescription;

  /// No description provided for @autoPathPaths.
  ///
  /// In en, this message translates to:
  /// **'Paths'**
  String get autoPathPaths;

  /// No description provided for @autoPathHandDraw.
  ///
  /// In en, this message translates to:
  /// **'Hand draw'**
  String get autoPathHandDraw;

  /// No description provided for @autoPathNativeVectors.
  ///
  /// In en, this message translates to:
  /// **'Native vectors'**
  String get autoPathNativeVectors;

  /// No description provided for @autoPathTimelineReady.
  ///
  /// In en, this message translates to:
  /// **'Ready in the Smart Timeline • Preview and MOV use the same paths'**
  String get autoPathTimelineReady;

  /// No description provided for @autoPathResultSemantics.
  ///
  /// In en, this message translates to:
  /// **'Auto Path applied with {sections} sections and {paths} paths'**
  String autoPathResultSemantics(int sections, int paths);

  /// No description provided for @autoPathReview.
  ///
  /// In en, this message translates to:
  /// **'AUTO PATH REVIEW'**
  String get autoPathReview;

  /// No description provided for @experimental.
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get experimental;

  /// No description provided for @suspectedFrameDescription.
  ///
  /// In en, this message translates to:
  /// **'A high-confidence canvas frame was excluded from the preview. Restore it if the border is intentional, then apply the paths.'**
  String get suspectedFrameDescription;

  /// No description provided for @suspectedFrameCount.
  ///
  /// In en, this message translates to:
  /// **'{count} suspected frame candidates are ready for review'**
  String suspectedFrameCount(Object count);

  /// No description provided for @restoreFrame.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restoreFrame;

  /// No description provided for @excludeFrame.
  ///
  /// In en, this message translates to:
  /// **'Exclude'**
  String get excludeFrame;

  /// No description provided for @scenePlanner.
  ///
  /// In en, this message translates to:
  /// **'Smart Timeline'**
  String get scenePlanner;

  /// No description provided for @scenePlannerHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag sections to set the real drawing order. Select related items to group them into a movable scene.'**
  String get scenePlannerHelp;

  /// No description provided for @drawSceneGroup.
  ///
  /// In en, this message translates to:
  /// **'Select on Canvas (optional)'**
  String get drawSceneGroup;

  /// No description provided for @finishSceneGroup.
  ///
  /// In en, this message translates to:
  /// **'Draw an enclosure on the canvas'**
  String get finishSceneGroup;

  /// No description provided for @resetSceneGroups.
  ///
  /// In en, this message translates to:
  /// **'Reset Groups'**
  String get resetSceneGroups;

  /// No description provided for @sceneSectionCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section} other{{count} sections}}'**
  String sceneSectionCount(int count);

  /// No description provided for @autoArrangeTimeline.
  ///
  /// In en, this message translates to:
  /// **'Auto Arrange'**
  String get autoArrangeTimeline;

  /// No description provided for @groupSelectedTimeline.
  ///
  /// In en, this message translates to:
  /// **'Group Selected ({count})'**
  String groupSelectedTimeline(int count);

  /// No description provided for @timelineDragHelp.
  ///
  /// In en, this message translates to:
  /// **'Drag scenes or items. Open a scene to reorder its contents.'**
  String get timelineDragHelp;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @textKind.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textKind;

  /// No description provided for @artworkKind.
  ///
  /// In en, this message translates to:
  /// **'Artwork'**
  String get artworkKind;

  /// No description provided for @ignore.
  ///
  /// In en, this message translates to:
  /// **'Ignore'**
  String get ignore;

  /// No description provided for @reveal.
  ///
  /// In en, this message translates to:
  /// **'Reveal'**
  String get reveal;

  /// No description provided for @advancedTiming.
  ///
  /// In en, this message translates to:
  /// **'Advanced Timing'**
  String get advancedTiming;

  /// No description provided for @advancedTimingDescription.
  ///
  /// In en, this message translates to:
  /// **'Independent drawing, travel, pauses, and per-section speed'**
  String get advancedTimingDescription;

  /// No description provided for @sectionsCustomized.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section customized} other{{count} sections customized}}'**
  String sectionsCustomized(int count);

  /// No description provided for @pauseBefore.
  ///
  /// In en, this message translates to:
  /// **'Pause before'**
  String get pauseBefore;

  /// No description provided for @pauseAfter.
  ///
  /// In en, this message translates to:
  /// **'Pause after'**
  String get pauseAfter;

  /// No description provided for @pauseAtSectionStart.
  ///
  /// In en, this message translates to:
  /// **'Pause at section start'**
  String get pauseAtSectionStart;

  /// No description provided for @pauseAtSectionEnd.
  ///
  /// In en, this message translates to:
  /// **'Pause at section end'**
  String get pauseAtSectionEnd;

  /// No description provided for @handEntranceAnimation.
  ///
  /// In en, this message translates to:
  /// **'Hand entrance animation'**
  String get handEntranceAnimation;

  /// No description provided for @handExitAnimation.
  ///
  /// In en, this message translates to:
  /// **'Hand exit animation'**
  String get handExitAnimation;

  /// No description provided for @noAnimation.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get noAnimation;

  /// No description provided for @fadeIn.
  ///
  /// In en, this message translates to:
  /// **'Fade in'**
  String get fadeIn;

  /// No description provided for @moveIn.
  ///
  /// In en, this message translates to:
  /// **'Move in'**
  String get moveIn;

  /// No description provided for @slingshot.
  ///
  /// In en, this message translates to:
  /// **'Slingshot'**
  String get slingshot;

  /// No description provided for @fadeOut.
  ///
  /// In en, this message translates to:
  /// **'Fade out'**
  String get fadeOut;

  /// No description provided for @moveOut.
  ///
  /// In en, this message translates to:
  /// **'Move out'**
  String get moveOut;

  /// No description provided for @disappear.
  ///
  /// In en, this message translates to:
  /// **'Disappear'**
  String get disappear;

  /// No description provided for @handAnimationDuration.
  ///
  /// In en, this message translates to:
  /// **'Hand animation duration'**
  String get handAnimationDuration;

  /// No description provided for @timingOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get timingOn;

  /// No description provided for @timingOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get timingOff;

  /// No description provided for @drawingSpeed.
  ///
  /// In en, this message translates to:
  /// **'Drawing speed'**
  String get drawingSpeed;

  /// No description provided for @keepHandVisible.
  ///
  /// In en, this message translates to:
  /// **'Keep hand visible while paused'**
  String get keepHandVisible;

  /// No description provided for @keepHandVisibleAfterDrawing.
  ///
  /// In en, this message translates to:
  /// **'Keep hand visible after drawing'**
  String get keepHandVisibleAfterDrawing;

  /// No description provided for @keepHandVisibleAfterDrawingDescription.
  ///
  /// In en, this message translates to:
  /// **'Keep the hand at the final pen position until the section or video ends.'**
  String get keepHandVisibleAfterDrawingDescription;

  /// No description provided for @pauseSoundDescription.
  ///
  /// In en, this message translates to:
  /// **'The writing sound remains silent during every pause.'**
  String get pauseSoundDescription;

  /// No description provided for @resetSection.
  ///
  /// In en, this message translates to:
  /// **'Reset section'**
  String get resetSection;

  /// No description provided for @voiceCue.
  ///
  /// In en, this message translates to:
  /// **'Voice cue'**
  String get voiceCue;

  /// No description provided for @notLinked.
  ///
  /// In en, this message translates to:
  /// **'Not linked'**
  String get notLinked;

  /// No description provided for @startSectionHere.
  ///
  /// In en, this message translates to:
  /// **'Start Section Here  •  {time}'**
  String startSectionHere(String time);

  /// No description provided for @fineTune.
  ///
  /// In en, this message translates to:
  /// **'Fine tune'**
  String get fineTune;

  /// No description provided for @clearVoiceCue.
  ///
  /// In en, this message translates to:
  /// **'Clear Voice Cue'**
  String get clearVoiceCue;

  /// No description provided for @cueConflict.
  ///
  /// In en, this message translates to:
  /// **'The previous section ends {seconds}s after this cue. Move the cue later or shorten earlier timing.'**
  String cueConflict(String seconds);

  /// No description provided for @revealOnly.
  ///
  /// In en, this message translates to:
  /// **'reveal only'**
  String get revealOnly;

  /// No description provided for @reversed.
  ///
  /// In en, this message translates to:
  /// **'reversed'**
  String get reversed;

  /// No description provided for @moveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get moveUp;

  /// No description provided for @moveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get moveDown;

  /// No description provided for @strokeActions.
  ///
  /// In en, this message translates to:
  /// **'Stroke actions'**
  String get strokeActions;

  /// No description provided for @reverseDirection.
  ///
  /// In en, this message translates to:
  /// **'Reverse direction'**
  String get reverseDirection;

  /// No description provided for @showHandOnStroke.
  ///
  /// In en, this message translates to:
  /// **'Show hand on this stroke'**
  String get showHandOnStroke;

  /// No description provided for @revealWithoutHand.
  ///
  /// In en, this message translates to:
  /// **'Reveal without hand'**
  String get revealWithoutHand;

  /// No description provided for @deleteStroke.
  ///
  /// In en, this message translates to:
  /// **'Delete stroke'**
  String get deleteStroke;

  /// No description provided for @dragToReorder.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder paths'**
  String get dragToReorder;

  /// No description provided for @previewThisStroke.
  ///
  /// In en, this message translates to:
  /// **'Preview this path'**
  String get previewThisStroke;

  /// No description provided for @addPausePoint.
  ///
  /// In en, this message translates to:
  /// **'Add pause point'**
  String get addPausePoint;

  /// No description provided for @pausePoints.
  ///
  /// In en, this message translates to:
  /// **'Pause points'**
  String get pausePoints;

  /// No description provided for @pausePoint.
  ///
  /// In en, this message translates to:
  /// **'Pause at {progress}% · {duration}s'**
  String pausePoint(Object duration, Object progress);

  /// No description provided for @pausePosition.
  ///
  /// In en, this message translates to:
  /// **'Position on path'**
  String get pausePosition;

  /// No description provided for @pauseDuration.
  ///
  /// In en, this message translates to:
  /// **'Pause duration'**
  String get pauseDuration;

  /// No description provided for @keepHandAtPause.
  ///
  /// In en, this message translates to:
  /// **'Keep hand visible'**
  String get keepHandAtPause;

  /// No description provided for @editPausePoint.
  ///
  /// In en, this message translates to:
  /// **'Edit pause point'**
  String get editPausePoint;

  /// No description provided for @deletePausePoint.
  ///
  /// In en, this message translates to:
  /// **'Delete pause point'**
  String get deletePausePoint;

  /// No description provided for @appearanceMethod.
  ///
  /// In en, this message translates to:
  /// **'Appearance method'**
  String get appearanceMethod;

  /// No description provided for @withHand.
  ///
  /// In en, this message translates to:
  /// **'Draw with hand'**
  String get withHand;

  /// No description provided for @withoutHand.
  ///
  /// In en, this message translates to:
  /// **'Reveal without hand'**
  String get withoutHand;

  /// No description provided for @moveUpTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move one position earlier'**
  String get moveUpTooltip;

  /// No description provided for @moveDownTooltip.
  ///
  /// In en, this message translates to:
  /// **'Move one position later'**
  String get moveDownTooltip;

  /// No description provided for @clickExactPenTip.
  ///
  /// In en, this message translates to:
  /// **'Click the exact pen tip'**
  String get clickExactPenTip;

  /// No description provided for @useThisPoint.
  ///
  /// In en, this message translates to:
  /// **'Use this point'**
  String get useThisPoint;

  /// No description provided for @handLibrary.
  ///
  /// In en, this message translates to:
  /// **'Hand Library'**
  String get handLibrary;

  /// No description provided for @handLibraryDescription.
  ///
  /// In en, this message translates to:
  /// **'Every hand keeps its own calibrated pen tip.'**
  String get handLibraryDescription;

  /// No description provided for @handVideoSize.
  ///
  /// In en, this message translates to:
  /// **'Hand size in video'**
  String get handVideoSize;

  /// No description provided for @handVideoSizeDescription.
  ///
  /// In en, this message translates to:
  /// **'Same size in Preview and MOV'**
  String get handVideoSizeDescription;

  /// No description provided for @resetHandVideoSize.
  ///
  /// In en, this message translates to:
  /// **'Reset to this hand\'s default size'**
  String get resetHandVideoSize;

  /// No description provided for @handMarkerRight.
  ///
  /// In en, this message translates to:
  /// **'Marker — Right'**
  String get handMarkerRight;

  /// No description provided for @handMarkerLeft.
  ///
  /// In en, this message translates to:
  /// **'Marker — Left'**
  String get handMarkerLeft;

  /// No description provided for @handMarkerCompact.
  ///
  /// In en, this message translates to:
  /// **'Marker — Compact'**
  String get handMarkerCompact;

  /// No description provided for @handDarkMarkerRight.
  ///
  /// In en, this message translates to:
  /// **'Dark Marker — Right'**
  String get handDarkMarkerRight;

  /// No description provided for @handFineLinerRight.
  ///
  /// In en, this message translates to:
  /// **'Fine Liner — Right'**
  String get handFineLinerRight;

  /// No description provided for @handBlueMarkerRight.
  ///
  /// In en, this message translates to:
  /// **'Blue Marker — Right'**
  String get handBlueMarkerRight;

  /// No description provided for @handFrontBlackMarkerRight.
  ///
  /// In en, this message translates to:
  /// **'Front Black Marker — Right'**
  String get handFrontBlackMarkerRight;

  /// No description provided for @handTechnicalPenWheat.
  ///
  /// In en, this message translates to:
  /// **'Technical Pen — Wheat'**
  String get handTechnicalPenWheat;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @defaultBadge.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get defaultBadge;

  /// No description provided for @customBadge.
  ///
  /// In en, this message translates to:
  /// **'CUSTOM'**
  String get customBadge;

  /// No description provided for @importCustomHand.
  ///
  /// In en, this message translates to:
  /// **'Import Custom Hand'**
  String get importCustomHand;

  /// No description provided for @calibratePenTip.
  ///
  /// In en, this message translates to:
  /// **'Calibrate Pen Tip'**
  String get calibratePenTip;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @pauseVoicePreview.
  ///
  /// In en, this message translates to:
  /// **'Pause Voice Guide preview'**
  String get pauseVoicePreview;

  /// No description provided for @playVoiceWithAnimation.
  ///
  /// In en, this message translates to:
  /// **'Play Voice Guide with the animation'**
  String get playVoiceWithAnimation;

  /// No description provided for @voiceGuideTooltip.
  ///
  /// In en, this message translates to:
  /// **'Voice Guide is used for preview and synchronization only. It is never exported.'**
  String get voiceGuideTooltip;

  /// No description provided for @voiceFileMissing.
  ///
  /// In en, this message translates to:
  /// **'File missing — locate to preview'**
  String get voiceFileMissing;

  /// No description provided for @voicePreviewOnly.
  ///
  /// In en, this message translates to:
  /// **'Preview & sync only • not exported'**
  String get voicePreviewOnly;

  /// No description provided for @dragToScrub.
  ///
  /// In en, this message translates to:
  /// **'Drag to scrub • markers are section cues'**
  String get dragToScrub;

  /// No description provided for @voiceGuideActions.
  ///
  /// In en, this message translates to:
  /// **'Voice Guide actions'**
  String get voiceGuideActions;

  /// No description provided for @locateVoiceGuide.
  ///
  /// In en, this message translates to:
  /// **'Locate Voice Guide'**
  String get locateVoiceGuide;

  /// No description provided for @replaceVoiceGuide.
  ///
  /// In en, this message translates to:
  /// **'Replace Voice Guide'**
  String get replaceVoiceGuide;

  /// No description provided for @removeVoiceGuide.
  ///
  /// In en, this message translates to:
  /// **'Remove Voice Guide'**
  String get removeVoiceGuide;

  /// No description provided for @locate.
  ///
  /// In en, this message translates to:
  /// **'Locate'**
  String get locate;

  /// No description provided for @pausedProgress.
  ///
  /// In en, this message translates to:
  /// **'Paused {progress}%'**
  String pausedProgress(int progress);

  /// No description provided for @previewProgress.
  ///
  /// In en, this message translates to:
  /// **'Preview {progress}%'**
  String previewProgress(int progress);

  /// No description provided for @fps.
  ///
  /// In en, this message translates to:
  /// **'fps'**
  String get fps;

  /// No description provided for @canvasAlreadyClear.
  ///
  /// In en, this message translates to:
  /// **'The canvas is already clear.'**
  String get canvasAlreadyClear;

  /// No description provided for @canvasCleared.
  ///
  /// In en, this message translates to:
  /// **'Canvas cleared. Hand and global settings were kept.'**
  String get canvasCleared;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'UNDO'**
  String get undo;

  /// No description provided for @replaceAnimationPaths.
  ///
  /// In en, this message translates to:
  /// **'Replace animation paths?'**
  String get replaceAnimationPaths;

  /// No description provided for @replaceAnimationPathsDescription.
  ///
  /// In en, this message translates to:
  /// **'Auto Reveal creates a clean animation for the whole image. Background images use smart edge detection to reveal the outline first, then the original colors; uncertain results safely fall back to diagonal hand sweeps. It will replace the current stroke list.'**
  String get replaceAnimationPathsDescription;

  /// No description provided for @replaceAndReveal.
  ///
  /// In en, this message translates to:
  /// **'Replace & Reveal'**
  String get replaceAndReveal;

  /// No description provided for @savedTo.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String savedTo(String path);

  /// No description provided for @settingsReset.
  ///
  /// In en, this message translates to:
  /// **'Settings reset to defaults. Canvas content was kept.'**
  String get settingsReset;

  /// No description provided for @importDrawingOrVoice.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing or a Voice Guide first.'**
  String get importDrawingOrVoice;

  /// No description provided for @voiceGuideReady.
  ///
  /// In en, this message translates to:
  /// **'Voice Guide ready. It will not be included in Export MOV.'**
  String get voiceGuideReady;

  /// No description provided for @importDrawingAndStroke.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing and create at least one stroke first.'**
  String get importDrawingAndStroke;

  /// No description provided for @preparingExport.
  ///
  /// In en, this message translates to:
  /// **'Preparing export'**
  String get preparingExport;

  /// No description provided for @renderingFrame.
  ///
  /// In en, this message translates to:
  /// **'Rendering frame {current} of {total}'**
  String renderingFrame(int current, int total);

  /// No description provided for @generatingWritingSound.
  ///
  /// In en, this message translates to:
  /// **'Generating synchronized writing sound'**
  String get generatingWritingSound;

  /// No description provided for @encodingProRes.
  ///
  /// In en, this message translates to:
  /// **'Encoding Apple ProRes 4444'**
  String get encodingProRes;

  /// No description provided for @exportComplete.
  ///
  /// In en, this message translates to:
  /// **'Export complete'**
  String get exportComplete;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'ProRes 4444 exported to {path}'**
  String exportedTo(String path);

  /// No description provided for @exportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @importDrawingToBegin.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing to begin'**
  String get importDrawingToBegin;

  /// No description provided for @importDrawingToStart.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing to start'**
  String get importDrawingToStart;

  /// No description provided for @pencilOnPaper.
  ///
  /// In en, this message translates to:
  /// **'Pencil on Paper'**
  String get pencilOnPaper;

  /// No description provided for @markerOnPaper.
  ///
  /// In en, this message translates to:
  /// **'Marker on Paper'**
  String get markerOnPaper;

  /// No description provided for @technicalPen.
  ///
  /// In en, this message translates to:
  /// **'Technical Pen'**
  String get technicalPen;

  /// No description provided for @realPaperSoft.
  ///
  /// In en, this message translates to:
  /// **'Real Paper — Soft'**
  String get realPaperSoft;

  /// No description provided for @realPaperPencil.
  ///
  /// In en, this message translates to:
  /// **'Real Paper — Pencil'**
  String get realPaperPencil;

  /// No description provided for @realPaperNatural.
  ///
  /// In en, this message translates to:
  /// **'Real Paper — Natural'**
  String get realPaperNatural;

  /// No description provided for @realPaperQuick.
  ///
  /// In en, this message translates to:
  /// **'Real Paper — Quick'**
  String get realPaperQuick;

  /// No description provided for @statusHandLibraryReady.
  ///
  /// In en, this message translates to:
  /// **'Hand library ready'**
  String get statusHandLibraryReady;

  /// No description provided for @statusCouldNotLoadHandLibrary.
  ///
  /// In en, this message translates to:
  /// **'Could not load the hand library: {error}'**
  String statusCouldNotLoadHandLibrary(Object error);

  /// No description provided for @statusDrawingImported.
  ///
  /// In en, this message translates to:
  /// **'Drawing imported. Draw the first stroke.'**
  String get statusDrawingImported;

  /// No description provided for @statusDrawingImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing drawing…'**
  String get statusDrawingImporting;

  /// No description provided for @statusCouldNotImportDrawing.
  ///
  /// In en, this message translates to:
  /// **'Could not import drawing: {error}'**
  String statusCouldNotImportDrawing(String error);

  /// No description provided for @statusCustomHandSaved.
  ///
  /// In en, this message translates to:
  /// **'Custom hand saved. Calibrate the pen tip once.'**
  String get statusCustomHandSaved;

  /// No description provided for @statusCouldNotImportHand.
  ///
  /// In en, this message translates to:
  /// **'Could not import hand: {error}'**
  String statusCouldNotImportHand(Object error);

  /// No description provided for @statusHandSelected.
  ///
  /// In en, this message translates to:
  /// **'{name} selected'**
  String statusHandSelected(Object name);

  /// No description provided for @statusCouldNotSelectHand.
  ///
  /// In en, this message translates to:
  /// **'Could not select hand: {error}'**
  String statusCouldNotSelectHand(Object error);

  /// No description provided for @statusSmoothRevealAdded.
  ///
  /// In en, this message translates to:
  /// **'Smooth text reveal added'**
  String get statusSmoothRevealAdded;

  /// No description provided for @statusStrokesReady.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 stroke ready} other{{count} strokes ready}}'**
  String statusStrokesReady(int count);

  /// No description provided for @statusTimingUndone.
  ///
  /// In en, this message translates to:
  /// **'Timing or Voice Guide change undone'**
  String get statusTimingUndone;

  /// No description provided for @statusLastStrokeRemoved.
  ///
  /// In en, this message translates to:
  /// **'Last stroke removed'**
  String get statusLastStrokeRemoved;

  /// No description provided for @statusAutoBatchRemoved.
  ///
  /// In en, this message translates to:
  /// **'Auto Path batch removed'**
  String get statusAutoBatchRemoved;

  /// No description provided for @statusTimingRestored.
  ///
  /// In en, this message translates to:
  /// **'Timing or Voice Guide change restored'**
  String get statusTimingRestored;

  /// No description provided for @statusStrokeRestored.
  ///
  /// In en, this message translates to:
  /// **'Stroke restored'**
  String get statusStrokeRestored;

  /// No description provided for @statusStrokeDeleted.
  ///
  /// In en, this message translates to:
  /// **'Stroke deleted'**
  String get statusStrokeDeleted;

  /// No description provided for @statusDirectionReversed.
  ///
  /// In en, this message translates to:
  /// **'Stroke direction reversed'**
  String get statusDirectionReversed;

  /// No description provided for @statusChangedToHand.
  ///
  /// In en, this message translates to:
  /// **'Stroke changed to hand drawing'**
  String get statusChangedToHand;

  /// No description provided for @statusChangedToReveal.
  ///
  /// In en, this message translates to:
  /// **'Stroke changed to reveal only'**
  String get statusChangedToReveal;

  /// No description provided for @statusImportBeforeAutoPath.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing before using Auto Path.'**
  String get statusImportBeforeAutoPath;

  /// No description provided for @statusDetectingSmartPaths.
  ///
  /// In en, this message translates to:
  /// **'Detecting text, shapes, and pen paths…'**
  String get statusDetectingSmartPaths;

  /// No description provided for @statusNoClearSection.
  ///
  /// In en, this message translates to:
  /// **'Auto Path did not find a clear section.'**
  String get statusNoClearSection;

  /// No description provided for @statusSectionsReady.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 section detected. Choose Hand or Reveal Text, then Apply.} other{{count} sections detected. Choose Hand or Reveal Text, then Apply.}}'**
  String statusSectionsReady(int count);

  /// No description provided for @statusAutoPathFailed.
  ///
  /// In en, this message translates to:
  /// **'Auto Path failed: {error}'**
  String statusAutoPathFailed(Object error);

  /// No description provided for @statusImportBeforeAutoReveal.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing before using Auto Reveal.'**
  String get statusImportBeforeAutoReveal;

  /// No description provided for @statusBuildingReveal.
  ///
  /// In en, this message translates to:
  /// **'Building a smooth reveal for the entire artwork…'**
  String get statusBuildingReveal;

  /// No description provided for @statusAutoRevealDirectional.
  ///
  /// In en, this message translates to:
  /// **'Auto Reveal ready using a full-artwork directional wipe.'**
  String get statusAutoRevealDirectional;

  /// No description provided for @statusAutoRevealSweep.
  ///
  /// In en, this message translates to:
  /// **'Auto Reveal ready with a continuous side-to-side hand sweep.'**
  String get statusAutoRevealSweep;

  /// No description provided for @statusSmartRegionReveal.
  ///
  /// In en, this message translates to:
  /// **'Smart Region Reveal is ready using {algorithm} detail analysis.'**
  String statusSmartRegionReveal(String algorithm);

  /// No description provided for @statusAutoRevealReady.
  ///
  /// In en, this message translates to:
  /// **'Auto Reveal ready: {count, plural, =1{1 section} other{{count} sections}} in visual order.'**
  String statusAutoRevealReady(int count);

  /// No description provided for @statusAutoRevealFallback.
  ///
  /// In en, this message translates to:
  /// **'Auto Reveal ready with the safe full-artwork fallback.'**
  String get statusAutoRevealFallback;

  /// No description provided for @statusAutomaticPathsAdded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 automatic path added} other{{count} automatic paths added}}. Preview is ready.'**
  String statusAutomaticPathsAdded(int count);

  /// No description provided for @statusOrderedSceneReveals.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 ordered scene reveal is ready} other{{count} ordered scene reveals are ready}}, with one broad hand path each.'**
  String statusOrderedSceneReveals(int count);

  /// No description provided for @statusSuggestionsCleared.
  ///
  /// In en, this message translates to:
  /// **'Auto Path suggestions cleared.'**
  String get statusSuggestionsCleared;

  /// No description provided for @statusPenCalibrated.
  ///
  /// In en, this message translates to:
  /// **'Pen tip calibrated and saved'**
  String get statusPenCalibrated;

  /// No description provided for @statusPenSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Pen tip set, but save failed: {error}'**
  String statusPenSaveFailed(Object error);

  /// No description provided for @statusCanvasRestored.
  ///
  /// In en, this message translates to:
  /// **'Canvas content restored.'**
  String get statusCanvasRestored;

  /// No description provided for @statusVoiceImported.
  ///
  /// In en, this message translates to:
  /// **'{name} imported as a preview-only Voice Guide.'**
  String statusVoiceImported(Object name);

  /// No description provided for @statusVoiceImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not import the Voice Guide: {error}'**
  String statusVoiceImportFailed(Object error);

  /// No description provided for @statusVoiceRemoved.
  ///
  /// In en, this message translates to:
  /// **'Voice Guide and its section cues removed.'**
  String get statusVoiceRemoved;

  /// No description provided for @statusCueImpossible.
  ///
  /// In en, this message translates to:
  /// **'This section cannot start at the selected time because the previous section ends later.'**
  String get statusCueImpossible;

  /// No description provided for @statusCueLinked.
  ///
  /// In en, this message translates to:
  /// **'Voice cue linked at {seconds}s.'**
  String statusCueLinked(Object seconds);

  /// No description provided for @statusCueCleared.
  ///
  /// In en, this message translates to:
  /// **'Voice cue cleared.'**
  String get statusCueCleared;

  /// No description provided for @statusSectionTimingReset.
  ///
  /// In en, this message translates to:
  /// **'Section timing reset'**
  String get statusSectionTimingReset;

  /// No description provided for @statusAdvancedTimingUpdated.
  ///
  /// In en, this message translates to:
  /// **'Advanced timing updated'**
  String get statusAdvancedTimingUpdated;

  /// No description provided for @statusProjectSaved.
  ///
  /// In en, this message translates to:
  /// **'Project saved'**
  String get statusProjectSaved;

  /// No description provided for @statusProjectOpenedMissingDrawing.
  ///
  /// In en, this message translates to:
  /// **'Project opened, but the drawing file is missing'**
  String get statusProjectOpenedMissingDrawing;

  /// No description provided for @statusProjectOpened.
  ///
  /// In en, this message translates to:
  /// **'Project opened'**
  String get statusProjectOpened;

  /// No description provided for @statusVoiceMissing.
  ///
  /// In en, this message translates to:
  /// **'Voice Guide is missing. Locate or remove it to continue syncing.'**
  String get statusVoiceMissing;

  /// No description provided for @statusNewProject.
  ///
  /// In en, this message translates to:
  /// **'New project. Selected hand was kept.'**
  String get statusNewProject;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get resolution;

  /// No description provided for @customWidth.
  ///
  /// In en, this message translates to:
  /// **'Width'**
  String get customWidth;

  /// No description provided for @customHeight.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get customHeight;

  /// No description provided for @pixelsUnit.
  ///
  /// In en, this message translates to:
  /// **'px'**
  String get pixelsUnit;

  /// No description provided for @customResolutionRange.
  ///
  /// In en, this message translates to:
  /// **'Enter a value from {min} to {max} px'**
  String customResolutionRange(int min, int max);

  /// No description provided for @applyResolution.
  ///
  /// In en, this message translates to:
  /// **'Apply size'**
  String get applyResolution;

  /// No description provided for @frameRate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get frameRate;

  /// No description provided for @background.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get background;

  /// No description provided for @canvasBackground.
  ///
  /// In en, this message translates to:
  /// **'Canvas background'**
  String get canvasBackground;

  /// No description provided for @canvasBackgroundDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the surface behind every scene. It is saved with the project and included in Preview and MOV.'**
  String get canvasBackgroundDescription;

  /// No description provided for @backgroundNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get backgroundNone;

  /// No description provided for @backgroundWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get backgroundWhite;

  /// No description provided for @backgroundBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get backgroundBlack;

  /// No description provided for @backgroundCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get backgroundCustom;

  /// No description provided for @backgroundPresets.
  ///
  /// In en, this message translates to:
  /// **'Surfaces'**
  String get backgroundPresets;

  /// No description provided for @backgroundNotebook.
  ///
  /// In en, this message translates to:
  /// **'Notebook'**
  String get backgroundNotebook;

  /// No description provided for @backgroundGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph paper'**
  String get backgroundGraph;

  /// No description provided for @backgroundCream.
  ///
  /// In en, this message translates to:
  /// **'Cream paper'**
  String get backgroundCream;

  /// No description provided for @backgroundChalkboard.
  ///
  /// In en, this message translates to:
  /// **'Chalkboard'**
  String get backgroundChalkboard;

  /// No description provided for @backgroundSoftGradient.
  ///
  /// In en, this message translates to:
  /// **'Soft gradient'**
  String get backgroundSoftGradient;

  /// No description provided for @backgroundWarmWhite.
  ///
  /// In en, this message translates to:
  /// **'Warm white'**
  String get backgroundWarmWhite;

  /// No description provided for @backgroundBlueprint.
  ///
  /// In en, this message translates to:
  /// **'Blueprint'**
  String get backgroundBlueprint;

  /// No description provided for @backgroundKraft.
  ///
  /// In en, this message translates to:
  /// **'Kraft paper'**
  String get backgroundKraft;

  /// No description provided for @backgroundDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get backgroundDark;

  /// No description provided for @backgroundLinen.
  ///
  /// In en, this message translates to:
  /// **'Linen'**
  String get backgroundLinen;

  /// No description provided for @customBackgroundColor.
  ///
  /// In en, this message translates to:
  /// **'Custom background color'**
  String get customBackgroundColor;

  /// No description provided for @hexColor.
  ///
  /// In en, this message translates to:
  /// **'Hex color'**
  String get hexColor;

  /// No description provided for @transparent.
  ///
  /// In en, this message translates to:
  /// **'Transparent'**
  String get transparent;

  /// No description provided for @startDelay.
  ///
  /// In en, this message translates to:
  /// **'Start delay'**
  String get startDelay;

  /// No description provided for @endHold.
  ///
  /// In en, this message translates to:
  /// **'End hold'**
  String get endHold;

  /// No description provided for @animation.
  ///
  /// In en, this message translates to:
  /// **'Animation'**
  String get animation;

  /// No description provided for @audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get audio;

  /// No description provided for @fileMenu.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get fileMenu;

  /// No description provided for @projectMenu.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get projectMenu;

  /// No description provided for @editMenu.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editMenu;

  /// No description provided for @viewMenu.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewMenu;

  /// No description provided for @windowMenu.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get windowMenu;

  /// No description provided for @helpMenu.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get helpMenu;

  /// No description provided for @importMenu.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importMenu;

  /// No description provided for @toolsMenu.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get toolsMenu;

  /// No description provided for @exportingMovie.
  ///
  /// In en, this message translates to:
  /// **'Exporting movie'**
  String get exportingMovie;

  /// No description provided for @exportSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Export completed'**
  String get exportSucceeded;

  /// No description provided for @exportFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Export failed'**
  String get exportFailedTitle;

  /// No description provided for @cancelExport.
  ///
  /// In en, this message translates to:
  /// **'Cancel Export'**
  String get cancelExport;

  /// No description provided for @exportCanceled.
  ///
  /// In en, this message translates to:
  /// **'Export canceled'**
  String get exportCanceled;

  /// No description provided for @finishingExport.
  ///
  /// In en, this message translates to:
  /// **'Finishing export…'**
  String get finishingExport;

  /// No description provided for @revealInFinder.
  ///
  /// In en, this message translates to:
  /// **'Reveal in Finder'**
  String get revealInFinder;

  /// No description provided for @openMovie.
  ///
  /// In en, this message translates to:
  /// **'Open Movie'**
  String get openMovie;

  /// No description provided for @copyPath.
  ///
  /// In en, this message translates to:
  /// **'Copy Path'**
  String get copyPath;

  /// No description provided for @pathCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied'**
  String get pathCopied;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @exportOutputDetails.
  ///
  /// In en, this message translates to:
  /// **'Apple ProRes 4444 • Alpha • {size} • {duration}'**
  String exportOutputDetails(String size, String duration);

  /// No description provided for @exportSafeNotice.
  ///
  /// In en, this message translates to:
  /// **'Your project is saved separately and was not changed.'**
  String get exportSafeNotice;

  /// No description provided for @licenses.
  ///
  /// In en, this message translates to:
  /// **'Licenses'**
  String get licenses;

  /// No description provided for @stop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// No description provided for @selectToolMenu.
  ///
  /// In en, this message translates to:
  /// **'Select Tool'**
  String get selectToolMenu;

  /// No description provided for @drawPathToolMenu.
  ///
  /// In en, this message translates to:
  /// **'Draw Path Tool'**
  String get drawPathToolMenu;

  /// No description provided for @revealTextToolMenu.
  ///
  /// In en, this message translates to:
  /// **'Reveal Text Tool'**
  String get revealTextToolMenu;

  /// No description provided for @addNode.
  ///
  /// In en, this message translates to:
  /// **'Add Node'**
  String get addNode;

  /// No description provided for @deleteNode.
  ///
  /// In en, this message translates to:
  /// **'Delete Node'**
  String get deleteNode;

  /// No description provided for @smoothNode.
  ///
  /// In en, this message translates to:
  /// **'Convert to Smooth'**
  String get smoothNode;

  /// No description provided for @cornerNode.
  ///
  /// In en, this message translates to:
  /// **'Convert to Corner'**
  String get cornerNode;

  /// No description provided for @splitPath.
  ///
  /// In en, this message translates to:
  /// **'Split Path Here'**
  String get splitPath;

  /// No description provided for @joinNextPath.
  ///
  /// In en, this message translates to:
  /// **'Join with Next Path'**
  String get joinNextPath;

  /// No description provided for @setStartNode.
  ///
  /// In en, this message translates to:
  /// **'Set as Start Node'**
  String get setStartNode;

  /// No description provided for @hidePath.
  ///
  /// In en, this message translates to:
  /// **'Hide Animation Path'**
  String get hidePath;

  /// No description provided for @showPath.
  ///
  /// In en, this message translates to:
  /// **'Show Animation Path'**
  String get showPath;

  /// No description provided for @resetMask.
  ///
  /// In en, this message translates to:
  /// **'Reset Reveal Mask'**
  String get resetMask;

  /// No description provided for @maskBrushSize.
  ///
  /// In en, this message translates to:
  /// **'Mask Brush Size'**
  String get maskBrushSize;

  /// No description provided for @maskFeather.
  ///
  /// In en, this message translates to:
  /// **'Mask Feather'**
  String get maskFeather;

  /// No description provided for @showMaskOverlay.
  ///
  /// In en, this message translates to:
  /// **'Show Mask Overlay'**
  String get showMaskOverlay;

  /// No description provided for @compareBeforeMask.
  ///
  /// In en, this message translates to:
  /// **'Preview Before Mask'**
  String get compareBeforeMask;

  /// No description provided for @exportPreset.
  ///
  /// In en, this message translates to:
  /// **'Export Preset'**
  String get exportPreset;

  /// No description provided for @exportUnavailableDescription.
  ///
  /// In en, this message translates to:
  /// **'Import a drawing and add at least one path to configure export.'**
  String get exportUnavailableDescription;

  /// No description provided for @presetYoutube4k.
  ///
  /// In en, this message translates to:
  /// **'YouTube / Course 4K'**
  String get presetYoutube4k;

  /// No description provided for @presetFinalCut4k.
  ///
  /// In en, this message translates to:
  /// **'Final Cut Overlay 4K'**
  String get presetFinalCut4k;

  /// No description provided for @presetVerticalLesson.
  ///
  /// In en, this message translates to:
  /// **'Vertical Lesson'**
  String get presetVerticalLesson;

  /// No description provided for @presetSquareLesson.
  ///
  /// In en, this message translates to:
  /// **'Square Lesson'**
  String get presetSquareLesson;

  /// No description provided for @presetPresentationHd.
  ///
  /// In en, this message translates to:
  /// **'Presentation 1080p'**
  String get presetPresentationHd;

  /// No description provided for @presetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get presetCustom;

  /// No description provided for @exportQuality.
  ///
  /// In en, this message translates to:
  /// **'Export Quality'**
  String get exportQuality;

  /// No description provided for @exportFullQuality.
  ///
  /// In en, this message translates to:
  /// **'Full Resolution'**
  String get exportFullQuality;

  /// No description provided for @exportProxyQuality.
  ///
  /// In en, this message translates to:
  /// **'Half-resolution Proxy'**
  String get exportProxyQuality;

  /// No description provided for @alphaMode.
  ///
  /// In en, this message translates to:
  /// **'Alpha Interpretation'**
  String get alphaMode;

  /// No description provided for @alphaPremultiplied.
  ///
  /// In en, this message translates to:
  /// **'Premultiplied Alpha'**
  String get alphaPremultiplied;

  /// No description provided for @alphaStraight.
  ///
  /// In en, this message translates to:
  /// **'Straight Alpha'**
  String get alphaStraight;

  /// No description provided for @clipMaskToLayer.
  ///
  /// In en, this message translates to:
  /// **'Clip Mask to Layer'**
  String get clipMaskToLayer;

  /// No description provided for @snapNodes.
  ///
  /// In en, this message translates to:
  /// **'Snap Nodes to Precision Grid'**
  String get snapNodes;

  /// No description provided for @timelineSectionProperties.
  ///
  /// In en, this message translates to:
  /// **'Section timing'**
  String get timelineSectionProperties;

  /// No description provided for @timelineSectionTimingDescription.
  ///
  /// In en, this message translates to:
  /// **'These exact durations drive the timeline, Preview, and MOV export.'**
  String get timelineSectionTimingDescription;

  /// No description provided for @sectionDrawingSpeedDescription.
  ///
  /// In en, this message translates to:
  /// **'This section will draw in {duration} s. Speed and duration stay synchronized.'**
  String sectionDrawingSpeedDescription(String duration);

  /// No description provided for @animateDuration.
  ///
  /// In en, this message translates to:
  /// **'Animate'**
  String get animateDuration;

  /// No description provided for @transitionDuration.
  ///
  /// In en, this message translates to:
  /// **'Transition'**
  String get transitionDuration;

  /// No description provided for @totalSectionDuration.
  ///
  /// In en, this message translates to:
  /// **'Total: {duration} s'**
  String totalSectionDuration(String duration);

  /// No description provided for @deleteTimelineSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete timeline section?'**
  String get deleteTimelineSectionTitle;

  /// No description provided for @deleteTimelineSectionDescription.
  ///
  /// In en, this message translates to:
  /// **'Remove “{name}” and its animation from the timeline? This does not delete the imported source file.'**
  String deleteTimelineSectionDescription(String name);

  /// No description provided for @zoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get zoomIn;

  /// No description provided for @zoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get zoomOut;

  /// No description provided for @importBehavior.
  ///
  /// In en, this message translates to:
  /// **'Import behavior'**
  String get importBehavior;

  /// No description provided for @fullScene.
  ///
  /// In en, this message translates to:
  /// **'Full scene'**
  String get fullScene;

  /// No description provided for @fullSceneDescription.
  ///
  /// In en, this message translates to:
  /// **'Preserve the complete image and its placement'**
  String get fullSceneDescription;

  /// No description provided for @singleElement.
  ///
  /// In en, this message translates to:
  /// **'Element'**
  String get singleElement;

  /// No description provided for @singleElementDescription.
  ///
  /// In en, this message translates to:
  /// **'Focus placement on the visible content'**
  String get singleElementDescription;

  /// No description provided for @artworkFit.
  ///
  /// In en, this message translates to:
  /// **'Artwork fit'**
  String get artworkFit;

  /// No description provided for @fitEntireImage.
  ///
  /// In en, this message translates to:
  /// **'Fit entire image'**
  String get fitEntireImage;

  /// No description provided for @fitVisibleContent.
  ///
  /// In en, this message translates to:
  /// **'Fit visible content'**
  String get fitVisibleContent;

  /// No description provided for @originalSize.
  ///
  /// In en, this message translates to:
  /// **'Original size'**
  String get originalSize;

  /// No description provided for @fillCanvas.
  ///
  /// In en, this message translates to:
  /// **'Fill canvas'**
  String get fillCanvas;

  /// No description provided for @fillCanvasWarning.
  ///
  /// In en, this message translates to:
  /// **'This option fills the canvas and may crop part of the artwork.'**
  String get fillCanvasWarning;

  /// No description provided for @positionAndSize.
  ///
  /// In en, this message translates to:
  /// **'Position and size'**
  String get positionAndSize;

  /// No description provided for @positionAndSizeDescription.
  ///
  /// In en, this message translates to:
  /// **'Exact canvas coordinates'**
  String get positionAndSizeDescription;

  /// No description provided for @centerHorizontal.
  ///
  /// In en, this message translates to:
  /// **'Center horizontally'**
  String get centerHorizontal;

  /// No description provided for @centerVertical.
  ///
  /// In en, this message translates to:
  /// **'Center vertically'**
  String get centerVertical;

  /// No description provided for @resetPlacement.
  ///
  /// In en, this message translates to:
  /// **'Reset placement'**
  String get resetPlacement;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
