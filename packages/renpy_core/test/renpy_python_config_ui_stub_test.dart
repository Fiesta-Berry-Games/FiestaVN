import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('config.screen_height / config.screen_width defaults', () {
    test('config.screen_height has a default', () {
      final s = scope();
      final result = evaluator.evaluate('config.screen_height', s);
      expect(result, isA<int>());
    });

    test('config.screen_width has a default', () {
      final s = scope();
      final result = evaluator.evaluate('config.screen_width', s);
      expect(result, isA<int>());
    });

    test('config.screen_height arithmetic works', () {
      final s = scope();
      // Seed the defaults so the evaluator sees them.
      s.write('config.screen_height', 720);
      final result = evaluator.evaluate('config.screen_height - 715', s);
      expect(result, isA<num>());
      expect(result, 5);
    });
  });

  group('ui module stub', () {
    test('ui.adjustment() evaluates', () {
      final s = scope();
      final result = evaluator.evaluate('ui.adjustment()', s);
      expect(result, isNotNull);
    });

    test('ui.unknown() evaluates to a stub', () {
      final s = scope();
      // Any unknown ui.* member resolves to an opaque stub rather than
      // throwing, matching the im module behavior.
      final result = evaluator.evaluate('ui.something', s);
      expect(result, isNotNull);
    });
  });

  group('renpy.* stubs', () {
    test('renpy.loadable returns false', () {
      final s = scope();
      final result = evaluator.evaluate("renpy.loadable('img.png')", s);
      expect(result, false);
    });

    test('renpy.get_registered_image returns null', () {
      final s = scope();
      final result = evaluator.evaluate("renpy.get_registered_image('x')", s);
      expect(result, isNull);
    });

    test('renpy.image_exists returns false', () {
      final s = scope();
      final result = evaluator.evaluate("renpy.image_exists('x')", s);
      expect(result, false);
    });

    test('renpy.retain_after_load returns null', () {
      final s = scope();
      final result = evaluator.evaluate('renpy.retain_after_load()', s);
      expect(result, isNull);
    });
  });

  group('store as a bare name', () {
    test('store.x reads a defined variable', () {
      final s = scope();
      s.write('x', 42);
      final result = evaluator.evaluate('store.x', s);
      expect(result, 42);
    });

    test('store.x reads null for an undefined variable', () {
      final s = scope();
      final result = evaluator.evaluate('store.x', s);
      expect(result, isNull);
    });

    test('store.x = value writes to the store', () {
      final s = scope();
      executor.execute('store.y = 99', s);
      expect(s.read('y'), 99);
    });
  });
}
