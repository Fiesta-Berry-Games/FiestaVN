import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for two best-effort evaluator builtins in renpy_python.dart:
///  - `_p(...)`: Ren'Py's paragraph/translatable-string marker. Identity on its
///    first argument so `define gui.about = _p("""...""")` stores the string.
///  - `Frame(...)`: an inert GUI displayable mirroring `Borders(...)` so
///    `define bubble.frame = Frame("img", 5, 5)` evaluates instead of being
///    skipped.
void main() {
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope scopeWith([Map<String, Object?>? store]) {
    return RenPyMapScope(
      store: store ?? <String, Object?>{},
      persistent: <String, Object?>{},
    );
  }

  Object? eval(String expression, [Map<String, Object?>? store]) {
    return evaluator.evaluate(expression, scopeWith(store));
  }

  List<RenPyDiagnostic> skippedFor(String source) {
    final script = RenPyParser().parse(source, 'p_frame.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();
  }

  group('_p paragraph/translatable marker is identity', () {
    test('_p("hello") evaluates to "hello"', () {
      expect(eval('_p("hello")'), 'hello');
    });

    test('_p of a triple-quoted multi-line string returns the string', () {
      expect(eval('_p("""line one\nline two""")'), 'line one\nline two');
    });

    test('_p with no arguments returns null without throwing', () {
      expect(eval('_p()'), isNull);
    });
  });

  group('Frame inert GUI displayable mirrors Borders', () {
    test('Frame("img", 5, 5) evaluates to a non-null value', () {
      expect(eval('Frame("img", 5, 5)'), isNotNull);
    });

    test('Frame accepts keyword args without throwing', () {
      expect(eval('Frame("img", 5, 5, tile=True)'), isNotNull);
    });
  });

  group('define via _p / Frame produces no skippedDefinition', () {
    test('define gui.about = _p("x")', () {
      final skipped = skippedFor('''
define gui.about = _p("x")

label start:
    "Done."
''');
      expect(skipped, isEmpty);
    });

    test('define bubble.frame = Frame("img", 5, 5)', () {
      final skipped = skippedFor('''
define bubble.frame = Frame("img", 5, 5)

label start:
    "Done."
''');
      expect(skipped, isEmpty);
    });
  });
}
