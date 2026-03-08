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
}
