import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('renpy version stubs', () {
    test('renpy.version_only evaluates to a string', () {
      final s = scope();
      final result = evaluator.evaluate('renpy.version_only', s);
      expect(result, isA<String>());
    });

    test('renpy.version_only.startswith("8") returns true', () {
      final s = scope();
      final result =
          evaluator.evaluate('renpy.version_only.startswith("8")', s);
      expect(result, true);
    });

    test('renpy.version_string evaluates to a string', () {
      final s = scope();
      final result = evaluator.evaluate('renpy.version_string', s);
      expect(result, isA<String>());
      expect((result as String).contains('Ren'), isTrue);
    });

    test('renpy.version_tuple evaluates to a list', () {
      final s = scope();
      final result = evaluator.evaluate('renpy.version_tuple', s);
      expect(result, isA<List>());
      expect((result as List).first, 8);
    });
  });

  group('menu builtin', () {
    test('menu is defined and resolves without error', () {
      final s = scope();
      final result = evaluator.evaluate('menu', s);
      expect(result, isNotNull);
    });

    test('renpy_menu = menu assignment works', () {
      final s = scope();
      final executor = const RenPyPythonExecutor();
      executor.execute('renpy_menu = menu', s);
      final result = s.read('renpy_menu');
      expect(result, isNotNull);
    });
  });

  group('config.pygame_events', () {
    test('config.pygame_events defaults to a list', () {
      final s = scope();
      final result = evaluator.evaluate('config.pygame_events', s);
      expect(result, isA<List>());
    });

    test('config.pygame_events supports extend', () {
      final s = scope();
      final executor = const RenPyPythonExecutor();
      executor.execute('config.pygame_events.extend([1, 2])', s);
      final result = evaluator.evaluate('config.pygame_events', s);
      expect(result, isA<List>());
      expect((result as List).length, 2);
    });
  });
}
