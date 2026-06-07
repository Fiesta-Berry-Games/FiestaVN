import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for forward references between `default` statements. A default's
/// right-hand side may reference a name bound by a LATER default (or by a
/// `define` processed before defaults); a bounded fixpoint retries the failed
/// defaults after each pass so a forward reference resolves instead of falling
/// back to a literal with a `skippedDefinition`. A genuinely unresolvable
/// default still ends as exactly one skip after the fixpoint, and load never
/// throws.
({List<RenPyDiagnostic> diagnostics, RenPyRunner runner}) _load(String source) {
  final script = RenPyParser().parse(source, 'default_ordering.rpy').script;
  final diagnostics = <RenPyDiagnostic>[];
  final runner = RenPyRunner(script);
  runner.onDiagnostic = diagnostics.add;
  return (diagnostics: diagnostics, runner: runner);
}

List<RenPyDiagnostic> _skipped(List<RenPyDiagnostic> diagnostics) =>
    diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();

void main() {
  group('default forward references resolve via a fixpoint', () {
    test('default referencing a later default resolves with no skip', () {
      // `a` references `b` which is defaulted LATER. The fixpoint retries
      // `a` after `b` binds, so `a == 3` and no skip.
      final result = _load('''
default a = b + 1
default b = 2

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['b'], 2);
      expect(variables['a'], 3);
    });

    test('default referencing a define resolves with no skip', () {
      // `bubble_user` defaults to `s`, which is defined via `define`.
      // Since defines are processed before defaults, `s` is already
      // available and `bubble_user` should resolve on the first pass.
      final result = _load('''
define s = 42

default bubble_user = s

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['s'], 42);
      expect(variables['bubble_user'], 42);
    });

    test('chained default forward references resolve across passes', () {
      // c -> b -> a, declared in reverse dependency order.
      final result = _load('''
default c = b + 1
default b = a + 1
default a = 1

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

    test('genuinely unresolvable default emits exactly one skip', () {
      final result = _load('''
default x = totally_undefined_name

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      final skips = _skipped(result.diagnostics);
      expect(skips, hasLength(1));
      expect(skips.single.detail, contains('x'));
    });

    test('a normal default with no forward reference is unaffected', () {
      final result = _load('''
default greeting = "hello"
default count = 7

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['greeting'], 'hello');
      expect(variables['count'], 7);
    });

    test('multiple defaults with forward refs to a single define', () {
      // Mirrors the Mysterious Messenger pattern:
      //   define s = ChatCharacter(...)
      //   default bubble_user = s
      //   default emoji_speaker = s
      final result = _load('''
define s = 99

default bubble_user = s
default emoji_speaker = s

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      final variables = result.runner.snapshot().variables;
      expect(variables['bubble_user'], 99);
      expect(variables['emoji_speaker'], 99);
    });

    test('default that is already set is not re-evaluated', () {
      // When a variable is already present (e.g. from a prior define),
      // the default should leave it alone and report success.
      final result = _load('''
define x = 10
default x = 20

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(_skipped(result.diagnostics), isEmpty);
      // The define wins; default does not overwrite.
      expect(result.runner.snapshot().variables['x'], 10);
    });
  });
}
