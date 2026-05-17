import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Drains the runner past every dialogue line until it is no longer waiting for
/// input, collecting the dialogue text in order.
List<String> _runCollecting(RenPyRunner runner, {String? jumpTo}) {
  final dialogue = <String>[];
  runner.onDialogue = (character, text) => dialogue.add(text);
  if (jumpTo != null) {
    runner.jumpToLabel(jumpTo);
  }
  runner.run();
  var guard = 0;
  while (runner.state == RenPyRunnerState.waitingForInput) {
    runner.continueExecution();
    if (guard++ > 1000) {
      fail('Runner did not terminate; possible fall-through loop.');
    }
  }
  return dialogue;
}

void main() {
  test(
    'jump into a nested label falls through to the next top-level label',
    () {
      // `b` is nested inside `a` by indentation; `c` is a top-level sibling of
      // `a`. After b's block ends with an empty call stack, execution must fall
      // through to c rather than completing.
      final script =
          RenPyParser().parse('''
label a:
    "A."
    label b:
        "B."

label c:
    "C."
''', 'fallthrough.rpy').script;
      final runner = RenPyRunner(script);

      final dialogue = _runCollecting(runner, jumpTo: 'b');

      expect(dialogue, ['B.', 'C.']);
      expect(runner.state, RenPyRunnerState.complete);
    },
  );

  test(
    'end of a top-level label falls through to the next top-level label',
    () {
      final script =
          RenPyParser().parse('''
label first:
    "First."

label second:
    "Second."
''', 'fallthrough.rpy').script;
      final runner = RenPyRunner(script);

      final dialogue = _runCollecting(runner, jumpTo: 'first');

      expect(dialogue, ['First.', 'Second.']);
      expect(runner.state, RenPyRunnerState.complete);
    },
  );

  test('sequential top-to-bottom flow runs through stacked labels', () {
    final script =
        RenPyParser().parse('''
label one:
    "One."

label two:
    "Two."

label three:
    "Three."
''', 'fallthrough.rpy').script;
    final runner = RenPyRunner(script);

    final dialogue = _runCollecting(runner);

    expect(dialogue, ['One.', 'Two.', 'Three.']);
    expect(runner.state, RenPyRunnerState.complete);
  });

  test('a label ending in jump does not fall through', () {
    final script =
        RenPyParser().parse('''
label start:
    "Start."
    jump finish

label skipped:
    "Skipped."

label finish:
    "Finish."
''', 'fallthrough.rpy').script;
    final runner = RenPyRunner(script);

    final dialogue = _runCollecting(runner, jumpTo: 'start');

    expect(dialogue, ['Start.', 'Finish.']);
    expect(runner.state, RenPyRunnerState.complete);
  });

  test('a label ending in return does not fall through', () {
    // With no call frame, `return` ends the script; the textually following
    // label must not run.
    final script =
        RenPyParser().parse('''
label start:
    "Start."
    return

label after:
    "After."
''', 'fallthrough.rpy').script;
    final runner = RenPyRunner(script);

    final dialogue = _runCollecting(runner, jumpTo: 'start');

    expect(dialogue, ['Start.']);
    expect(runner.state, RenPyRunnerState.complete);
  });

  test('deeply nested label falls through past every enclosing label', () {
    // `inner` is nested two levels deep (under `mid`, under `outer`); `next`
    // is a top-level sibling of `outer`. Fall-through must climb both levels.
    final script =
        RenPyParser().parse('''
label outer:
    "Outer."
    label mid:
        "Mid."
        label inner:
            "Inner."

label next:
    "Next."
''', 'fallthrough.rpy').script;
    final runner = RenPyRunner(script);

    final dialogue = _runCollecting(runner, jumpTo: 'inner');

    expect(dialogue, ['Inner.', 'Next.']);
    expect(runner.state, RenPyRunnerState.complete);
  });

  test('AquaGuardians-style nested route sections reach the next question', () {
    // Mirrors the real bug: per-section labels (correct/wrong/done) nested
    // under questionN, with questionN+1 as a top-level sibling. Jumping to a
    // section answer must fall through to the next question, not dead-end.
    final script =
        RenPyParser().parse('''
label question1:
    "Question 1?"
    menu:
        "Right choice":
            jump correct1
        "Wrong choice":
            jump wrong1
    label correct1:
        "Correct!"
        jump choice1_done
    label wrong1:
        "Wrong!"
        jump choice1_done
    label choice1_done:
        "Section 1 complete."

label question2:
    "Question 2?"
''', 'aquaguardians.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.onMenu = (choices, onChoice, caption) => onChoice(0);

    runner.jumpToLabel('question1');
    runner.run();
    var guard = 0;
    while (runner.state == RenPyRunnerState.waitingForInput) {
      runner.continueExecution();
      if (guard++ > 1000) fail('Runner did not terminate.');
    }

    expect(dialogue, [
      'Question 1?',
      'Correct!',
      'Section 1 complete.',
      'Question 2?',
    ]);
    expect(runner.state, RenPyRunnerState.complete);
  });

  test('call/return is preserved with nested labels and fall-through', () {
    // A called label that ends without `return` falls through to its sibling,
    // then `return` pops back to just after the call site.
    final script =
        RenPyParser().parse('''
label start:
    "Start."
    call helper
    "Back."
    return

label helper:
    "Helper."
    label helper_tail:
        "Tail."
        return
''', 'fallthrough.rpy').script;
    final runner = RenPyRunner(script);

    final dialogue = _runCollecting(runner, jumpTo: 'start');

    expect(dialogue, ['Start.', 'Helper.', 'Tail.', 'Back.']);
    expect(runner.state, RenPyRunnerState.complete);
  });
}
