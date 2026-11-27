class StartupSoundState {
  const StartupSoundState({this.enabled = true});

  final bool enabled;

  StartupSoundState copyWith({bool? enabled}) =>
      StartupSoundState(enabled: enabled ?? this.enabled);
}
