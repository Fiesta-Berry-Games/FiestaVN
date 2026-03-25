import 'dart:io';

import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('Reference Game 3 tutorial script', () {
    late String source;

    setUpAll(() async {
      source = await File('test/games/3/game/script.rpy').readAsString();
    });

    test('hides seen-set-gated menu choices before a topic is selected', () {
      final script = RenPyParser().parse(source, 'script3.rpy').script;
      final runner = RenPyRunner(script);
      var choices = <String>[];

      runner.onMenu = (items, onChoice, caption) {
        choices = items;
      };

      runner.jumpToLabel('start');
      runner.run();
      _continueUntilMenu(runner, () => choices.isNotEmpty);

      expect(choices, [
        "What are some features of Ren'Py games?",
        'How do I write my own games with it?',
        'Why are we in Washington, DC?',
      ]);
    });

    test('reaches imagemap and audio helper path from the writing topic', () {
      final script = RenPyParser().parse(source, 'script3.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final audio = <RenPyAudioEvent>[];
      final menuChoices = <List<String>>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onAudio = audio.add;
      runner.onMenu = (items, onChoice, caption) {
        menuChoices.add(items);
        if (menuChoices.length == 1) {
          onChoice(items.indexOf('How do I write my own games with it?'));
        }
      };

      runner.jumpToLabel('start');
      runner.run();
      _continueUntilMenu(runner, () => menuChoices.length >= 2);

      expect(dialogue, contains('You picked me!'));
      expect(
        audio,
        contains(
          const RenPyAudioEvent.play(
            channel: 'music',
            asset: 'sun-flower-slow-drag.mid',
          ),
        ),
      );
      expect(
        audio,
        contains(
          const RenPyAudioEvent.play(
            channel: 'sound',
            asset: '18005551212.wav',
          ),
        ),
      );
      expect(menuChoices.last, contains("I think I've heard enough."));
    });
  });
}

void _continueUntilMenu(RenPyRunner runner, bool Function() done) {
  for (var step = 0; step < 1000 && !done(); step += 1) {
    if (runner.state == RenPyRunnerState.waitingForInput) {
      runner.continueExecution();
    }
  }

  if (!done()) {
    fail('Timed out waiting for menu.');
  }
}
