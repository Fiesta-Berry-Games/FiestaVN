import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for the `Fixed` and `InvertMatrix` inert placeholder builtins.
///
/// Both are Ren'Py displayable constructors that we don't render; they must
/// evaluate to a non-null [_GuiPlaceholder]-like value so an enclosing
/// `Achievement(...)` or `define` assignment completes instead of being
/// skipped.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope([Map<String, Object?>? store]) => RenPyMapScope(
        store: store ?? <String, Object?>{},
        persistent: <String, Object?>{},
      );

  Map<String, Object?> run(String source) {
    final store = <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: store, persistent: <String, Object?>{}),
    );
    return store;
  }

  group('Fixed placeholder', () {
    test('Fixed() with no args returns a non-null placeholder', () {
      final s = scope();
      final result = evaluator.evaluate('Fixed()', s);
      expect(result, isNotNull);
      expect(result.toString(), contains('Fixed'));
    });

    test('Fixed with child displayables returns a placeholder', () {
      final s = scope();
      final result = evaluator.evaluate(
          'Fixed(Transform("a.webp", fit="contain"), fit_first=True)', s);
      expect(result, isNotNull);
    });

    test('Fixed with multiple children and kwargs returns a placeholder', () {
      final s = scope();
      final result = evaluator.evaluate(
          'Fixed(Solid("#fff"), Crop((0,0,10,10), "x.webp"), xysize=(100,100))',
          s);
      expect(result, isNotNull);
    });
  });

  group('InvertMatrix placeholder', () {
    test('InvertMatrix(1.0) returns a non-null placeholder', () {
      final s = scope();
      final result = evaluator.evaluate('InvertMatrix(1.0)', s);
      expect(result, isNotNull);
      expect(result.toString(), contains('InvertMatrix'));
    });

    test('InvertMatrix(0.5) returns a placeholder', () {
      final s = scope();
      final result = evaluator.evaluate('InvertMatrix(0.5)', s);
      expect(result, isNotNull);
    });

    test('Transform with matrixcolor=InvertMatrix returns a placeholder', () {
      final s = scope();
      final result = evaluator.evaluate(
          'Transform("icon.webp", align=(0.5, 0.53), matrixcolor=InvertMatrix(1.0))',
          s);
      expect(result, isNotNull);
    });
  });

  group('Achievement with Fixed/InvertMatrix nested args', () {
    test('Achievement with Fixed+InvertMatrix evaluates to placeholder', () {
      final store = run('''
try_real_time = Achievement("IRL", "irl",
    "Turn on real-time mode.",
    Fixed(
        Transform("Menu.webp", fit="contain"),
        Transform("Call.webp", align=(0.5, 0.53), matrixcolor=InvertMatrix(1.0)),
        fit_first=True
    )
)
''');
      expect(store['try_real_time'], isNotNull);
    });

    test('Achievement with plain Transform still evaluates', () {
      final store = run(
          'a = Achievement("Ring", "ring", "Try calling.", Transform("icon.webp", xsize=155, fit="contain"))');
      expect(store['a'], isNotNull);
    });
  });
}
