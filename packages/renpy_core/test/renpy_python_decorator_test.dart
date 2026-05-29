import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Decorators on a `def`/`class` inside a python block are parsed and DISCARDED
/// (their call/registry semantics are irrelevant to headless logic), and the
/// function/class is defined undecorated. These tests exercise the single,
/// stacked, and dotted/called (`@gui.variant`-style) decorator forms, and
/// confirm a decorator does not abort the surrounding block.
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

  group('function decorators (discarded)', () {
    test('a single decorator is ignored and the function is callable', () {
      final store = run('''
@deco
def f(x):
    return x + 1
y = f(2)
''');
      expect(store['y'], 3);
      expect(store['f'], isNotNull);
    });

    test('stacked decorators are ignored and the function is callable', () {
      final store = run('''
@a
@b(1)
def g(x):
    return x * 2
z = g(5)
''');
      expect(store['z'], 10);
    });

    test(
      'a dotted/called decorator (@gui.variant) does not skip the block',
      () {
        // The def and the statements after it must both execute; previously the
        // `@gui.variant(...)` line aborted the whole block.
        final store = run('''
before = 1
@gui.variant("small")
def small():
    return 42
after = small()
done = 2
''');
        expect(store['before'], 1);
        expect(store['after'], 42);
        expect(store['done'], 2);
      },
    );

    test('a decorator on a class defines the bare class', () {
      final store = run('''
@register
class Widget:
    def __init__(self, n):
        self.n = n
w = Widget(7)
v = w.n
''');
      expect(store['v'], 7);
    });

    test('an unknown/garbage decorator does not abort beyond fallback', () {
      // The decorator references an undefined name; because decorators are
      // discarded without evaluation, the function is still defined and the
      // following statement runs.
      final store = run('''
@nonexistent.thing
def h():
    return "ok"
r = h()
''');
      expect(store['r'], 'ok');
    });
  });
}
