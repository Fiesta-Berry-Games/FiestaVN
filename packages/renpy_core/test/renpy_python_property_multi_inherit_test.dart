import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
        store: <String, Object?>{},
        persistent: <String, Object?>{},
      );

  test('multiple inheritance takes first base', () {
    final s = scope();
    executor.execute('''
class Base:
    def greet(self):
        return "hello"

class Mixin:
    pass

class Child(Base, Mixin):
    pass

c = Child()
result = c.greet()
''', s);
    expect(s.read('result'), 'hello');
  });

  test('@property decorator makes method accessible as attribute', () {
    final s = scope();
    executor.execute('''
class Rect:
    def __init__(self, w, h):
        self.w = w
        self.h = h
    @property
    def area(self):
        return self.w * self.h

r = Rect(3, 4)
result = r.area
''', s);
    expect(s.read('result'), 12);
  });

  test('@property works with inheritance', () {
    final s = scope();
    executor.execute('''
class Base:
    def __init__(self):
        self._name = "base"
    @property
    def name(self):
        return self._name

class Child(Base):
    def __init__(self):
        super().__init__()
        self._name = "child"

c = Child()
result = c.name
''', s);
    expect(s.read('result'), 'child');
  });
}
