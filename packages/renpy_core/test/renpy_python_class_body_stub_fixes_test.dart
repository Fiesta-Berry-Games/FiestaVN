import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Interpreter-level fixes:
///  - Task 1: a class-body docstring (a bare expression statement) is ignored
///    rather than aborting the whole class definition.
///  - Task 2: `renpy.register_statement(...)` and `renpy.image(...)` are
///    recognized no-ops returning None instead of skipping.
///  - Task 3: subscript assignment to a namespaced (`config.`/`gui.`) dict
///    target auto-vivifies the map rather than skipping.
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

  group('TASK 1: class-body docstrings are ignored', () {
    test('docstring-first class still defines and instantiates', () {
      // Pre-fix: the leading docstring is an _ExpressionStatement, hits the
      // `else` in _ClassStatement.exec and throws -> the class never defines.
      final scope = newScope();
      executor.execute('''
class Q(object):
    """A quiz question."""
    def __init__(self, n):
        self.n = n
    def doubled(self):
        return self.n * 2

q = Q(5)
v = q.n
d = q.doubled()
''', scope);
      expect(scope.read('v'), 5);
      expect(scope.read('d'), 10);
    });

    test('triple-quoted multi-line docstring is ignored', () {
      final scope = newScope();
      executor.execute('''
class C(object):
    """
    Multi-line
    docstring.
    """
    def __init__(self):
        self.ok = True

c = C()
ok = c.ok
''', scope);
      expect(scope.read('ok'), isTrue);
    });

    test(
      'LTC shape: docstring-first class materializes in a comprehension',
      () {
        final scope = newScope();
        executor.execute('''
class QuizQuestion(object):
    """LearnToCodeRPG-style quiz question."""
    def __init__(self, prompt):
        self.prompt = prompt

questions = [QuizQuestion(p) for p in ["a", "b", "c"]]
count = len(questions)
first = questions[0].prompt
''', scope);
        expect(scope.read('count'), 3);
        expect(scope.read('first'), 'a');
      },
    );

    test('function-body docstring already worked (control)', () {
      final scope = newScope();
      executor.execute('''
def f(x):
    """A function docstring."""
    return x + 1

r = f(41)
''', scope);
      expect(scope.read('r'), 42);
    });

    test('genuinely-unsupported class-body statement still throws', () {
      // Fallback contract: a bare `if` at class level remains unsupported.
      expect(
        () => executor.execute('''
class Bad(object):
    if True:
        pass
''', newScope()),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });

  group('TASK 2: register_statement / image are no-ops', () {
    test('renpy.register_statement(...) returns None without skipping', () {
      // Pre-fix: hits the default branch -> throws "unsupported renpy.*".
      expect(eval('renpy.register_statement("foo")'), isNull);
    });

    test('renpy.image(...) returns None without skipping', () {
      final scope = newScope();
      scope.write('x', 1);
      expect(eval('renpy.image("eileen happy", x)', scope), isNull);
    });

    test('a still-unsupported renpy.* call throws (fallback preserved)', () {
      expect(
        () => eval('renpy.totally_made_up_function()'),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });

  group('TASK 3: subscript-assign to namespaced dict targets', () {
    test('config.<map>[key] = value auto-vivifies the map', () {
      // Pre-fix: `config.self_closing_custom_text_tags` is undefined, so the
      // base evaluates the bare `config` receiver -> NameError, and the whole
      // subscript-assign skips.
      final scope = newScope();
      executor.execute('''
icon_tag = "ICON"
config.self_closing_custom_text_tags["icon"] = icon_tag
''', scope);
      final map = eval('config.self_closing_custom_text_tags', scope) as Map;
      expect(map['icon'], 'ICON');
    });

    test('config map with a tuple key works', () {
      final scope = newScope();
      executor.execute('''
config.font_replacement_map[("a", "b")] = ("c", "d")
''', scope);
      final map = eval('config.font_replacement_map', scope) as Map;
      // Tuples are backed by Dart Lists (identity-keyed in a Map), so look the
      // entry up via the stored key rather than a freshly-built equal list.
      expect(map.length, 1);
      expect(map.keys.single, ['a', 'b']);
      expect(map.values.single, ['c', 'd']);
    });

    test('an existing scoped map is mutated, not replaced', () {
      final scope = newScope();
      executor.execute('''
config.tags = {"keep": 1}
config.tags["added"] = 2
''', scope);
      final map = eval('config.tags', scope) as Map;
      expect(map['keep'], 1);
      expect(map['added'], 2);
    });
  });
}
