import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  test('bare raise inside try/except re-raises', () {
    final s = scope();
    executor.execute('''
result = "not set"
try:
    try:
        x = 1 / 0
    except:
        raise
except:
    result = "caught re-raise"
''', s);
    expect(s.read('result'), 'caught re-raise');
  });

  test('class with bare raise in method registers', () {
    final s = scope();
    executor.execute('''
class Validator:
    def validate(self, value):
        try:
            if value < 0:
                raise
        except:
            return False
        return True
v = Validator()
result = v.validate(5)
''', s);
    expect(s.read('result'), true);
  });

  test('@property with setter works', () {
    final s = scope();
    executor.execute('''
class Person:
    def __init__(self, name):
        self._name = name
    @property
    def name(self):
        return self._name
    @name.setter
    def name(self, value):
        self._name = value.upper()

p = Person("alice")
before = p.name
p.name = "bob"
after = p.name
''', s);
    expect(s.read('before'), 'alice');
    expect(s.read('after'), 'BOB');
  });

  test('__dict__ access returns instance attributes', () {
    final s = scope();
    executor.execute('''
class Obj:
    def __init__(self):
        self.x = 1
        self.y = 2
o = Obj()
result = o.__dict__['x']
''', s);
    expect(s.read('result'), 1);
  });
}
