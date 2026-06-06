import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// `config.lint_stats_callbacks` is a standard Ren'Py mutable list that games
/// extend in `init python:` (LearnToCodeRPG:
/// `config.lint_stats_callbacks.append(lint_stats_callback)`). It must be seeded
/// as an empty list so the `.append(...)` operates on a real container via the
/// scoped-name fast path instead of skipping on an unresolved `config` name.
void main() {
  ({
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'configseed.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return (diagnostics: diagnostics, runner: runner);
  }

  List<RenPyDiagnostic> skipped(List<RenPyDiagnostic> diagnostics) => diagnostics
      .where(
        (d) =>
            d.code == RenPyDiagnosticCode.skippedPython ||
            d.code == RenPyDiagnosticCode.skippedDefinition,
      )
      .toList();

  test('config.lint_stats_callbacks.append works without a define', () {
    final result = play('''
init python:
    def cb():
        return 1
    config.lint_stats_callbacks.append(cb)
    n = len(config.lint_stats_callbacks)

label start:
    "done"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(skipped(result.diagnostics), isEmpty);
    expect(result.runner.snapshot().variables['n'], 1);
  });
}
