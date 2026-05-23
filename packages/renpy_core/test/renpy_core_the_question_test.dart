import 'dart:io';

import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('The Question runner', () {
    late String source;

    setUpAll(() async {
      source =
          await File(
            '../../apps/renfly/assets/games/the_question/game/script.rpy',
          ).readAsString();
    });

    test('runs the good ending through the videogame branch', () {
      final result = RenPyParser().parse(
        source,
        'the_question/game/script.rpy',
      );
      final runner = RenPyRunner(result.script);
      final dialogue = <String>[];
      final images = <String>[];

      runner.onDialogue =
          (character, text) => dialogue.add('${character ?? 'Narrator'}:$text');
      runner.onImage = (scene, show, hide) {
        if (scene != null) images.add('scene:$scene');
        if (show != null) images.add('show:$show');
      };
      runner.onMenu = (choices, onChoice, caption) => onChoice(0);

      runner.jumpToLabel('start');
      runner.run();
      _finishDialogue(runner);

      expect(runner.state, RenPyRunnerState.complete);
      expect(images, contains('scene:bg lecturehall'));
      expect(images, contains('show:sylvie green normal'));
      expect(dialogue, contains('Sylvie:Hi there! How was class?'));
      expect(dialogue, contains('Narrator:{b}Good Ending{/b}.'));
      expect(
        dialogue.any(
          (line) => line.contains('Our first game is based on one of Sylvie'),
        ),
        isFalse,
      );
    });

    test('runs the good ending through the book branch and honors if book', () {
      final result = RenPyParser().parse(
        source,
        'the_question/game/script.rpy',
      );
      final runner = RenPyRunner(result.script);
      final dialogue = <String>[];
      var menuCount = 0;

      runner.onDialogue =
          (character, text) => dialogue.add('${character ?? 'Narrator'}:$text');
      runner.onMenu = (choices, onChoice, caption) {
        menuCount++;
        onChoice(menuCount == 1 ? 0 : 1);
      };

      runner.jumpToLabel('start');
      runner.run();
      _finishDialogue(runner);

      expect(runner.state, RenPyRunnerState.complete);
      expect(dialogue, contains('Narrator:{b}Good Ending{/b}.'));
      expect(
        dialogue.any(
          (line) => line.contains('Our first game is based on one of Sylvie'),
        ),
        isTrue,
      );
    });

    test('runs the bad ending branch', () {
      final result = RenPyParser().parse(
        source,
        'the_question/game/script.rpy',
      );
      final runner = RenPyRunner(result.script);
      final dialogue = <String>[];

      runner.onDialogue =
          (character, text) => dialogue.add('${character ?? 'Narrator'}:$text');
      runner.onMenu = (choices, onChoice, caption) => onChoice(1);

      runner.jumpToLabel('start');
      runner.run();
      _finishDialogue(runner);

      expect(runner.state, RenPyRunnerState.complete);
      expect(dialogue, contains('Narrator:{b}Bad Ending{/b}.'));
    });
  });
}

void _finishDialogue(RenPyRunner runner) {
  var guard = 0;
  while (runner.state == RenPyRunnerState.waitingForInput && guard++ < 200) {
    runner.continueExecution();
  }
  expect(guard, lessThan(200));
}
