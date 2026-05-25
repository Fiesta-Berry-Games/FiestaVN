import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for two evaluator fixes in renpy_python.dart:
///  - Fix 1: `u'...'` / `U'...'` string-literal prefixes lex as plain strings,
///    so hex colors like `u'#002ead'` evaluate correctly (and a bare name that
///    merely starts with `u` still resolves as a name).
///  - Fix 2: a best-effort `Borders(...)` builtin that returns an inert, opaque
///    marker so `define gui.x = Borders(...)` evaluates instead of being
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

  group('Fix 1: u/U string prefix', () {
    test("u'#002ead' evaluates to the plain string with the # preserved", () {
      expect(eval("u'#002ead'"), '#002ead');
    });

    test("U'#fff' evaluates to the plain string", () {
      expect(eval("U'#fff'"), '#fff');
    });

    test('u/U double-quoted strings also work', () {
      expect(eval('u"hello"'), 'hello');
      expect(eval('U"world"'), 'world');
    });

    test('a bare name starting with u still resolves as a name', () {
      expect(eval('username', {'username': 'ada'}), 'ada');
    });
  });

  group('Fix 2: Borders builtin', () {
    test(
      'Borders(5, 5, 5, 5) evaluates without throwing to a non-null value',
      () {
        final value = eval('Borders(5, 5, 5, 5)');
        expect(value, isNotNull);
      },
    );

    test('Borders accepts keyword args without throwing', () {
      final value = eval('Borders(5, 5, 5, 5, left=10)');
      expect(value, isNotNull);
    });
  });

  group('Fix 2: Borders via define produces no skippedDefinition', () {
    test('define gui.namebox_borders = Borders(5,5,5,5)', () {
      final script =
          RenPyParser().parse('''
define gui.namebox_borders = Borders(5, 5, 5, 5)

label start:
    "Done."
''', 'borders.rpy').script;
      final runner = RenPyRunner(script);
      final diagnostics = <RenPyDiagnostic>[];
      runner.onDiagnostic = diagnostics.add;
      runner.jumpToLabel('start');
      runner.run();

      final skipped =
          diagnostics
              .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
              .toList();
      expect(skipped, isEmpty);
    });
  });
}
