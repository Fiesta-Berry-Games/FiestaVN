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
      const _PlaybackCall.stop(channel: 'music', fadeout: '1.5'),
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
  Future<void> dispose() async {}
}

class _PlaybackCall {
  const _PlaybackCall.play({
    required this.channel,
    required this.asset,
    required this.assetSourcePath,
  }) : action = 'play',
       fadeout = null;

  const _PlaybackCall.stop({required this.channel, this.fadeout})
    : action = 'stop',
      asset = null,
      assetSourcePath = null;

  final String action;
  final String channel;
  final String? asset;
  final String? assetSourcePath;
  final String? fadeout;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _PlaybackCall &&
            action == other.action &&
            channel == other.channel &&
            asset == other.asset &&
            assetSourcePath == other.assetSourcePath &&
            fadeout == other.fadeout;
  }

  @override
  int get hashCode =>
      Object.hash(action, channel, asset, assetSourcePath, fadeout);

  @override
  String toString() {
    return '_PlaybackCall.$action(channel: $channel, asset: $asset, '
        'assetSourcePath: $assetSourcePath, fadeout: $fadeout)';
  }
}
