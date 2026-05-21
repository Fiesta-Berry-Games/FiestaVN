import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Interpreter-level tests (no runner/parser) for the build/gui/variant config
/// no-op surface and the `renpy.random.choice(seq=...)` keyword form.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope newScope([Map<String, Object?>? store]) {
    return RenPyMapScope(
      store: store ?? <String, Object?>{},
      persistent: <String, Object?>{},
    );
  }

  Object? eval(String expression, [RenPyMapScope? scope]) {
    return evaluator.evaluate(expression, scope ?? newScope());
  }

  group('TASK A: build/gui config calls are silent no-ops', () {
    test('build.classify returns None without throwing', () {
      // Pre-fix: `build` resolves to no name -> RenPyPythonNameError.
      expect(eval("build.classify('**~', None)"), isNull);
    });

    test('build.archive returns None without throwing', () {
      expect(eval('build.archive("x", "all")'), isNull);
    });

    test('build.documentation returns None without throwing', () {
      expect(eval("build.documentation('*.txt')"), isNull);
    });

    test('any build.<method>() is a no-op returning None', () {
      expect(eval('build.something_new(1, 2, 3)'), isNull);
      expect(eval('build.include_old_themes()'), isNull);
    });

    test('gui.init returns None without throwing', () {
      // Pre-fix: `gui.init` is a scoped name with no stored value, so it falls
      // through to evaluating the bare `gui` receiver -> NameError.
      expect(eval('gui.init(1280, 960)'), isNull);
    });

    test('a multi-line init-style block mixing directives runs clean', () {
      final scope = newScope();
      // Pre-fix: the first build/gui directive throws and aborts the block.
      executor.execute('''
gui.init(1280, 720)
build.classify('**~', None)
build.archive("archive", "all")
build.documentation('*.txt')
ok = 7
''', scope);
      expect(scope.read('ok'), 7);
    });

    test('gui namespace stays live for attribute read/write', () {
      final scope = newScope();
      // gui.init no-op must NOT clobber the gui namespace for `gui.foo`.
      executor.execute('''
gui.init(1280, 720)
gui.foo = 5
''', scope);
      expect(eval('gui.foo', scope), 5);
    });
  });

  group('TASK A: fallback contract preserved for unknown calls', () {
    test('a genuinely-unknown bare call still throws', () {
      // Must NOT become a no-op: the runner relies on this to emit its
      // skipped-Python diagnostic and fall back gracefully.
      expect(() => eval('frobnicate()'), throwsA(isA<RenPyPythonError>()));
    });

    test('an unknown dotted method call still throws', () {
      expect(() => eval('mystery.method()'), throwsA(isA<RenPyPythonError>()));
    });
  });

  group('TASK A: renpy.variant is falsy', () {
    test('renpy.variant("touch") is falsy', () {
      expect(
        RenPyPythonEvaluator.truthy(eval('renpy.variant("touch")')),
        isFalse,
      );
    });

    test('renpy.variant("small") is falsy', () {
      expect(
        RenPyPythonEvaluator.truthy(eval('renpy.variant("small")')),
        isFalse,
      );
    });
  });

  group('TASK B: renpy.random.choice accepts seq= keyword', () {
    test('seq= keyword form returns an element of the list', () {
      // Pre-fix: keywords were ignored and positional was empty -> throw.
      final result = eval('renpy.random.choice(seq=[10, 20, 30])');
      expect([10, 20, 30], contains(result));
    });

    test('positional form still works', () {
      final result = eval('renpy.random.choice([10, 20, 30])');
      expect([10, 20, 30], contains(result));
    });
  });
}
