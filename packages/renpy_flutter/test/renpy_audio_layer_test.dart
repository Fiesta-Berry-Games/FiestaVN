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
      const _PlaybackCall(
        channel: 'music',
        asset: 'illurock.opus',
        assetSourcePath: 'games/the_question/game/illurock.opus',
      ),
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
      _PlaybackCall(
        channel: channel,
        asset: asset,
        assetSourcePath: assetSourcePath,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _PlaybackCall {
  const _PlaybackCall({
    required this.channel,
    required this.asset,
    required this.assetSourcePath,
  });

  final String channel;
  final String asset;
  final String assetSourcePath;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _PlaybackCall &&
            channel == other.channel &&
            asset == other.asset &&
            assetSourcePath == other.assetSourcePath;
  }

  @override
  int get hashCode => Object.hash(channel, asset, assetSourcePath);

  @override
  String toString() {
    return '_PlaybackCall(channel: $channel, asset: $asset, '
        'assetSourcePath: $assetSourcePath)';
  }
}
