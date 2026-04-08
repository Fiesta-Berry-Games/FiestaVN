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

  test(
    'runner assigns dotted Python namespace fields for later conditions',
    () {
      final script =
          RenPyParser().parse('''
label start:
    \$ AyyInfo.L = 2

    if AyyInfo.L == 2:
        "Assigned."
    else:
        "Missing."
''', 'python_shim.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Assigned.']);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
    },
  );

  test(
    'runner mutates dotted Python namespace fields for later conditions',
    () {
      final script =
          RenPyParser().parse('''
label start:
    \$ AyyInfo.L += 1

    if AyyInfo.L == 1:
        "Incremented."
    else:
        "Missing."
''', 'python_shim.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['Incremented.']);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
    },
  );

  test('runner recognizes harmless dotted Python method calls', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ MasterClock.AddTime(0, 0, 1)
    "Continued."
''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['Continued.']);
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

  test('runner evaluates boolean condition expressions', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ AyyInfo.L = 2
    \$ AyyNoticed1 = True

    if AyyInfo.L == 2 and (AyyNoticed1 or persistent.missing_flag):
        "Matched."
    else:
        "Missing."

    if not (AyyInfo.L == 3 or False):
        "Negated."
    else:
        "Wrong."

    if not AyyNoticed1 or AyyInfo.L == 2:
        "Python precedence."
    else:
        "Wrong precedence."
''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();
    runner.continueExecution();

    expect(dialogue, ['Matched.', 'Negated.', 'Python precedence.']);
  });

  test('runner evaluates ordered comparison conditions', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ AyyInfo.L = 2

    if AyyInfo.L >= 2:
        "Gte."
    else:
        "No gte."

    if AyyInfo.L < 3:
        "Lt."
    else:
        "No lt."

    if AyyInfo.L <= 1:
        "No lte."
    else:
        "Gt."
''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();
    runner.continueExecution();

    expect(dialogue, ['Gte.', 'Lt.', 'Gt.']);
  });

  test('runner compares parenthesized condition results', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ AyyInfo.L = 2

    if (AyyInfo.L > 1) == True:
        "Nested true."
    else:
        "Nested false."

    if (AyyInfo.L < 1) != True:
        "Nested not true."
    else:
        "Nested wrong."
    if (AyyInfo.L == 2) == True:
        "Nested equality."
    else:
        "Nested equality wrong."

''', 'python_shim.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();
    runner.continueExecution();

    expect(dialogue, ['Nested true.', 'Nested not true.', 'Nested equality.']);
  });
}
