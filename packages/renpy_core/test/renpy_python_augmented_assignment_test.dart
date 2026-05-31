import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope mk(Map<String, Object?> store) =>
      RenPyMapScope(store: store, persistent: <String, Object?>{});

  group('FIX - augmented-assignment detection is string-aware', () {
    test('plain assignment whose value contains += does not skip', () {
      final scope = mk(<String, Object?>{});
      executor.execute('data = " +="', scope);
      expect(scope.read('data'), ' +=');
    });

    test('plain assignment whose value contains -= does not skip', () {
      final scope = mk(<String, Object?>{});
      executor.execute('x = "a -= b"', scope);
      expect(scope.read('x'), 'a -= b');
    });

    test('plain assignment whose value contains //= does not skip', () {
      final scope = mk(<String, Object?>{});
      executor.execute('s = "x //= 2"', scope);
      expect(scope.read('s'), 'x //= 2');
    });

    test('plain assignment whose value contains **= does not skip', () {
      final scope = mk(<String, Object?>{});
      executor.execute('s = "y **= 3"', scope);
      expect(scope.read('s'), 'y **= 3');
    });

    test('augmented op inside brackets is ignored', () {
      final scope = mk(<String, Object?>{});
      executor.execute('items = [" +=", " -="]', scope);
      final items = scope.read('items') as List;
      expect(items, [' +=', ' -=']);
    });

    test('real augmented assignment still works at top level', () {
      final scope = mk(<String, Object?>{});
      executor.execute('x = 10', scope);
      executor.execute('x += 5', scope);
      expect(scope.read('x'), 15);
    });

    test('real //= augmented assignment works', () {
      final scope = mk(<String, Object?>{});
      executor.execute('x = 10', scope);
      executor.execute('x //= 3', scope);
      expect(scope.read('x'), 3);
    });

    test('real **= augmented assignment works', () {
      final scope = mk(<String, Object?>{});
      executor.execute('x = 2', scope);
      executor.execute('x **= 3', scope);
      expect(scope.read('x'), 8);
    });

    test('augmented assignment with string containing = on RHS', () {
      final scope = mk(<String, Object?>{});
      executor.execute('msgs = []', scope);
      executor.execute('msgs += ["a == b"]', scope);
      final msgs = scope.read('msgs') as List;
      expect(msgs, ['a == b']);
    });

    test('LearnToCodeRPG QuizQuestion pattern with += in true= kwarg', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
class QuizQuestion:
    def __init__(self, question, true, false1, false2, false3):
        self.question = question
        self.true = true
        self.false1 = false1
        self.false2 = false2
        self.false3 = false3
''', scope);
      executor.execute(
        'q = QuizQuestion(question="Which operator adds?", '
        'true=" +=", false1=" -=", false2=" *=", false3=" /=")',
        scope,
      );
      final q = scope.read('q');
      expect(q, isNotNull);
      expect(evaluator.evaluate('q.true', scope), ' +=');
      expect(evaluator.evaluate('q.false1', scope), ' -=');
    });

    test('escaped quote does not end string tracking', () {
      final scope = mk(<String, Object?>{});
      executor.execute(r'x = "hello \" += world"', scope);
      expect(scope.read('x'), r'hello " += world');
    });

    test('single-quoted string containing += does not skip', () {
      final scope = mk(<String, Object?>{});
      executor.execute("x = ' +='", scope);
      expect(scope.read('x'), ' +=');
    });

    test('real *= assignment works (not confused with **=)', () {
      final scope = mk(<String, Object?>{});
      executor.execute('x = 4', scope);
      executor.execute('x *= 3', scope);
      expect(scope.read('x'), 12);
    });

    test('real /= assignment works (not confused with //=)', () {
      final scope = mk(<String, Object?>{});
      executor.execute('x = 10.0', scope);
      executor.execute('x /= 4', scope);
      expect(scope.read('x'), 2.5);
    });

    test('subscript target with augmented op works', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"key": 1}', scope);
      executor.execute('d["key"] += 5', scope);
      expect(evaluator.evaluate('d["key"]', scope), 6);
    });
  });

  group('FIX - inline comments in bracket continuations', () {
    test('comment after arg in multi-line call does not crash', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
x = dict(
    a=1, # first
    b=2  # second
    )
''', scope);
      expect(evaluator.evaluate('x["a"]', scope), 1);
      expect(evaluator.evaluate('x["b"]', scope), 2);
    });
  });

  group('FIX - *args and **kwargs in function calls', () {
    test('**kwargs spreads a dict into keyword arguments', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
def greet(name, greeting="hello"):
    return greeting + " " + name
kw = {"greeting": "hi"}
result = greet("world", **kw)
''', scope);
      expect(scope.read('result'), 'hi world');
    });

    test('*args spreads a list into positional arguments', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
def add(a, b):
    return a + b
args = [3, 4]
result = add(*args)
''', scope);
      expect(scope.read('result'), 7);
    });

    test('**kwargs with other keyword args', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
def fn(a, b, c):
    return [a, b, c]
extra = {"c": 3}
result = fn(1, b=2, **extra)
''', scope);
      final result = scope.read('result') as List;
      expect(result, [1, 2, 3]);
    });
  });

  group('FIX - persistent.x defaults to null when unset', () {
    test('unset persistent attribute returns null', () {
      final scope = mk(<String, Object?>{});
      final result = evaluator.evaluate('persistent.unset_field', scope);
      expect(result, isNull);
    });

    test('persistent.x is None check works for init guard', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
if persistent.achievements is None:
    persistent.achievements = set()
''', scope);
      final ach = scope.read('persistent.achievements');
      expect(ach, isA<Set>());
    });

    test('persistent.achievements.add works after init', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
if persistent.achievements is None:
    persistent.achievements = set()
persistent.achievements.add("test")
''', scope);
      final ach = scope.read('persistent.achievements') as Set;
      expect(ach, contains('test'));
    });
  });

  group('FIX - parseModule error recovery', () {
    test('a bad statement does not prevent later defs from parsing', () {
      final scope = mk(<String, Object?>{});
      executor.execute('''
x = 1
config.font_replacement_map["a", True] = ("b", False)
y = 2
''', scope);
      expect(scope.read('x'), 1);
      expect(scope.read('y'), 2);
    });
  });
}
