import 'package:flutter/widgets.dart';

enum ReleaseChangeType { newFeature, improvement, fix }

class LocalizedReleaseText {
  LocalizedReleaseText(Map<String, String> translations)
    : translations = Map.unmodifiable(translations);

  final Map<String, String> translations;

  String resolve(Locale locale) =>
      translations[locale.languageCode] ??
      translations['en'] ??
      translations.values.first;

  factory LocalizedReleaseText.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Localized release text must be an object.');
    }
    final translations = <String, String>{};
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        translations[entry.key] = value;
      }
    }
    if (!translations.containsKey('en')) {
      throw const FormatException('Localized release text requires English.');
    }
    return LocalizedReleaseText(translations);
  }
}

class ReleaseNoteEntry {
  const ReleaseNoteEntry({
    required this.type,
    required this.title,
    required this.description,
  });

  final ReleaseChangeType type;
  final LocalizedReleaseText title;
  final LocalizedReleaseText description;

  factory ReleaseNoteEntry.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Release note entry must be an object.');
    }
    final typeName = json['type'];
    final type = ReleaseChangeType.values
        .where((value) => value.name == typeName)
        .firstOrNull;
    if (type == null) {
      throw FormatException('Unsupported release change type: $typeName');
    }
    return ReleaseNoteEntry(
      type: type,
      title: LocalizedReleaseText.fromJson(json['title']),
      description: LocalizedReleaseText.fromJson(json['description']),
    );
  }
}

class AppRelease {
  const AppRelease({
    required this.version,
    required this.releaseDate,
    required this.entries,
    this.buildNumber,
    this.isCurrent = false,
  });

  final String version;
  final int? buildNumber;
  final DateTime releaseDate;
  final List<ReleaseNoteEntry> entries;
  final bool isCurrent;

  factory AppRelease.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Release must be an object.');
    }
    final version = json['version'];
    final releaseDate = DateTime.tryParse(
      json['releaseDate']?.toString() ?? '',
    );
    final entriesJson = json['entries'];
    if (version is! String ||
        version.isEmpty ||
        releaseDate == null ||
        entriesJson is! List) {
      throw const FormatException('Release metadata is incomplete.');
    }
    final entries = entriesJson
        .map(ReleaseNoteEntry.fromJson)
        .toList(growable: false);
    if (entries.isEmpty) {
      throw FormatException('Release $version has no entries.');
    }
    return AppRelease(
      version: version,
      buildNumber: json['buildNumber'] is int
          ? json['buildNumber'] as int
          : null,
      releaseDate: releaseDate,
      entries: entries,
      isCurrent: json['isCurrent'] == true,
    );
  }
}
