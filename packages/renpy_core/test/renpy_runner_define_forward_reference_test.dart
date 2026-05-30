import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for forward references between `define` statements. A define's
/// right-hand side may reference a name bound by a LATER define; a bounded
/// fixpoint retries the failed defines after each pass so a forward reference
/// resolves instead of falling back to a literal with a `skippedDefinition`.
/// A genuinely unresolvable define still ends as exactly one skip after the
/// fixpoint, and load never throws.
({List<RenPyDiagnostic> diagnostics, RenPyRunner runner}) _load(String source) {
  final script = RenPyParser().parse(source, 'define_forward.rpy').script;
  final diagnostics = <RenPyDiagnostic>[];
  final runner = RenPyRunner(script);
  // Wiring the callback flushes diagnostics buffered during construction
  // (define/default are applied in the constructor).
  runner.onDiagnostic = diagnostics.add;
  return (diagnostics: diagnostics, runner: runner);
}

List<RenPyDiagnostic> _skipped(List<RenPyDiagnostic> diagnostics) =>
    diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();

void main() {
  group('define forward references resolve via a fixpoint', () {
    test('bare-name forward reference resolves and emits no skip', () {
      // `a` references `b` which is defined LATER. Pre-fix: evaluating `b + 1`
      // before `b` exists fails -> literal fallback + skip. Post-fix: the
      // fixpoint retries `a` after `b` binds, so `a == 3` and no skip.
      final result = _load('''
define a = b + 1
define b = 2

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['b'], 2);
      expect(variables['a'], 3);
    });

    test('namespaced forward reference resolves and emits no skip', () {
      // Mirrors LearnToCodeRPG: `define config.X = gui.Y` before `gui.Y`.
      // The derived bare-name target lets the test read the resolved value
      // from snapshot().variables; the config.derived target confirms a
      // namespaced target also resolves (no skip).
      final result = _load('''
define config.derived = gui.base
define derived = gui.base
define gui.base = 5

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['derived'], 5);
    });

    test('chained forward references resolve across multiple passes', () {
      // c -> b -> a, declared in reverse dependency order. A single retry pass
      // is not enough; the bounded fixpoint converges over several passes.
      final result = _load('''
define c = b + 1
define b = a + 1
define a = 1

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['a'], 1);
      expect(variables['b'], 2);
      expect(variables['c'], 3);
    });

    test('genuinely unresolvable define emits exactly one skip', () {
      // No define ever binds `totally_undefined_name`, so the fixpoint makes no
      // progress and the define ends as one skip after a graceful, terminating
      // loop (no infinite loop).
      final result = _load('''
define x = totally_undefined_name

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      final skips = _skipped(result.diagnostics);
      expect(skips, hasLength(1));
      expect(skips.single.detail, contains('x'));
    });

    test('a normal define with no forward reference is unaffected', () {
      // Regression: a define that resolves on the first pass stays silent and
      // stores the evaluated value exactly as before.
      final result = _load('''
define greeting = "hello"
define count = 7

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['greeting'], 'hello');
      expect(variables['count'], 7);
    });

    test('the last define of a re-defined name wins despite an earlier '
        'forward reference', () {
      // Ren'Py: the textually-LAST define of a name wins. The earlier
      // `a = b + 100` is a forward reference (dead - overwritten by `a = 2`)
      // and must NOT resolve on a later pass and clobber `a`. Likewise a
      // re-defined name whose earlier define is unresolvable must not emit a
      // spurious skip - only the surviving last define matters.
      final result = _load('''
define a = b + 100
define b = 1
define a = 2

define z = totally_undefined_name
define z = 5

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      final variables = result.runner.snapshot().variables;
      expect(variables['a'], 2);
      expect(variables['z'], 5);
      expect(_skipped(result.diagnostics), isEmpty);
    });
  });
}
