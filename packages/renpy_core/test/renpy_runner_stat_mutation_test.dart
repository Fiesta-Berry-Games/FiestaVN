import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Runner-level regression for the #1 correctness gap: object method calls that
/// mutate state (`player_stats.change_stats(...)`, `calendar.next()`) used to be
/// emitted as `skippedPython` diagnostics and never took effect, so a later
/// `if obj.field >= N` branch read stale state and took the wrong path.
///
/// These tests only USE [RenPyRunner]; they assert the post-mutation branch is
/// taken and that no skip diagnostic is emitted. The user class is defined and
/// instantiated in a label-reachable `python:` block so the test is independent
/// of the runner's init-phase `default`/`init python` ordering (see the file
/// note at the bottom): the focus here is that the `$ obj.method(args)` call
/// dispatches and mutates the live instance.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'stat_mutation.rpy').script;
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

  test('change_stats mutates and the post-mutation branch is taken', () {
    final result = play('''
label start:
    python:
        class PlayerStats:
            def __init__(self):
                self.stats = {"knowledge": 0}
            def change_stats(self, kind, amount):
                self.stats[kind] = self.stats[kind] + amount
        player_stats = PlayerStats()
    \$ player_stats.change_stats("knowledge", 1)
    \$ player_stats.change_stats("knowledge", 2)
    if player_stats.stats["knowledge"] >= 3:
        "Knowledgeable."
    else:
        "Still learning."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Knowledgeable.']);
    expect(skipped(result.diagnostics), isEmpty);
  });

  test('calendar.next() advances the day and gates a later branch', () {
    final result = play('''
label start:
    python:
        class Calendar:
            def __init__(self):
                self.day = 1
            def next(self):
                self.day += 1
        calendar = Calendar()
    \$ calendar.next()
    \$ calendar.next()
    if calendar.day >= 3:
        "Three days in."
    else:
        "Early days."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Three days in.']);
    expect(skipped(result.diagnostics), isEmpty);
  });

  test('store-qualified method call mutates the live instance', () {
    final result = play('''
label start:
    python:
        class Wallet:
            def __init__(self):
                self.gold = 0
            def earn(self, amount):
                self.gold += amount
        wallet = Wallet()
    \$ store.wallet.earn(50)
    if wallet.gold >= 50:
        "Rich."
    else:
        "Broke."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Rich.']);
    expect(skipped(result.diagnostics), isEmpty);
  });

  test('a method that updates a store global keeps that global in sync', () {
    final result = play('''
default total_knowledge = 0

label start:
    python:
        class PlayerStats:
            def __init__(self):
                self.knowledge = 0
            def study(self, amount):
                self.knowledge += amount
                store.total_knowledge += amount
        player_stats = PlayerStats()
    \$ player_stats.study(4)
    if total_knowledge >= 4:
        "Class total updated."
    else:
        "No change."
''');

    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Class total updated.']);
    expect(skipped(result.diagnostics), isEmpty);
    expect(result.runner.pythonScope.read('total_knowledge'), 4);
  });
}
