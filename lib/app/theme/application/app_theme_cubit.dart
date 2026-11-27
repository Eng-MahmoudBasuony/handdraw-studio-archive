import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/theme/domain/app_theme_preference.dart';
import 'package:handdraw_studio/app/theme/domain/app_theme_repository.dart';

class AppThemeCubit extends Cubit<AppThemePreference> {
  AppThemeCubit(
    this._repository, {
    AppThemePreference initialPreference = AppThemePreference.system,
  }) : super(initialPreference);

  final AppThemeRepository _repository;
  int _selectionRevision = 0;

  Future<void> hydrate() async {
    final revision = _selectionRevision;
    final preference = await _repository.load();
    if (!isClosed && revision == _selectionRevision && preference != state) {
      emit(preference);
    }
  }

  void select(AppThemePreference preference) {
    if (preference == state) return;
    _selectionRevision++;
    emit(preference);
    unawaited(_repository.save(preference));
  }
}
