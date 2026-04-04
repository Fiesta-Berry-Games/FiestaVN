import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  test('player preferences expose RenPy default mixers', () {
    const preferences = RenPyPlayerPreferences();

    expect(preferences.mixerVolume(RenPyPlayerPreferences.mainMixer), 1);
    expect(preferences.mixerVolume(RenPyPlayerPreferences.musicMixer), 1);
    expect(preferences.mixerVolume(RenPyPlayerPreferences.sfxMixer), 1);
    expect(preferences.mixerVolume(RenPyPlayerPreferences.voiceMixer), 1);
    expect(
      preferences.isMixerMuted(RenPyPlayerPreferences.musicMixer),
      isFalse,
    );
  });

  test('player preferences round-trip mixer volumes and mute flags', () {
    final preferences = const RenPyPlayerPreferences()
        .setMixerVolume(RenPyPlayerPreferences.musicMixer, 0.75)
        .setMixerMuted(RenPyPlayerPreferences.musicMixer, true)
        .setMixerVolume('ambience', 0.5);

    final restored = RenPyPlayerPreferences.fromJson(preferences.toJson());

    expect(restored.mixerVolume(RenPyPlayerPreferences.musicMixer), 0.75);
    expect(restored.isMixerMuted(RenPyPlayerPreferences.musicMixer), isTrue);
    expect(restored.mixerVolume('ambience'), 0.5);
    expect(restored.isMixerMuted('ambience'), isFalse);
  });

  test('player preferences clamp mixer volume into RenPy range', () {
    final preferences = const RenPyPlayerPreferences()
        .setMixerVolume(RenPyPlayerPreferences.musicMixer, 2)
        .setMixerVolume(RenPyPlayerPreferences.sfxMixer, -1);

    expect(preferences.mixerVolume(RenPyPlayerPreferences.musicMixer), 1);
    expect(preferences.mixerVolume(RenPyPlayerPreferences.sfxMixer), 0);
  });

  test('player preferences restore legacy music mute values', () {
    final preferences = RenPyPlayerPreferences.fromJson({
      RenPyPlayerPreferences.musicMutedKey: true,
    });

    expect(preferences.musicMuted, isTrue);
    expect(preferences.isMixerMuted(RenPyPlayerPreferences.musicMixer), isTrue);
  });
}
