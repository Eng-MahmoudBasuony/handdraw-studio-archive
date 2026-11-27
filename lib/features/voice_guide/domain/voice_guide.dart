class VoiceGuide {
  VoiceGuide({
    required this.path,
    required this.name,
    required this.durationSeconds,
    required List<double> waveform,
    this.securityBookmark,
  }) : waveform = List.unmodifiable(waveform);

  final String path;
  final String name;
  final double durationSeconds;
  final List<double> waveform;
  final String? securityBookmark;

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'durationSeconds': durationSeconds,
    'waveform': waveform,
    'securityBookmark': securityBookmark,
  };

  factory VoiceGuide.fromJson(Map<String, dynamic> json) => VoiceGuide(
    path: json['path'] as String? ?? '',
    name: json['name'] as String? ?? 'Voice Guide',
    durationSeconds: (json['durationSeconds'] as num? ?? 0).toDouble(),
    waveform: (json['waveform'] as List<dynamic>? ?? const [])
        .map((value) => (value as num).toDouble().clamp(0.0, 1.0))
        .toList(growable: false),
    securityBookmark: json['securityBookmark'] as String?,
  );
}
