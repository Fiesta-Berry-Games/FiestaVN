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

  test('runner strips play audio modifiers from filename expressions', () {
    final script =
        RenPyParser().parse('''
label start:
    play music "/music/She End.ogg" fadein 2.0
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(audio, [
      const RenPyAudioEvent.play(channel: 'music', asset: '/music/She End.ogg'),
    ]);
  });

  test('runner maps legacy renpy audio helper calls to audio events', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.music_start('sun-flower-slow-drag.mid')
    \$ renpy.play("18005551212.wav")
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'music',
        asset: 'sun-flower-slow-drag.mid',
      ),
      const RenPyAudioEvent.play(channel: 'sound', asset: '18005551212.wav'),
    ]);
  });

  test('runner applies registered channel mixer and loop metadata', () {
    final script =
        RenPyParser().parse('''
init python:
    renpy.music.register_channel("ME", "sfx", loop=False)

label start:
    play ME "/ME/rain_2.wav"
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'ME',
        asset: '/ME/rain_2.wav',
        mixer: 'sfx',
        loop: false,
      ),
    ]);
  });
}
