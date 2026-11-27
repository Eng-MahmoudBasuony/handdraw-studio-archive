abstract interface class StartupSoundRepository {
  Future<bool> loadEnabled();

  Future<void> saveEnabled(bool enabled);
}
