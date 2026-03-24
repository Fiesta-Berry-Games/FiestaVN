import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner assigns a deterministic result from renpy imagemap calls', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ result = renpy.imagemap("ground.png", "selected.png", [
        (100, 100, 300, 400, "eileen"),
        (500, 100, 700, 400, "lucy")
        ])

    if result == "eileen":
        "Picked Eileen."
    elif result == "lucy":
        "Picked Lucy."
    else:
        "Picked nobody."
''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['Picked Eileen.']);
    expect(runner.state, RenPyRunnerState.waitingForInput);
  });

  test('runner treats renpy full restart as terminal completion', () {
    final script =
        RenPyParser().parse('''
label start:
    "Before restart."
    \$ renpy.full_restart()
    "After restart."
''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();

    expect(dialogue, ['Before restart.']);
    expect(runner.state, RenPyRunnerState.complete);
  });
}
