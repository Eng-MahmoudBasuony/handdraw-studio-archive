import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:handdraw_studio/app/localization/domain/app_locale_preference.dart';
import 'package:handdraw_studio/app/localization/domain/app_locale_repository.dart';

class AppLocaleCubit extends Cubit<AppLocalePreference> {
  AppLocaleCubit(
    this._repository, {
    AppLocalePreference initialPreference = AppLocalePreference.system,
  }) : super(initialPreference);

  final AppLocaleRepository _repository;
  int _selectionRevision = 0;

  Future<void> hydrate() async {
    final revision = _selectionRevision;
    final preference = await _repository.load();
    if (!isClosed && revision == _selectionRevision && preference != state) {
      emit(preference);
    }
  }

  void select(AppLocalePreference preference) {
    if (preference == state) return;
    _selectionRevision++;
    emit(preference);
    unawaited(_repository.save(preference));
  }
}
