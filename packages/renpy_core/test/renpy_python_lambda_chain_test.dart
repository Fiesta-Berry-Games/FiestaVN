import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
        store: <String, Object?>{},
        persistent: <String, Object?>{},
      );

  test('lambda with no args evaluates', () {
    final s = scope();
    executor.execute('f = lambda: True\nresult = f()', s);
    expect(s.read('result'), true);
  });

  test('lambda with args evaluates', () {
    final s = scope();
    executor.execute('f = lambda x, y: x + y\nresult = f(3, 4)', s);
    expect(s.read('result'), 7);
  });

  test('lambda as keyword argument', () {
    final s = scope();
    executor.execute(
      '''
def takes_fn(name, warp=None):
    if warp is not None:
        return warp()
    return False
result = takes_fn("test", warp=lambda: True)
''',
      s,
    );
    expect(s.read('result'), true);
  });

  test('lambda with default argument', () {
    final s = scope();
    executor.execute('f = lambda x, y=10: x + y\nresult = f(5)', s);
    expect(s.read('result'), 15);
  });

  test('lambda in expression evaluator', () {
    final s = scope();
    s.write('f', null);
    executor.execute('f = lambda: 42', s);
    final result = evaluator.evaluate('f()', s);
    expect(result, 42);
  });

  test('lambda with ternary body', () {
    final s = scope();
    executor.execute(
      'f = lambda x: "yes" if x else "no"\nresult = f(True)',
      s,
    );
    expect(s.read('result'), 'yes');
  });

  test('register_sl_displayable returns chainable placeholder', () {
    final s = scope();
    // Should not throw: the chained .add_property calls must all succeed.
    executor.execute(
      '''
renpy.register_sl_displayable("my_bar", None, "bar", 0, replaces=True,
    pass_context=True
    ).add_property("hovered"
    ).add_property("unhovered"
    ).add_property("value"
    )
''',
      s,
    );
  });
}
