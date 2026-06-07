import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for Creator-Defined Statement (CDS) support. Games call
/// `renpy.register_statement(name, ...)` in `init python:` blocks to
/// register custom statement verbs. The runner must:
///   1. Capture the verb name during init.
///   2. Reclassify say statements whose "speaker" matches a CDS verb.
///   3. Silently skip generic statements that match a CDS verb at runtime.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'cds.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    // Drain all waiting dialogue: the runner pauses after each say line, so
    // keep resuming until it completes or no longer waits.
    while (runner.state == RenPyRunnerState.waitingForInput) {
      runner.continueExecution();
    }
    return (dialogue: dialogue, diagnostics: diagnostics, runner: runner);
  }

  test('registered CDS verb is skipped cleanly at runtime', () {
    final result = play(r'''
init python:
    renpy.register_statement("msg", parse=None, execute=None)

label start:
    "Before CDS"
    msg ja "Hello!" sser1
    "After CDS"
''');

    // The CDS line must NOT appear as dialogue.
    expect(result.dialogue, ['Before CDS', 'After CDS']);
    // No unknownStatement diagnostic for the CDS line.
    expect(
      result.diagnostics.where(
        (d) => d.code == RenPyDiagnosticCode.unknownStatement,
      ),
      isEmpty,
    );
  });

  test('multi-word CDS verb is recognised and skipped', () {
    final result = play(r'''
init python:
    renpy.register_statement("enter chatroom", parse=None, execute=None)

label start:
    "Before"
    enter chatroom ja
    "After"
''');

    expect(result.dialogue, ['Before', 'After']);
    expect(
      result.diagnostics.where(
        (d) => d.code == RenPyDiagnosticCode.unknownStatement,
      ),
      isEmpty,
    );
  });

  test('multiple CDS verbs registered in one init block', () {
    final result = play(r'''
init python:
    renpy.register_statement("msg", parse=None, execute=None)
    renpy.register_statement("award", parse=None, execute=None)
    renpy.register_statement("enter chatroom", parse=None, execute=None)

label start:
    "A"
    msg ja "Hello"
    award heart ja
    enter chatroom ja
    "B"
''');

    expect(result.dialogue, ['A', 'B']);
    expect(
      result.diagnostics.where(
        (d) => d.code == RenPyDiagnosticCode.unknownStatement,
      ),
      isEmpty,
    );
  });

  test('unregistered verb still emits unknownStatement diagnostic', () {
    final result = play(r'''
label start:
    "Before"
    somefakecommand foo bar
    "After"
''');

    expect(result.dialogue, contains('Before'));
    expect(result.dialogue, contains('After'));
    expect(
      result.diagnostics.where(
        (d) => d.code == RenPyDiagnosticCode.unknownStatement,
      ),
      isNotEmpty,
    );
  });

  test('CDS verb inside an if-branch is reclassified and skipped', () {
    final result = play(r'''
init python:
    renpy.register_statement("msg", parse=None, execute=None)

label start:
    "Start"
    if True:
        msg ja "Inside if"
    "End"
''');

    expect(result.dialogue, ['Start', 'End']);
    expect(
      result.diagnostics.where(
        (d) => d.code == RenPyDiagnosticCode.unknownStatement,
      ),
      isEmpty,
    );
  });

  test('CDS verb without quoted arg (bare token line) is skipped', () {
    // Some CDS statements have no quoted text at all, e.g. `enter chatroom`.
    final result = play(r'''
init python:
    renpy.register_statement("play buzzsfx", parse=None, execute=None)

label start:
    "Start"
    play buzzsfx
    "End"
''');

    expect(result.dialogue, ['Start', 'End']);
    expect(
      result.diagnostics.where(
        (d) => d.code == RenPyDiagnosticCode.unknownStatement,
      ),
      isEmpty,
    );
  });
}
