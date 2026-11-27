import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handdraw_studio/core/storage/recent_directory_store.dart';

void main() {
  test('remembers a different last folder for every picker', () async {
    final root = await Directory.systemTemp.createTemp(
      'handdraw-recents-test-',
    );
    addTearDown(() => root.delete(recursive: true));
    final drawings = await Directory('${root.path}/drawings').create();
    final hands = await Directory('${root.path}/hands').create();
    final preferences = File('${root.path}/preferences.json');

    final firstSession = RecentDirectoryStore(preferencesFile: preferences);
    await firstSession.rememberFile(
      RecentDirectoryKey.drawing,
      '${drawings.path}/title.png',
    );
    await firstSession.rememberFile(
      RecentDirectoryKey.hand,
      '${hands.path}/marker.png',
    );

    final nextSession = RecentDirectoryStore(preferencesFile: preferences);
    expect(
      await nextSession.directoryFor(RecentDirectoryKey.drawing),
      drawings.path,
    );
    expect(await nextSession.directoryFor(RecentDirectoryKey.hand), hands.path);
    expect(
      await nextSession.directoryFor(RecentDirectoryKey.projectOpen),
      isNull,
    );
  });
}
