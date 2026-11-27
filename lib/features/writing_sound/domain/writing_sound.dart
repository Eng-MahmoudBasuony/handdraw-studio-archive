enum WritingSoundPreset {
  pencil,
  marker,
  technicalPen,
  recordedSoftPaper,
  recordedPencilPaper,
  recordedNaturalPaper,
  recordedQuickPaper;

  /// The first-choice sound for new projects and legacy projects that did not
  /// store an explicit sound selection.
  static const defaultPreset = WritingSoundPreset.recordedPencilPaper;

  String get label => switch (this) {
    WritingSoundPreset.pencil => 'Pencil on Paper',
    WritingSoundPreset.marker => 'Marker on Paper',
    WritingSoundPreset.technicalPen => 'Technical Pen',
    WritingSoundPreset.recordedSoftPaper => 'Real Paper — Soft',
    WritingSoundPreset.recordedPencilPaper => 'Real Paper — Pencil',
    WritingSoundPreset.recordedNaturalPaper => 'Real Paper — Natural',
    WritingSoundPreset.recordedQuickPaper => 'Real Paper — Quick',
  };

  String? get assetPath => switch (this) {
    WritingSoundPreset.recordedSoftPaper =>
      'assets/sounds/writing_paper_soft.wav',
    WritingSoundPreset.recordedPencilPaper =>
      'assets/sounds/writing_paper_pencil.wav',
    WritingSoundPreset.recordedNaturalPaper =>
      'assets/sounds/writing_paper_natural.wav',
    WritingSoundPreset.recordedQuickPaper =>
      'assets/sounds/writing_paper_quick.wav',
    _ => null,
  };

  bool get isRecorded => assetPath != null;

  static WritingSoundPreset fromName(String? name) => values.firstWhere(
    (preset) => preset.name == name,
    orElse: () => defaultPreset,
  );
}
