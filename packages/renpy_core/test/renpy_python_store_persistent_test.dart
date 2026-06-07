// Tests for `store.persistent.x` read/write aliasing the persistent namespace.
//
// RenPy exposes `store.persistent` as an alias for the persistent namespace, so
// `store.persistent.x` and `persistent.x` must resolve to the same value.
// A prior regression produced a truthy `_BoundMethod` for unset attributes (or
// for attributes accessed via the `store.persistent.` prefix) instead of routing
// to the real persistent scope.
import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  RenPyMapScope scope({
    Map<String, Object?> store = const {},
    Map<String, Object?> persistent = const {},
  }) =>
      RenPyMapScope(
        store: Map<String, Object?>.of(store),
        persistent: Map<String, Object?>.of(persistent),
      );

  const eval = RenPyPythonEvaluator();
  const exec = RenPyPythonExecutor();

  group('store.persistent.x read', () {
    test('unset attribute reads as null (falsy)', () {
      final s = scope(persistent: {});
      final result = eval.evaluate('store.persistent.animated_backgrounds', s);
      expect(result, isNull,
          reason: 'unset store.persistent.x should be null, not a BoundMethod');
    });

    test('explicitly-false attribute reads as false (falsy)', () {
      final s = scope(persistent: {'animated_backgrounds': false});
      final result =
          eval.evaluate('store.persistent.animated_backgrounds', s);
      expect(result, equals(false));
      expect(RenPyPythonEvaluator.truthy(result), isFalse);
    });

    test('explicitly-true attribute reads as true (truthy)', () {
      final s = scope(persistent: {'testing_mode': true});
      final result = eval.evaluate('store.persistent.testing_mode', s);
      expect(result, equals(true));
      expect(RenPyPythonEvaluator.truthy(result), isTrue);
    });

    test('store.persistent.x matches bare persistent.x', () {
      final s = scope(persistent: {'flag': 42});
      final viaStore = eval.evaluate('store.persistent.flag', s);
      final viaBare = eval.evaluate('persistent.flag', s);
      expect(viaStore, equals(viaBare));
    });

    test('if store.persistent.x: is falsy when x is unset', () {
      final s = scope(persistent: {});
      // The regression: this was True (truthy BoundMethod) before the fix.
      final cond = eval.evaluate('store.persistent.animated_backgrounds', s);
      expect(RenPyPythonEvaluator.truthy(cond), isFalse,
          reason: 'if store.persistent.unset_flag: should not branch');
    });

    test('if not store.persistent.x: is truthy when x is unset', () {
      final s = scope(persistent: {});
      final cond =
          eval.evaluate('not store.persistent.animated_backgrounds', s);
      expect(RenPyPythonEvaluator.truthy(cond), isTrue);
    });
  });

  group('store.persistent.x write', () {
    test('writes are reflected in the persistent scope', () {
      final s = scope(persistent: {});
      exec.execute('store.persistent.my_flag = True', s);
      expect(s.has('persistent.my_flag'), isTrue);
      expect(s.read('persistent.my_flag'), equals(true));
    });

    test('written value is readable via both store.persistent.x and persistent.x',
        () {
      final s = scope(persistent: {});
      exec.execute('store.persistent.score = 99', s);
      final viaStore = eval.evaluate('store.persistent.score', s);
      final viaBare = eval.evaluate('persistent.score', s);
      expect(viaStore, equals(99));
      expect(viaBare, equals(99));
    });
  });

  group('regression: prior agent truthy BoundMethod bug', () {
    // The prior fix attempt caused a regression where previously-passing code
    // (store.persistent.flag that is unset) suddenly became truthy, causing
    // branches to be taken incorrectly.  These tests pin the correct behaviour.

    test('unset persistent flag does not enter if-branch', () {
      // Simulate: if store.persistent.animated_backgrounds: ... (should not enter)
      final s = scope(persistent: {});
      exec.execute('''
if store.persistent.animated_backgrounds:
    x = True
else:
    x = False
''', s);
      // If the regression is present, x would be True (BoundMethod is truthy).
      expect(eval.evaluate('x', s), equals(false));
    });

    test('explicitly-set False flag does not enter if-branch', () {
      final s = scope(persistent: {'animated_backgrounds': false});
      exec.execute('''
if store.persistent.animated_backgrounds:
    x = True
else:
    x = False
''', s);
      expect(eval.evaluate('x', s), equals(false));
    });

    test('explicitly-set True flag enters if-branch', () {
      final s = scope(persistent: {'animated_backgrounds': true});
      exec.execute('''
if store.persistent.animated_backgrounds:
    x = True
else:
    x = False
''', s);
      expect(eval.evaluate('x', s), equals(true));
    });
  });
}
