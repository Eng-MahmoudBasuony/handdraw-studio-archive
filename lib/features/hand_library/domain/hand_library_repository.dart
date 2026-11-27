import 'dart:typed_data';

import 'package:handdraw_studio/features/hand_library/domain/hand_preset.dart';

abstract interface class HandLibraryRepository {
  Future<HandLibrarySnapshot> load();

  Future<HandLibrarySnapshot> importCustom({
    required HandLibrarySnapshot current,
    required String sourcePath,
    required Uint8List bytes,
  });

  Future<void> save(HandLibrarySnapshot snapshot);
}
