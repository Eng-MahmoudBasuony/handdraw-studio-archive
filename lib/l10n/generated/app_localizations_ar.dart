// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'HandDraw Studio';

  @override
  String get language => 'اللغة';

  @override
  String get languageSystem => 'لغة النظام';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get newAction => 'جديد';

  @override
  String get openAction => 'فتح';

  @override
  String get saveAction => 'حفظ';

  @override
  String get clearCanvas => 'مسح اللوحة';

  @override
  String get newProject => 'مشروع جديد';

  @override
  String get openProject => 'فتح مشروع';

  @override
  String get saveProject => 'حفظ المشروع';

  @override
  String get unsavedChanges => 'تغييرات غير محفوظة';

  @override
  String get chooseDrawing => 'اختيار الرسم';

  @override
  String get chooseHand => 'اختيار اليد';

  @override
  String get images => 'الصور';

  @override
  String get handDrawProject => 'مشروع HandDraw';

  @override
  String get voiceRecordings => 'التسجيلات الصوتية';

  @override
  String get quickTimeMovie => 'فيلم QuickTime';

  @override
  String get exportMovie => 'تصدير الفيلم';

  @override
  String get projectActions => 'إجراءات المشروع';

  @override
  String get appInformation => 'معلومات التطبيق';

  @override
  String get aboutApp => 'حول HandDraw Studio';

  @override
  String get whatsNew => 'ما الجديد';

  @override
  String get releaseNotesDescription =>
      'تعرّف على الميزات والتحسينات والإصلاحات الموجودة في كل إصدار من HandDraw Studio.';

  @override
  String get releaseNotesLoadFailed => 'تعذر تحميل سجل الإصدارات.';

  @override
  String versionLabel(String version) {
    return 'الإصدار $version';
  }

  @override
  String get currentVersion => 'الحالي';

  @override
  String get releaseNew => 'جديد';

  @override
  String get releaseImproved => 'محسّن';

  @override
  String get releaseFixed => 'إصلاح';

  @override
  String get aboutTheApp => 'عن التطبيق';

  @override
  String get aboutDescription =>
      'يحوّل HandDraw Studio الصور والنصوص والرسومات إلى حركات رسم يدوي دقيقة وجاهزة للمونتاج الاحترافي.';

  @override
  String get creator => 'المطوّر';

  @override
  String get systemInformation => 'معلومات النظام';

  @override
  String get legalAndCredits => 'التراخيص والاعتمادات';

  @override
  String get soundCreditsDescription =>
      'تحتفظ تسجيلات الكتابة المدمجة بأسماء مصادرها الأصلية داخل اعتمادات المشروع، وتتوفر تراخيص الحزم أدناه.';

  @override
  String get openSourceLicenses => 'تراخيص المصادر المفتوحة';

  @override
  String copyrightNotice(int year) {
    return '© $year Mahmoud Basuony. جميع الحقوق محفوظة.';
  }

  @override
  String versionBuild(String version, String build) {
    return 'الإصدار $version • البناء $build';
  }

  @override
  String get version => 'الإصدار';

  @override
  String get build => 'رقم البناء';

  @override
  String get platform => 'المنصة';

  @override
  String get exportFormat => 'صيغة التصدير';

  @override
  String get defaultCanvas => 'اللوحة الافتراضية';

  @override
  String get copySystemInfo => 'نسخ معلومات النظام';

  @override
  String get systemInfoCopied => 'تم نسخ معلومات النظام.';

  @override
  String get undoStroke => 'تراجع عن المسار (⌘Z)';

  @override
  String get redoStroke => 'إعادة المسار (⌘⇧Z)';

  @override
  String get openInspector => 'فتح لوحة الخصائص';

  @override
  String get closeInspector => 'إغلاق لوحة الخصائص';

  @override
  String get importVoice => 'استيراد تعليق صوتي';

  @override
  String get voiceGuide => 'دليل الصوت';

  @override
  String get resume => 'استكمال';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get stopPreview => 'إيقاف المعاينة';

  @override
  String get preview => 'معاينة';

  @override
  String get exportMov => 'تصدير MOV';

  @override
  String get drawing => 'الرسم';

  @override
  String get sourceFile => 'ملف المصدر';

  @override
  String get hands => 'الأيدي';

  @override
  String get hand => 'يد';

  @override
  String get penTip => 'سن القلم';

  @override
  String get analyzing => 'جارٍ التحليل…';

  @override
  String get analysisRecognizingText => 'التعرّف على النصوص';

  @override
  String get analysisReadingPixels => 'قراءة بكسلات الصورة';

  @override
  String get analysisPreparingRaster => 'تجهيز تفاصيل الصورة';

  @override
  String get analysisTracingText => 'تتبّع مسارات النصوص';

  @override
  String get analysisFindingShapes => 'اكتشاف مناطق الرسم';

  @override
  String get analysisTracingShapes => 'تتبّع مسارات الرسم';

  @override
  String get analysisValidatingPaths => 'فحص تغطية المسارات';

  @override
  String get analysisFinalizing => 'إنهاء تجهيز المسارات';

  @override
  String analysisElapsedRemaining(String elapsed, String remaining) {
    return 'مرّ $elapsed • متبقٍ نحو $remaining';
  }

  @override
  String analysisElapsedEstimating(String elapsed) {
    return 'مرّ $elapsed • جارٍ تقدير الوقت المتبقي';
  }

  @override
  String get autoPath => 'مسارات تلقائية';

  @override
  String get autoPathUnavailableForBackgroundTitle =>
      'المسارات التلقائية غير مناسبة لهذه الصورة';

  @override
  String get autoPathUnavailableForBackgroundDescription =>
      'يبدو أن هذه صورة ملونة أو لها خلفية كاملة. المسارات التلقائية سترسم الخلفية وقد تعطي نتيجة سيئة. استخدم الإظهار التلقائي ليكشف الصورة الأصلية بشكل طبيعي من غير التأثير على الصور الشفافة أو SVG.';

  @override
  String get useAutoReveal => 'استخدام الإظهار التلقائي';

  @override
  String get autoReveal => 'إظهار تلقائي';

  @override
  String get select => 'تحديد';

  @override
  String get drawPath => 'رسم مسار';

  @override
  String get manualDrawReveal => 'رسم وكشف يدوي';

  @override
  String get manualDrawRevealDescription =>
      'ارسم مسار اليد مباشرة؛ يكشف المسار المرتب نفسه الصورة الأصلية في المعاينة وMOV.';

  @override
  String get manualRevealWidth => 'فرشاة الكشف';

  @override
  String get revealText => 'إظهار النص';

  @override
  String get maskReveal => 'إضافة للقناع';

  @override
  String get maskErase => 'مسح من القناع';

  @override
  String get addCameraShot => 'إضافة كاميرا';

  @override
  String get project => 'المشروع';

  @override
  String get resetSettings => 'إعادة الإعدادات';

  @override
  String get notSelected => 'غير محدد';

  @override
  String get detectingPaths =>
      'جارٍ اكتشاف النصوص والرسومات والمسارات المركزية…';

  @override
  String get timingReveal => 'التوقيت والإظهار';

  @override
  String get timingUnavailableDescription =>
      'أضف مسارًا واحدًا على الأقل لتعديل التوقيت والإظهار.';

  @override
  String get baseDuration => 'المدة الأساسية';

  @override
  String get globalDrawingSpeed => 'سرعة الرسم العامة';

  @override
  String get drawingTime => 'مدة الرسم';

  @override
  String get penTravelSpeed => 'سرعة انتقال القلم';

  @override
  String get penTravelTime => 'مدة انتقال القلم';

  @override
  String get fitToDuration => 'ملاءمة مع مدة';

  @override
  String get fitToDurationTitle => 'ملاءمة الرسم مع مدة محددة';

  @override
  String get fitToDurationDescription =>
      'حدد مدة الناتج النهائية بدقة. سيُضبط معدل الرسم فقط، بينما تظل انتقالات القلم والوقفات والعلامات الصوتية والتثبيت كما هي.';

  @override
  String get targetDuration => 'المدة المطلوبة (بالثواني)';

  @override
  String fitDurationRange(String minimum, String maximum) {
    return 'النطاق المتاح مع التوقيت الثابت الحالي: $minimum–$maximum ث';
  }

  @override
  String get fitDurationImpossible =>
      'لا يمكن الوصول إلى هذه المدة دون تغيير الوقفات الثابتة أو انتقال القلم أو التثبيت.';

  @override
  String get apply => 'تطبيق';

  @override
  String get autoTiming => 'التوقيت التلقائي';

  @override
  String autoTimingValue(String wait, String hold) {
    return 'انتظار $wait ث  •  تثبيت $hold ث';
  }

  @override
  String get sections => 'الأقسام';

  @override
  String sectionsDetected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم اكتشاف $count قسم تلقائيًا',
      many: 'تم اكتشاف $count قسمًا تلقائيًا',
      few: 'تم اكتشاف $count أقسام تلقائيًا',
      two: 'تم اكتشاف قسمين تلقائيًا',
      one: 'تم اكتشاف قسم واحد تلقائيًا',
      zero: 'لم يتم اكتشاف أقسام تلقائيًا',
    );
    return '$_temp0';
  }

  @override
  String get outputDuration => 'مدة الناتج';

  @override
  String get revealWidth => 'عرض الإظهار';

  @override
  String get handSection => 'اليد';

  @override
  String get handUnavailableDescription =>
      'اختر يدًا لتعديل الحجم والدوران والاتجاه.';

  @override
  String get size => 'الحجم';

  @override
  String get rotationOffset => 'إزاحة الدوران';

  @override
  String get writingSound => 'صوت الكتابة';

  @override
  String get writingSoundUnavailableDescription =>
      'أضف مسارًا واحدًا على الأقل لاستخدام صوت الكتابة المتزامن.';

  @override
  String get startupSound => 'صوت الافتتاحية';

  @override
  String get playStartupSound => 'تشغيل صوت الافتتاحية';

  @override
  String get startupSoundDescription =>
      'يعمل صوت افتتاحي هادئ مرة واحدة عند فتح التطبيق ويتلاشى بسلاسة.';

  @override
  String get includeWritingSound => 'تضمين صوت الكتابة';

  @override
  String get writingSoundOnDescription =>
      'متزامن في المعاينة وملف MOV المُصدّر';

  @override
  String get writingSoundOffDescription => 'متوقف — ملف MOV المُصدّر بلا صوت';

  @override
  String get soundType => 'نوع الصوت';

  @override
  String get previewSelectedSound => 'معاينة الصوت المختار';

  @override
  String get playingSoundPreview => 'جارٍ تشغيل العينة…';

  @override
  String get stopSoundPreview => 'إيقاف معاينة الصوت';

  @override
  String get soundPreviewFailed => 'تعذر تشغيل هذه العينة';

  @override
  String get volume => 'مستوى الصوت';

  @override
  String get mute => 'كتم الصوت';

  @override
  String get unmute => 'تشغيل الصوت';

  @override
  String get noAudioAvailable => 'لا يوجد صوت في هذا المشروع';

  @override
  String get videoQuality => 'جودة الفيديو';

  @override
  String get strokes => 'المسارات';

  @override
  String get emptyStrokesHelp =>
      'اختر رسم مسار لتحريك اليد، أو إظهار النص لظهور سلس بدون اليد.';

  @override
  String get autoPathSections => 'أقسام المسارات التلقائية';

  @override
  String get autoPathApplied => 'تم التطبيق';

  @override
  String get autoPathAppliedDescription =>
      'تم تطبيق المسارات التلقائية بالفعل، والنتيجة جاهزة للترتيب والمعاينة والتصدير.';

  @override
  String get autoPathPaths => 'المسارات';

  @override
  String get autoPathHandDraw => 'رسم باليد';

  @override
  String get autoPathNativeVectors => 'متجهات أصلية';

  @override
  String get autoPathTimelineReady =>
      'جاهز في الخط الزمني الذكي • تستخدم المعاينة وMOV المسارات نفسها';

  @override
  String autoPathResultSemantics(int sections, int paths) {
    return 'تم تطبيق المسارات التلقائية بعدد $sections قسم و$paths مسار';
  }

  @override
  String get autoPathReview => 'مراجعة المسارات التلقائية';

  @override
  String get experimental => 'تجريبي';

  @override
  String get suspectedFrameDescription =>
      'تم استبعاد إطار اللوحة من المعاينة بثقة عالية. أعده إذا كان الحد مقصودًا، ثم طبّق المسارات.';

  @override
  String suspectedFrameCount(Object count) {
    return 'يوجد $count إطار مشتبه به جاهز للمراجعة';
  }

  @override
  String get restoreFrame => 'إعادة الإطار';

  @override
  String get excludeFrame => 'استبعاد الإطار';

  @override
  String get scenePlanner => 'الخط الزمني الذكي';

  @override
  String get scenePlannerHelp =>
      'اسحب العناصر لتحديد ترتيب الرسم الحقيقي، وحدد العناصر المرتبطة لتجميعها في مشهد يتحرك كوحدة واحدة.';

  @override
  String get drawSceneGroup => 'تحديد من الكانفاس (اختياري)';

  @override
  String get finishSceneGroup => 'ارسم تحديدًا مغلقًا على الكانفاس';

  @override
  String get resetSceneGroups => 'إعادة المجموعات';

  @override
  String sceneSectionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قسم',
      many: '$count قسمًا',
      few: '$count أقسام',
      two: 'قسمان',
      one: 'قسم واحد',
    );
    return '$_temp0';
  }

  @override
  String get autoArrangeTimeline => 'ترتيب ذكي';

  @override
  String groupSelectedTimeline(int count) {
    return 'تجميع المحدد ($count)';
  }

  @override
  String get timelineDragHelp =>
      'اسحب المشاهد أو العناصر، وافتح المشهد لترتيب محتوياته.';

  @override
  String get cancel => 'إلغاء';

  @override
  String get textKind => 'نص';

  @override
  String get artworkKind => 'رسم';

  @override
  String get ignore => 'تجاهل';

  @override
  String get reveal => 'إظهار';

  @override
  String get advancedTiming => 'التوقيت المتقدم';

  @override
  String get advancedTimingDescription =>
      'سرعة مستقلة للرسم والانتقال والوقفات ولكل قسم';

  @override
  String sectionsCustomized(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تخصيص $count قسم',
      many: 'تم تخصيص $count قسمًا',
      few: 'تم تخصيص $count أقسام',
      two: 'تم تخصيص قسمين',
      one: 'تم تخصيص قسم واحد',
    );
    return '$_temp0';
  }

  @override
  String get pauseBefore => 'وقفة قبل';

  @override
  String get pauseAfter => 'وقفة بعد';

  @override
  String get pauseAtSectionStart => 'إيقاف عند بداية المقطع';

  @override
  String get pauseAtSectionEnd => 'إيقاف عند نهاية المقطع';

  @override
  String get handEntranceAnimation => 'حركة دخول اليد';

  @override
  String get handExitAnimation => 'حركة خروج اليد';

  @override
  String get noAnimation => 'بدون حركة';

  @override
  String get fadeIn => 'ظهور تدريجي';

  @override
  String get moveIn => 'دخول متحرك';

  @override
  String get slingshot => 'انطلاق مرن';

  @override
  String get fadeOut => 'اختفاء تدريجي';

  @override
  String get moveOut => 'خروج متحرك';

  @override
  String get disappear => 'اختفاء فوري';

  @override
  String get handAnimationDuration => 'مدة حركة اليد';

  @override
  String get timingOn => 'تشغيل';

  @override
  String get timingOff => 'إيقاف';

  @override
  String get drawingSpeed => 'سرعة الرسم';

  @override
  String get keepHandVisible => 'إبقاء اليد ظاهرة أثناء الوقفة';

  @override
  String get keepHandVisibleAfterDrawing => 'إبقاء اليد ظاهرة بعد انتهاء الرسم';

  @override
  String get keepHandVisibleAfterDrawingDescription =>
      'تظل اليد عند موضع سن القلم الأخير حتى نهاية المقطع أو الفيديو.';

  @override
  String get pauseSoundDescription => 'يظل صوت الكتابة صامتًا أثناء كل وقفة.';

  @override
  String get resetSection => 'إعادة ضبط القسم';

  @override
  String get voiceCue => 'علامة صوتية';

  @override
  String get notLinked => 'غير مرتبط';

  @override
  String startSectionHere(String time) {
    return 'ابدأ القسم هنا  •  $time';
  }

  @override
  String get fineTune => 'ضبط دقيق';

  @override
  String get clearVoiceCue => 'حذف العلامة الصوتية';

  @override
  String cueConflict(String seconds) {
    return 'ينتهي القسم السابق بعد هذه العلامة بـ $seconds ث. انقل العلامة لاحقًا أو قصّر التوقيت السابق.';
  }

  @override
  String get revealOnly => 'إظهار فقط';

  @override
  String get reversed => 'معكوس';

  @override
  String get moveUp => 'تحريك لأعلى';

  @override
  String get moveDown => 'تحريك لأسفل';

  @override
  String get strokeActions => 'إجراءات المسار';

  @override
  String get reverseDirection => 'عكس الاتجاه';

  @override
  String get showHandOnStroke => 'إظهار اليد على هذا المسار';

  @override
  String get revealWithoutHand => 'إظهار بدون يد';

  @override
  String get deleteStroke => 'حذف المسار';

  @override
  String get dragToReorder => 'اسحب لإعادة ترتيب المسارات';

  @override
  String get previewThisStroke => 'معاينة هذا المسار';

  @override
  String get addPausePoint => 'إضافة وقفة داخل المسار';

  @override
  String get pausePoints => 'وقفات المسار';

  @override
  String pausePoint(Object duration, Object progress) {
    return 'وقفة عند $progress% · $duration ث';
  }

  @override
  String get pausePosition => 'الموضع على المسار';

  @override
  String get pauseDuration => 'مدة الوقفة';

  @override
  String get keepHandAtPause => 'إبقاء اليد ظاهرة';

  @override
  String get editPausePoint => 'تعديل وقفة المسار';

  @override
  String get deletePausePoint => 'حذف وقفة المسار';

  @override
  String get appearanceMethod => 'طريقة الظهور';

  @override
  String get withHand => 'رسم باليد';

  @override
  String get withoutHand => 'إظهار بدون يد';

  @override
  String get moveUpTooltip => 'نقل خطوة إلى ترتيب أسبق';

  @override
  String get moveDownTooltip => 'نقل خطوة إلى ترتيب لاحق';

  @override
  String get clickExactPenTip => 'اضغط على موضع سن القلم بدقة';

  @override
  String get useThisPoint => 'استخدام هذه النقطة';

  @override
  String get handLibrary => 'مكتبة الأيدي';

  @override
  String get handLibraryDescription => 'كل يد تحتفظ بموضع سن القلم الخاص بها.';

  @override
  String get handVideoSize => 'حجم اليد في الفيديو';

  @override
  String get handVideoSizeDescription => 'نفس الحجم في المعاينة وMOV';

  @override
  String get resetHandVideoSize => 'إعادة الحجم الافتراضي لهذه اليد';

  @override
  String get handMarkerRight => 'ماركر — يد يمنى';

  @override
  String get handMarkerLeft => 'ماركر — يد يسرى';

  @override
  String get handMarkerCompact => 'ماركر — مدمجة';

  @override
  String get handDarkMarkerRight => 'ماركر داكن — يد يمنى';

  @override
  String get handFineLinerRight => 'قلم رفيع — يد يمنى';

  @override
  String get handBlueMarkerRight => 'ماركر أزرق — يد يمنى';

  @override
  String get handFrontBlackMarkerRight => 'ماركر أسود أمامي — يد يمنى';

  @override
  String get handTechnicalPenWheat => 'قلم تقني — بشرة قمحية';

  @override
  String get close => 'إغلاق';

  @override
  String get defaultBadge => 'افتراضية';

  @override
  String get customBadge => 'مخصصة';

  @override
  String get importCustomHand => 'استيراد يد مخصصة';

  @override
  String get calibratePenTip => 'معايرة سن القلم';

  @override
  String get done => 'تم';

  @override
  String get pauseVoicePreview => 'إيقاف معاينة دليل الصوت مؤقتًا';

  @override
  String get playVoiceWithAnimation => 'تشغيل دليل الصوت مع الحركة';

  @override
  String get voiceGuideTooltip =>
      'يُستخدم دليل الصوت للمعاينة والمزامنة فقط، ولا يتم تصديره.';

  @override
  String get voiceFileMissing => 'الملف مفقود — حدده للمعاينة';

  @override
  String get voicePreviewOnly => 'للمعاينة والمزامنة فقط • لا يتم تصديره';

  @override
  String get dragToScrub => 'اسحب للتنقل • العلامات تشير إلى الأقسام';

  @override
  String get voiceGuideActions => 'إجراءات دليل الصوت';

  @override
  String get locateVoiceGuide => 'تحديد ملف دليل الصوت';

  @override
  String get replaceVoiceGuide => 'استبدال دليل الصوت';

  @override
  String get removeVoiceGuide => 'إزالة دليل الصوت';

  @override
  String get locate => 'تحديد الملف';

  @override
  String pausedProgress(int progress) {
    return 'متوقف مؤقتًا $progress%';
  }

  @override
  String previewProgress(int progress) {
    return 'معاينة $progress%';
  }

  @override
  String get fps => 'إطار/ث';

  @override
  String get canvasAlreadyClear => 'اللوحة فارغة بالفعل.';

  @override
  String get canvasCleared =>
      'تم مسح اللوحة مع الاحتفاظ باليد والإعدادات العامة.';

  @override
  String get undo => 'تراجع';

  @override
  String get replaceAnimationPaths => 'استبدال مسارات الحركة؟';

  @override
  String get replaceAnimationPathsDescription =>
      'سينشئ الإظهار التلقائي حركة نظيفة للصورة كاملة. تستخدم الصور ذات الخلفية اكتشافًا ذكيًا للحواف لإظهار الحدود أولًا ثم الألوان الأصلية، ومع النتائج غير المؤكدة يعود تلقائيًا إلى تمريرات اليد القطرية الآمنة. سيستبدل قائمة المسارات الحالية.';

  @override
  String get replaceAndReveal => 'استبدال وإظهار';

  @override
  String savedTo(String path) {
    return 'تم الحفظ في $path';
  }

  @override
  String get settingsReset =>
      'عادت الإعدادات للقيم الافتراضية مع الاحتفاظ بمحتوى اللوحة.';

  @override
  String get importDrawingOrVoice => 'استورد رسمًا أو دليلًا صوتيًا أولًا.';

  @override
  String get voiceGuideReady =>
      'دليل الصوت جاهز ولن يتم تضمينه في ملف MOV المُصدّر.';

  @override
  String get importDrawingAndStroke =>
      'استورد رسمًا وأنشئ مسارًا واحدًا على الأقل أولًا.';

  @override
  String get preparingExport => 'جارٍ تجهيز التصدير';

  @override
  String renderingFrame(int current, int total) {
    return 'جارٍ تجهيز الإطار $current من $total';
  }

  @override
  String get generatingWritingSound => 'جارٍ إنشاء صوت الكتابة المتزامن';

  @override
  String get encodingProRes => 'جارٍ ترميز Apple ProRes 4444';

  @override
  String get exportComplete => 'اكتمل التصدير';

  @override
  String exportedTo(String path) {
    return 'تم تصدير ProRes 4444 إلى $path';
  }

  @override
  String exportFailed(String error) {
    return 'فشل التصدير: $error';
  }

  @override
  String get importDrawingToBegin => 'استورد رسمًا للبدء';

  @override
  String get importDrawingToStart => 'استورد رسمًا للبدء';

  @override
  String get pencilOnPaper => 'قلم رصاص على ورق';

  @override
  String get markerOnPaper => 'قلم ماركر على ورق';

  @override
  String get technicalPen => 'قلم تقني';

  @override
  String get realPaperSoft => 'ورق حقيقي — هادئ';

  @override
  String get realPaperPencil => 'ورق حقيقي — قلم رصاص';

  @override
  String get realPaperNatural => 'ورق حقيقي — طبيعي';

  @override
  String get realPaperQuick => 'ورق حقيقي — سريع';

  @override
  String get statusHandLibraryReady => 'مكتبة الأيدي جاهزة';

  @override
  String statusCouldNotLoadHandLibrary(Object error) {
    return 'تعذر تحميل مكتبة الأيدي: $error';
  }

  @override
  String get statusDrawingImported => 'تم استيراد الرسم. ارسم المسار الأول.';

  @override
  String get statusDrawingImporting => 'جارٍ استيراد الرسم…';

  @override
  String statusCouldNotImportDrawing(String error) {
    return 'تعذر استيراد الرسم: $error';
  }

  @override
  String get statusCustomHandSaved =>
      'تم حفظ اليد المخصصة. عاير سن القلم مرة واحدة.';

  @override
  String statusCouldNotImportHand(Object error) {
    return 'تعذر استيراد اليد: $error';
  }

  @override
  String statusHandSelected(Object name) {
    return 'تم تحديد $name';
  }

  @override
  String statusCouldNotSelectHand(Object error) {
    return 'تعذر تحديد اليد: $error';
  }

  @override
  String get statusSmoothRevealAdded => 'تمت إضافة إظهار سلس للنص';

  @override
  String statusStrokesReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مسار جاهز',
      many: '$count مسارًا جاهزًا',
      few: '$count مسارات جاهزة',
      two: 'مساران جاهزان',
      one: 'مسار واحد جاهز',
    );
    return '$_temp0';
  }

  @override
  String get statusTimingUndone => 'تم التراجع عن تغيير التوقيت أو دليل الصوت';

  @override
  String get statusLastStrokeRemoved => 'تم حذف آخر مسار';

  @override
  String get statusAutoBatchRemoved => 'تم حذف مجموعة المسارات التلقائية';

  @override
  String get statusTimingRestored => 'تمت استعادة تغيير التوقيت أو دليل الصوت';

  @override
  String get statusStrokeRestored => 'تمت استعادة المسار';

  @override
  String get statusStrokeDeleted => 'تم حذف المسار';

  @override
  String get statusDirectionReversed => 'تم عكس اتجاه المسار';

  @override
  String get statusChangedToHand => 'تم تحويل المسار إلى رسم باليد';

  @override
  String get statusChangedToReveal => 'تم تحويل المسار إلى إظهار فقط';

  @override
  String get statusImportBeforeAutoPath =>
      'استورد رسمًا قبل استخدام المسارات التلقائية.';

  @override
  String get statusDetectingSmartPaths =>
      'جارٍ اكتشاف النصوص والأشكال ومسارات القلم…';

  @override
  String get statusNoClearSection => 'لم تعثر المسارات التلقائية على قسم واضح.';

  @override
  String statusSectionsReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم اكتشاف $count قسم. اختر يد أو إظهار النص ثم طبّق.',
      many: 'تم اكتشاف $count قسمًا. اختر يد أو إظهار النص ثم طبّق.',
      few: 'تم اكتشاف $count أقسام. اختر يد أو إظهار النص ثم طبّق.',
      two: 'تم اكتشاف قسمين. اختر يد أو إظهار النص ثم طبّق.',
      one: 'تم اكتشاف قسم واحد. اختر يد أو إظهار النص ثم طبّق.',
    );
    return '$_temp0';
  }

  @override
  String statusAutoPathFailed(Object error) {
    return 'فشلت المسارات التلقائية: $error';
  }

  @override
  String get statusImportBeforeAutoReveal =>
      'استورد رسمًا قبل استخدام الإظهار التلقائي.';

  @override
  String get statusBuildingReveal => 'جارٍ إنشاء إظهار سلس للرسم بالكامل…';

  @override
  String get statusAutoRevealDirectional =>
      'الإظهار التلقائي جاهز باستخدام مسح اتجاهي للرسم بالكامل.';

  @override
  String get statusAutoRevealSweep =>
      'الإظهار التلقائي جاهز بحركة يد متصلة من جانب إلى آخر.';

  @override
  String statusSmartRegionReveal(String algorithm) {
    return 'الإظهار الذكي بالمناطق جاهز باستخدام تحليل التفاصيل $algorithm.';
  }

  @override
  String statusAutoRevealReady(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count قسم',
      many: '$count قسمًا',
      few: '$count أقسام',
      two: 'قسمان',
      one: 'قسم واحد',
    );
    return 'الإظهار التلقائي جاهز: $_temp0 بالترتيب البصري.';
  }

  @override
  String get statusAutoRevealFallback =>
      'الإظهار التلقائي جاهز باستخدام البديل الآمن للرسم بالكامل.';

  @override
  String statusAutomaticPathsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count مسار تلقائي',
      many: '$count مسارًا تلقائيًا',
      few: '$count مسارات تلقائية',
      two: 'مسارين تلقائيين',
      one: 'مسار تلقائي واحد',
    );
    return 'تمت إضافة $_temp0. المعاينة جاهزة.';
  }

  @override
  String statusOrderedSceneReveals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'أصبح كشف $count مشهد مرتبًا وجاهزًا',
      many: 'أصبح كشف $count مشهدًا مرتبًا وجاهزًا',
      few: 'أصبحت كشوف $count مشاهد مرتبة وجاهزة',
      two: 'أصبح كشف مشهدين مرتبًا وجاهزًا',
      one: 'أصبح كشف مشهد واحد مرتبًا وجاهزًا',
    );
    return '$_temp0، بمسار يد عريض واحد لكل مشهد.';
  }

  @override
  String get statusSuggestionsCleared => 'تم مسح اقتراحات المسارات التلقائية.';

  @override
  String get statusPenCalibrated => 'تمت معايرة سن القلم وحفظه';

  @override
  String statusPenSaveFailed(Object error) {
    return 'تم ضبط سن القلم لكن فشل الحفظ: $error';
  }

  @override
  String get statusCanvasRestored => 'تمت استعادة محتوى اللوحة.';

  @override
  String statusVoiceImported(Object name) {
    return 'تم استيراد $name كدليل صوت للمعاينة فقط.';
  }

  @override
  String statusVoiceImportFailed(Object error) {
    return 'تعذر استيراد دليل الصوت: $error';
  }

  @override
  String get statusVoiceRemoved =>
      'تمت إزالة دليل الصوت وعلامات الأقسام المرتبطة به.';

  @override
  String get statusCueImpossible =>
      'لا يمكن بدء هذا القسم عند الوقت المحدد لأن القسم السابق ينتهي بعده.';

  @override
  String statusCueLinked(Object seconds) {
    return 'تم ربط العلامة الصوتية عند $seconds ث.';
  }

  @override
  String get statusCueCleared => 'تم حذف العلامة الصوتية.';

  @override
  String get statusSectionTimingReset => 'تمت إعادة ضبط توقيت القسم';

  @override
  String get statusAdvancedTimingUpdated => 'تم تحديث التوقيت المتقدم';

  @override
  String get statusProjectSaved => 'تم حفظ المشروع';

  @override
  String get statusProjectOpenedMissingDrawing =>
      'تم فتح المشروع لكن ملف الرسم مفقود';

  @override
  String get statusProjectOpened => 'تم فتح المشروع';

  @override
  String get statusVoiceMissing =>
      'دليل الصوت مفقود. حدده أو أزله لمتابعة المزامنة.';

  @override
  String get statusNewProject => 'مشروع جديد مع الاحتفاظ باليد المحددة.';

  @override
  String get theme => 'المظهر';

  @override
  String get themeSystem => 'حسب النظام';

  @override
  String get themeLight => 'فاتح';

  @override
  String get themeDark => 'داكن';

  @override
  String get resolution => 'الدقة';

  @override
  String get customWidth => 'العرض';

  @override
  String get customHeight => 'الارتفاع';

  @override
  String get pixelsUnit => 'بكسل';

  @override
  String customResolutionRange(int min, int max) {
    return 'أدخل قيمة من $min إلى $max بكسل';
  }

  @override
  String get applyResolution => 'تطبيق المقاس';

  @override
  String get frameRate => 'معدل الإطارات';

  @override
  String get background => 'الخلفية';

  @override
  String get canvasBackground => 'خلفية الكانفز';

  @override
  String get canvasBackgroundDescription =>
      'اختر السطح خلف كل المشاهد. تُحفظ الخلفية مع المشروع وتظهر في المعاينة وتصدير MOV.';

  @override
  String get backgroundNone => 'بدون';

  @override
  String get backgroundWhite => 'أبيض';

  @override
  String get backgroundBlack => 'أسود';

  @override
  String get backgroundCustom => 'لون مخصص';

  @override
  String get backgroundPresets => 'الأسطح';

  @override
  String get backgroundNotebook => 'دفتر مسطر';

  @override
  String get backgroundGraph => 'ورق مربعات';

  @override
  String get backgroundCream => 'ورق كريمي';

  @override
  String get backgroundChalkboard => 'سبورة طباشير';

  @override
  String get backgroundSoftGradient => 'تدرج هادئ';

  @override
  String get backgroundWarmWhite => 'أبيض دافئ';

  @override
  String get backgroundBlueprint => 'مخطط هندسي';

  @override
  String get backgroundKraft => 'ورق كرافت';

  @override
  String get backgroundDark => 'داكن';

  @override
  String get backgroundLinen => 'نسيج كتاني';

  @override
  String get customBackgroundColor => 'لون خلفية مخصص';

  @override
  String get hexColor => 'اللون السداسي';

  @override
  String get transparent => 'شفافة';

  @override
  String get startDelay => 'انتظار البداية';

  @override
  String get endHold => 'تثبيت النهاية';

  @override
  String get animation => 'الحركة';

  @override
  String get audio => 'الصوت';

  @override
  String get fileMenu => 'ملف';

  @override
  String get projectMenu => 'المشروع';

  @override
  String get editMenu => 'تحرير';

  @override
  String get viewMenu => 'عرض';

  @override
  String get windowMenu => 'نافذة';

  @override
  String get helpMenu => 'مساعدة';

  @override
  String get importMenu => 'استيراد';

  @override
  String get toolsMenu => 'الأدوات';

  @override
  String get exportingMovie => 'جارٍ تصدير الفيديو';

  @override
  String get exportSucceeded => 'اكتمل التصدير';

  @override
  String get exportFailedTitle => 'فشل التصدير';

  @override
  String get cancelExport => 'إلغاء التصدير';

  @override
  String get exportCanceled => 'تم إلغاء التصدير';

  @override
  String get finishingExport => 'جارٍ إنهاء التصدير…';

  @override
  String get revealInFinder => 'إظهار في Finder';

  @override
  String get openMovie => 'فتح الفيديو';

  @override
  String get copyPath => 'نسخ المسار';

  @override
  String get pathCopied => 'تم نسخ المسار';

  @override
  String get dismiss => 'إغلاق';

  @override
  String get tryAgain => 'إعادة المحاولة';

  @override
  String exportOutputDetails(String size, String duration) {
    return 'Apple ProRes 4444 • شفافية • $size • $duration';
  }

  @override
  String get exportSafeNotice => 'مشروعك محفوظ بشكل منفصل ولم يتم تغييره.';

  @override
  String get licenses => 'التراخيص';

  @override
  String get stop => 'إيقاف';

  @override
  String get selectToolMenu => 'أداة التحديد';

  @override
  String get drawPathToolMenu => 'أداة رسم المسار';

  @override
  String get revealTextToolMenu => 'أداة إظهار النص';

  @override
  String get addNode => 'إضافة نقطة';

  @override
  String get deleteNode => 'حذف النقطة';

  @override
  String get smoothNode => 'تحويل إلى نقطة ناعمة';

  @override
  String get cornerNode => 'تحويل إلى نقطة زاوية';

  @override
  String get splitPath => 'تقسيم المسار هنا';

  @override
  String get joinNextPath => 'ضم المسار التالي';

  @override
  String get setStartNode => 'تعيين كنقطة بداية';

  @override
  String get hidePath => 'إخفاء مسار الحركة';

  @override
  String get showPath => 'إظهار مسار الحركة';

  @override
  String get resetMask => 'إعادة ضبط قناع الإظهار';

  @override
  String get maskBrushSize => 'حجم فرشاة القناع';

  @override
  String get maskFeather => 'نعومة حافة القناع';

  @override
  String get showMaskOverlay => 'إظهار طبقة القناع';

  @override
  String get compareBeforeMask => 'معاينة ما قبل القناع';

  @override
  String get exportPreset => 'إعداد التصدير';

  @override
  String get exportUnavailableDescription =>
      'استورد رسمًا وأضف مسارًا واحدًا على الأقل لضبط التصدير.';

  @override
  String get presetYoutube4k => 'دورة أو YouTube بدقة 4K';

  @override
  String get presetFinalCut4k => 'طبقة Final Cut بدقة 4K';

  @override
  String get presetVerticalLesson => 'درس رأسي';

  @override
  String get presetSquareLesson => 'درس مربع';

  @override
  String get presetPresentationHd => 'عرض تقديمي 1080p';

  @override
  String get presetCustom => 'مخصص';

  @override
  String get exportQuality => 'جودة التصدير';

  @override
  String get exportFullQuality => 'الدقة الكاملة';

  @override
  String get exportProxyQuality => 'Proxy بنصف الدقة';

  @override
  String get alphaMode => 'طريقة تفسير الشفافية';

  @override
  String get alphaPremultiplied => 'شفافية Premultiplied';

  @override
  String get alphaStraight => 'شفافية Straight';

  @override
  String get clipMaskToLayer => 'حصر القناع داخل العنصر';

  @override
  String get snapNodes => 'محاذاة النقاط إلى شبكة دقيقة';

  @override
  String get timelineSectionProperties => 'توقيت المقطع';

  @override
  String get timelineSectionTimingDescription =>
      'تتحكم هذه المدد الدقيقة في الخط الزمني والمعاينة وتصدير MOV.';

  @override
  String sectionDrawingSpeedDescription(String duration) {
    return 'سيتم رسم هذا المقطع خلال $duration ث. تظل السرعة والمدة متزامنتين.';
  }

  @override
  String get animateDuration => 'الرسم';

  @override
  String get transitionDuration => 'الانتقال';

  @override
  String totalSectionDuration(String duration) {
    return 'الإجمالي: $duration ث';
  }

  @override
  String get deleteTimelineSectionTitle => 'حذف المقطع من الخط الزمني؟';

  @override
  String deleteTimelineSectionDescription(String name) {
    return 'هل تريد إزالة «$name» وحركته من الخط الزمني؟ لن يتم حذف ملف المصدر المستورد.';
  }

  @override
  String get zoomIn => 'تكبير';

  @override
  String get zoomOut => 'تصغير';

  @override
  String get importBehavior => 'طريقة الاستيراد';

  @override
  String get fullScene => 'مشهد كامل';

  @override
  String get fullSceneDescription => 'الحفاظ على الصورة كاملة وموضعها';

  @override
  String get singleElement => 'عنصر';

  @override
  String get singleElementDescription => 'تركيز الموضع على المحتوى الظاهر';

  @override
  String get artworkFit => 'ملاءمة الرسم';

  @override
  String get fitEntireImage => 'إظهار الصورة كاملة';

  @override
  String get fitVisibleContent => 'ملاءمة المحتوى الظاهر';

  @override
  String get originalSize => 'الحجم الأصلي';

  @override
  String get fillCanvas => 'ملء الكانفز';

  @override
  String get fillCanvasWarning =>
      'سيملأ هذا الخيار الكانفز وقد يقتص جزءًا من الرسم.';

  @override
  String get positionAndSize => 'الموضع والحجم';

  @override
  String get positionAndSizeDescription => 'إحداثيات دقيقة داخل الكانفز';

  @override
  String get centerHorizontal => 'توسيط أفقي';

  @override
  String get centerVertical => 'توسيط رأسي';

  @override
  String get resetPlacement => 'إعادة ضبط الموضع';
}
