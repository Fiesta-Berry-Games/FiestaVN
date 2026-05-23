import 'dart:io';
import 'package:renpy_core/renpy_core.dart';
import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() async {
  group('RenPy Core – runner & integration', () {
    late RenPyParser parser;

    setUp(() => parser = RenPyParser());

    test(
      'Runner can execute Reference Game 2 (nested menus) to completion',
      () async {
        final file = File('test/games/2/game/script.rpy');
        final source = await file.readAsString();

        final result = parser.parse(source, 'script2.rpy');
        final runner = RenPyRunner(result.script);

        final images = <String>[];
        final dialogue = <String>[];

        runner.onImage = (scene, show, hide) {
          if (scene != null) images.add('scene:$scene');
          if (show != null) images.add('show:$show');
        };

        // Auto-pick the first option every time a menu appears.
        runner.onMenu = (choices, onChoice, caption) => onChoice(0);

        runner.onDialogue = (c, t) => dialogue.add(c != null ? '$c:$t' : t);

        runner.jumpToLabel('start');
        runner.run();

        while (runner.state == RenPyRunnerState.waitingForInput) {
          runner.continueExecution();
        }

        expect(runner.state, RenPyRunnerState.complete);

        // Quick reality-checks.
        expect(images, contains('scene:S2'));
        expect(images, contains('show:S3'));
        expect(images, contains('show:S6')); // Reached inner-menu path.
        expect(dialogue.isNotEmpty, isTrue); // At least some dialogue fired.
      },
    );
  });

  test('Runner falls back to the first choice when onMenu is null', () async {
    final src = await File('test/games/2/game/script.rpy').readAsString();
    final parser = RenPyParser();

    final res = parser.parse(src, 'script2.rpy');
    final runner = RenPyRunner(res.script);

    final images = <String>[];
    runner.onImage = (scene, show, hide) {
      if (scene != null) images.add('scene:$scene');
      if (show != null) images.add('show:$show');
    };

    // --- no onMenu → automatic first-choice selection ---
    runner.jumpToLabel('start');
    runner.run();
    while (runner.state == RenPyRunnerState.waitingForInput) {
      runner.continueExecution();
    }

    expect(runner.state, RenPyRunnerState.complete);

    // Choosing the first option at both menu levels eventually shows “S6”
    expect(images, contains('show:S6'));
  });

  test(
    'Runner executes alternate branch when second top-level choice is taken',
    () async {
      final src = await File('test/games/2/game/script.rpy').readAsString();
      final parser = RenPyParser();

      final res = parser.parse(src, 'script2.rpy');
      final runner = RenPyRunner(res.script);

      final images = <String>[];
      runner.onImage = (scene, show, hide) {
        if (scene != null) images.add('scene:$scene');
        if (show != null) images.add('show:$show');
      };

      // Pick index 1 (the second choice) at the *first* menu only.
      var handledTopMenu = false;
      runner.onMenu = (choices, onChoice, caption) {
        if (!handledTopMenu) {
          onChoice(1); // second option → “Nope, nothing said…”
          handledTopMenu = true;
        } else {
          onChoice(0); // default for any nested menu (shouldn’t fire)
        }
      };

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      expect(runner.state, RenPyRunnerState.complete);

      // We should be on the LR5 scene branch, NOT the S6 branch.
      expect(images, contains('scene:LR5'));
      expect(images, isNot(contains('show:S6')));
    },
  );
}
