import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/startup_sound/domain/startup_sound_repository.dart';
import 'package:handdraw_studio/app/startup_sound/domain/startup_sound_state.dart';

class StartupSoundCubit extends Cubit<StartupSoundState> {
  StartupSoundCubit(this._repository, {bool initiallyEnabled = true})
    : super(StartupSoundState(enabled: initiallyEnabled));

  final StartupSoundRepository _repository;
  int _selectionRevision = 0;

  Future<void> hydrate() async {
    final revision = _selectionRevision;
    final enabled = await _repository.loadEnabled();
    if (!isClosed &&
        revision == _selectionRevision &&
        enabled != state.enabled) {
      emit(state.copyWith(enabled: enabled));
    }
  }

  void setEnabled(bool enabled) {
    if (enabled == state.enabled) return;
    _selectionRevision++;
    emit(state.copyWith(enabled: enabled));
    unawaited(_repository.saveEnabled(enabled));
  }
}
