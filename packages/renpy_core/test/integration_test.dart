import 'dart:io';
import 'package:renpy_core/renpy_core.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Full-run integration on Reference Game 1 script', () {
    late RenPyRunner runner;

    setUp(() async {
      final src = await File('test/games/1/game/script.rpy').readAsString();
      final res = RenPyParser().parse(src, '001.rpy');
      runner = RenPyRunner(res.script);
    });

    test('Script reaches completion without error', () {
      final dialogue = <String>[];
      final images = <String>[];

      runner.onDialogue = (c, t) => dialogue.add(c != null ? '$c: $t' : t);
      runner.onImage = (scene, show, hide) {
        if (scene != null) images.add('Scene: $scene');
        if (show != null) images.add('Show:  $show');
      };

      runner.jumpToLabel('start');
      runner.run();

      // Advance until finished.
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      expect(runner.state, RenPyRunnerState.complete);
      expect(images, contains('Scene: whitehouse'));
      expect(images, contains('Show:  eileen happy'));
      expect(images, contains('Show:  eileen upset'));
      expect(dialogue.length, 4); // 3 Eileen, 1 narrator.
    });
  });
}
