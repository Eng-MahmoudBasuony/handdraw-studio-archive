import 'dart:ui';

enum SmartSectionKind { text, shape }

enum SmartSectionMode { handDraw, revealText, ignore }

enum SmartSectionRole { content, connector, globalDecoration }

enum SmartSectionArtifactHint { suspectedFrame }

/// Feature-gated path-analysis behavior. Defaults deliberately preserve the
/// shipping algorithm until an experiment has passed the product fixtures.
final class SmartPathProcessingOptions {
  const SmartPathProcessingOptions({
    this.suspectedFrameDetection = false,
    this.suspectedFrameConfidenceThreshold = 0.96,
  });

  static const fromEnvironment = SmartPathProcessingOptions(
    suspectedFrameDetection: bool.fromEnvironment(
      'HANDDRAW_SPIKE_SUSPECTED_FRAME',
    ),
  );

  final bool suspectedFrameDetection;
  final double suspectedFrameConfidenceThreshold;
}

/// Reproducibility data returned with every analysis. The editor persists a
/// project-owned copy when the generated paths are accepted.
final class SmartPathProcessingRecord {
  const SmartPathProcessingRecord({
    this.engineId = 'handdraw-smart-path',
    this.algorithmVersion = 1,
    this.suspectedFrameDetection = false,
    this.suspectedFrameConfidenceThreshold = 0.96,
  });

  final String engineId;
  final int algorithmVersion;
  final bool suspectedFrameDetection;
  final double suspectedFrameConfidenceThreshold;

  List<String> get featureSet => [
    if (suspectedFrameDetection) 'suspected-frame-detection-v1',
  ];
}

class SmartCharacterRegion {
  const SmartCharacterRegion({required this.value, required this.bounds});

  final String value;
  final Rect bounds;
}

class SmartTextRegion {
  const SmartTextRegion({
    required this.text,
    required this.bounds,
    required this.confidence,
    this.characters = const [],
  });

  final String text;
  final Rect bounds;
  final double confidence;
  final List<SmartCharacterRegion> characters;
}

class SmartGeneratedPath {
  const SmartGeneratedPath({required this.points});

  final List<Offset> points;
}

class SmartPathSection {
  const SmartPathSection({
    required this.id,
    required this.kind,
    required this.bounds,
    required this.label,
    required this.paths,
    required this.recommendedRevealWidth,
    required this.mode,
    this.confidence = 1,
    this.rightToLeft = false,
    this.role = SmartSectionRole.content,
    this.hasPreciseTrace = false,
    this.artifactHint,
    this.artifactConfidence = 0,
  });

  final String id;
  final SmartSectionKind kind;
  final Rect bounds;
  final String label;
  final List<SmartGeneratedPath> paths;
  final double recommendedRevealWidth;
  final SmartSectionMode mode;
  final double confidence;
  final bool rightToLeft;
  final SmartSectionRole role;
  final bool hasPreciseTrace;
  final SmartSectionArtifactHint? artifactHint;
  final double artifactConfidence;

  bool get isSuspectedFrame =>
      artifactHint == SmartSectionArtifactHint.suspectedFrame;

  SmartPathSection copyWith({
    SmartSectionMode? mode,
    SmartSectionArtifactHint? artifactHint,
    double? artifactConfidence,
  }) => SmartPathSection(
    id: id,
    kind: kind,
    bounds: bounds,
    label: label,
    paths: paths,
    recommendedRevealWidth: recommendedRevealWidth,
    mode: mode ?? this.mode,
    confidence: confidence,
    rightToLeft: rightToLeft,
    role: role,
    hasPreciseTrace: hasPreciseTrace,
    artifactHint: artifactHint ?? this.artifactHint,
    artifactConfidence: artifactConfidence ?? this.artifactConfidence,
  );

  List<Offset> get revealPoints {
    final inset = (bounds.width * 0.015).clamp(0.001, 0.008);
    final y = bounds.center.dy;
    final start = Offset(bounds.left + inset, y);
    final end = Offset(bounds.right - inset, y);
    return rightToLeft ? [end, start] : [start, end];
  }
}

class SmartTextPathTrace {
  const SmartTextPathTrace({
    required this.paths,
    required this.bounds,
    required this.recommendedRevealWidth,
  });

  final List<SmartGeneratedPath> paths;
  final Rect bounds;
  final double recommendedRevealWidth;

  bool get isUsable => paths.any((path) => path.points.length >= 2);
}

class SmartPathAnalysis {
  const SmartPathAnalysis({
    required this.sections,
    this.warnings = const [],
    this.processing = const SmartPathProcessingRecord(),
  });

  final List<SmartPathSection> sections;
  final List<String> warnings;
  final SmartPathProcessingRecord processing;
}
