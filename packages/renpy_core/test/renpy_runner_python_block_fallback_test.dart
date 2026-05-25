import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests for the per-statement fallback inside a multi-statement
/// `python:` / `init python:` block. Before the fix a single unsupported
/// statement discarded the whole block, losing the supported statements that
/// preceded it; after the fix each top-level statement runs independently and
/// only the failing one is skipped.
({List<String> dialogue, List<RenPyDiagnostic> diagnostics, RenPyRunner runner})
_play(String source) {
  final script = RenPyParser().parse(source, 'block_fallback.rpy').script;
  final runner = RenPyRunner(script);
  final dialogue = <String>[];
  final diagnostics = <RenPyDiagnostic>[];
  runner.onDialogue = (_, text) => dialogue.add(text);
  runner.onDiagnostic = diagnostics.add;
  runner.jumpToLabel('start');
  runner.run();
  return (dialogue: dialogue, diagnostics: diagnostics, runner: runner);
}

List<RenPyDiagnostic> _skipped(List<RenPyDiagnostic> diagnostics) =>
    diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedPython)
        .toList();

void main() {
  group('multi-statement python block per-statement fallback', () {
    test('supported statement survives an unsupported sibling', () {
      // Line 1 is a supported assignment; line 2 calls an unsupported API.
      // Pre-fix: the whole block was discarded and `picked` was never set, so
      // the branch fell through to "missing". Post-fix: line 1 applies and only
      // line 2 is skipped.
      final result = _play('''
label start:
    python:
        picked = "alpha"
        renpy.totally_unsupported_op()
    if picked == "alpha":
        "got alpha"
    else:
        "missing"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(result.dialogue, contains('got alpha'));

      final skips = _skipped(result.diagnostics);
      expect(skips, hasLength(1));
      expect(skips.single.detail, contains('renpy.totally_unsupported_op'));
      expect(skips.single.detail, isNot(contains('picked')));
    });

    test('fully supported multi-line block runs with no diagnostic', () {
      final result = _play('''
label start:
    python:
        a = 2
        b = 3
        c = a + b
    if c == 5:
        "five"
    else:
        "other"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(result.dialogue, contains('five'));
      expect(_skipped(result.diagnostics), isEmpty);
    });

    test(
      'side effects before an unsupported statement are not double-applied',
      () {
        // A `+=` counter and a `list.append` precede an unsupported call. The
        // supported statements must each apply EXACTLY ONCE. A whole-block-then-
        // retry strategy would commit them during the failed whole-block attempt
        // and apply them again on the per-statement retry (count -> 2, log ->
        // [a, a]); running each statement once keeps count == 1 and log == [a].
        final result = _play('''
default count = 0
default log = []

label start:
    python:
        count += 1
        log.append("a")
        renpy.totally_unsupported_op()
    "count is [count]"
''');

        expect(result.runner.state, isNot(RenPyRunnerState.error));
        expect(result.runner.snapshot().variables['count'], 1);
        expect(result.runner.snapshot().variables['log'], ['a']);
        // Only the unsupported call is skipped.
        expect(_skipped(result.diagnostics), hasLength(1));
        expect(
          _skipped(result.diagnostics).single.detail,
          contains('renpy.totally_unsupported_op'),
        );
      },
    );

    test('compound statement body is not split across its lines', () {
      // The unsupported call lives inside an `if` body. The whole `if` is one
      // top-level statement, so it is skipped as a unit (its indented body is
      // never lifted out), while the supported assignment before it survives.
      final result = _play('''
label start:
    python:
        ok = "kept"
        if True:
            renpy.totally_unsupported_op()
    if ok == "kept":
        "kept it"
    else:
        "lost it"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(result.dialogue, contains('kept it'));
      expect(_skipped(result.diagnostics), hasLength(1));
    });
  });
}
