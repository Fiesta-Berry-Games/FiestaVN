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
        final assetSourcePath = RenPyAudioAssetResolver.assetSourcePath(
          gameRoot: widget.gameRoot,
          asset: status.asset,
        );
        _playback
            .play(
              channel: status.channel,
              asset: status.asset,
              assetSourcePath: assetSourcePath,
            )
            .onError((error, stackTrace) {
              debugPrint('Failed to play RenPy audio ${status.asset}: $error');
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
  Future<void> dispose() async {}
}
