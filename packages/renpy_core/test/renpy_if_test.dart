import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner selects elif blocks using equality conditions', () {
    final script =
        RenPyParser().parse('''
default mood = "sad"

label start:
    if mood == "happy":
        "Happy."
    elif mood == "sad":
        "Sad."
    else:
        "Other."
''', 'if.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['Sad.']);
    expect(runner.state, RenPyRunnerState.waitingForInput);
  });
}
