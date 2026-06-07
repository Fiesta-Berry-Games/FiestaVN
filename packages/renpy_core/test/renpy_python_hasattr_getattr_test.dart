import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  // ---------------------------------------------------------------------------
  // hasattr
  // ---------------------------------------------------------------------------
  group('hasattr', () {
    test('on class instance with existing attribute', () {
      final s = scope();
      executor.execute('''
class Foo:
    def __init__(self):
        self.x = 1
f = Foo()
result = hasattr(f, 'x')
result2 = hasattr(f, 'missing')
''', s);
      expect(s.read('result'), true);
      expect(s.read('result2'), false);
    });

    test('on class instance with method', () {
      final s = scope();
      executor.execute('''
class Bar:
    def greet(self):
        return "hi"
b = Bar()
result = hasattr(b, 'greet')
''', s);
      expect(s.read('result'), true);
    });

    test('on class instance with class-level attribute', () {
      final s = scope();
      executor.execute('''
class Baz:
    cls_var = 42
b = Baz()
result = hasattr(b, 'cls_var')
''', s);
      expect(s.read('result'), true);
    });

    test('on dict', () {
      final s = scope();
      executor.execute('''
d = {'a': 1, 'b': 2}
result = hasattr(d, 'a')
result2 = hasattr(d, 'c')
''', s);
      expect(s.read('result'), true);
      expect(s.read('result2'), false);
    });
  });

  // ---------------------------------------------------------------------------
  // getattr
  // ---------------------------------------------------------------------------
  group('getattr', () {
    test('reads existing attribute', () {
      final s = scope();
      executor.execute('''
class Obj:
    def __init__(self):
        self.val = 99
o = Obj()
result = getattr(o, 'val')
''', s);
      expect(s.read('result'), 99);
    });

    test('returns default for missing attribute', () {
      final s = scope();
      executor.execute('''
class Obj:
    pass
o = Obj()
result = getattr(o, 'missing', 'fallback')
''', s);
      expect(s.read('result'), 'fallback');
    });

    test('throws without default for missing attribute', () {
      final s = scope();
      expect(
        () => executor.execute('''
class Obj:
    pass
o = Obj()
result = getattr(o, 'missing')
''', s),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Crop
  // ---------------------------------------------------------------------------
  group('Crop', () {
    test('evaluates as placeholder', () {
      final s = scope();
      final result = evaluator.evaluate("Crop((0, 0, 155, 155), 'img.png')", s);
      expect(result, isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // __ (double underscore translation function)
  // ---------------------------------------------------------------------------
  group('__ translation function', () {
    test('returns its argument', () {
      final s = scope();
      final result = evaluator.evaluate("__('hello')", s);
      expect(result, 'hello');
    });

    test('returns empty string for no args', () {
      final s = scope();
      final result = evaluator.evaluate('__()', s);
      expect(result, '');
    });
  });

  // ---------------------------------------------------------------------------
  // _GuiPlaceholder attribute assignment
  // ---------------------------------------------------------------------------
  group('_GuiPlaceholder attribute assignment', () {
    test('can assign and read attribute on placeholder', () {
      final s = scope();
      executor.execute('''
g = GalleryImage("cg common_1")
g.condition = "True"
result = g.condition
''', s);
      expect(s.read('result'), 'True');
    });
  });

  // ---------------------------------------------------------------------------
  // namedtuple
  // ---------------------------------------------------------------------------
  group('namedtuple', () {
    test('creates instances with field access', () {
      final s = scope();
      executor.execute('''
GameTone = namedtuple('GameTone', ['title', 'file'])
tone = GameTone("Basic", "basic.ogg")
result_title = tone.title
result_file = tone.file
''', s);
      expect(s.read('result_title'), 'Basic');
      expect(s.read('result_file'), 'basic.ogg');
    });

    test('works with string field spec', () {
      final s = scope();
      executor.execute('''
Point = namedtuple('Point', 'x y')
p = Point(3, 4)
result_x = p.x
result_y = p.y
''', s);
      expect(s.read('result_x'), 3);
      expect(s.read('result_y'), 4);
    });
  });
}
