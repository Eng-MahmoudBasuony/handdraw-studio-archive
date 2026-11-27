import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:handdraw_studio/features/app_info/application/release_notes_cubit.dart';
import 'package:handdraw_studio/features/app_info/application/release_notes_state.dart';
import 'package:handdraw_studio/features/app_info/domain/app_build_info.dart';
import 'package:handdraw_studio/features/app_info/domain/release_note.dart';
import 'package:handdraw_studio/features/app_info/domain/release_notes_repository.dart';
import 'package:handdraw_studio/features/app_info/infrastructure/json_release_notes_repository.dart';
import 'package:handdraw_studio/features/app_info/infrastructure/release_notes_data_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'release catalog starts with the current build and stays newest first',
    (tester) async {
      final releases = await const JsonReleaseNotesRepository(
        AssetReleaseNotesDataSource(),
      ).loadReleases();

      expect(releases, isNotEmpty);
      expect(releases.first.version, AppBuildInfo.version);
      expect(releases.first.isCurrent, isTrue);
      expect(releases.first.entries, isNotEmpty);
      expect(releases.where((release) => release.isCurrent), hasLength(1));
      expect(releases.map((release) => release.version), contains('1.0.0'));
      for (var index = 1; index < releases.length; index++) {
        expect(
          releases[index - 1].releaseDate.isBefore(releases[index].releaseDate),
          isFalse,
        );
      }
    },
  );

  test('localized release text supports locale fallback', () async {
    final json =
        '''
      {"schemaVersion":1,"releases":[{"version":"${AppBuildInfo.version}","buildNumber":${AppBuildInfo.buildNumber},"releaseDate":"2026-08-24","isCurrent":true,"entries":[{"type":"fix","title":{"en":"Fix","ar":"إصلاح","fr":"Correction"},"description":{"en":"Description","ar":"وصف"}}]}]}
    ''';
    final releases = await JsonReleaseNotesRepository(
      _StringReleaseNotesDataSource(json),
    ).loadReleases();

    expect(
      releases.single.entries.single.title.resolve(const Locale('fr')),
      'Correction',
    );
    expect(
      releases.single.entries.single.title.resolve(const Locale('de')),
      'Fix',
    );
  });

  test('rejects unsupported release notes schemas', () async {
    final repository = JsonReleaseNotesRepository(
      _StringReleaseNotesDataSource('{"schemaVersion":2,"releases":[]}'),
    );
    await expectLater(repository.loadReleases(), throwsFormatException);
  });

  test('ReleaseNotesCubit exposes loaded and failure states', () async {
    final loadedCubit = ReleaseNotesCubit(_FakeReleaseNotesRepository());
    addTearDown(loadedCubit.close);
    await loadedCubit.load();
    expect(loadedCubit.state.status, ReleaseNotesStatus.loaded);
    expect(loadedCubit.state.releases, hasLength(1));

    final failedCubit = ReleaseNotesCubit(
      _FakeReleaseNotesRepository(shouldFail: true),
    );
    addTearDown(failedCubit.close);
    await failedCubit.load();
    expect(failedCubit.state.status, ReleaseNotesStatus.failure);
  });

  test('About version stays aligned with pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(
      pubspec,
      contains('version: ${AppBuildInfo.version}+${AppBuildInfo.buildNumber}'),
    );
  });
}

class _StringReleaseNotesDataSource implements ReleaseNotesDataSource {
  const _StringReleaseNotesDataSource(this.value);

  final String value;

  @override
  Future<String> load() async => value;
}

class _FakeReleaseNotesRepository implements ReleaseNotesRepository {
  const _FakeReleaseNotesRepository({this.shouldFail = false});

  final bool shouldFail;

  @override
  Future<List<AppRelease>> loadReleases() async {
    if (shouldFail) throw const FormatException('Invalid test data');
    return [
      AppRelease(
        version: AppBuildInfo.version,
        buildNumber: int.parse(AppBuildInfo.buildNumber),
        releaseDate: DateTime(2026, 8, 21),
        isCurrent: true,
        entries: [
          ReleaseNoteEntry(
            type: ReleaseChangeType.fix,
            title: LocalizedReleaseText({'en': 'Fix'}),
            description: LocalizedReleaseText({'en': 'Description'}),
          ),
        ],
      ),
    ];
  }
}
