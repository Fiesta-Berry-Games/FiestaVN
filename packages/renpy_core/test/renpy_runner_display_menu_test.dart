import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for `renpy.display_menu(...)` intercepted at the statement level, plus
/// the `renpy.say(..., interact=False)` non-blocking path that LearnToCodeRPG
/// pairs with it.
void main() {
  group('renpy.display_menu', () {
    test('assignment form: synchronous harness sets result and continues', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ result = renpy.display_menu([("A", 1), ("B", 2)])
    "after"
''', 'display_menu.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];
      List<String>? offered;

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;
      // Synchronous answer: choose index 1 inside onMenu.
      runner.onMenu = (choices, onChoice, caption) {
        offered = choices;
        onChoice(1);
      };

      runner.jumpToLabel('start');
      runner.run();

      expect(offered, ['A', 'B']);
      expect(runner.variableValue('result'), 2);
      expect(dialogue, ['after']);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
    });

    test(
      'assignment form: deferred harness resumes via the onChoice closure',
      () {
        final script =
            RenPyParser().parse('''
label start:
    \$ result = renpy.display_menu([("A", 1), ("B", 2)])
    "after"
''', 'display_menu.rpy').script;
        final runner = RenPyRunner(script);
        final dialogue = <String>[];
        List<String>? offered;
        Function(int)? deferred;

        runner.onDialogue = (character, text) => dialogue.add(text);
        // Deferred answer: stash the closure and return without choosing.
        runner.onMenu = (choices, onChoice, caption) {
          offered = choices;
          deferred = onChoice;
        };

        runner.jumpToLabel('start');
        runner.run();

        // Still waiting: nothing has been chosen and execution is parked.
        expect(offered, ['A', 'B']);
        expect(runner.state, RenPyRunnerState.waitingForInput);
        expect(dialogue, isEmpty);

        // Host answers later, the way a real UI would.
        deferred!(1);

        expect(runner.variableValue('result'), 2);
        expect(dialogue, ['after']);
      },
    );

    test('bare form runs and continues, discarding the result', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ renpy.display_menu([("A", 1)])
    "after"
''', 'display_menu.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;
      runner.onMenu = (choices, onChoice, caption) => onChoice(0);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['after']);
      expect(runner.state, isNot(RenPyRunnerState.error));
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
    });

    test('list of plain strings: caption equals value', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ result = renpy.display_menu(["A", "B"])
    "after"
''', 'display_menu.rpy').script;
      final runner = RenPyRunner(script);
      List<String>? offered;

      runner.onMenu = (choices, onChoice, caption) {
        offered = choices;
        onChoice(0);
      };

      runner.jumpToLabel('start');
      runner.run();

      expect(offered, ['A', 'B']);
      expect(runner.variableValue('result'), 'A');
    });

    test('onMenu == null falls back to the first choice', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ result = renpy.display_menu([("A", 1), ("B", 2)])
    "after"
''', 'display_menu.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      // No onMenu wired.

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.variableValue('result'), 1);
      expect(dialogue, ['after']);
    });

    test(
      'non-list / empty / unevaluable arg gracefully skips and survives',
      () {
        for (final arg in ['42', '[]', 'undefined_thing']) {
          final script =
              RenPyParser().parse('''
label start:
    \$ result = renpy.display_menu($arg)
    "after"
''', 'display_menu.rpy').script;
          final runner = RenPyRunner(script);
          final dialogue = <String>[];
          final diagnostics = <RenPyDiagnostic>[];

          runner.onDialogue = (character, text) => dialogue.add(text);
          runner.onDiagnostic = diagnostics.add;
          runner.onMenu = (choices, onChoice, caption) => onChoice(0);

          runner.jumpToLabel('start');
          runner.run();

          expect(dialogue, ['after'], reason: 'arg=$arg should continue');
          expect(
            runner.state,
            isNot(RenPyRunnerState.error),
            reason: 'arg=$arg',
          );
          expect(
            diagnostics.where(
              (d) => d.code == RenPyDiagnosticCode.skippedPython,
            ),
            isNotEmpty,
            reason: 'arg=$arg should emit a skip diagnostic',
          );
        }
      },
    );
  });

  group('renpy.say(interact=False)', () {
    test('emits dialogue and does not strand the following statement', () {
      // Two interact=False says back to back: if the first stranded the runner
      // (waiting for input), the second would never emit. A trailing assignment
      // statement (not a blocking say) lets us assert the runner did not park.
      final script =
          RenPyParser().parse('''
label start:
    \$ renpy.say(None, "no wait", interact=False)
    \$ renpy.say(None, "still going", interact=False)
    \$ done = True
''', 'say_no_interact.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      // Both lines emitted without a wait stranding the second one, and the
      // following statement ran (runner did not park on input).
      expect(dialogue, ['no wait', 'still going']);
      expect(runner.variableValue('done'), true);
      expect(runner.state, isNot(RenPyRunnerState.waitingForInput));
    });
  });
}

extension on RenPyRunner {
  dynamic variableValue(String name) => snapshot().variables[name];
}
