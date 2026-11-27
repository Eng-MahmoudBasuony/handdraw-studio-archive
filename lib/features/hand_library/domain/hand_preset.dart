import 'dart:ui';

enum HandPresetSource { bundled, custom }

const _unset = Object();

class HandPreset {
  const HandPreset({
    required this.id,
    required this.name,
    required this.source,
    required this.penTip,
    required this.defaultScale,
    required this.defaultRotationDegrees,
    this.assetPath,
    this.managedPath,
    this.originalPath,
    this.flipX = false,
  });

  final String id;
  final String name;
  final HandPresetSource source;
  final String? assetPath;
  final String? managedPath;
  final String? originalPath;
  final Offset penTip;
  final double defaultScale;
  final double defaultRotationDegrees;
  final bool flipX;

  bool get isBundled => source == HandPresetSource.bundled;
  bool get isCustom => source == HandPresetSource.custom;

  String? get imageLocation => isBundled ? assetPath : managedPath;

  HandPreset copyWith({
    String? name,
    Object? assetPath = _unset,
    Object? managedPath = _unset,
    Object? originalPath = _unset,
    Offset? penTip,
    double? defaultScale,
    double? defaultRotationDegrees,
    bool? flipX,
  }) {
    return HandPreset(
      id: id,
      name: name ?? this.name,
      source: source,
      assetPath: identical(assetPath, _unset)
          ? this.assetPath
          : assetPath as String?,
      managedPath: identical(managedPath, _unset)
          ? this.managedPath
          : managedPath as String?,
      originalPath: identical(originalPath, _unset)
          ? this.originalPath
          : originalPath as String?,
      penTip: penTip ?? this.penTip,
      defaultScale: defaultScale ?? this.defaultScale,
      defaultRotationDegrees:
          defaultRotationDegrees ?? this.defaultRotationDegrees,
      flipX: flipX ?? this.flipX,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'source': source.name,
    'assetPath': assetPath,
    'managedPath': managedPath,
    'originalPath': originalPath,
    'penTip': [penTip.dx, penTip.dy],
    'defaultScale': defaultScale,
    'defaultRotationDegrees': defaultRotationDegrees,
    'flipX': flipX,
  };

  factory HandPreset.fromJson(Map<String, dynamic> json) {
    final rawTip = json['penTip'] as List<dynamic>? ?? const [0.18, 0.72];
    final sourceName = json['source'] as String?;
    return HandPreset(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Custom Hand',
      source: sourceName == HandPresetSource.bundled.name
          ? HandPresetSource.bundled
          : HandPresetSource.custom,
      assetPath: json['assetPath'] as String?,
      managedPath: json['managedPath'] as String?,
      originalPath: json['originalPath'] as String?,
      penTip: Offset(
        (rawTip[0] as num).toDouble(),
        (rawTip[1] as num).toDouble(),
      ),
      defaultScale: (json['defaultScale'] as num? ?? 0.24).toDouble(),
      defaultRotationDegrees: (json['defaultRotationDegrees'] as num? ?? 0)
          .toDouble(),
      flipX: json['flipX'] as bool? ?? false,
    );
  }
}

class HandLibrarySnapshot {
  const HandLibrarySnapshot({
    required this.presets,
    required this.selectedPresetId,
    this.applicationDefaults,
  });

  final List<HandPreset> presets;
  final String selectedPresetId;
  final HandApplicationDefaults? applicationDefaults;

  HandPreset get selectedPreset => presets.firstWhere(
    (preset) => preset.id == selectedPresetId,
    orElse: () => presets.first,
  );

  HandApplicationDefaults get resolvedApplicationDefaults =>
      applicationDefaults ?? HandApplicationDefaults.fromPreset(selectedPreset);

  HandLibrarySnapshot copyWith({
    List<HandPreset>? presets,
    String? selectedPresetId,
    HandApplicationDefaults? applicationDefaults,
  }) {
    return HandLibrarySnapshot(
      presets: List.unmodifiable(presets ?? this.presets),
      selectedPresetId: selectedPresetId ?? this.selectedPresetId,
      applicationDefaults: applicationDefaults ?? this.applicationDefaults,
    );
  }
}

/// User-selected defaults that follow the editor across project boundaries.
///
/// Pen-tip calibration remains owned by each [HandPreset], while these values
/// describe how the currently selected hand should appear in every project.
final class HandApplicationDefaults {
  const HandApplicationDefaults({
    required this.scale,
    required this.rotationDegrees,
    required this.flipX,
    this.keepHandVisibleAfterDrawing = false,
  });

  factory HandApplicationDefaults.fromPreset(
    HandPreset preset, {
    bool keepHandVisibleAfterDrawing = false,
  }) => HandApplicationDefaults(
    scale: preset.defaultScale,
    rotationDegrees: preset.defaultRotationDegrees,
    flipX: preset.flipX,
    keepHandVisibleAfterDrawing: keepHandVisibleAfterDrawing,
  );

  final double scale;
  final double rotationDegrees;
  final bool flipX;
  final bool keepHandVisibleAfterDrawing;

  HandApplicationDefaults copyWith({
    double? scale,
    double? rotationDegrees,
    bool? flipX,
    bool? keepHandVisibleAfterDrawing,
  }) => HandApplicationDefaults(
    scale: scale ?? this.scale,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    flipX: flipX ?? this.flipX,
    keepHandVisibleAfterDrawing:
        keepHandVisibleAfterDrawing ?? this.keepHandVisibleAfterDrawing,
  );

  Map<String, dynamic> toJson() => {
    'scale': scale,
    'rotationDegrees': rotationDegrees,
    'flipX': flipX,
    'keepHandVisibleAfterDrawing': keepHandVisibleAfterDrawing,
  };

  factory HandApplicationDefaults.fromJson(
    Map<String, dynamic> json, {
    required HandPreset fallback,
  }) => HandApplicationDefaults(
    scale: (json['scale'] as num? ?? fallback.defaultScale)
        .toDouble()
        .clamp(0.06, 0.90)
        .toDouble(),
    rotationDegrees:
        (json['rotationDegrees'] as num? ?? fallback.defaultRotationDegrees)
            .toDouble()
            .clamp(-180.0, 180.0)
            .toDouble(),
    flipX: json['flipX'] as bool? ?? fallback.flipX,
    keepHandVisibleAfterDrawing:
        json['keepHandVisibleAfterDrawing'] as bool? ?? false,
  );
}

abstract final class BuiltInHands {
  static const defaultPresetId = 'marker-technical-wheat-right';
  static const assetPath = 'assets/hands/hand-writing-marker.png';
  static const darkMarkerAssetPath = 'assets/hands/marker-dark-right-v1.png';
  static const fineLinerAssetPath = 'assets/hands/fineliner-light-right-v1.png';
  static const blueMarkerAssetPath = 'assets/hands/marker-blue-right-v1.png';
  static const frontBlackMarkerAssetPath =
      'assets/hands/front-black-marker-right-v1.png';
  static const wheatTechnicalPenAssetPath =
      'assets/hands/technical-pen-wheat-right-v1.png';

  static const markerRight = HandPreset(
    id: 'marker-right',
    name: 'Marker — Right',
    source: HandPresetSource.bundled,
    assetPath: assetPath,
    // Visible nib apex: source pixel (248, 114) in the 1536×1024 PNG.
    penTip: Offset(0.161458, 0.111328),
    defaultScale: 0.24,
    defaultRotationDegrees: 0,
  );

  static const markerLeft = HandPreset(
    id: 'marker-left',
    name: 'Marker — Left',
    source: HandPresetSource.bundled,
    assetPath: assetPath,
    penTip: Offset(0.161458, 0.111328),
    defaultScale: 0.24,
    defaultRotationDegrees: 0,
    flipX: true,
  );

  static const markerCompact = HandPreset(
    id: 'marker-compact',
    name: 'Marker — Compact',
    source: HandPresetSource.bundled,
    assetPath: assetPath,
    penTip: Offset(0.161458, 0.111328),
    defaultScale: 0.18,
    defaultRotationDegrees: -7,
  );

  static const darkMarkerRight = HandPreset(
    id: 'marker-dark-right',
    name: 'Dark Marker — Right',
    source: HandPresetSource.bundled,
    assetPath: darkMarkerAssetPath,
    // Visible nib apex: source pixel (177, 664.5).
    penTip: Offset(0.115234, 0.648926),
    defaultScale: 0.22,
    defaultRotationDegrees: 0,
  );

  static const fineLinerRight = HandPreset(
    id: 'marker-fineliner-right',
    name: 'Fine Liner — Right',
    source: HandPresetSource.bundled,
    assetPath: fineLinerAssetPath,
    // Visible nib apex: source pixel (229, 582.5).
    penTip: Offset(0.149089, 0.568848),
    defaultScale: 0.22,
    defaultRotationDegrees: 0,
  );

  static const blueMarkerRight = HandPreset(
    id: 'marker-blue-right',
    name: 'Blue Marker — Right',
    source: HandPresetSource.bundled,
    assetPath: blueMarkerAssetPath,
    // Visible nib apex: source pixel (291, 582).
    penTip: Offset(0.189453, 0.568359),
    defaultScale: 0.22,
    defaultRotationDegrees: 0,
  );

  static const frontBlackMarkerRight = HandPreset(
    id: 'marker-front-black-right',
    name: 'Front Black Marker — Right',
    source: HandPresetSource.bundled,
    assetPath: frontBlackMarkerAssetPath,
    // Calibrated against the visible chisel nib apex in the 1536×1024 PNG.
    penTip: Offset(0.376953, 0.045898),
    // The reference style intentionally occupies most of the video height.
    defaultScale: 0.85,
    defaultRotationDegrees: 0,
  );

  static const wheatTechnicalPenRight = HandPreset(
    id: 'marker-technical-wheat-right',
    name: 'Technical Pen — Wheat',
    source: HandPresetSource.bundled,
    assetPath: wheatTechnicalPenAssetPath,
    // Calibrated against the visible nib apex in the bundled 1536×1024 PNG.
    penTip: Offset(0.114583, 0.485677),
    defaultScale: 0.22,
    defaultRotationDegrees: 0,
  );

  static const all = [
    markerRight,
    markerLeft,
    markerCompact,
    darkMarkerRight,
    fineLinerRight,
    blueMarkerRight,
    frontBlackMarkerRight,
    wheatTechnicalPenRight,
  ];

  static HandPreset get defaultPreset => wheatTechnicalPenRight;
}
