import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/widgets.dart';
import 'package:renpy_core/renpy_core.dart' show RenPyAudioAction;

import 'renpy_flutter_controller.dart';
import 'renpy_preference_store.dart';

/// Plays RenPy audio commands observed from a [RenPyFlutterController].
class RenPyAudioLayer extends StatefulWidget {
  const RenPyAudioLayer({
    super.key,
    required this.controller,
    required this.gameRoot,
    this.playback,
    this.musicMuted = false,
    this.preferences,
  });

  final RenPyFlutterController controller;
  final String gameRoot;
  final RenPyAudioPlayback? playback;
  final bool musicMuted;
  final RenPyPlayerPreferences? preferences;

  @override
  State<RenPyAudioLayer> createState() => _RenPyAudioLayerState();
}

class _RenPyAudioLayerState extends State<RenPyAudioLayer> {
  late RenPyAudioPlayback _playback;
  late bool _ownsPlayback;

  @override
  void initState() {
    super.initState();
    _playback = widget.playback ?? AudioplayersRenPyAudioPlayback();
    _ownsPlayback = widget.playback == null;
    _applyPreferences();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(RenPyAudioLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }

    if (!identical(oldWidget.playback, widget.playback)) {
      if (_ownsPlayback) {
        _playback.dispose();
      }
      _playback = widget.playback ?? AudioplayersRenPyAudioPlayback();
      _ownsPlayback = widget.playback == null;
    }

    if (oldWidget.musicMuted != widget.musicMuted ||
        !identical(oldWidget.preferences, widget.preferences) ||
        !identical(oldWidget.playback, widget.playback)) {
      _applyPreferences();
    }
  }

  void _applyPreferences() {
    final preferences = widget.preferences;
    if (preferences == null) {
      _playback.setMuted(channel: 'music', muted: widget.musicMuted).onError((
        error,
        stackTrace,
      ) {
        debugPrint('Failed to update RenPy music mute preference: $error');
      });
      return;
    }

    for (final entry in preferences.mixers.entries) {
      final mixer = entry.value;
      _playback
          .setMixer(
            channel: entry.key,
            volume: mixer.volume,
            muted: mixer.muted,
          )
          .onError((error, stackTrace) {
            debugPrint('Failed to update RenPy mixer ${entry.key}: $error');
          });
    }
  }

  void _onControllerChanged() {
    final status = widget.controller.value;
    if (status is! RenPyAudioChange) return;

    switch (status.action) {
      case RenPyAudioAction.play:
        final asset = status.asset;
        if (asset == null) return;
        final assetSourcePath = RenPyAudioAssetResolver.assetSourcePath(
          gameRoot: widget.gameRoot,
          asset: asset,
        );
        _playback
            .play(
              channel: status.channel,
              asset: asset,
              assetSourcePath: assetSourcePath,
            )
            .onError((error, stackTrace) {
              debugPrint('Failed to play RenPy audio $asset: $error');
            });
      case RenPyAudioAction.stop:
        _playback
            .stop(channel: status.channel, fadeout: status.fadeout)
            .onError((error, stackTrace) {
              debugPrint(
                'Failed to stop RenPy audio ${status.channel}: $error',
              );
            });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    if (_ownsPlayback) {
      _playback.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Resolves RenPy audio filenames into paths accepted by audioplayers.
final class RenPyAudioAssetResolver {
  const RenPyAudioAssetResolver._();

  static String assetSourcePath({
    required String gameRoot,
    required String asset,
  }) {
    final normalizedAsset = asset
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    final assetKey =
        normalizedAsset.startsWith('assets/')
            ? normalizedAsset
            : _join(gameRoot, normalizedAsset);

    return assetKey.startsWith('assets/')
        ? assetKey.substring('assets/'.length)
        : assetKey;
  }

  static String _join(String root, String asset) {
    if (root.isEmpty) return asset;
    if (root.endsWith('/')) return '$root$asset';
    return '$root/$asset';
  }
}

/// Testable audio backend used by [RenPyAudioLayer].
abstract interface class RenPyAudioPlayback {
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  });

  Future<void> stop({required String channel, String? fadeout});

  Future<void> setMuted({required String channel, required bool muted});

  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  });

  Future<void> dispose();
}

/// Production audio backend backed by the web-compatible audioplayers plugin.
class AudioplayersRenPyAudioPlayback implements RenPyAudioPlayback {
  final Map<String, audio.AudioPlayer> _players = {};
  final Map<String, bool> _muted = {};
  final Map<String, _AudioMixerState> _mixers = {};

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {
    final player = _players.putIfAbsent(channel, audio.AudioPlayer.new);
    await player.setVolume(_effectiveVolume(channel));
    await player.setReleaseMode(
      channel == 'music' ? audio.ReleaseMode.loop : audio.ReleaseMode.release,
    );
    await player.play(audio.AssetSource(assetSourcePath));
  }

  @override
  Future<void> stop({required String channel, String? fadeout}) async {
    final player = _players.remove(channel);
    if (player == null) return;

    final fadeoutSeconds = double.tryParse(fadeout ?? '');
    if (fadeoutSeconds != null && fadeoutSeconds > 0) {
      await _fadeOut(player, fadeoutSeconds);
    }

    await player.stop();
    await player.dispose();
  }

  @override
  Future<void> setMuted({required String channel, required bool muted}) async {
    _muted[channel] = muted;
    await setMixer(
      channel: channel,
      volume: _mixers[channel]?.volume ?? 1,
      muted: muted,
    );
  }

  @override
  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  }) async {
    _mixers[channel] = _AudioMixerState(volume: volume, muted: muted);
    await _applyMixerToPlayers(channel);
  }

  Future<void> _applyMixerToPlayers(String mixer) async {
    final futures = <Future<void>>[];
    for (final entry in _players.entries) {
      if (mixer == RenPyPlayerPreferences.mainMixer ||
          _mixerForChannel(entry.key) == mixer) {
        futures.add(entry.value.setVolume(_effectiveVolume(entry.key)));
      }
    }
    await Future.wait(futures);
  }

  double _effectiveVolume(String channel) {
    final main =
        _mixers[RenPyPlayerPreferences.mainMixer] ?? const _AudioMixerState();
    final mixer =
        _mixers[_mixerForChannel(channel)] ?? const _AudioMixerState();
    if (main.muted || mixer.muted || (_muted[channel] ?? false)) return 0;
    return main.volume * mixer.volume;
  }

  String _mixerForChannel(String channel) {
    return channel == 'sound' ? RenPyPlayerPreferences.sfxMixer : channel;
  }

  Future<void> _fadeOut(audio.AudioPlayer player, double seconds) async {
    const steps = 10;
    final stepDuration = Duration(
      milliseconds: (seconds * Duration.millisecondsPerSecond / steps).round(),
    );

    for (var step = steps - 1; step >= 0; step -= 1) {
      await player.setVolume(step / steps);
      await Future<void>.delayed(stepDuration);
    }
  }

  @override
  Future<void> dispose() async {
    final players = _players.values.toList();
    _players.clear();
    await Future.wait(players.map((player) => player.dispose()));
  }
}

/// Audio backend for externally loaded project files held in memory.
class RenPyBytesAudioPlayback implements RenPyAudioPlayback {
  RenPyBytesAudioPlayback(
    Map<String, Uint8List> assets, {
    Uint8List? Function(String assetPath)? readAsset,
  }) : _assets = Map.unmodifiable(assets),
       _readAsset = readAsset;

  final Map<String, Uint8List> _assets;
  final Uint8List? Function(String assetPath)? _readAsset;
  final Map<String, audio.AudioPlayer> _players = {};
  final Map<String, bool> _muted = {};
  final Map<String, _AudioMixerState> _mixers = {};

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {
    final bytes =
        _assets[assetSourcePath] ??
        _assets[asset] ??
        _readAsset?.call(assetSourcePath) ??
        _readAsset?.call(asset);
    if (bytes == null) return;

    final player = _players.putIfAbsent(channel, audio.AudioPlayer.new);
    await player.setVolume(_effectiveVolume(channel));
    await player.setReleaseMode(
      channel == 'music' ? audio.ReleaseMode.loop : audio.ReleaseMode.release,
    );
    await player.play(audio.BytesSource(bytes));
  }

  @override
  Future<void> stop({required String channel, String? fadeout}) async {
    final player = _players.remove(channel);
    if (player == null) return;
    await player.stop();
    await player.dispose();
  }

  @override
  Future<void> setMuted({required String channel, required bool muted}) async {
    _muted[channel] = muted;
    await setMixer(
      channel: channel,
      volume: _mixers[channel]?.volume ?? 1,
      muted: muted,
    );
  }

  @override
  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  }) async {
    _mixers[channel] = _AudioMixerState(volume: volume, muted: muted);
    await _applyMixerToPlayers(channel);
  }

  Future<void> _applyMixerToPlayers(String mixer) async {
    final futures = <Future<void>>[];
    for (final entry in _players.entries) {
      if (mixer == RenPyPlayerPreferences.mainMixer ||
          _mixerForChannel(entry.key) == mixer) {
        futures.add(entry.value.setVolume(_effectiveVolume(entry.key)));
      }
    }
    await Future.wait(futures);
  }

  double _effectiveVolume(String channel) {
    final main =
        _mixers[RenPyPlayerPreferences.mainMixer] ?? const _AudioMixerState();
    final mixer =
        _mixers[_mixerForChannel(channel)] ?? const _AudioMixerState();
    if (main.muted || mixer.muted || (_muted[channel] ?? false)) return 0;
    return main.volume * mixer.volume;
  }

  String _mixerForChannel(String channel) {
    return channel == 'sound' ? RenPyPlayerPreferences.sfxMixer : channel;
  }

  @override
  Future<void> dispose() async {
    final players = _players.values.toList();
    _players.clear();
    await Future.wait(players.map((player) => player.dispose()));
  }
}

/// Audio backend for tests and callers that intentionally disable audio.
class RenPyNoOpAudioPlayback implements RenPyAudioPlayback {
  const RenPyNoOpAudioPlayback();

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {}

  @override
  Future<void> stop({required String channel, String? fadeout}) async {}

  @override
  Future<void> setMuted({required String channel, required bool muted}) async {}

  @override
  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  }) async {}

  @override
  Future<void> dispose() async {}
}

final class _AudioMixerState {
  const _AudioMixerState({this.volume = 1, this.muted = false});

  final double volume;
  final bool muted;
}
