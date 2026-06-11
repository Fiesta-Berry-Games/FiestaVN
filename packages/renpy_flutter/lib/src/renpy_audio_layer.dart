import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:renpy_core/renpy_core.dart' show RenPyAudioAction;
import 'package:sound_dart/sound_dart.dart';

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
    _playback = widget.playback ?? SoundRenPyAudioPlayback();
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
      _playback = widget.playback ?? SoundRenPyAudioPlayback();
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

/// Resolves RenPy audio filenames into game-root-relative source paths.
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

/// Shared mixer, fade, queue, and per-channel serialization logic for the
/// audio backends that drive `sound_dart` [Playback]s.
abstract class _SoundRenPyAudioPlaybackBase implements RenPyAudioPlayback {
  // The currently playing track per channel. Entries are always removed from
  // this map BEFORE being disposed, so completion callbacks can tell a
  // natural finish (still registered) from a replacement (already gone).
  final Map<String, Playback> _playbacks = {};
  final Map<String, bool> _muted = {};
  final Map<String, _AudioMixerState> _mixers = {};
  final Map<String, String> _channelMixers = {};
  final Map<String, double> _channelVolumes = {};
  // Serializes play/stop on a per-channel basis so a rapid second operation
  // cannot drive a playback that an earlier sequence is still disposing.
  final Map<String, Future<void>> _channelLocks = {};
  // Tracks queued via `queue`, keyed by channel, played in order as each
  // current track completes.
  final Map<String, List<_QueuedTrack>> _queuedTracks = {};
  bool _disposed = false;

  /// Resolves the sound source for the requested asset, or null when the
  /// asset cannot be located.
  Future<SoundSource?> _resolveSource({
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
      if (_playbacks[channel] == null) {
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

  /// Starts [asset] on [channel], replacing the current track. Watches the
  /// new playback's completion so a queued track (if any) starts when this
  /// one ends.
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
    final source = await _resolveSource(
      asset: asset,
      assetSourcePath: assetSourcePath,
    );
    if (source == null || _disposed) return;

    if (mixer != null) _channelMixers[channel] = mixer;
    final existing = _playbacks.remove(channel);
    if (existing != null) {
      final fadeoutSeconds = double.tryParse(fadeout ?? '');
      if (fadeoutSeconds != null && fadeoutSeconds > 0) {
        await existing.fade(
          _effectiveVolume(channel),
          0,
          _fadeDuration(fadeoutSeconds),
        );
      }
      await existing.stop();
      await existing.dispose();
    }
    if (_disposed) return;

    _channelVolumes[channel] = _trackVolume(volume);
    final effectiveVolume = _effectiveVolume(channel);
    final fadeinSeconds = double.tryParse(fadein ?? '');
    final playback = await Sound.load(
      source,
      volume:
          fadeinSeconds != null && fadeinSeconds > 0 ? 0 : effectiveVolume,
      loop: loop ?? channel == 'music',
    );
    if (_disposed) {
      await playback.dispose();
      return;
    }
    _playbacks[channel] = playback;
    _watchCompletion(channel, playback);
    await playback.play();
    if (fadeinSeconds != null && fadeinSeconds > 0) {
      if (!_isCurrentPlayback(channel, playback)) return;
      await playback.fade(0, effectiveVolume, _fadeDuration(fadeinSeconds));
    }
  }

  /// Watches [playback]'s completion so the next queued track on [channel]
  /// starts when the current one finishes. A looping track never completes,
  /// so it simply holds the queue until replaced. Backends complete the
  /// future on dispose too; the identity check filters those out because
  /// replaced playbacks leave [_playbacks] before they are disposed.
  void _watchCompletion(String channel, Playback playback) {
    unawaited(
      playback.onComplete.then((_) {
        if (_disposed || !_isCurrentPlayback(channel, playback)) return;
        if (playback.state != PlaybackState.completed) return;
        unawaited(_advanceQueue(channel));
      }),
    );
  }

  Duration _fadeDuration(double seconds) {
    return Duration(
      milliseconds: (seconds * Duration.millisecondsPerSecond).round(),
    );
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
      final playback = _playbacks.remove(channel);
      if (playback == null) return;

      final fadeoutSeconds = double.tryParse(fadeout ?? '');
      if (fadeoutSeconds != null && fadeoutSeconds > 0) {
        await playback.fade(
          _effectiveVolume(channel),
          0,
          _fadeDuration(fadeoutSeconds),
        );
      }

      _channelMixers.remove(channel);
      _channelVolumes.remove(channel);
      await playback.stop();
      await playback.dispose();
    });
  }

  /// Whether [playback] is still the track registered for [channel]; once a
  /// later operation replaced or removed it we must not keep driving it.
  bool _isCurrentPlayback(String channel, Playback playback) {
    return !_disposed && identical(_playbacks[channel], playback);
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
    for (final entry in _playbacks.entries) {
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

  @override
  Future<void> dispose() async {
    _disposed = true;
    _queuedTracks.clear();
    final playbacks = _playbacks.values.toList();
    _playbacks.clear();
    await Future.wait(playbacks.map((playback) => playback.dispose()));
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

/// Production audio backend playing bundled Flutter assets via `sound_dart`
/// (Rust/FFI on native platforms — bundle the `sound_flutter` plugin in the
/// app for the native library — and WebAudio on the web).
class SoundRenPyAudioPlayback extends _SoundRenPyAudioPlaybackBase {
  SoundRenPyAudioPlayback({AssetBundle? bundle}) : _bundle = bundle;

  final AssetBundle? _bundle;

  @override
  Future<SoundSource?> _resolveSource({
    required String asset,
    required String assetSourcePath,
  }) async {
    final ByteData data;
    try {
      data = await (_bundle ?? rootBundle).load('assets/$assetSourcePath');
    } on FlutterError {
      return null;
    }
    return SoundSource.bytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      format: _audioFormatOf(assetSourcePath),
    );
  }
}

/// Audio backend for externally loaded project files held in memory.
class RenPyBytesAudioPlayback extends _SoundRenPyAudioPlaybackBase {
  RenPyBytesAudioPlayback(
    Map<String, Uint8List> assets, {
    Uint8List? Function(String assetPath)? readAsset,
  }) : _assets = Map.unmodifiable(assets),
       _readAsset = readAsset;

  final Map<String, Uint8List> _assets;
  final Uint8List? Function(String assetPath)? _readAsset;

  @override
  Future<SoundSource?> _resolveSource({
    required String asset,
    required String assetSourcePath,
  }) async {
    final bytes =
        _assets[assetSourcePath] ??
        _assets[asset] ??
        _readAsset?.call(assetSourcePath) ??
        _readAsset?.call(asset);
    if (bytes == null) return null;
    return SoundSource.bytes(bytes, format: _audioFormatOf(assetSourcePath));
  }
}

/// Audio backend that streams tracks over HTTP from a base URL, for games
/// whose assets are served remotely instead of bundled (the URL is the base
/// joined with the game-root-relative track path).
class RenPyUrlAudioPlayback extends _SoundRenPyAudioPlaybackBase {
  RenPyUrlAudioPlayback({required String baseUrl, http.Client? httpClient})
    : _baseUrl = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      _httpClient = httpClient;

  final String _baseUrl;
  final http.Client? _httpClient;

  @override
  Future<SoundSource?> _resolveSource({
    required String asset,
    required String assetSourcePath,
  }) async {
    final uri = Uri.parse('$_baseUrl$assetSourcePath');
    try {
      final client = _httpClient;
      final response =
          client == null ? await http.get(uri) : await client.get(uri);
      if (response.statusCode != 200) return null;
      return SoundSource.bytes(
        response.bodyBytes,
        format: _audioFormatOf(assetSourcePath),
      );
    } on Object {
      return null;
    }
  }
}

/// The lowercase file extension of [path] as a format hint, or null.
String? _audioFormatOf(String path) {
  final dot = path.lastIndexOf('.');
  final slash = path.lastIndexOf('/');
  if (dot < 0 || dot < slash || dot == path.length - 1) return null;
  return path.substring(dot + 1).toLowerCase();
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
