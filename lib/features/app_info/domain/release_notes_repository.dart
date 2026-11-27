import 'package:handdraw_studio/features/app_info/domain/release_note.dart';

abstract interface class ReleaseNotesRepository {
  Future<List<AppRelease>> loadReleases();
}
