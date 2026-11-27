import 'dart:convert';

import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'package:handdraw_studio/features/app_info/domain/release_note.dart';
import 'package:handdraw_studio/features/app_info/domain/release_notes_repository.dart';
import 'package:handdraw_studio/features/app_info/infrastructure/release_notes_data_source.dart';

class JsonReleaseNotesRepository implements ReleaseNotesRepository {
  const JsonReleaseNotesRepository(this.dataSource);

  final ReleaseNotesDataSource dataSource;

  @override
  Future<List<AppRelease>> loadReleases() async {
    final decoded = jsonDecode(await dataSource.load());
    if (decoded is! Map<String, dynamic> || decoded['schemaVersion'] != 1) {
      throw const FormatException('Unsupported release notes schema.');
    }
    final releasesJson = decoded['releases'];
    if (releasesJson is! List) {
      throw const FormatException('Release notes must contain releases.');
    }
    final releases =
        releasesJson.map(AppRelease.fromJson).toList(growable: false)
          ..sort((a, b) {
            final dateOrder = b.releaseDate.compareTo(a.releaseDate);
            return dateOrder != 0
                ? dateOrder
                : _compareVersions(b.version, a.version);
          });
    if (releases.isEmpty ||
        releases.where((release) => release.isCurrent).length != 1) {
      throw const FormatException(
        'Release notes require exactly one current release.',
      );
    }
    if (releases.first.version != AppBuildInfo.version ||
        releases.first.buildNumber != int.tryParse(AppBuildInfo.buildNumber) ||
        !releases.first.isCurrent) {
      throw const FormatException(
        'Current release does not match the installed build.',
      );
    }
    return List.unmodifiable(releases);
  }

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map(int.tryParse).toList();
    final rightParts = right.split('.').map(int.tryParse).toList();
    final length = leftParts.length > rightParts.length
        ? leftParts.length
        : rightParts.length;
    for (var index = 0; index < length; index++) {
      final comparison = (leftParts.elementAtOrNull(index) ?? 0).compareTo(
        rightParts.elementAtOrNull(index) ?? 0,
      );
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}
