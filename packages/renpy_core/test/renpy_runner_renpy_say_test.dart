import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for the programmatic `renpy.say(who, what)` statement form that
/// LearnToCodeRPG uses (~52x) with two positional args and no `interact=`
/// keyword, plus the existing `interact=False` / keyword forms.
void main() {
  group('renpy.say(who, what) two positional args', () {
    test(
      'defined Character speaker emits a dialogue event and waits like a line',
      () {
        final script =
            RenPyParser().parse('''
define e = Character("Eileen", color="#c8ffc8")

label start:
    \$ renpy.say(e, "Hello.")
    "after"
''', 'renpy_say.rpy').script;
        final runner = RenPyRunner(script);
        final events = <RenPyDialogueEvent>[];
        final dialogue = <String>[];
        final diagnostics = <RenPyDiagnostic>[];

        runner.onDialogueEvent = events.add;
        runner.onDialogue = (character, text) => dialogue.add(text);
        runner.onDiagnostic = diagnostics.add;

        runner.jumpToLabel('start');
        runner.run();

        // The programmatic say emitted with the character's display name and
        // text, and execution parked (waits for input like a normal line).
        expect(events, hasLength(1));
        expect(events.first.displayName, 'Eileen');
        expect(events.first.text, 'Hello.');
        expect(events.first.color, '#c8ffc8');
        expect(runner.state, RenPyRunnerState.waitingForInput);

        // No skip diagnostic for the say statement.
        expect(
          diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
          isEmpty,
        );

        // Advancing past the line continues to the next statement.
        runner.continueExecution();
        runner.run();
        expect(dialogue.last, 'after');
      },
    );

    test('None speaker emits a narrator line', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ renpy.say(None, "Narration.")
    "after"
''', 'renpy_say_narr.rpy').script;
      final runner = RenPyRunner(script);
      final events = <RenPyDialogueEvent>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDialogueEvent = events.add;
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      expect(events, hasLength(1));
      expect(events.first.text, 'Narration.');
      expect(events.first.displayName, isNull);
      expect(events.first.characterId, isNull);
      expect(runner.state, RenPyRunnerState.waitingForInput);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
    });

    test('unresolvable text arg falls back gracefully without crashing', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ renpy.say(None, some_undefined_thing.attr.deeper)
    "after"
''', 'renpy_say_bad.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      // The runner survived (did not enter an error state) and reached the
      // next line - graceful fallback upheld.
      expect(runner.state, isNot(RenPyRunnerState.error));
    });
  });

  group('renpy.say keyword / interact forms (regression guard)', () {
    test('interact=False does not wait and continues immediately', () {
      final script =
          RenPyParser().parse('''
define e = Character("Eileen")

label start:
    \$ renpy.say(e, "Quick.", interact=False)
    "after"
''', 'renpy_say_no_interact.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      // interact=False means it does not park; both lines run in one pass.
      expect(dialogue, ['Quick.', 'after']);
    });

    test('what= keyword form still works', () {
      final script =
          RenPyParser().parse('''
define e = Character("Eileen")

label start:
    \$ renpy.say(e, what="Keyword.")
    "after"
''', 'renpy_say_what_kw.rpy').script;
      final runner = RenPyRunner(script);
      final events = <RenPyDialogueEvent>[];

      runner.onDialogueEvent = events.add;

      runner.jumpToLabel('start');
      runner.run();

      expect(events, hasLength(1));
      expect(events.first.displayName, 'Eileen');
      expect(events.first.text, 'Keyword.');
    });
  });
}
