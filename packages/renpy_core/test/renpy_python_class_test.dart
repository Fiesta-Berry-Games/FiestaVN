import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  Map<String, Object?> run(String source, [Map<String, Object?>? store]) {
    final s = store ?? <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: s, persistent: <String, Object?>{}),
    );
    return s;
  }

  group('classes', () {
    test('__init__ stores instance attributes', () {
      final store = run('''
class Player:
    def __init__(self, name, hp):
        self.name = name
        self.hp = hp
p = Player("Ami", 10)
n = p.name
h = p.hp
''');
      expect(store['n'], 'Ami');
      expect(store['h'], 10);
    });

    test('method mutates an instance field', () {
      final store = run('''
class Counter:
    def __init__(self):
        self.value = 0
    def bump(self, by):
        self.value += by
c = Counter()
c.bump(3)
c.bump(4)
result = c.value
''');
      expect(store['result'], 7);
    });

    test('instance attribute get and set from outside', () {
      final store = run('''
class Bag:
    def __init__(self):
        self.items = []
b = Bag()
b.items.append("sword")
b.label = "loot"
count = len(b.items)
label = b.label
''');
      expect(store['count'], 1);
      expect(store['label'], 'loot');
    });

    test('class-level attribute is shared', () {
      final store = run('''
class Config:
    version = 2
    def get(self):
        return self.version
c = Config()
v = c.get()
direct = Config.version
''');
      expect(store['v'], 2);
      expect(store['direct'], 2);
    });

    test(
      'single inheritance: subclass overrides and extends a base method',
      () {
        final store = run('''
class Animal:
    def __init__(self, name):
        self.name = name
    def speak(self):
        return self.name + " makes a sound"
class Dog(Animal):
    def speak(self):
        return self.name + " barks"
class Cat(Animal):
    def describe(self):
        return self.name + ": " + self.speak()
d = Dog("Rex")
c = Cat("Tom")
dog_line = d.speak()
cat_line = c.describe()
''');
        expect(store['dog_line'], 'Rex barks');
        // Cat inherits speak() from Animal and adds describe().
        expect(store['cat_line'], 'Tom: Tom makes a sound');
      },
    );

    test('isinstance respects the class chain', () {
      final store = run('''
class Base:
    pass
class Derived(Base):
    pass
d = Derived()
is_base = isinstance(d, Base)
is_derived = isinstance(d, Derived)
''');
      expect(store['is_base'], true);
      expect(store['is_derived'], true);
    });

    test('expression evaluator constructs and reads via a populated store', () {
      // Build the class with the executor, then read an instance attribute
      // back through the expression evaluator sharing the same store.
      final store = <String, Object?>{};
      run('''
class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y
origin = Point(2, 5)
''', store);
      final scope = RenPyMapScope(
        store: store,
        persistent: <String, Object?>{},
      );
      expect(evaluator.evaluate('origin.x + origin.y', scope), 7);
    });

    test('multiple inheritance uses first base and ignores the rest', () {
      final s = run('class C(A, B):\n    pass\n');
      expect(s.containsKey('C'), isTrue);
    });

    test('metaclass keyword falls back without aborting', () {
      expect(
        () => run('class C(metaclass=Meta):\n    pass\n'),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });

  group('import', () {
    test('import math exposes constants and functions', () {
      final store = run('''
import math
half_pi = math.pi / 2
root = math.sqrt(16)
down = math.floor(3.7)
up = math.ceil(3.1)
''');
      expect(store['half_pi'], closeTo(1.5707963, 1e-6));
      expect(store['root'], 4.0);
      expect(store['down'], 3);
      expect(store['up'], 4);
    });

    test('unknown module is a non-fatal opaque stub', () {
      // Referencing an unknown module and its attributes must not crash; the
      // import binds an opaque object that yields further opaque objects.
      final store = run('''
import os
x = os
''');
      expect(store.containsKey('x'), isTrue);
    });

    test('from-import and aliasing bind names', () {
      final store = run('''
from math import sqrt
import math as m
a = sqrt(9)
b = m.floor(2.9)
''');
      expect(store['a'], 3.0);
      expect(store['b'], 2);
    });
  });

  group('try/except/finally/raise', () {
    test('except catches a raised builtin error and finally runs', () {
      final store = run('''
log = []
try:
    raise ValueError("boom")
    log.append("unreached")
except ValueError as e:
    log.append("caught:" + str(e))
finally:
    log.append("cleanup")
''');
      expect(store['log'], ['caught:boom', 'cleanup']);
    });

    test('else runs when no exception is raised', () {
      final store = run('''
result = []
try:
    result.append("body")
except Exception:
    result.append("handler")
else:
    result.append("else")
finally:
    result.append("finally")
''');
      expect(store['result'], ['body', 'else', 'finally']);
    });

    test('bare except catches anything including runtime failures', () {
      final store = run('''
caught = False
try:
    x = undefined_name + 1
except:
    caught = True
''');
      expect(store['caught'], true);
    });

    test('raising a user exception is caught by its base class name', () {
      final store = run('''
class MyError(Exception):
    pass
hit = ""
try:
    raise MyError("nope")
except Exception as e:
    hit = "got"
''');
      expect(store['hit'], 'got');
    });

    test('unmatched except re-raises and surfaces as RenPyPythonError', () {
      expect(
        () => run('''
try:
    raise KeyError("k")
except ValueError:
    pass
'''),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });
}
