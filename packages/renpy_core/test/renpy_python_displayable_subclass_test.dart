// Tests for subclassing renpy.Displayable and single-line `if`/`else` support.
import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope newScope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('renpy.Displayable subclass', () {
    test('class extending renpy.Displayable is accepted', () {
      final scope = newScope();
      executor.execute('''
class MyDisplay(renpy.Displayable):
    def __init__(self):
        super(MyDisplay, self).__init__()
        self.value = 42
''', scope);
      executor.execute('d = MyDisplay()', scope);
      final d = scope.read('d');
      expect(d, isNotNull);
    });

    test('Tear-like class with single-line if parses and is defined', () {
      final scope = newScope();
      // Mirrors the actual Tear class structure from the game
      executor.execute(r'''
class Tear(renpy.Displayable):
    def __init__(self, number, offtimeMult, ontimeMult,
                    offsetMin, offsetMax, srf=None):
        super(Tear, self).__init__()
        self.number = number
        if not srf: self.srf = None
        else: self.srf = srf
        self.pieces = []
    def render(self, width, height, st, at):
        return None
''', scope);
      final cls = evaluator.evaluate('Tear', scope);
      expect(cls, isNotNull);
    });

    test('instance of renpy.Displayable subclass has expected attributes', () {
      final scope = newScope();
      executor.execute('''
class Widget(renpy.Displayable):
    def __init__(self, x, y):
        super(Widget, self).__init__()
        self.x = x
        self.y = y
w = Widget(10, 20)
''', scope);
      expect(evaluator.evaluate('w.x', scope), 10);
      expect(evaluator.evaluate('w.y', scope), 20);
    });
  });

  group('single-line if/else support', () {
    test('single-line if without else', () {
      final scope = newScope();
      executor.execute('''
x = 5
if x > 3: y = True
''', scope);
      expect(scope.read('y'), isTrue);
    });

    test('single-line if branch not taken', () {
      final scope = newScope();
      executor.execute('''
x = 1
y = False
if x > 3: y = True
''', scope);
      expect(scope.read('y'), isFalse);
    });

    test('single-line if with single-line else', () {
      final scope = newScope();
      executor.execute('''
srf = None
if not srf: result = "no srf"
else: result = "has srf"
''', scope);
      expect(scope.read('result'), 'no srf');
    });

    test('single-line else taken', () {
      final scope = newScope();
      executor.execute('''
srf = "something"
if not srf: result = "no srf"
else: result = "has srf"
''', scope);
      expect(scope.read('result'), 'has srf');
    });

    test('single-line if in method body', () {
      final scope = newScope();
      executor.execute('''
class Obj():
    def __init__(self, val):
        if val: self.x = val
        else: self.x = 0
o1 = Obj(7)
o2 = Obj(None)
''', scope);
      expect(evaluator.evaluate('o1.x', scope), 7);
      expect(evaluator.evaluate('o2.x', scope), 0);
    });
  });
}
