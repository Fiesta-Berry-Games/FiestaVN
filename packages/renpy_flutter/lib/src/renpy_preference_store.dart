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

/// How the virtual game stage maps onto the available viewport.
enum RenPyStageFit {
  /// Pick automatically: [fill] when the viewport is much narrower than the
  /// stage (portrait phones), [fit] otherwise.
  auto,

  /// Letterbox the whole stage into the viewport, shrinking everything
  /// uniformly (the classic zoomed-out view).
  fit,

  /// Scale the visuals to cover the viewport, cropping the overflow, while
  /// dialogue and controls lay out on the real viewport. On a portrait phone
  /// this shows full-height characters instead of a thin letterboxed band.
  fill,
}

/// Mutable Ren'Py-style preferences understood by the Flutter player.
class RenPyPlayerPreferences {
  const RenPyPlayerPreferences({Map<String, RenPyMixerPreference>? mixers})
    : _mixers = mixers,
      textCps = defaultTextCps,
      autoDelay = defaultAutoDelay,
      autoForward = false,
      skip = false,
      stageFit = RenPyStageFit.auto;

  const RenPyPlayerPreferences._({
    Map<String, RenPyMixerPreference>? mixers,
    this.textCps = defaultTextCps,
    this.autoDelay = defaultAutoDelay,
    this.autoForward = false,
    this.skip = false,
    this.stageFit = RenPyStageFit.auto,
  }) : _mixers = mixers;

  static const musicMutedKey = 'musicMuted';
  static const mixersKey = 'mixers';
  static const textCpsKey = 'textCps';
  static const autoDelayKey = 'autoDelay';
  static const autoForwardKey = 'autoForward';
  static const skipKey = 'skip';
  static const stageFitKey = 'stageFit';

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

  /// Characters-per-second reveal speed. Zero reveals the line instantly.
  static const defaultTextCps = 0.0;

  /// Maximum selectable characters-per-second before snapping to instant.
  static const maxTextCps = 80.0;

  /// Auto-forward delay multiplier applied to the per-line pause.
  static const defaultAutoDelay = 1.0;

  /// Bounds for the auto-forward delay multiplier slider.
  static const minAutoDelay = 0.0;
  static const maxAutoDelay = 4.0;

  final Map<String, RenPyMixerPreference>? _mixers;

  /// Characters revealed per second; zero means show the full line at once.
  final double textCps;

  /// Multiplier applied to the auto-forward delay between lines.
  final double autoDelay;

  /// Whether auto-forward advances dialogue without user input.
  final bool autoForward;

  /// Whether skip fast-forwards dialogue until a menu or user input.
  final bool skip;

  /// How the game stage maps onto the viewport (letterbox vs cover).
  final RenPyStageFit stageFit;

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
    return _copyWith(mixers: {...?_mixers, mixer: preference});
  }

  RenPyPlayerPreferences setTextCps(double cps) {
    return _copyWith(textCps: _clampTextCps(cps));
  }

  RenPyPlayerPreferences setAutoDelay(double delay) {
    return _copyWith(autoDelay: _clampAutoDelay(delay));
  }

  RenPyPlayerPreferences setAutoForward(bool enabled) {
    return _copyWith(autoForward: enabled);
  }

  RenPyPlayerPreferences setSkip(bool enabled) {
    return _copyWith(skip: enabled);
  }

  RenPyPlayerPreferences setStageFit(RenPyStageFit fit) {
    return _copyWith(stageFit: fit);
  }

  RenPyPlayerPreferences copyWith({bool? musicMuted}) {
    if (musicMuted == null) return this;
    return setMixerMuted(musicMixer, musicMuted);
  }

  RenPyPlayerPreferences _copyWith({
    Map<String, RenPyMixerPreference>? mixers,
    double? textCps,
    double? autoDelay,
    bool? autoForward,
    bool? skip,
    RenPyStageFit? stageFit,
  }) {
    return RenPyPlayerPreferences._(
      mixers: mixers ?? _mixers,
      textCps: textCps ?? this.textCps,
      autoDelay: autoDelay ?? this.autoDelay,
      autoForward: autoForward ?? this.autoForward,
      skip: skip ?? this.skip,
      stageFit: stageFit ?? this.stageFit,
    );
  }

  Map<String, Object?> toJson() {
    return {
      mixersKey: {
        for (final entry in mixers.entries) entry.key: entry.value.toJson(),
      },
      textCpsKey: textCps,
      autoDelayKey: autoDelay,
      autoForwardKey: autoForward,
      skipKey: skip,
      stageFitKey: stageFit.name,
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

    return RenPyPlayerPreferences._(
      mixers: mixers,
      textCps: _readTextCps(json[textCpsKey]),
      autoDelay: _readAutoDelay(json[autoDelayKey]),
      autoForward: json[autoForwardKey] == true,
      skip: json[skipKey] == true,
      stageFit: _readStageFit(json[stageFitKey]),
    );
  }

  static RenPyStageFit _readStageFit(Object? value) {
    for (final fit in RenPyStageFit.values) {
      if (fit.name == value) return fit;
    }
    return RenPyStageFit.auto;
  }

  static double _readTextCps(Object? value) {
    if (value is num) return _clampTextCps(value.toDouble());
    return defaultTextCps;
  }

  static double _readAutoDelay(Object? value) {
    if (value is num) return _clampAutoDelay(value.toDouble());
    return defaultAutoDelay;
  }

  static double _clampTextCps(double value) {
    return value.clamp(0, maxTextCps).toDouble();
  }

  static double _clampAutoDelay(double value) {
    return value.clamp(minAutoDelay, maxAutoDelay).toDouble();
  }
}
