import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  Map<String, Object?> run(String source, [Map<String, Object?>? store]) {
    final s = store ?? <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: s, persistent: <String, Object?>{}),
    );
    return s;
  }

  group('class body resilience', () {
    test('parseable methods survive when a class-level assignment fails', () {
      // The assignment `x = some_undefined_function()` will fail at exec time,
      // but the class should still register with the `greet` method intact.
      final store = run('''
class Greeter:
    x = some_undefined_function()
    def greet(self, name):
        return "hello " + name
g = Greeter()
msg = g.greet("world")
''');
      expect(store['msg'], 'hello world');
    });

    test('methods before and after a failing statement are all registered', () {
      final store = run('''
class Multi:
    def first(self):
        return 1
    x = undefined_thing()
    def second(self):
        return 2
    def third(self):
        return 3
m = Multi()
a = m.first()
b = m.second()
c = m.third()
''');
      expect(store['a'], 1);
      expect(store['b'], 2);
      expect(store['c'], 3);
    });

    test('class with only failing statements still gets registered', () {
      // Even if every body statement fails, the class itself should be created
      // (with no methods/attributes) rather than throwing.
      final store = run('''
class Empty:
    x = nonexistent_call()
    y = another_missing()
e = Empty()
''');
      expect(store.containsKey('e'), isTrue);
    });

    test('method with unsupported body is skipped but class survives', () {
      // A def whose body references unknown names will parse fine but fail
      // when called. The class should still register the method -- the error
      // only surfaces at call time, not at class-definition time.
      final store = run('''
class Worker:
    def good(self):
        return 42
    def bad(self):
        return completely_unknown_builtin()
w = Worker()
g = w.good()
''');
      expect(store['g'], 42);
    });
  });
}
