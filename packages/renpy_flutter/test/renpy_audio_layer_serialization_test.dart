import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers_platform_interface/audioplayers_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAudioplayersPlatform platform;

  setUp(() {
    platform = _FakeAudioplayersPlatform();
    AudioplayersPlatformInterface.instance = platform;
    GlobalAudioplayersPlatformInterface.instance =
        _FakeGlobalAudioplayersPlatform();
  });

  group('per-channel serialization', () {
    test(
      'back-to-back play/stop on the same channel leaves channel stopped',
      () async {
        final playback = RenPyBytesAudioPlayback({
          'music/theme.ogg': Uint8List.fromList(const [1, 2, 3]),
          'music/other.ogg': Uint8List.fromList(const [4, 5, 6]),
        });
        addTearDown(playback.dispose);

        // Start the first track with a fade in, then immediately fire a second
        // operation on the same channel without awaiting the first. Without
        // per-channel serialization the stop would dispose the player while the
        // play sequence is still driving it.
        final play = playback.play(
          channel: 'music',
          asset: 'theme.ogg',
          assetSourcePath: 'music/theme.ogg',
          fadein: '0.4',
        );
        final stop = playback.stop(channel: 'music', fadeout: '0.1');

        await expectLater(Future.wait([play, stop]), completes);

        // The channel must be fully stopped: its player has been disposed and no
        // dangling player remains registered.
        expect(platform.alivePlayerCount, 0);

        // A later play on the same channel must still work on a fresh player.
        await playback.play(
          channel: 'music',
          asset: 'other.ogg',
          assetSourcePath: 'music/other.ogg',
        );
        expect(platform.alivePlayerCount, 1);
      },
    );

    test(
      'back-to-back play/play on the same channel ends on the last track',
      () async {
        final playback = RenPyBytesAudioPlayback({
          'music/first.ogg': Uint8List.fromList(const [1]),
          'music/second.ogg': Uint8List.fromList(const [2]),
        });
        addTearDown(playback.dispose);

        final first = playback.play(
          channel: 'music',
          asset: 'first.ogg',
          assetSourcePath: 'music/first.ogg',
          fadein: '0.1',
          fadeout: '0.1',
        );
        final second = playback.play(
          channel: 'music',
          asset: 'second.ogg',
          assetSourcePath: 'music/second.ogg',
          fadein: '0.1',
          fadeout: '0.1',
        );

        await expectLater(Future.wait([first, second]), completes);

        // Exactly one player remains for the channel and the last source set on
        // it is the second track.
        expect(platform.alivePlayerCount, 1);
        expect(platform.lastSourceBytes, Uint8List.fromList(const [2]));
      },
    );

    test(
      'dispose during an in-flight fade does not drive a disposed player',
      () async {
        final playback = RenPyBytesAudioPlayback({
          'music/theme.ogg': Uint8List.fromList(const [1, 2, 3]),
        });

        final play = playback.play(
          channel: 'music',
          asset: 'theme.ogg',
          assetSourcePath: 'music/theme.ogg',
          fadein: '0.2',
        );

        await playback.dispose();
        await expectLater(play, completes);
        expect(platform.alivePlayerCount, 0);
      },
    );
  });

  group('audio queue', () {
    test('queued track starts after the current track completes', () async {
      final playback = RenPyBytesAudioPlayback({
        'music/bgm1.ogg': Uint8List.fromList(const [1]),
        'music/bgm2.ogg': Uint8List.fromList(const [2]),
      });
      addTearDown(playback.dispose);

      await playback.play(
        channel: 'music',
        asset: 'bgm1.ogg',
        assetSourcePath: 'music/bgm1.ogg',
        loop: false,
      );
      await playback.queue(
        channel: 'music',
        asset: 'bgm2.ogg',
        assetSourcePath: 'music/bgm2.ogg',
        loop: false,
      );

      // The first track is still playing; the queued track has not started.
      expect(platform.lastSourceBytes, Uint8List.fromList(const [1]));

      // Simulate the current track finishing; the queued track takes over.
      platform.emitCompleteForAll();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(platform.lastSourceBytes, Uint8List.fromList(const [2]));
      expect(platform.alivePlayerCount, 1);
    });

    test('queue on an idle channel starts immediately', () async {
      final playback = RenPyBytesAudioPlayback({
        'music/bgm.ogg': Uint8List.fromList(const [9]),
      });
      addTearDown(playback.dispose);

      await playback.queue(
        channel: 'music',
        asset: 'bgm.ogg',
        assetSourcePath: 'music/bgm.ogg',
        loop: false,
      );

      expect(platform.lastSourceBytes, Uint8List.fromList(const [9]));
      expect(platform.alivePlayerCount, 1);
    });

    testWidgets('voice plays non-looping through the audio layer', (
      tester,
    ) async {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      final playback = _RecordingAudioPlayback();

      await tester.pumpWidget(
        RenPyAudioLayer(
          controller: controller,
          gameRoot: 'game',
          playback: playback,
        ),
      );

      controller.value = const RenPyAudioChange.play(
        channel: 'voice',
        asset: 'v/line1.ogg',
        loop: false,
      );
      await tester.pump();

      expect(playback.playedSourcePaths, ['game/v/line1.ogg']);
      expect(playback.queuedSourcePaths, isEmpty);
    });

    testWidgets('queued change routes to the backend queue', (tester) async {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      final playback = _RecordingAudioPlayback();

      await tester.pumpWidget(
        RenPyAudioLayer(
          controller: controller,
          gameRoot: 'game',
          playback: playback,
        ),
      );

      controller.value = const RenPyAudioChange.play(
        channel: 'music',
        asset: 'bgm1.ogg',
      );
      await tester.pump();
      controller.value = const RenPyAudioChange.play(
        channel: 'music',
        asset: 'bgm2.ogg',
        queued: true,
      );
      await tester.pump();

      expect(playback.playedSourcePaths, ['game/bgm1.ogg']);
      expect(playback.queuedSourcePaths, ['game/bgm2.ogg']);
    });
  });

  group('ifChanged cache reset on backend swap', () {
    testWidgets('play with ifChanged replays on a swapped backend', (
      tester,
    ) async {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      final first = _RecordingAudioPlayback();
      final second = _RecordingAudioPlayback();

      await tester.pumpWidget(
        RenPyAudioLayer(
          controller: controller,
          gameRoot: 'game',
          playback: first,
        ),
      );

      controller.value = const RenPyAudioChange.play(
        channel: 'music',
        asset: 'theme.ogg',
      );
      await tester.pump();
      expect(first.playedSourcePaths, ['game/theme.ogg']);

      // Swap to a brand new backend. Its dedup cache must not inherit the
      // previous backend's playing tracks.
      await tester.pumpWidget(
        RenPyAudioLayer(
          controller: controller,
          gameRoot: 'game',
          playback: second,
        ),
      );

      controller.value = const RenPyAudioChange.play(
        channel: 'music',
        asset: 'theme.ogg',
        ifChanged: true,
      );
      await tester.pump();

      expect(second.playedSourcePaths, ['game/theme.ogg']);
    });
  });
}

class _RecordingAudioPlayback implements RenPyAudioPlayback {
  final List<String> playedSourcePaths = [];
  final List<String> queuedSourcePaths = [];

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadein,
    String? mixer,
    String? fadeout,
    String? volume,
    bool? loop,
  }) async {
    playedSourcePaths.add(assetSourcePath);
  }

  @override
  Future<void> queue({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadein,
    String? mixer,
    String? fadeout,
    String? volume,
    bool? loop,
  }) async {
    queuedSourcePaths.add(assetSourcePath);
  }

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

/// Minimal fake of the audioplayers platform so the real audio backends run
/// their player lifecycle without a native plugin.
class _FakeAudioplayersPlatform extends AudioplayersPlatformInterface {
  final Set<String> _alivePlayers = {};
  final Map<String, StreamController<AudioEvent>> _eventStreams = {};
  Uint8List? lastSourceBytes;

  int get alivePlayerCount => _alivePlayers.length;

  /// Emits a completion event on every alive player so queued tracks advance.
  void emitCompleteForAll() {
    for (final stream in _eventStreams.values) {
      stream.add(const AudioEvent(eventType: AudioEventType.complete));
    }
  }

  void _requireAlive(String playerId, String method) {
    if (!_alivePlayers.contains(playerId)) {
      throw StateError('$method called on disposed player $playerId');
    }
  }

  @override
  Future<void> create(String playerId) async {
    _alivePlayers.add(playerId);
    _eventStreams[playerId] = StreamController<AudioEvent>.broadcast();
  }

  @override
  Future<void> dispose(String playerId) async {
    _alivePlayers.remove(playerId);
    await _eventStreams.remove(playerId)?.close();
  }

  @override
  Future<void> setSourceBytes(
    String playerId,
    Uint8List bytes, {
    String? mimeType,
  }) async {
    _requireAlive(playerId, 'setSourceBytes');
    lastSourceBytes = bytes;
    _eventStreams[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Future<void> setSourceUrl(
    String playerId,
    String url, {
    bool? isLocal,
    String? mimeType,
  }) async {
    _requireAlive(playerId, 'setSourceUrl');
    _eventStreams[playerId]?.add(
      const AudioEvent(eventType: AudioEventType.prepared, isPrepared: true),
    );
  }

  @override
  Stream<AudioEvent> getEventStream(String playerId) =>
      _eventStreams[playerId]!.stream;

  @override
  Future<int?> getCurrentPosition(String playerId) async => 0;

  @override
  Future<int?> getDuration(String playerId) async => 0;

  @override
  Future<void> pause(String playerId) async {}

  @override
  Future<void> release(String playerId) async {}

  @override
  Future<void> resume(String playerId) async {
    _requireAlive(playerId, 'resume');
  }

  @override
  Future<void> seek(String playerId, Duration position) async {}

  @override
  Future<void> setAudioContext(String playerId, AudioContext context) async {}

  @override
  Future<void> setBalance(String playerId, double balance) async {}

  @override
  Future<void> setPlaybackRate(String playerId, double playbackRate) async {}

  @override
  Future<void> setPlayerMode(String playerId, PlayerMode playerMode) async {}

  @override
  Future<void> setReleaseMode(String playerId, ReleaseMode releaseMode) async {
    _requireAlive(playerId, 'setReleaseMode');
  }

  @override
  Future<void> setVolume(String playerId, double volume) async {
    _requireAlive(playerId, 'setVolume');
  }

  @override
  Future<void> stop(String playerId) async {}

  @override
  Future<void> emitError(String playerId, String code, String message) async {}

  @override
  Future<void> emitLog(String playerId, String message) async {}
}

class _FakeGlobalAudioplayersPlatform
    extends GlobalAudioplayersPlatformInterface {
  final StreamController<GlobalAudioEvent> _events =
      StreamController<GlobalAudioEvent>.broadcast();

  @override
  Future<void> init() async {}

  @override
  Future<void> setGlobalAudioContext(AudioContext context) async {}

  @override
  Future<void> emitGlobalLog(String message) async {}

  @override
  Future<void> emitGlobalError(String code, String message) async {}

  @override
  Stream<GlobalAudioEvent> getGlobalEventStream() => _events.stream;
}
