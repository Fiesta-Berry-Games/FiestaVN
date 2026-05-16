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
  final Map<String, String> _playingAssetSourcePaths = {};

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
      // The new backend starts with no playing tracks, so the ifChanged dedup
      // cache from the previous backend must not suppress replaying them.
      _playingAssetSourcePaths.clear();
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
        if (status.queued) {
          _playback
              .queue(
                channel: status.channel,
                asset: asset,
                assetSourcePath: assetSourcePath,
                fadein: status.fadein,
                fadeout: status.fadeout,
                volume: status.volume,
                mixer: status.mixer,
                loop: status.loop,
              )
              .onError((error, stackTrace) {
                debugPrint('Failed to queue RenPy audio $asset: $error');
              });
          return;
        }
        if (status.ifChanged == true &&
            _playingAssetSourcePaths[status.channel] == assetSourcePath) {
          return;
        }
        _playback
            .play(
              channel: status.channel,
              asset: asset,
              assetSourcePath: assetSourcePath,
              fadein: status.fadein,
              fadeout: status.fadeout,
              volume: status.volume,
              mixer: status.mixer,
              loop: status.loop,
            )
            .onError((error, stackTrace) {
              debugPrint('Failed to play RenPy audio $asset: $error');
            });
        _playingAssetSourcePaths[status.channel] = assetSourcePath;
      case RenPyAudioAction.stop:
        _playingAssetSourcePaths.remove(status.channel);
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
    String? fadeout,
    String? volume,
    required String assetSourcePath,
    String? fadein,
    String? mixer,
    bool? loop,
  });

  /// Appends a track to [channel]'s playlist, to begin when the current track
  /// finishes. If nothing is playing it begins immediately.
  Future<void> queue({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadeout,
    String? volume,
    String? fadein,
    String? mixer,
    bool? loop,
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

/// Shared mixer, fade, and per-channel serialization logic for the audio
/// backends that drive real [audio.AudioPlayer]s.
abstract class _AudioPlayersRenPyAudioPlaybackBase
    implements RenPyAudioPlayback {
  final Map<String, audio.AudioPlayer> _players = {};
  final Map<String, bool> _muted = {};
  final Map<String, _AudioMixerState> _mixers = {};
  final Map<String, String> _channelMixers = {};
  final Map<String, double> _channelVolumes = {};
  // Serializes play/stop on a per-channel basis so a rapid second operation
  // cannot drive a player that an earlier sequence is still disposing.
  final Map<String, Future<void>> _channelLocks = {};
  // Tracks queued via `queue`, keyed by channel, played in order as each
  // current track completes.
  final Map<String, List<_QueuedTrack>> _queuedTracks = {};
  // Per-channel subscription to the current player's completion stream, used to
  // advance the channel's queue.
  final Map<String, StreamSubscription<void>> _completionSubs = {};
  bool _disposed = false;

  /// Resolves the audioplayers source for the requested asset, or null when the
  /// asset cannot be located.
  audio.Source? _sourceFor({
    required String asset,
    required String assetSourcePath,
  });

  /// Runs [operation] only after any pending operation on [channel] completes.
  Future<void> _serialize(String channel, Future<void> Function() operation) {
    final pending = _channelLocks[channel] ?? Future<void>.value();
    final next = pending.then((_) => operation());
    _channelLocks[channel] = next.catchError((_) {});
    return next;
  }

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadeout,
    String? volume,
    String? fadein,
    String? mixer,
    bool? loop,
  }) {
    // A fresh play replaces the channel's playlist, so any queued tracks are
    // discarded.
    _queuedTracks.remove(channel);
    return _serialize(
      channel,
      () => _startTrack(
        channel: channel,
        asset: asset,
        assetSourcePath: assetSourcePath,
        fadeout: fadeout,
        volume: volume,
        fadein: fadein,
        mixer: mixer,
        loop: loop,
      ),
    );
  }

  @override
  Future<void> queue({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadeout,
    String? volume,
    String? fadein,
    String? mixer,
    bool? loop,
  }) {
    final track = _QueuedTrack(
      asset: asset,
      assetSourcePath: assetSourcePath,
      fadeout: fadeout,
      volume: volume,
      fadein: fadein,
      mixer: mixer,
      loop: loop,
    );
    return _serialize(channel, () async {
      if (_disposed) return;
      // Nothing playing on the channel: a queued track starts immediately.
      if (_players[channel] == null) {
        await _startTrack(
          channel: channel,
          asset: track.asset,
          assetSourcePath: track.assetSourcePath,
          fadeout: track.fadeout,
          volume: track.volume,
          fadein: track.fadein,
          mixer: track.mixer,
          loop: track.loop,
        );
        return;
      }
      (_queuedTracks[channel] ??= <_QueuedTrack>[]).add(track);
    });
  }

  /// Starts [asset] on [channel]'s player, replacing the current track. Wires a
  /// completion listener so a queued track (if any) starts when this one ends.
  Future<void> _startTrack({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadeout,
    String? volume,
    String? fadein,
    String? mixer,
    bool? loop,
  }) async {
    if (_disposed) return;
    final source = _sourceFor(asset: asset, assetSourcePath: assetSourcePath);
    if (source == null) return;

    if (mixer != null) _channelMixers[channel] = mixer;
    final existingPlayer = _players[channel];
    final player = existingPlayer ?? audio.AudioPlayer();
    _players[channel] = player;
    final fadeoutSeconds = double.tryParse(fadeout ?? '');
    if (existingPlayer != null &&
        fadeoutSeconds != null &&
        fadeoutSeconds > 0) {
      await _fadeOut(player, _effectiveVolume(channel), fadeoutSeconds);
      if (!_isCurrentPlayer(channel, player)) return;
    }
    if (existingPlayer != null) {
      await existingPlayer.stop();
      if (!_isCurrentPlayer(channel, player)) return;
    }
    _channelVolumes[channel] = _trackVolume(volume);
    final effectiveVolume = _effectiveVolume(channel);
    final fadeinSeconds = double.tryParse(fadein ?? '');
    await player.setVolume(
      fadeinSeconds != null && fadeinSeconds > 0 ? 0 : effectiveVolume,
    );
    if (!_isCurrentPlayer(channel, player)) return;
    final looping = loop ?? channel == 'music';
    await player.setReleaseMode(
      looping ? audio.ReleaseMode.loop : audio.ReleaseMode.release,
    );
    if (!_isCurrentPlayer(channel, player)) return;
    _listenForCompletion(channel, player);
    await player.play(source);
    if (fadeinSeconds != null && fadeinSeconds > 0) {
      if (!_isCurrentPlayer(channel, player)) return;
      await _fadeIn(player, effectiveVolume, fadeinSeconds);
    }
  }

  /// Subscribes to [player]'s completion so the next queued track on [channel]
  /// starts when the current one finishes. A looping track never completes, so
  /// it simply holds the queue until replaced.
  void _listenForCompletion(String channel, audio.AudioPlayer player) {
    _completionSubs.remove(channel)?.cancel();
    _completionSubs[channel] = player.onPlayerComplete.listen((_) {
      if (_disposed || !_isCurrentPlayer(channel, player)) return;
      _advanceQueue(channel);
    });
  }

  /// Starts the next queued track on [channel], if any, after the current track
  /// completed.
  Future<void> _advanceQueue(String channel) {
    return _serialize(channel, () async {
      if (_disposed) return;
      final queued = _queuedTracks[channel];
      if (queued == null || queued.isEmpty) return;
      final next = queued.removeAt(0);
      if (queued.isEmpty) _queuedTracks.remove(channel);
      await _startTrack(
        channel: channel,
        asset: next.asset,
        assetSourcePath: next.assetSourcePath,
        fadeout: next.fadeout,
        volume: next.volume,
        fadein: next.fadein,
        mixer: next.mixer,
        loop: next.loop,
      );
    });
  }

  @override
  Future<void> stop({required String channel, String? fadeout}) {
    _queuedTracks.remove(channel);
    return _serialize(channel, () async {
      final player = _players[channel];
      if (player == null) return;

      final fadeoutSeconds = double.tryParse(fadeout ?? '');
      if (fadeoutSeconds != null && fadeoutSeconds > 0) {
        await _fadeOut(player, _effectiveVolume(channel), fadeoutSeconds);
        if (!_isCurrentPlayer(channel, player)) return;
      }

      await player.stop();
      if (!_isCurrentPlayer(channel, player)) return;
      await _completionSubs.remove(channel)?.cancel();
      _players.remove(channel);
      _channelMixers.remove(channel);
      _channelVolumes.remove(channel);
      await player.dispose();
    });
  }

  /// Whether [player] is still the player registered for [channel]; once a
  /// later operation replaced or removed it we must not keep driving it.
  bool _isCurrentPlayer(String channel, audio.AudioPlayer player) {
    return !_disposed && identical(_players[channel], player);
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
    return main.volume * mixer.volume * (_channelVolumes[channel] ?? 1);
  }

  String _mixerForChannel(String channel) {
    final registeredMixer = _channelMixers[channel];
    if (registeredMixer != null) return registeredMixer;
    return switch (channel) {
      'sound' => RenPyPlayerPreferences.sfxMixer,
      'voice' => RenPyPlayerPreferences.voiceMixer,
      'music' => RenPyPlayerPreferences.musicMixer,
      _ => channel,
    };
  }

  Future<void> _fadeOut(
    audio.AudioPlayer player,
    double volume,
    double seconds,
  ) async {
    const steps = 10;
    final stepDuration = Duration(
      milliseconds: (seconds * Duration.millisecondsPerSecond / steps).round(),
    );

    for (var step = steps - 1; step >= 0; step -= 1) {
      if (_disposed) return;
      await player.setVolume(volume * step / steps);
      await Future<void>.delayed(stepDuration);
    }
  }

  Future<void> _fadeIn(
    audio.AudioPlayer player,
    double targetVolume,
    double seconds,
  ) async {
    const steps = 10;
    final stepDuration = Duration(
      milliseconds: (seconds * Duration.millisecondsPerSecond / steps).round(),
    );
    for (var step = 1; step <= steps; step += 1) {
      if (_disposed) return;
      await player.setVolume(targetVolume * step / steps);
      await Future<void>.delayed(stepDuration);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _queuedTracks.clear();
    final subs = _completionSubs.values.toList();
    _completionSubs.clear();
    await Future.wait(subs.map((sub) => sub.cancel()));
    final players = _players.values.toList();
    _players.clear();
    await Future.wait(players.map((player) => player.dispose()));
  }
}

/// A track awaiting playback in a channel's queue.
final class _QueuedTrack {
  const _QueuedTrack({
    required this.asset,
    required this.assetSourcePath,
    this.fadeout,
    this.volume,
    this.fadein,
    this.mixer,
    this.loop,
  });

  final String asset;
  final String assetSourcePath;
  final String? fadeout;
  final String? volume;
  final String? fadein;
  final String? mixer;
  final bool? loop;
}

/// Production audio backend backed by the web-compatible audioplayers plugin.
class AudioplayersRenPyAudioPlayback
    extends _AudioPlayersRenPyAudioPlaybackBase {
  @override
  audio.Source? _sourceFor({
    required String asset,
    required String assetSourcePath,
  }) {
    return audio.AssetSource(assetSourcePath);
  }
}

/// Audio backend for externally loaded project files held in memory.
class RenPyBytesAudioPlayback extends _AudioPlayersRenPyAudioPlaybackBase {
  RenPyBytesAudioPlayback(
    Map<String, Uint8List> assets, {
    Uint8List? Function(String assetPath)? readAsset,
  }) : _assets = Map.unmodifiable(assets),
       _readAsset = readAsset;

  final Map<String, Uint8List> _assets;
  final Uint8List? Function(String assetPath)? _readAsset;

  @override
  audio.Source? _sourceFor({
    required String asset,
    required String assetSourcePath,
  }) {
    final bytes =
        _assets[assetSourcePath] ??
        _assets[asset] ??
        _readAsset?.call(assetSourcePath) ??
        _readAsset?.call(asset);
    if (bytes == null) return null;
    return audio.BytesSource(bytes);
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
    String? fadeout,
    String? volume,
    String? fadein,
    String? mixer,
    bool? loop,
  }) async {}

  @override
  Future<void> queue({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadeout,
    String? volume,
    String? fadein,
    String? mixer,
    bool? loop,
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

double _trackVolume(String? volume) {
  final parsed = double.tryParse(volume ?? '');
  if (parsed == null) return 1;
  if (parsed < 0) return 0;
  if (parsed > 1) return 1;
  return parsed;
}

final class _AudioMixerState {
  const _AudioMixerState({this.volume = 1, this.muted = false});

  final double volume;
  final bool muted;
}
