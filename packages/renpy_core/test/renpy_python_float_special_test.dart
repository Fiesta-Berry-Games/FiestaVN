import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const evaluator = RenPyPythonEvaluator();
  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  test('float inf/nan', () {
    final s = scope();
    expect(evaluator.evaluate("float('inf')", s), double.infinity);
    expect(evaluator.evaluate("float('-inf')", s), double.negativeInfinity);
    expect((evaluator.evaluate("float('nan')", s) as double).isNaN, isTrue);
    // Case insensitive
    expect(evaluator.evaluate("float('INF')", s), double.infinity);
    expect(evaluator.evaluate("float('Nan')", s) is double, isTrue);
  });
}
