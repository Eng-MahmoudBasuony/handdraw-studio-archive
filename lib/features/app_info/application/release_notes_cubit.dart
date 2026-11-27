import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/features/app_info/application/release_notes_state.dart';
import 'package:handdraw_studio/features/app_info/domain/release_notes_repository.dart';

class ReleaseNotesCubit extends Cubit<ReleaseNotesState> {
  ReleaseNotesCubit(this._repository) : super(const ReleaseNotesState());

  final ReleaseNotesRepository _repository;

  Future<void> load() async {
    if (state.status == ReleaseNotesStatus.loading) return;
    emit(state.copyWith(status: ReleaseNotesStatus.loading));
    try {
      final releases = await _repository.loadReleases();
      emit(
        ReleaseNotesState(
          status: ReleaseNotesStatus.loaded,
          releases: releases,
        ),
      );
    } catch (_) {
      emit(state.copyWith(status: ReleaseNotesStatus.failure));
    }
  }
}
