import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('audio layer plays RenPy audio changes from bundled assets', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    final playback = _RecordingAudioPlayback();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      RenPyAudioLayer(
        controller: controller,
        gameRoot: 'assets/games/the_question/game',
        playback: playback,
      ),
    );

    controller.value = const RenPyAudioChange.play(
      channel: 'music',
      asset: 'illurock.opus',
    );
    await tester.pump();

    expect(playback.calls, [
      const _PlaybackCall.mute(channel: 'music', muted: false),
      const _PlaybackCall.play(
        channel: 'music',
        asset: 'illurock.opus',
        assetSourcePath: 'games/the_question/game/illurock.opus',
      ),
    ]);
  });

  testWidgets('audio layer stops RenPy audio channels', (tester) async {
    final controller = RenPyFlutterController();
    final playback = _RecordingAudioPlayback();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      RenPyAudioLayer(
        controller: controller,
        gameRoot: 'assets/games/the_question/game',
        playback: playback,
      ),
    );

    controller.value = const RenPyAudioChange.stop(
      channel: 'music',
      fadeout: '1.5',
    );
    await tester.pump();

    expect(playback.calls, [
      const _PlaybackCall.mute(channel: 'music', muted: false),
      const _PlaybackCall.stop(channel: 'music', fadeout: '1.5'),
    ]);
  });

  testWidgets('audio layer normalizes leading-slash RenPy audio paths', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    final playback = _RecordingAudioPlayback();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      RenPyAudioLayer(
        controller: controller,
        gameRoot: 'game',
        playback: playback,
      ),
    );

    controller.value = const RenPyAudioChange.play(
      channel: 'music',
      asset: '/music/She End.ogg',
    );
    await tester.pump();

    expect(playback.calls, [
      const _PlaybackCall.mute(channel: 'music', muted: false),
      const _PlaybackCall.play(
        channel: 'music',
        asset: '/music/She End.ogg',
        assetSourcePath: 'game/music/She End.ogg',
      ),
    ]);
  });

  testWidgets('audio layer applies music mute preference', (tester) async {
    final controller = RenPyFlutterController();
    final playback = _RecordingAudioPlayback();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      RenPyAudioLayer(
        controller: controller,
        gameRoot: 'game',
        playback: playback,
      ),
    );

    expect(playback.calls, [
      const _PlaybackCall.mute(channel: 'music', muted: false),
    ]);

    await tester.pumpWidget(
      RenPyAudioLayer(
        controller: controller,
        gameRoot: 'game',
        playback: playback,
        musicMuted: true,
      ),
    );

    expect(playback.calls, [
      const _PlaybackCall.mute(channel: 'music', muted: false),
      const _PlaybackCall.mute(channel: 'music', muted: true),
    ]);
  });

  testWidgets('audio layer applies RenPy mixer preferences', (tester) async {
    final controller = RenPyFlutterController();
    final playback = _RecordingAudioPlayback();
    addTearDown(controller.dispose);
    addTearDown(playback.dispose);

    await tester.pumpWidget(
      RenPyAudioLayer(
        controller: controller,
        gameRoot: 'game',
        playback: playback,
        preferences: const RenPyPlayerPreferences()
            .setMixerVolume(RenPyPlayerPreferences.musicMixer, 0.75)
            .setMixerMuted(RenPyPlayerPreferences.sfxMixer, true)
            .setMixerVolume('ambience', 0.4),
      ),
    );

    expect(playback.calls, [
      const _PlaybackCall.mixer(channel: 'main', volume: 1, muted: false),
      const _PlaybackCall.mixer(channel: 'music', volume: 0.75, muted: false),
      const _PlaybackCall.mixer(channel: 'sfx', volume: 1, muted: true),
      const _PlaybackCall.mixer(channel: 'voice', volume: 1, muted: false),
      const _PlaybackCall.mixer(channel: 'ambience', volume: 0.4, muted: false),
    ]);
  });
}

class _RecordingAudioPlayback implements RenPyAudioPlayback {
  final List<_PlaybackCall> calls = [];

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
  }) async {
    calls.add(
      _PlaybackCall.play(
        channel: channel,
        asset: asset,
        assetSourcePath: assetSourcePath,
      ),
    );
  }

  @override
  Future<void> stop({required String channel, String? fadeout}) async {
    calls.add(_PlaybackCall.stop(channel: channel, fadeout: fadeout));
  }

  @override
  Future<void> setMuted({required String channel, required bool muted}) async {
    calls.add(_PlaybackCall.mute(channel: channel, muted: muted));
  }

  @override
  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  }) async {
    calls.add(
      _PlaybackCall.mixer(channel: channel, volume: volume, muted: muted),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _PlaybackCall {
  const _PlaybackCall.play({
    required this.channel,
    required this.asset,
    required this.assetSourcePath,
  }) : action = 'play',
       fadeout = null,
       muted = null,
       volume = null;

  const _PlaybackCall.stop({required this.channel, this.fadeout})
    : action = 'stop',
      asset = null,
      assetSourcePath = null,
      muted = null,
      volume = null;

  const _PlaybackCall.mute({required this.channel, required this.muted})
    : action = 'mute',
      asset = null,
      assetSourcePath = null,
      fadeout = null,
      volume = null;

  final String action;

  const _PlaybackCall.mixer({
    required this.channel,
    required this.volume,
    required this.muted,
  }) : action = 'mixer',
       asset = null,
       assetSourcePath = null,
       fadeout = null;
  final String channel;
  final String? asset;
  final String? assetSourcePath;
  final String? fadeout;
  final bool? muted;

  final double? volume;
  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _PlaybackCall &&
            action == other.action &&
            channel == other.channel &&
            asset == other.asset &&
            assetSourcePath == other.assetSourcePath &&
            fadeout == other.fadeout &&
            muted == other.muted &&
            volume == other.volume;
  }

  @override
  int get hashCode => Object.hash(
    action,
    channel,
    asset,
    assetSourcePath,
    fadeout,
    muted,
    volume,
  );

  @override
  String toString() {
    return '_PlaybackCall.$action(channel: $channel, asset: $asset, '
        'assetSourcePath: $assetSourcePath, fadeout: $fadeout, '
        'muted: $muted, volume: $volume)';
  }
}
