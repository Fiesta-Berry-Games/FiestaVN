import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('im module stub', () {
    test('im.matrix.tint returns a non-null value', () {
      final s = scope();
      final v = evaluator.evaluate('im.matrix.tint(0.44, 0.44, 0.75)', s);
      expect(v, isNotNull);
    });

    test('im.matrix multiplication produces a value', () {
      final s = scope();
      executor.execute(
        'tint_dark = im.matrix.tint(0.44, 0.44, 0.75) * im.matrix.brightness(-0.02)',
        s,
      );
      expect(s.read('tint_dark'), isNotNull);
    });

    test('im.Sepia returns a placeholder', () {
      final s = scope();
      final v = evaluator.evaluate("im.Sepia('test.png')", s);
      expect(v, isNotNull);
    });
  });

  group('renpy namespace attributes', () {
    test('renpy.mobile evaluates to false', () {
      final v = evaluator.evaluate('renpy.mobile', scope());
      expect(v, false);
    });

    test('if not renpy.mobile: executes the body', () {
      final s = scope();
      executor.execute('if not renpy.mobile:\n    x = 42', s);
      expect(s.read('x'), 42);
    });

    test('renpy.Displayable resolves for class inheritance', () {
      final s = scope();
      executor.execute('class MyDisp(renpy.Displayable):\n    pass', s);
      expect(s.read('MyDisp'), isNotNull);
    });

    test('renpy.display.layout.DynamicDisplayable resolves as base', () {
      final s = scope();
      executor.execute(
        'class Blink(renpy.display.layout.DynamicDisplayable):\n'
        '    def __init__(self):\n'
        '        self.x = 1',
        s,
      );
      expect(s.read('Blink'), isNotNull);
    });
  });

  group('builtin displayable/transition names', () {
    test('ImageDissolve evaluates to a placeholder', () {
      final s = scope();
      executor.execute('x = ImageDissolve("eye.png", 2, ramplen=128)', s);
      expect(s.read('x'), isNotNull);
    });

    test('Composite evaluates to a placeholder', () {
      final s = scope();
      executor.execute('x = Composite((1920, 1080), (0, 0), "bg")', s);
      expect(s.read('x'), isNotNull);
    });
  });

  group('Action base class', () {
    test('class extending Action registers', () {
      final s = scope();
      executor.execute(
        'class CopyCode(Action):\n'
        '    def __init__(self, s):\n'
        '        self.s = s',
        s,
      );
      expect(s.read('CopyCode'), isNotNull);
    });
  });

  group('MusicRoom stub', () {
    test('MusicRoom constructor and add method', () {
      final s = scope();
      executor.execute('mr = MusicRoom(fadeout=1.0)', s);
      executor.execute('mr.add("file.ogg", always_unlocked=True)', s);
      expect(s.read('mr'), isNotNull);
    });
  });

  group('renpy API additions', () {
    test('renpy.music.register_channel is a no-op', () {
      final s = scope();
      executor.execute('renpy.music.register_channel("test_channel")', s);
    });

    test('renpy.list_files returns empty list', () {
      final s = scope();
      final v = evaluator.evaluate('renpy.list_files()', s);
      expect(v, isA<List>());
      expect((v as List), isEmpty);
    });

    test('renpy.known_languages returns empty set', () {
      final s = scope();
      final v = evaluator.evaluate('renpy.known_languages()', s);
      expect(v, isA<Set>());
    });

    test('renpy.show is a no-op from Python', () {
      final s = scope();
      executor.execute('renpy.show("bg room")', s);
    });

    test('renpy.hide is a no-op from Python', () {
      final s = scope();
      executor.execute('renpy.hide("bg room")', s);
    });

    test('renpy.pause is a no-op from Python', () {
      final s = scope();
      executor.execute('renpy.pause(4.0)', s);
    });
  });

  group('class dotted base name and tolerant base', () {
    test('unknown base degrades to empty proxy', () {
      final s = scope();
      executor.execute(
        'class Foo(UnknownBase):\n    def bar(self):\n        return 1',
        s,
      );
      expect(s.read('Foo'), isNotNull);
    });

    test('dotted unknown base degrades gracefully', () {
      final s = scope();
      executor.execute('class Foo(some.deep.Module):\n    pass', s);
      expect(s.read('Foo'), isNotNull);
    });
  });

  group('class body local namespace', () {
    test('class attribute visible to later class-level expressions', () {
      final s = scope();
      executor.execute(
        'class Tags():\n'
        '    custom = ["a", "b"]\n'
        '    cancel = ["/" + t for t in custom]',
        s,
      );
      executor.execute('t = Tags()', s);
      final cancel = evaluator.evaluate('t.cancel', s);
      expect(cancel, ['/a', '/b']);
    });
  });

  group('return tuple', () {
    test('return a, b returns a list (tuple)', () {
      final s = scope();
      executor.execute('def pair():\n    return 1, 2', s);
      final v = evaluator.evaluate('pair()', s);
      expect(v, [1, 2]);
    });
  });

  group('dict spread', () {
    test('{**d1, **d2} merges dicts', () {
      final s = scope();
      executor.execute('d1 = {"a": 1, "b": 2}', s);
      executor.execute('d2 = {"b": 3, "c": 4}', s);
      executor.execute('merged = {**d1, **d2}', s);
      final merged = s.read('merged') as Map;
      expect(merged['a'], 1);
      expect(merged['b'], 3);
      expect(merged['c'], 4);
    });

    test('dict spread mixed with key-value entries', () {
      final s = scope();
      executor.execute('base = {"x": 10}', s);
      executor.execute('result = {"a": 1, **base, "b": 2}', s);
      final result = s.read('result') as Map;
      expect(result['a'], 1);
      expect(result['x'], 10);
      expect(result['b'], 2);
    });

    test('{**d} spread-only dict', () {
      final s = scope();
      executor.execute('src = {"k": "v"}', s);
      executor.execute('copy = {**src}', s);
      final copy = s.read('copy') as Map;
      expect(copy['k'], 'v');
    });
  });

  group('urllib.parse stub', () {
    test('urllib.parse.quote returns string unchanged', () {
      final s = scope();
      executor.execute('import urllib.parse', s);
      executor.execute('encoded = urllib.parse.quote("hello world")', s);
      expect(s.read('encoded'), 'hello world');
    });
  });

  group('copy.deepcopy stub', () {
    test('deepcopy of list returns new list', () {
      final s = scope();
      executor.execute('from copy import deepcopy', s);
      executor.execute('orig = [1, 2, 3]', s);
      executor.execute('dup = deepcopy(orig)', s);
      executor.execute('dup.append(4)', s);
      expect((s.read('orig') as List).length, 3);
      expect((s.read('dup') as List).length, 4);
    });

    test('deepcopy of class instance clones attributes', () {
      final s = scope();
      executor.execute('from copy import deepcopy', s);
      executor.execute(
        'class Item:\n    def __init__(self, p):\n        self.price = p',
        s,
      );
      executor.execute('a = Item(10)', s);
      executor.execute('b = deepcopy(a)', s);
      executor.execute('b.price = 20', s);
      expect(evaluator.evaluate('a.price', s), 10);
      expect(evaluator.evaluate('b.price', s), 20);
    });
  });

  group('GuiPlaceholder method calls', () {
    test('method call on GuiPlaceholder is a no-op', () {
      final s = scope();
      executor.execute('x = Transform("test")', s);
      executor.execute('x.some_method()', s);
    });
  });

  group('class body locals cleanup on error', () {
    test('locals stack is restored after class body failure', () {
      final s = scope();
      try {
        executor.execute('class Bad():\n    import os', s);
      } catch (_) {}
      // A subsequent simple statement must still work - the stale locals
      // frame must have been cleaned up.
      executor.execute('y = 99', s);
      expect(s.read('y'), 99);
    });
  });

  group('return single value (non-tuple regression)', () {
    test('return of single value works', () {
      final s = scope();
      executor.execute('def f():\n    return 42', s);
      expect(evaluator.evaluate('f()', s), 42);
    });

    test('return of expression works', () {
      final s = scope();
      executor.execute('def f(x):\n    return x + 1', s);
      expect(evaluator.evaluate('f(5)', s), 6);
    });
  });

  group('dict spread edge cases', () {
    test('spreading empty dict', () {
      final s = scope();
      executor.execute('empty = {}', s);
      executor.execute('result = {**empty}', s);
      expect(s.read('result'), isA<Map>());
      expect((s.read('result') as Map), isEmpty);
    });

    test('spreading non-dict value degrades to empty', () {
      final s = scope();
      executor.execute('x = 42', s);
      executor.execute('result = {**x}', s);
      expect(s.read('result'), isA<Map>());
      expect((s.read('result') as Map), isEmpty);
    });
  });
}
