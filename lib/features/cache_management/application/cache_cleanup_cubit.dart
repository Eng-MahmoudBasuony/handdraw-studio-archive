import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:handdraw_studio/features/cache_management/infrastructure/app_cache_service.dart';

class CacheCleanupState {
  const CacheCleanupState({
    this.busy = false,
    this.result,
    this.failed = false,
  });
  final bool busy;
  final CacheCleanupResult? result;
  final bool failed;
  CacheCleanupState copyWith({
    bool? busy,
    CacheCleanupResult? result,
    bool? failed,
  }) => CacheCleanupState(
    busy: busy ?? this.busy,
    result: result ?? this.result,
    failed: failed ?? this.failed,
  );
}

class CacheCleanupCubit extends Cubit<CacheCleanupState> {
  CacheCleanupCubit(this.service) : super(const CacheCleanupState());
  final AppCacheService service;
  Future<void> clear() async {
    if (state.busy) return;
    emit(const CacheCleanupState(busy: true));
    try {
      final result = await service.clear();
      if (!isClosed) emit(state.copyWith(busy: false, result: result));
    } catch (_) {
      if (!isClosed) emit(state.copyWith(busy: false, failed: true));
    }
  }
}
