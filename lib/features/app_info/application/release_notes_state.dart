import 'package:handdraw_studio/features/app_info/domain/release_note.dart';

enum ReleaseNotesStatus { initial, loading, loaded, failure }

class ReleaseNotesState {
  const ReleaseNotesState({
    this.status = ReleaseNotesStatus.initial,
    this.releases = const [],
  });

  final ReleaseNotesStatus status;
  final List<AppRelease> releases;

  ReleaseNotesState copyWith({
    ReleaseNotesStatus? status,
    List<AppRelease>? releases,
  }) => ReleaseNotesState(
    status: status ?? this.status,
    releases: releases ?? this.releases,
  );
}
