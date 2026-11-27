import 'dart:convert';

import 'package:flutter/services.dart';

abstract interface class ReleaseNotesDataSource {
  Future<String> load();
}

class AssetReleaseNotesDataSource implements ReleaseNotesDataSource {
  const AssetReleaseNotesDataSource({
    this.assetPath = 'assets/data/release_notes.json',
  });

  final String assetPath;

  @override
  Future<String> load() async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return utf8.decode(bytes);
  }
}
