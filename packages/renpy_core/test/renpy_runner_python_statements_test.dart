import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'statements.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return (dialogue: dialogue, diagnostics: diagnostics, runner: runner);
  }

  List<RenPyDiagnostic> skipped(List<RenPyDiagnostic> diagnostics) =>
      diagnostics
          .where((d) => d.code == RenPyDiagnosticCode.skippedPython)
          .toList();

  test('multi-line python block loops and mutates the store', () {
    final result = play('''
default scores = [3, 4, 5]

label start:
    python:
        total = 0
        for s in scores:
            total += s
        if total > 10:
            verdict = "high"
        else:
            verdict = "low"
    if verdict == "high":
        "Score is high."
    else:
        "Score is low."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Score is high.']);
    expect(skipped(result.diagnostics), isEmpty);
    expect(result.runner.variableValue('total'), 12);
    expect(result.runner.variableValue('verdict'), 'high');
  });

  test('dollar subscript assignment changes later behavior', () {
    final result = play('''
default inventory = {"potions": 0}

label start:
    \$ inventory["potions"] = 3
    if inventory["potions"] >= 3:
        "Stocked up."
    else:
        "Empty handed."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Stocked up.']);
    expect(skipped(result.diagnostics), isEmpty);
  });

  test('def in a python block is callable from \$ and from an if', () {
    final result = play('''
label start:
    python:
        def bonus(x):
            return x * 2
        points = bonus(10)
    \$ points = bonus(points)
    if bonus(points) > 50:
        "Big bonus."
    else:
        "Small bonus."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Big bonus.']);
    expect(skipped(result.diagnostics), isEmpty);
    expect(result.runner.variableValue('points'), 40);
  });

  test('for/while with break and continue inside a block', () {
    final result = play('''
label start:
    python:
        kept = []
        for n in range(10):
            if n % 2 == 0:
                continue
            if n > 7:
                break
            kept.append(n)
        i = 0
        while True:
            i += 1
            if i >= 3:
                break
    if kept == [1, 3, 5, 7] and i == 3:
        "Loops worked."
    else:
        "Loops broke."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Loops worked.']);
    expect(skipped(result.diagnostics), isEmpty);
    expect(result.runner.variableValue('i'), 3);
    expect(result.runner.variableValue('kept'), [1, 3, 5, 7]);
  });

  test('stat-tracking function persists state across calls', () {
    final result = play('''
label start:
    python:
        hp = 100
        def damage(amount):
            global hp
            hp -= amount
        damage(30)
        damage(20)
    if hp == 50:
        "Wounded."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Wounded.']);
    expect(result.runner.variableValue('hp'), 50);
  });

  test('class block executes and constructs instances', () {
    final result = play('''
label start:
    python:
        class Enemy:
            def __init__(self, hp):
                self.hp = hp
        boss = Enemy(30)
        boss_hp = boss.hp
    "After the block."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['After the block.']);
    expect(result.runner.variableValue('boss_hp'), 30);
  });

  test('import block is non-fatal and runs its assignments', () {
    final result = play('''
label start:
    python:
        import os
        x = 1
    "Survived."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Survived.']);
    // The block executed: the import is a non-fatal stub and the assignment
    // took effect.
    expect(result.runner.variableValue('x'), 1);
  });
}

extension on RenPyRunner {
  dynamic variableValue(String name) => snapshot().variables[name];
}
