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

  test('runner preserves play audio modifiers separately from filename', () {
    final script =
        RenPyParser().parse('''
label start:
    play music "/music/She End.ogg" fadein 2.0 noloop
    play sound "click.ogg" loop
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'music',
        asset: '/music/She End.ogg',
        fadein: '2.0',
        loop: false,
      ),
      const RenPyAudioEvent.play(
        channel: 'sound',
        asset: 'click.ogg',
        loop: true,
      ),
    ]);
  });

  test('runner preserves play fadeout volume and if changed modifiers', () {
    final script =
        RenPyParser().parse('''
label start:
    play music "theme.ogg" fadeout 1.0 fadein 2.0 volume 0.5 if_changed
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'music',
        asset: 'theme.ogg',
        fadeout: '1.0',
        fadein: '2.0',
        volume: '0.5',
        ifChanged: true,
      ),
    ]);
  });

  test('play audio loop modifiers override registered channel defaults', () {
    final script =
        RenPyParser().parse('''
init python:
    renpy.music.register_channel("ambience", "music", loop=True)

label start:
    play ambience "rain.ogg" noloop
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'ambience',
        asset: 'rain.ogg',
        mixer: 'music',
        loop: false,
      ),
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

  test('runner maps renpy music helper calls to audio events', () {
    final script =
        RenPyParser().parse('''
init python:
    renpy.music.register_channel("ambience", "sfx", loop=False)

label start:
    \$ renpy.music.play("theme.ogg", channel="ambience", fadeout=1.0, fadein=2.0, loop=True, if_changed=True, relative_volume=0.5)
    \$ renpy.music.stop(channel="ambience", fadeout=0.75)
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'ambience',
        asset: 'theme.ogg',
        fadeout: '1.0',
        fadein: '2.0',
        volume: '0.5',
        ifChanged: true,
        mixer: 'sfx',
        loop: true,
      ),
      const RenPyAudioEvent.stop(channel: 'ambience', fadeout: '0.75'),
    ]);
  });

  test('runner maps renpy sound helper calls to audio events', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.sound.play("click, hard.ogg", channel="voice", fadeout=0.25, fadein=0.5, loop=False, if_changed=True, relative_volume=0.25)
    \$ renpy.sound.stop(channel="voice", fadeout=0.125)
''', 'audio.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];

    runner.onAudio = audio.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(audio, [
      const RenPyAudioEvent.play(
        channel: 'voice',
        asset: 'click, hard.ogg',
        fadeout: '0.25',
        fadein: '0.5',
        volume: '0.25',
        ifChanged: true,
        loop: false,
      ),
      const RenPyAudioEvent.stop(channel: 'voice', fadeout: '0.125'),
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
