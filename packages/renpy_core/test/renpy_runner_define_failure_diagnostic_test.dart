import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests that a `define`/`default` whose right-hand side cannot be
/// evaluated (e.g. an undefined class constructor) now surfaces a skip
/// diagnostic instead of silently storing the literal source string. Bindings
/// that evaluate cleanly (numbers, strings, characters) stay silent.
({List<RenPyDiagnostic> diagnostics, RenPyRunner runner}) _load(String source) {
  final script = RenPyParser().parse(source, 'define_failure.rpy').script;
  final diagnostics = <RenPyDiagnostic>[];
  final runner = RenPyRunner(script);
  // Wiring the callback flushes any diagnostics buffered during construction
  // (define/default are applied in the constructor).
  runner.onDiagnostic = diagnostics.add;
  return (diagnostics: diagnostics, runner: runner);
}

List<RenPyDiagnostic> _skipped(List<RenPyDiagnostic> diagnostics) =>
    diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();

void main() {
  group('define/default evaluation-failure diagnostics', () {
    test('default with an undefined constructor emits a diagnostic', () {
      // Pre-fix: `default broken = Broken()` silently stored the string
      // "Broken()" and emitted nothing. Post-fix: a skip diagnostic naming the
      // binding is emitted and load still completes (state not error).
      final result = _load('''
default broken = Broken()

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      final skips = _skipped(result.diagnostics);
      expect(skips, hasLength(1));
      expect(skips.single.detail, contains('broken'));
      expect(skips.single.detail, contains('Broken()'));
    });

    test('define with an undefined constructor emits a diagnostic', () {
      final result = _load('''
define widget = MissingWidget(1, 2)

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      final skips = _skipped(result.diagnostics);
      expect(skips, hasLength(1));
      expect(skips.single.detail, contains('widget'));
    });

    test('plain literal default and a Character define stay silent', () {
      final result = _load('''
define e = Character("Eileen", color="#c8ffc8")
default y = 5
default name = "Alice"

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
    });
  });
}
