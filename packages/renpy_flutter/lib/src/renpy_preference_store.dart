/// Stores Ren'Py-style player preferences outside script state.
abstract interface class RenPyPreferenceStore {
  Map<String, Object?> load();

  void save(Map<String, Object?> values);
}

/// In-memory preference store useful for tests and embedded runners.
class RenPyMemoryPreferenceStore implements RenPyPreferenceStore {
  RenPyMemoryPreferenceStore([Map<String, Object?>? initialValues])
    : _values = Map<String, Object?>.of(initialValues ?? const {});

  Map<String, Object?> _values;

  @override
  Map<String, Object?> load() => Map<String, Object?>.of(_values);

  @override
  void save(Map<String, Object?> values) {
    _values = Map<String, Object?>.of(values);
  }
}

/// Per-mixer Ren'Py-style audio preference values.
class RenPyMixerPreference {
  const RenPyMixerPreference({this.volume = 1, this.muted = false});

  static const volumeKey = 'volume';
  static const mutedKey = 'muted';

  final double volume;
  final bool muted;

  RenPyMixerPreference copyWith({double? volume, bool? muted}) {
    return RenPyMixerPreference(
      volume: volume == null ? this.volume : _clampVolume(volume),
      muted: muted ?? this.muted,
    );
  }

  Map<String, Object?> toJson() => {volumeKey: volume, mutedKey: muted};

  static RenPyMixerPreference fromJson(Object? value) {
    if (value is! Map) return const RenPyMixerPreference();
    return RenPyMixerPreference(
      volume: _readVolume(value[volumeKey]),
      muted: value[mutedKey] == true,
    );
  }

  static double _readVolume(Object? value) {
    if (value is num) return _clampVolume(value.toDouble());
    return 1;
  }

  static double _clampVolume(double value) => value.clamp(0, 1).toDouble();
}

/// Mutable Ren'Py-style preferences understood by the Flutter player.
class RenPyPlayerPreferences {
  const RenPyPlayerPreferences({Map<String, RenPyMixerPreference>? mixers})
    : _mixers = mixers;

  static const musicMutedKey = 'musicMuted';
  static const mixersKey = 'mixers';

  static const mainMixer = 'main';
  static const musicMixer = 'music';
  static const sfxMixer = 'sfx';
  static const voiceMixer = 'voice';

  static const defaultMixers = <String>[
    mainMixer,
    musicMixer,
    sfxMixer,
    voiceMixer,
  ];

  final Map<String, RenPyMixerPreference>? _mixers;

  bool get musicMuted => isMixerMuted(musicMixer);

  Map<String, RenPyMixerPreference> get mixers {
    return {
      for (final mixer in defaultMixers) mixer: mixerPreference(mixer),
      ...?_mixers,
    };
  }

  RenPyMixerPreference mixerPreference(String mixer) {
    return _mixers?[mixer] ?? const RenPyMixerPreference();
  }

  double mixerVolume(String mixer) => mixerPreference(mixer).volume;

  bool isMixerMuted(String mixer) => mixerPreference(mixer).muted;

  RenPyPlayerPreferences setMixerVolume(String mixer, double volume) {
    return _setMixer(mixer, mixerPreference(mixer).copyWith(volume: volume));
  }

  RenPyPlayerPreferences setMixerMuted(String mixer, bool muted) {
    return _setMixer(mixer, mixerPreference(mixer).copyWith(muted: muted));
  }

  RenPyPlayerPreferences _setMixer(
    String mixer,
    RenPyMixerPreference preference,
  ) {
    return RenPyPlayerPreferences(mixers: {...?_mixers, mixer: preference});
  }

  RenPyPlayerPreferences copyWith({bool? musicMuted}) {
    if (musicMuted == null) return this;
    return setMixerMuted(musicMixer, musicMuted);
  }

  Map<String, Object?> toJson() {
    return {
      mixersKey: {
        for (final entry in mixers.entries) entry.key: entry.value.toJson(),
      },
    };
  }

  static RenPyPlayerPreferences fromJson(Map<String, Object?> json) {
    final decodedMixers = json[mixersKey];
    final mixers = <String, RenPyMixerPreference>{};
    if (decodedMixers is Map) {
      for (final entry in decodedMixers.entries) {
        mixers[entry.key.toString()] = RenPyMixerPreference.fromJson(
          entry.value,
        );
      }
    }

    if (json[musicMutedKey] == true) {
      mixers[musicMixer] = (mixers[musicMixer] ?? const RenPyMixerPreference())
          .copyWith(muted: true);
    }

    return RenPyPlayerPreferences(mixers: mixers);
  }
}
