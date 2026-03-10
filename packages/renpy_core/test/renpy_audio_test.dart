import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner emits structured play audio events', () {
    final script =
        RenPyParser().parse('''
label start:
    play music "illurock.opus"
    play sound "audio/Effects/Voice/Hmm.ogg"
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(audio, [
      const RenPyAudioEvent.play(channel: 'music', asset: 'illurock.opus'),
      const RenPyAudioEvent.play(
        channel: 'sound',
        asset: 'audio/Effects/Voice/Hmm.ogg',
      ),
    ]);
  });

  test('runner emits structured stop audio events', () {
    final script =
        RenPyParser().parse('''
label start:
    play music "illurock.opus"
    stop music fadeout 1.5
    stop sound
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(audio, [
      const RenPyAudioEvent.play(channel: 'music', asset: 'illurock.opus'),
      const RenPyAudioEvent.stop(channel: 'music', fadeout: '1.5'),
      const RenPyAudioEvent.stop(channel: 'sound'),
    ]);
  });
}
