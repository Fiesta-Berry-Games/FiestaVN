import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('A1: runner uses the Python expression evaluator', () {
    test('\$ n = len(items) feeds a later condition', () {
      final script =
          RenPyParser().parse('''
default items = [1, 2, 3]

label start:
    \$ n = len(items)
    if n > 2:
        "Plenty."
    else:
        "Few."
''', 'len.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.variableValue('n'), 3);
      expect(dialogue, ['Plenty.']);
    });

    test('\$ items.append(x) mutation changes later behavior', () {
      final script =
          RenPyParser().parse('''
default items = [1, 2]

label start:
    \$ items.append(3)
    \$ items.append(4)
    if len(items) == 4:
        "Four items now."
''', 'append.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.variableValue('items'), [1, 2, 3, 4]);
      expect(dialogue, ['Four items now.']);
    });

    test('subscript in an if condition', () {
      final script =
          RenPyParser().parse('''
default scores = [9, 1, 4]

label start:
    if scores[0] > 5:
        "High first score."
    else:
        "Low first score."
''', 'subscript.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['High first score.']);
    });

    test('\$ s = "Hi {}".format(who) and a say of the formatted value', () {
      // `.format` runs through the new evaluator and is stored, then said.
      // (Square-bracket interpolation inside dialogue text is an A2/screen
      // concern and is not wired here, so the say line references `s` directly.)
      final script =
          RenPyParser().parse('''
default who = "Sam"

label start:
    \$ s = "Hi {}".format(who)
    if s == "Hi Sam":
        "Greeted Sam."
''', 'format.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.variableValue('s'), 'Hi Sam');
      expect(dialogue, ['Greeted Sam.']);
    });

    test('dict subscript drives a condition', () {
      final script =
          RenPyParser().parse('''
default stats = {"hp": 10, "mp": 3}

label start:
    if stats["hp"] >= 10:
        "Full health."
''', 'dict.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Full health.']);
    });

    test('comprehension assignment', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ evens = [x for x in range(6) if x % 2 == 0]
    if len(evens) == 3:
        "Three evens."
''', 'comp.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.variableValue('evens'), [0, 2, 4]);
      expect(dialogue, ['Three evens.']);
    });

    test('unsupported expression falls back without regressing', () {
      // `jump expression` resolves a label name; a bare unknown name must still
      // resolve to its string form via the legacy fallback path.
      final script =
          RenPyParser().parse('''
label start:
    \$ destination = "chapter_two"
    jump expression destination

label chapter_two:
    "Arrived."
''', 'fallback.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Arrived.']);
    });

    test('a malformed builtin call degrades instead of aborting the script', () {
      // `range("oops")` parses but fails at evaluation with a Dart type error.
      // That must be normalized to a RenPyPythonError so the runner falls back
      // rather than entering a fatal error state.
      final script =
          RenPyParser().parse('''
label start:
    \$ x = range("oops")
    "Survived."
''', 'badcall.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.state, isNot(RenPyRunnerState.error));
      expect(dialogue, ['Survived.']);
    });
  });
}

extension on RenPyRunner {
  dynamic variableValue(String name) {
    final snapshot = this.snapshot();
    return snapshot.variables[name];
  }
}
