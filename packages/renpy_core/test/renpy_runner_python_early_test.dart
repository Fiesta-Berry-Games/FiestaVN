import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests for the `python early:` phase. Ren'Py runs a
/// `python early:` block BEFORE every `init python:` block (and thus before
/// `define`/`default`). The parser turns it into a top-level
/// RenPyPythonStatement with `isInit == true`; the runner must execute it at
/// load, at the earliest priority, so classes/values it declares exist when a
/// later `init python:` block (or define/default) depends on them.
///
/// Mirrors the LearnToCodeRPG shape where `python early:` defines a class and a
/// separate `init python:` block builds lists of instances from it.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'early.rpy').script;
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
          .where(
            (d) =>
                d.code == RenPyDiagnosticCode.skippedPython ||
                d.code == RenPyDiagnosticCode.skippedDefinition,
          )
          .toList();

  group('python early runs before init/define/default', () {
    test(
      'a class defined in python early is usable by a later init python block',
      () {
        // Pre-fix: the `python early:` body was never executed (the runner only
        // applied audio-channel registration to a top-level
        // RenPyPythonStatement), so `Q` did not exist when the `init python:`
        // block built `items`. The list/total were empty/undefined. Now the
        // early block runs first and `Q` is available.
        final result = play('''
python early:
    class Q(object):
        def __init__(self, n):
            self.n = n

init python:
    items = [Q(i) for i in range(3)]
    total = items[0].n + items[1].n + items[2].n

label start:
    "done"
''');

        expect(result.runner.state, isNot(RenPyRunnerState.error));
        expect(skipped(result.diagnostics), isEmpty);
        expect(result.runner.snapshot().variables['total'], 3);
        expect(result.runner.snapshot().variables['items'], hasLength(3));
      },
    );

    test('python early runs before a plain init python block', () {
      // The early block seeds `phase = "early"`; the plain init block appends
      // "-init". If the early block did not run first (or at all), the result
      // would not be "early-init".
      final result = play('''
python early:
    phase = "early"

init python:
    phase = phase + "-init"

label start:
    "done"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['phase'], 'early-init');
    });

    test('a broken python early body emits a skip and load completes', () {
      // Graceful fallback: an erroring early block must not abort construction;
      // it emits a skip diagnostic and the rest of load (the init block, the
      // default, the script) proceeds.
      final result = play('''
python early:
    undefined_name_qqq(1, 2, 3)

init python:
    ok = 1

default loaded = ok

label start:
    if loaded == 1:
        "Loaded anyway."
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(result.dialogue, ['Loaded anyway.']);
      expect(
        result.diagnostics.where(
          (d) => d.code == RenPyDiagnosticCode.skippedPython,
        ),
        isNotEmpty,
      );
      expect(result.runner.snapshot().variables['loaded'], 1);
    });

    test('a top-level decorated def in init python emits no spurious skip', () {
      // The runner executes an init-python body by splitting it into top-level
      // statements; a `@decorator` line must stay attached to its `def` rather
      // than being split into a lone segment that fails to parse and emits a
      // bogus skippedPython. (Mirrors AquaGuardians' top-level `@gui.variant`.)
      final result = play('''
init python:
    base = 1
    @gui.variant("small")
    def scaled(x):
        return x + base
    computed = scaled(10)

label start:
    if computed == 11:
        "ran"
''');

      expect(result.dialogue, ['ran']);
      expect(result.runner.snapshot().variables['computed'], 11);
      expect(skipped(result.diagnostics), isEmpty);
    });
  });
}
