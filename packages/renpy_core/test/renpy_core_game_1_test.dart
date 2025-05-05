import 'dart:io';
import 'package:renpy_core/renpy_core.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('RenPy Core – runner & integration', ()
  {
    late RenPyParser parser;

    setUp(() => parser = RenPyParser());

    test(
      'Runner can execute tutorial script Reference Game 1 script',
          () async {
        final file = File('test/games/1/game/script.rpy');
        final source = await file.readAsString();

        final result = parser.parse(source, 'script.rpy');
        final runner = RenPyRunner(result.script);

        final dialogue = <Map<String, String?>>[];
        final images = <Map<String, String?>>[];

        runner.onDialogue = (c, t) => dialogue.add({'c': c, 't': t});
        runner.onImage =
            (scene, show, hide) =>
            images.add({'scene': scene, 'show': show, 'hide': hide});

        runner.jumpToLabel('start');
        runner.run();

        // Run through the script to completion.
        while (runner.state == RenPyRunnerState.waitingForInput) {
          runner.continueExecution();
        }

        // Check the final state.
        expect(runner.state, RenPyRunnerState.complete);

        // Check image events.
        expect(images.length, 3); // scene + 2 shows.
        expect(images[0]['scene'], equals('whitehouse'));
        expect(images[1]['show'], equals('eileen happy'));
        expect(images[2]['show'], equals('eileen upset'));

        // Check dialogues.
        expect(dialogue.length, 4); // 3 by Eileen, 1 narrator.

        // Check first line of speech.
        expect(dialogue.first['c'], equals('Eileen'));
        expect(
          dialogue.first['t'],
          equals("I'm standing in front of the White House."),
        );
      },
    );
  });
}
