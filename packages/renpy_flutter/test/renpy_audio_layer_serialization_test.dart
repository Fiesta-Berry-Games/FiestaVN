import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:sound_dart/sound_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSoundBackend backend;

  setUp(() async {
    await Sound.reset();
    backend = _FakeSoundBackend();
    Sound.registerBackend(backend, makeActive: true);
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
        // per-channel serialization the stop would dispose the playback while
        // the play sequence is still driving it.
        final play = playback.play(
          channel: 'music',
          asset: 'theme.ogg',
          assetSourcePath: 'music/theme.ogg',
          fadein: '0.4',
        );
        final stop = playback.stop(channel: 'music', fadeout: '0.1');

        await expectLater(Future.wait([play, stop]), completes);

        // The channel must be fully stopped: its playback has been disposed
        // and no dangling playback remains registered.
        expect(backend.alivePlaybackCount, 0);

        // A later play on the same channel must still work on a fresh
        // playback.
        await playback.play(
          channel: 'music',
          asset: 'other.ogg',
          assetSourcePath: 'music/other.ogg',
        );
        expect(backend.alivePlaybackCount, 1);
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

        // Exactly one playback remains for the channel and the last source
        // loaded is the second track.
        expect(backend.alivePlaybackCount, 1);
        expect(backend.lastSourceBytes, Uint8List.fromList(const [2]));
      },
    );

    test(
      'dispose during an in-flight fade does not drive a disposed playback',
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
        expect(backend.alivePlaybackCount, 0);
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
      expect(backend.lastSourceBytes, Uint8List.fromList(const [1]));

      // Simulate the current track finishing; the queued track takes over.
      backend.emitCompleteForAll();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(backend.lastSourceBytes, Uint8List.fromList(const [2]));
      expect(backend.alivePlaybackCount, 1);
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

      expect(backend.lastSourceBytes, Uint8List.fromList(const [9]));
      expect(backend.alivePlaybackCount, 1);
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

/// Minimal fake `sound_dart` backend so the real audio playback bases run
/// without any native audio, while the test observes loads, live playbacks,
/// and natural completions.
class _FakeSoundBackend extends SoundBackend {
  final List<_FakePlayback> playbacks = [];

  Uint8List? lastSourceBytes;

  int get alivePlaybackCount =>
      playbacks.where((p) => p.state != PlaybackState.disposed).length;

  /// Simulates every live playback reaching its natural end.
  void emitCompleteForAll() {
    for (final playback in List.of(playbacks)) {
      playback.emitComplete();
    }
  }

  @override
  String get name => 'fake';

  @override
  bool get isAvailable => true;

  @override
  int get priority => 1000000;

  @override
  Future<void> initialize() async {}

  @override
  Future<Playback> load(
    SoundSource source, {
    double volume = 1.0,
    bool loop = false,
  }) async {
    lastSourceBytes = switch (source) {
      BytesSource(:final bytes) => bytes,
      FileSource() => null,
    };
    final playback = _FakePlayback(volume: volume, loop: loop);
    playbacks.add(playback);
    return playback;
  }

  @override
  Future<void> dispose() async {
    for (final playback in List.of(playbacks)) {
      await playback.dispose();
    }
  }
}

class _FakePlayback implements Playback {
  _FakePlayback({required this.volume, required bool loop}) : looping = loop;

  double volume;
  bool looping;
  PlaybackState _state = PlaybackState.idle;
  final Completer<void> _completer = Completer<void>();

  void emitComplete() {
    if (_state == PlaybackState.disposed) return;
    _state = PlaybackState.completed;
    if (!_completer.isCompleted) _completer.complete();
  }

  @override
  PlaybackState get state => _state;

  @override
  bool get isPlaying => _state == PlaybackState.playing;

  @override
  Future<void> get onComplete => _completer.future;

  @override
  Future<void> play() async {
    if (_state == PlaybackState.disposed) return;
    _state = PlaybackState.playing;
  }

  @override
  Future<void> stop() async {
    if (_state == PlaybackState.playing) _state = PlaybackState.stopped;
  }

  @override
  Future<void> pause() async {
    if (_state == PlaybackState.playing) _state = PlaybackState.paused;
  }

  @override
  Future<void> resume() async {
    if (_state == PlaybackState.paused) _state = PlaybackState.playing;
  }

  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  @override
  Future<void> setLooping(bool value) async {
    looping = value;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Duration get position => Duration.zero;

  @override
  Duration? get duration => null;

  @override
  Future<void> dispose() async {
    _state = PlaybackState.disposed;
    if (!_completer.isCompleted) _completer.complete();
  }
}
