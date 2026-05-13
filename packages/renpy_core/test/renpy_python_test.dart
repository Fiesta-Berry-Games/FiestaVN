import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

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

  group('literals', () {
    test('numbers, booleans, none', () {
      expect(eval('42'), 42);
      expect(eval('3.5'), 3.5);
      expect(eval('True'), true);
      expect(eval('False'), false);
      expect(eval('None'), isNull);
      expect(eval('0x10'), 16);
    });

    test('strings and adjacent-string concatenation', () {
      expect(eval('"hello"'), 'hello');
      expect(eval('"foo" "bar"'), 'foobar');
      expect(eval(r'"line\nbreak"'), 'line\nbreak');
    });

    test('list, tuple, dict and set literals', () {
      expect(eval('[1, 2, 3]'), [1, 2, 3]);
      expect(eval('(1, 2)'), [1, 2]);
      expect(eval('{"a": 1, "b": 2}'), {'a': 1, 'b': 2});
      expect(eval('{1, 2, 2, 3}'), {1, 2, 3});
      expect(eval('[]'), <Object?>[]);
      expect(eval('{}'), <Object?, Object?>{});
    });
  });

  group('operators and precedence', () {
    test('arithmetic precedence', () {
      expect(eval('2 + 3 * 4'), 14);
      expect(eval('(2 + 3) * 4'), 20);
      expect(eval('2 ** 3 ** 2'), 512); // right associative
      expect(eval('7 // 2'), 3);
      expect(eval('7 % 3'), 1);
      expect(eval('10 / 4'), 2.5);
      expect(eval('-2 ** 2'), -4); // unary binds looser than **
    });

    test('comparisons including chained', () {
      expect(eval('1 < 2'), true);
      expect(eval('1 < 2 < 3'), true);
      expect(eval('1 < 2 > 5'), false);
      expect(eval('3 == 3'), true);
      expect(eval('"a" < "b"'), true);
    });

    test('boolean operators short-circuit and return operands', () {
      expect(eval('True and False'), false);
      expect(eval('0 or 5'), 5);
      expect(eval('not 0'), true);
      expect(eval('1 and 2'), 2);
    });

    test('membership and identity', () {
      expect(eval('2 in [1, 2, 3]'), true);
      expect(eval('5 not in [1, 2, 3]'), true);
      expect(eval('"b" in "abc"'), true);
      expect(eval('None is None'), true);
      expect(eval('1 is not None'), true);
    });

    test('ternary', () {
      expect(eval('"yes" if 1 else "no"'), 'yes');
      expect(eval('"yes" if 0 else "no"'), 'no');
    });

    test('string multiply and concat', () {
      expect(eval('"ab" * 3'), 'ababab');
      expect(eval('"a" + "b"'), 'ab');
      expect(eval('[1] + [2]'), [1, 2]);
    });
  });

  group('namespace', () {
    test('reads store variables', () {
      expect(eval('x + 1', {'x': 4}), 5);
    });

    test('reads persistent scope', () {
      final scope = RenPyMapScope(
        store: <String, Object?>{},
        persistent: <String, Object?>{'seen': true},
      );
      expect(evaluator.evaluate('persistent.seen', scope), true);
    });

    test('unknown name throws a name error for fallback', () {
      expect(() => eval('missing'), throwsA(isA<RenPyPythonNameError>()));
    });
  });

  group('subscript and slice', () {
    test('indexing', () {
      expect(
        eval('xs[0]', {
          'xs': [10, 20, 30],
        }),
        10,
      );
      expect(
        eval('xs[-1]', {
          'xs': [10, 20, 30],
        }),
        30,
      );
      expect(eval('"hello"[1]'), 'e');
      expect(
        eval('d["k"]', {
          'd': {'k': 9},
        }),
        9,
      );
    });

    test('slices', () {
      expect(
        eval('xs[1:3]', {
          'xs': [0, 1, 2, 3, 4],
        }),
        [1, 2],
      );
      expect(
        eval('xs[:2]', {
          'xs': [0, 1, 2, 3],
        }),
        [0, 1],
      );
      expect(
        eval('xs[::2]', {
          'xs': [0, 1, 2, 3, 4],
        }),
        [0, 2, 4],
      );
      expect(
        eval('xs[::-1]', {
          'xs': [1, 2, 3],
        }),
        [3, 2, 1],
      );
      expect(eval('"hello"[1:4]'), 'ell');
    });
  });

  group('builtins', () {
    test('len, range, sum, min, max, abs, round', () {
      expect(eval('len([1, 2, 3])'), 3);
      expect(eval('len("hello")'), 5);
      expect(eval('range(3)'), [0, 1, 2]);
      expect(eval('range(1, 4)'), [1, 2, 3]);
      expect(eval('sum([1, 2, 3])'), 6);
      expect(eval('min([3, 1, 2])'), 1);
      expect(eval('max(3, 1, 2)'), 3);
      expect(eval('abs(-5)'), 5);
      expect(eval('round(3.14159, 2)'), 3.14);
    });

    test('conversions', () {
      expect(eval('str(42)'), '42');
      expect(eval('int("10")'), 10);
      expect(eval('float("2.5")'), 2.5);
      expect(eval('bool([])'), false);
      expect(eval('list("ab")'), ['a', 'b']);
      expect(eval('sorted([3, 1, 2])'), [1, 2, 3]);
    });

    test('enumerate, zip, reversed, any, all', () {
      expect(eval('enumerate(["a", "b"])'), [
        [0, 'a'],
        [1, 'b'],
      ]);
      expect(eval('zip([1, 2], [3, 4])'), [
        [1, 3],
        [2, 4],
      ]);
      expect(eval('reversed([1, 2, 3])'), [3, 2, 1]);
      expect(eval('any([0, 1])'), true);
      expect(eval('all([1, 0])'), false);
    });

    test('isinstance', () {
      expect(eval('isinstance(5, int)'), true);
      expect(eval('isinstance("x", int)'), false);
      expect(eval('isinstance(5, (int, str))'), true);
    });
  });

  group('methods', () {
    test('string methods', () {
      expect(eval('"Hello".upper()'), 'HELLO');
      expect(eval('"  hi  ".strip()'), 'hi');
      expect(eval('"a,b,c".split(",")'), ['a', 'b', 'c']);
      expect(eval('",".join(["a", "b"])'), 'a,b');
      expect(eval('"abc".replace("b", "x")'), 'axc');
      expect(eval('"abc".startswith("ab")'), true);
      expect(eval('"abc".endswith("c")'), true);
      expect(eval('"abc".find("c")'), 2);
    });

    test('list mutation persists in the namespace', () {
      final store = <String, Object?>{
        'items': [1, 2],
      };
      final scope = RenPyMapScope(
        store: store,
        persistent: <String, Object?>{},
      );
      expect(evaluator.evaluate('items.append(3)', scope), isNull);
      expect(store['items'], [1, 2, 3]);
      expect(evaluator.evaluate('items.pop()', scope), 3);
      expect(store['items'], [1, 2]);
    });

    test('dict methods including mutation', () {
      final store = <String, Object?>{
        'd': {'a': 1},
      };
      final scope = RenPyMapScope(
        store: store,
        persistent: <String, Object?>{},
      );
      expect(evaluator.evaluate('d.get("a")', scope), 1);
      expect(evaluator.evaluate('d.get("z", 0)', scope), 0);
      expect(evaluator.evaluate('d.keys()', scope), ['a']);
      evaluator.evaluate('d.setdefault("b", 2)', scope);
      expect((store['d'] as Map)['b'], 2);
    });

    test('set methods including mutation', () {
      final store = <String, Object?>{
        's': {1, 2},
      };
      final scope = RenPyMapScope(
        store: store,
        persistent: <String, Object?>{},
      );
      evaluator.evaluate('s.add(3)', scope);
      expect(store['s'], {1, 2, 3});
      evaluator.evaluate('s.discard(1)', scope);
      expect(store['s'], {2, 3});
    });
  });

  group('comprehensions', () {
    test('list comprehension with filter', () {
      expect(eval('[x * 2 for x in range(4)]'), [0, 2, 4, 6]);
      expect(eval('[x for x in range(6) if x % 2 == 0]'), [0, 2, 4]);
    });

    test('dict and set comprehensions', () {
      expect(eval('{x: x * x for x in range(3)}'), {0: 0, 1: 1, 2: 4});
      expect(eval('{x % 2 for x in range(4)}'), {0, 1});
    });

    test('tuple unpacking target', () {
      expect(eval('[a + b for a, b in [(1, 2), (3, 4)]]'), [3, 7]);
    });
  });

  group('string formatting', () {
    test('.format with positional and indexed fields', () {
      expect(eval('"Hi {}".format("Sam")'), 'Hi Sam');
      expect(eval('"{0} {1} {0}".format("a", "b")'), 'a b a');
    });

    test('percent formatting', () {
      expect(eval('"Hi %s" % "Sam"'), 'Hi Sam');
      expect(eval('"%d/%d" % (3, 4)'), '3/4');
      expect(eval('"%.2f" % 3.14159'), '3.14');
      expect(eval('"%03d" % 7'), '007');
    });

    test('f-strings', () {
      expect(eval('f"x={x}"', {'x': 5}), 'x=5');
      expect(eval('f"{a}+{b}={a + b}"', {'a': 2, 'b': 3}), '2+3=5');
      expect(eval(r'f"{v:.1f}"', {'v': 3.14159}), '3.1');
    });
  });

  group('graceful failure', () {
    test('unsupported syntax throws RenPyPythonError', () {
      expect(() => eval('lambda x: x'), throwsA(isA<RenPyPythonError>()));
      expect(() => eval('1 +'), throwsA(isA<RenPyPythonError>()));
      expect(() => eval('foo('), throwsA(isA<RenPyPythonError>()));
    });

    test('runtime errors surface as RenPyPythonError', () {
      expect(() => eval('1 / 0'), throwsA(isA<RenPyPythonError>()));
      expect(
        () => eval('xs[10]', {
          'xs': [1],
        }),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });

  group('statement executor', () {
    const executor = RenPyPythonExecutor();

    Map<String, Object?> run(String source, [Map<String, Object?>? store]) {
      final s = store ?? <String, Object?>{};
      executor.execute(source, scopeWith(s));
      return s;
    }

    test('plain and chained assignment', () {
      final store = run('a = 1\nb = c = a + 1');
      expect(store['a'], 1);
      expect(store['b'], 2);
      expect(store['c'], 2);
    });

    test('tuple unpacking and swap', () {
      final store = run('a, b = 1, 2\na, b = b, a');
      expect(store['a'], 2);
      expect(store['b'], 1);
    });

    test('augmented assignment on subscript and attribute targets', () {
      final store = run('d["n"] += 5\nlst[0] *= 3', {
        'd': <Object?, Object?>{'n': 10},
        'lst': [4, 5],
      });
      expect((store['d'] as Map)['n'], 15);
      expect((store['lst'] as List)[0], 12);
    });

    test('for with tuple unpack and accumulation', () {
      final store = run(
        '''
total = 0
for k, v in pairs:
    total += v
''',
        {
          'pairs': [
            ['a', 1],
            ['b', 2],
            ['c', 3],
          ],
        },
      );
      expect(store['total'], 6);
    });

    test('for ... else runs when no break', () {
      final store = run('''
found = False
for x in [1, 2, 3]:
    if x == 9:
        found = True
        break
else:
    found = None
''');
      expect(store['found'], isNull);
    });

    test('while with break and continue', () {
      final store = run('''
i = 0
acc = 0
while i < 10:
    i += 1
    if i % 2 == 0:
        continue
    if i > 7:
        break
    acc += i
''');
      expect(store['acc'], 1 + 3 + 5 + 7);
    });

    test('if/elif/else chains', () {
      final store = run(
        '''
if n > 10:
    bucket = "big"
elif n > 5:
    bucket = "mid"
else:
    bucket = "small"
''',
        {'n': 7},
      );
      expect(store['bucket'], 'mid');
    });

    test('def with defaults, closure and recursion-free call', () {
      final store = run('''
def scaled(x, factor=2):
    return x * factor
a = scaled(5)
b = scaled(5, 3)
''');
      expect(store['a'], 10);
      expect(store['b'], 15);
    });

    test('def reads store globals and global writes back', () {
      final store = run('''
gold = 0
def earn(amount):
    global gold
    gold += amount
earn(5)
earn(7)
''');
      expect(store['gold'], 12);
    });

    test('function locals do not leak into the store', () {
      final store = run('''
def helper():
    temp = 99
    return temp
result = helper()
''');
      expect(store['result'], 99);
      expect(store.containsKey('temp'), isFalse);
    });

    test('star-args and kwargs collectors', () {
      final store = run('''
def collect(first, *rest, **opts):
    return [first, rest, opts]
out = collect(1, 2, 3, mode="x")
''');
      final out = store['out'] as List;
      expect(out[0], 1);
      expect(out[1], [2, 3]);
      expect(out[2], {'mode': 'x'});
    });

    test('pass and semicolon-joined statements', () {
      final store = run('pass\na = 1; b = 2');
      expect(store['a'], 1);
      expect(store['b'], 2);
    });

    test('persistent writes flow through the scope', () {
      final persistent = <String, Object?>{};
      executor.execute(
        'persistent.coins = 3\npersistent.coins += 4',
        RenPyMapScope(store: <String, Object?>{}, persistent: persistent),
      );
      expect(persistent['coins'], 7);
    });

    test('unsupported constructs raise RenPyPythonError', () {
      expect(
        () => run('with open("x") as f:\n    pass\n'),
        throwsA(isA<RenPyPythonError>()),
      );
      expect(() => run('del a\n'), throwsA(isA<RenPyPythonError>()));
      expect(() => run('yield 1\n'), throwsA(isA<RenPyPythonError>()));
      expect(() => run('assert x == 1\n'), throwsA(isA<RenPyPythonError>()));
    });
  });
}
