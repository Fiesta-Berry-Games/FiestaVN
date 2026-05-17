import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('named menus as jump targets', () {
    test('jump enters a named menu and presents its choices', () {
      final script =
          RenPyParser().parse('''
label start:
    jump pick

label pick:
    menu choose:
        "A":
            "Picked A."
        "B":
            "Picked B."
''', 'named_menu.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      List<String>? offered;

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onMenu = (choices, onChoice, caption) {
        offered = choices;
        onChoice(0);
      };

      runner.jumpToLabel('start');
      runner.run();

      expect(offered, ['A', 'B']);
      expect(dialogue, ['Picked A.']);
    });

    test('retry pattern: a choice that jumps back re-enters the menu', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ tries = 0
    menu guess:
        "Guess again" if tries < 3:
            \$ tries += 1
            jump guess
        "Give up":
            if tries == 3:
                "Gave up after three tries."
''', 'retry.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      var menuCount = 0;

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onMenu = (choices, onChoice, caption) {
        menuCount += 1;
        // Keep guessing until the guard hides the first option, then give up.
        onChoice(choices.length > 1 ? 0 : 0);
      };

      runner.jumpToLabel('start');
      runner.run();

      // The menu is shown four times: three guesses then the final menu where
      // only "Give up" remains.
      expect(menuCount, 4);
      expect(dialogue, ['Gave up after three tries.']);
    });

    test('call into a named menu returns to the caller', () {
      final script =
          RenPyParser().parse('''
label start:
    call ask
    "Back home."
    return

label ask:
    menu ask_menu:
        "Yes":
            \$ answer = "yes"
        "No":
            \$ answer = "no"
    return
''', 'call_menu.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onMenu = (choices, onChoice, caption) => onChoice(0);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Back home.']);
    });

    test('anonymous menus are unaffected', () {
      final script =
          RenPyParser().parse('''
label start:
    menu:
        "Only":
            "Chosen."
''', 'anon.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onMenu = (choices, onChoice, caption) => onChoice(0);
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Chosen.']);
    });
  });

  group('top-level while loops', () {
    test('while count < 3 with \$ count += 1 iterates exactly 3 times', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ count = 0
    while count < 3:
        \$ count += 1
        "Tick."
    if count == 3:
        "Done at three."
''', 'while.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      // Advance through each dialogue line.
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      // Exactly three body passes, and the final count is 3 (loop ran 3x).
      expect(dialogue, ['Tick.', 'Tick.', 'Tick.', 'Done at three.']);
    });

    test('a while with a false condition runs its body zero times', () {
      final script =
          RenPyParser().parse('''
label start:
    while False:
        "Never."
    "After."
''', 'while0.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      expect(dialogue, ['After.']);
    });
  });

  group('top-level for loops', () {
    test('for i in [1, 2, 3] runs the body 3 times with i bound', () {
      final script =
          RenPyParser().parse('''
label start:
    for i in [1, 2, 3]:
        if i == 1:
            "One."
        if i == 2:
            "Two."
        if i == 3:
            "Three."
    if i == 3:
        "Loop var persisted."
''', 'for.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      // i is bound to each item in turn, and persists as 3 after the loop.
      expect(dialogue, ['One.', 'Two.', 'Three.', 'Loop var persisted.']);
    });

    test('for over an empty list skips the body', () {
      final script =
          RenPyParser().parse('''
label start:
    for x in []:
        "Never."
    "After."
''', 'for_empty.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      expect(dialogue, ['After.']);
    });
  });

  group('break and continue', () {
    test('break exits the loop early', () {
      final script =
          RenPyParser().parse('''
label start:
    for i in [1, 2, 3, 4, 5]:
        if i == 3:
            break
        "Item."
    "After."
''', 'break.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      expect(dialogue, ['Item.', 'Item.', 'After.']);
    });

    test('continue skips the rest of the body for that pass', () {
      final script =
          RenPyParser().parse('''
label start:
    for i in [1, 2, 3, 4]:
        if i == 2:
            continue
        "Item."
    "After."
''', 'continue.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      // The body runs for 1, 3 and 4 (skipping 2): three "Item." lines.
      expect(dialogue, ['Item.', 'Item.', 'Item.', 'After.']);
    });

    test('continue in a while re-checks the condition', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ n = 0
    \$ shown = 0
    while n < 4:
        \$ n += 1
        if n == 2:
            continue
        \$ shown += 1
    if shown == 3:
        "Three shown."
    if n == 4:
        "Four total."
''', 'while_continue.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput) {
        runner.continueExecution();
      }

      expect(dialogue, ['Three shown.', 'Four total.']);
    });
  });
}
