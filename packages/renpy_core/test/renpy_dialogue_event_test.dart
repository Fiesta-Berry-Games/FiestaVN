import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner emits dialogue events with character metadata', () {
    final script =
        RenPyParser().parse('''
define s = Character(_("Sylvie"), color="#c8ffc8")

label start:
    s "Hi there!"
    "Narration."
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyDialogueEvent>[];
    final legacy = <String>[];

    runner.onDialogueEvent = events.add;
    runner.onDialogue =
        (character, text) => legacy.add('${character ?? 'Narrator'}:$text');

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();

    expect(events, [
      const RenPyDialogueEvent(
        characterId: 's',
        displayName: 'Sylvie',
        text: 'Hi there!',
        color: '#c8ffc8',
      ),
      const RenPyDialogueEvent(text: 'Narration.'),
    ]);
    expect(legacy, ['Sylvie:Hi there!', 'Narrator:Narration.']);
  });

  test('runner extends the previous dialogue event for extend statements', () {
    final script =
        RenPyParser().parse('''
define e = Character(_("Erika"), color="#99ccff")

label start:
    "First."
    extend " Second."
    e "Named."
    extend " Again."
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyDialogueEvent>[];

    runner.onDialogueEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();
    runner.continueExecution();
    runner.continueExecution();

    expect(events, [
      const RenPyDialogueEvent(text: 'First.'),
      const RenPyDialogueEvent(text: 'First. Second.'),
      const RenPyDialogueEvent(
        characterId: 'e',
        displayName: 'Erika',
        text: 'Named.',
        color: '#99ccff',
      ),
      const RenPyDialogueEvent(
        characterId: 'e',
        displayName: 'Erika',
        text: 'Named. Again.',
        color: '#99ccff',
      ),
    ]);
  });

  test('runner clears previous dialogue context for nvl clear', () {
    final script =
        RenPyParser().parse('''
label start:
    "Before."
    nvl clear
    extend "After."
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyDialogueEvent>[];

    runner.onDialogueEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();

    expect(events, [
      const RenPyDialogueEvent(text: 'Before.'),
      const RenPyDialogueEvent(text: 'After.'),
    ]);
  });

  test('runner does not wait for input after nw text tags', () {
    final script =
        RenPyParser().parse('''
label start:
    "Flash.{nw}"
    "Next."
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['Flash.{nw}', 'Next.']);
    expect(runner.state, RenPyRunnerState.waitingForInput);
  });

  test('runner falls through from one top-level label to the next', () {
    final script =
        RenPyParser().parse('''
label start:
    "First."

label next:
    "Second."
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();

    expect(dialogue, ['First.', 'Second.']);
    expect(runner.state, RenPyRunnerState.waitingForInput);
  });

  test('jump from a called label preserves the call return point', () {
    final script =
        RenPyParser().parse('''
label start:
    call setup
    "After call."

label setup:
    jump target

label target:
    return
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['After call.']);
    expect(runner.state, RenPyRunnerState.waitingForInput);
  });

  test('return inside a nested block returns to the caller', () {
    final script =
        RenPyParser().parse('''
label start:
    call setup
    "After call."

label setup:
    if True:
        return
    "Skipped."
''', 'dialogue.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['After call.']);
    expect(runner.state, RenPyRunnerState.waitingForInput);
  });
}
