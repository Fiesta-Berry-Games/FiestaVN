import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('trailing {nw} only suppresses the terminal wait', () {
    test('mid-line {w} pauses even when the line ends with {nw}', () {
      final script =
          RenPyParser().parse('''
label start:
    "Hello{w=1.0} World{nw}"
    "Next."
''', 'nw.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <RenPyDialogueEvent>[];

      runner.onDialogueEvent = dialogue.add;

      runner.jumpToLabel('start');
      runner.run();

      // Pauses at the interior {w=1.0} instead of skipping straight through.
      expect(dialogue, [
        const RenPyDialogueEvent(
          text: 'Hello{w=1.0}',
          autoContinueDuration: 1.0,
        ),
      ]);
      expect(runner.state, RenPyRunnerState.waitingForInput);

      runner.continueExecution();

      // The terminal {nw} suppresses the final wait, so execution advances to
      // the next line without waiting after the full text is shown.
      expect(dialogue, [
        const RenPyDialogueEvent(
          text: 'Hello{w=1.0}',
          autoContinueDuration: 1.0,
        ),
        const RenPyDialogueEvent(text: 'Hello{w=1.0} World{nw}'),
        const RenPyDialogueEvent(text: 'Next.'),
      ]);
      expect(runner.state, RenPyRunnerState.waitingForInput);
    });

    test(
      'trailing {nw} with no interior waits still skips the terminal wait',
      () {
        final script =
            RenPyParser().parse('''
label start:
    "Flash.{nw}"
    "Next."
''', 'nw.rpy').script;
        final runner = RenPyRunner(script);
        final dialogue = <String>[];

        runner.onDialogue = (character, text) => dialogue.add(text);

        runner.jumpToLabel('start');
        runner.run();

        expect(dialogue, ['Flash.{nw}', 'Next.']);
        expect(runner.state, RenPyRunnerState.waitingForInput);
      },
    );
  });

  group('jump/call expression resolve dynamic targets', () {
    test('jump expression follows a variable holding the label name', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ destination = "chapter_two"
    jump expression destination

label chapter_two:
    "Arrived."
''', 'jumpexpr.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Arrived.']);
    });

    test('call expression follows a quoted string literal target', () {
      final script =
          RenPyParser().parse('''
label start:
    call expression "greet"
    "Back."

label greet:
    "Hi."
    return
''', 'callexpr.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      // The call resolved to the `greet` label and ran its dialogue.
      expect(dialogue, ['Hi.']);

      // `return` resumes after the call site back in `start`.
      runner.continueExecution();
      expect(dialogue, ['Hi.', 'Back.']);
    });
  });

  group('augmented assignment operators', () {
    RenPyRunner runnerFor(String operatorLine) {
      final script =
          RenPyParser().parse('''
label start:
    \$ x = 8
    \$ $operatorLine
    "done"
''', 'aug.rpy').script;
      return RenPyRunner(script);
    }

    void runStart(RenPyRunner runner) {
      runner.jumpToLabel('start');
      runner.run();
    }

    test('multiplication', () {
      final runner = runnerFor('x *= 2');
      runStart(runner);
      expect(runner.variableValue('x'), 16);
    });

    test('division yields a double', () {
      final runner = runnerFor('x /= 2');
      runStart(runner);
      expect(runner.variableValue('x'), 4.0);
    });

    test('modulo', () {
      final runner = runnerFor('x %= 3');
      runStart(runner);
      expect(runner.variableValue('x'), 2);
    });

    test('floor division stays integer', () {
      final runner = runnerFor('x //= 3');
      runStart(runner);
      expect(runner.variableValue('x'), 2);
    });

    test('power', () {
      final runner = runnerFor('x **= 2');
      runStart(runner);
      expect(runner.variableValue('x'), 64);
    });

    test('addition and subtraction still work', () {
      final adder = runnerFor('x += 5');
      runStart(adder);
      expect(adder.variableValue('x'), 13);

      final subtractor = runnerFor('x -= 5');
      runStart(subtractor);
      expect(subtractor.variableValue('x'), 3);
    });

    test('division by zero leaves the variable unchanged and diagnoses', () {
      final runner = runnerFor('x /= 0');
      final diagnostics = <RenPyDiagnostic>[];
      runner.onDiagnostic = diagnostics.add;
      runStart(runner);

      expect(runner.variableValue('x'), 8);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isNotEmpty,
      );
    });

    test('type mismatch no longer overwrites with the right-hand value', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ x = "hi"
    \$ x *= "no"
    "done"
''', 'aug.rpy').script;
      final runner = RenPyRunner(script);
      final diagnostics = <RenPyDiagnostic>[];
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      // Previously the operator returned the right-hand operand, masking the
      // bad state; now the original value is preserved.
      expect(runner.variableValue('x'), 'hi');
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isNotEmpty,
      );
    });
  });

  group('reset re-initializes per-game state', () {
    test('reset clears mutated defaults and re-runs initialization', () {
      final script =
          RenPyParser().parse('''
define e = Character("Eileen")
default count = 0

label start:
    \$ count += 5
    "Counted."
''', 'reset.rpy').script;
      final runner = RenPyRunner(script);

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.variableValue('count'), 5);
      expect(runner.characterDefined('e'), isTrue);

      runner.reset();

      // The default is restored and the character definition is re-applied.
      expect(runner.variableValue('count'), 0);
      expect(runner.characterDefined('e'), isTrue);
      expect(runner.state, RenPyRunnerState.ready);
    });

    test('run() auto-restart after completion resets defaults', () {
      final script =
          RenPyParser().parse('''
default count = 0

label start:
    \$ count += 3
    "Counted."
''', 'reset.rpy').script;
      final runner = RenPyRunner(script);

      runner.jumpToLabel('start');
      runner.run();
      runner.continueExecution();
      expect(runner.state, RenPyRunnerState.complete);
      expect(runner.variableValue('count'), 3);

      // Re-running from a completed state restarts cleanly: the default is
      // re-initialized to 0 before re-execution rather than carrying the
      // mutated value forward (which would otherwise reach 6).
      runner.run();
      expect(runner.variableValue('count'), 3);
    });

    test('reset preserves cross-game persistent data', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ persistent.seen = True
    "Seen."
''', 'reset.rpy').script;
      final runner = RenPyRunner(script);

      runner.jumpToLabel('start');
      runner.run();
      expect(runner.persistent['seen'], isTrue);

      runner.reset();

      expect(runner.persistent['seen'], isTrue);
    });
  });

  group('low: call/return restores currentLabel', () {
    test('currentLabel returns to the caller after a return', () {
      final script =
          RenPyParser().parse('''
label start:
    call subroutine
    "Back home."

label subroutine:
    "Inside."
    return
''', 'call.rpy').script;
      final runner = RenPyRunner(script);

      runner.jumpToLabel('start');
      runner.run();
      expect(runner.currentLabel, 'subroutine');

      runner.continueExecution();
      // After the return, the public label reflects the caller again.
      expect(runner.currentLabel, 'start');
    });
  });

  group('low: menu set does not clobber a pre-existing scalar', () {
    test('a scalar set target is preserved as a member', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ chosen = 7
    menu:
        set chosen
        "First":
            "Picked first."
''', 'menu.rpy').script;
      final runner = RenPyRunner(script);

      runner.onMenu = (choices, onChoice, caption) => onChoice(0);

      runner.jumpToLabel('start');
      runner.run();

      final value = runner.variableValue('chosen');
      expect(value, isA<List>());
      expect((value as List).contains(7), isTrue);
      expect(value.contains('First'), isTrue);
    });
  });
}

extension on RenPyRunner {
  dynamic variableValue(String name) {
    final snapshot = this.snapshot();
    return snapshot.variables[name];
  }

  bool characterDefined(String name) {
    final snapshot = this.snapshot();
    return snapshot.characters.containsKey(name);
  }
}
