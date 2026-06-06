import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// `define` is sugar for `init python` at priority 0, so a define and an
/// `init python:` block at the same priority interleave by SOURCE ORDER. A name
/// bound by a define must therefore be visible to an `init python:` block that
/// FOLLOWS it (LearnToCodeRPG's `npc = annika` and
/// `register_channel(CHANNEL_RHYTHM_GAME)`), and stay invisible to one that
/// precedes it. Previously ALL init-python ran before ANY define, so a define
/// was never visible to an init-python block.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'order.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return (dialogue: dialogue, diagnostics: diagnostics, runner: runner);
  }

  List<RenPyDiagnostic> skipped(List<RenPyDiagnostic> diagnostics) => diagnostics
      .where(
        (d) =>
            d.code == RenPyDiagnosticCode.skippedPython ||
            d.code == RenPyDiagnosticCode.skippedDefinition,
      )
      .toList();

  group('define / init-python interleave by source order', () {
    test('a define before an init python block is visible inside that block',
        () {
      // Mirrors `define CHANNEL = 'c'` then a later `init python:` reading it.
      final result = play('''
define CHANNEL_RHYTHM_GAME = 'chan'

init python:
    chan = CHANNEL_RHYTHM_GAME

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['chan'], 'chan');
    });

    test('a character define before an init python block is visible (npc=annika)',
        () {
      final result = play('''
define annika = Character("Annika")

init python:
    npc = annika

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      // `npc` aliases the character; it resolves to a non-null value.
      expect(result.runner.snapshot().variables['npc'], isNotNull);
    });

    test('a define AFTER an init python block is NOT visible to that block', () {
      // Faithful one-directional ordering: the block runs before the later
      // define, so LATE is unresolved at block time and the statement skips.
      final result = play('''
init python:
    seen = LATE

define LATE = 1

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isNotEmpty);
    });

    test('python early still runs before an interleaved define + init python',
        () {
      final result = play('''
python early:
    phase = "early"

define MID = "-define"

init python:
    phase = phase + MID

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['phase'], 'early-define');
    });

    test('defines that forward-reference each other (contiguous run) resolve',
        () {
      // A contiguous run of defines is still applied via the bounded fixpoint,
      // so a forward reference between them resolves regardless of order.
      final result = play('''
define derived = base + 1
define base = 5

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['derived'], 6);
    });
  });
}
