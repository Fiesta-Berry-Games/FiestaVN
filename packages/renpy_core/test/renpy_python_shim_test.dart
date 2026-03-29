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

  test('runner stores persistent assignments for later conditions', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ persistent.confession_finished = True

    if persistent.confession_finished:
        "Unlocked."
    else:
        "Locked."
''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.persistent, {'confession_finished': true});
    expect(dialogue, ['Unlocked.']);
    expect(
      diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
      isEmpty,
    );
  });

  test('runner restores persistent assignments from a shared store', () {
    final store = RenPyMemoryPersistentStore();
    final firstScript =
        RenPyParser().parse('''
label start:
    \$ persistent.confession_finished = True
    "Stored."
''', 'first.rpy').script;
    final firstRunner = RenPyRunner(firstScript, persistentStore: store);

    firstRunner.jumpToLabel('start');
    firstRunner.run();

    expect(firstRunner.persistent, {'confession_finished': true});

    final secondScript =
        RenPyParser().parse('''
label start:
    if persistent.confession_finished:
        "Restored."
    else:
        "Missing."
''', 'second.rpy').script;
    final secondRunner = RenPyRunner(secondScript, persistentStore: store);
    final dialogue = <String>[];

    secondRunner.onDialogue = (character, text) => dialogue.add(text);
    secondRunner.jumpToLabel('start');
    secondRunner.run();

    expect(secondRunner.persistent, {'confession_finished': true});
    expect(dialogue, ['Restored.']);
  });
}
