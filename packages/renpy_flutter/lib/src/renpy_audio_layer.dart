import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/widgets.dart';
import 'package:renpy_core/renpy_core.dart' show RenPyAudioAction;

import 'renpy_flutter_controller.dart';

/// Plays RenPy audio commands observed from a [RenPyFlutterController].
class RenPyAudioLayer extends StatefulWidget {
  const RenPyAudioLayer({
    super.key,
    required this.controller,
    required this.gameRoot,
    this.playback,
  });

  final RenPyFlutterController controller;
  final String gameRoot;
  final RenPyAudioPlayback? playback;

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
    final normalizedAsset = asset.replaceAll(r'\', '/');
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

  Future<void> dispose();
}

/// Production audio backend backed by the web-compatible audioplayers plugin.
class AudioplayersRenPyAudioPlayback implements RenPyAudioPlayback {
  final Map<String, audio.AudioPlayer> _players = {};

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {
    final player = _players.putIfAbsent(channel, audio.AudioPlayer.new);
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
  RenPyBytesAudioPlayback(Map<String, Uint8List> assets)
    : _assets = Map.unmodifiable(assets);

  final Map<String, Uint8List> _assets;
  final Map<String, audio.AudioPlayer> _players = {};

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {
    final bytes = _assets[assetSourcePath] ?? _assets[asset];
    if (bytes == null) return;

    final player = _players.putIfAbsent(channel, audio.AudioPlayer.new);
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
  Future<void> dispose() async {}
}
