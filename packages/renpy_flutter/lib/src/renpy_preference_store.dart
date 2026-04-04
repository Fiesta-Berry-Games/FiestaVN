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

/// Mutable Ren'Py-style preferences understood by the Flutter player.
class RenPyPlayerPreferences {
  const RenPyPlayerPreferences({this.musicMuted = false});

  static const musicMutedKey = 'musicMuted';

  final bool musicMuted;

  RenPyPlayerPreferences copyWith({bool? musicMuted}) {
    return RenPyPlayerPreferences(musicMuted: musicMuted ?? this.musicMuted);
  }

  Map<String, Object?> toJson() => {musicMutedKey: musicMuted};

  static RenPyPlayerPreferences fromJson(Map<String, Object?> json) {
    return RenPyPlayerPreferences(musicMuted: json[musicMutedKey] == true);
  }
}
