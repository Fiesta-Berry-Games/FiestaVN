import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Bare-comma tuple subscripts: `d[a, b, c]` means `d[(a, b, c)]` (CPython).
///
/// LearnToCodeRPG's `config.font_replacement_map["...", True, False] = (...)`
/// previously failed to parse (`expected ] found ,`), skipping the statement.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  test('a two-element tuple subscript reads via a list key', () {
    final s = scope();
    executor.execute("d = {}\nd[1, 2] = 'x'", s);
    final d = s.read('d') as Map;
    expect(d.length, 1);
    expect(d.keys.single, [1, 2]);
    expect(d.values.single, 'x');
  });

  test('a three-element tuple subscript-assign auto-vivifies', () {
    final s = scope();
    executor.execute(
      'config.font_replacement_map["a", True, False] = ("b", False, False)',
      s,
    );
    final map = evaluator.evaluate('config.font_replacement_map', s) as Map;
    expect(map.length, 1);
    expect(map.keys.single, ['a', true, false]);
    expect(map.values.single, ['b', false, false]);
  });

  test('a trailing comma yields a one-element tuple key', () {
    final s = scope();
    executor.execute("d = {}\nd[5,] = 9", s);
    final d = s.read('d') as Map;
    expect(d.keys.single, [5]);
  });

  test('a plain single-element subscript still works (no regression)', () {
    final s = scope();
    executor.execute("d = {}\nd['k'] = 1\nv = d['k']", s);
    expect(s.read('v'), 1);
  });

  test('a slice subscript still works (no regression)', () {
    expect(evaluator.evaluate('[1, 2, 3, 4][1:3]', scope()), [2, 3]);
  });
}
