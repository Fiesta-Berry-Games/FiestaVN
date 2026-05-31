import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Daily-loop fidelity cluster. Three independent graceful-degradation
/// fixes in the Python evaluator, driven through the same public harness the
/// existing interpreter tests use: a class/statement body via the statement
/// [RenPyPythonExecutor] (an `init python:` block) and expression evaluation /
/// `$ ...` statements via the [RenPyPythonEvaluator], sharing one
/// [RenPyMapScope].
void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope mk(Map<String, Object?> store) =>
      RenPyMapScope(store: store, persistent: <String, Object?>{});

  group('FIX A - call_screen / is_playing degrade benignly', () {
    test('renpy.call_screen inside a method lets the mutation survive', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      // Calendar.next style: mutate self, then call_screen the "next day" UI.
      // Before the fix, call_screen threw and aborted the whole statement, so
      // the foo mutation was lost. After the fix, call_screen returns null and
      // the method completes.
      executor.execute('''
class Calendar:
    def __init__(self):
        self.foo = 1
    def next(self):
        self.foo += 1
        renpy.call_screen("text_over_black_bg_screen")
''', scope);
      store['calendar'] = evaluator.evaluate('Calendar()', scope);

      // Must NOT throw, and the mutation must take effect.
      evaluator.evaluate('calendar.next()', scope);
      evaluator.evaluate('calendar.next()', scope);

      expect(evaluator.evaluate('calendar.foo', scope), 3);
    });

    test('renpy.call_screen evaluates to null in an expression', () {
      final scope = mk(<String, Object?>{});
      expect(
        evaluator.evaluate(
          'renpy.call_screen("confirm_and_share_screen")',
          scope,
        ),
        isNull,
      );
    });

    test('renpy.sound.is_playing() returns False in an expression', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('x = (not renpy.sound.is_playing())', scope);
      expect(store['x'], isTrue);
    });

    test('renpy.music.is_playing() returns False', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('renpy.music.is_playing()', scope), isFalse);
    });
  });

  group('FIX B - set algebra in binary operators', () {
    test('set difference (-) returns elements of a not in b', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('r = list({1, 2, 3} - {2})', scope);
      final r = store['r'] as List;
      expect(r.toSet(), {1, 3});
    });

    test('set symmetric difference (^)', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('r = {1, 2} ^ {2, 3}', scope);
      expect(store['r'], {1, 3});
    });

    test('operands are unchanged by - and ^', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = {1, 2, 3}', scope);
      executor.execute('b = {2}', scope);
      executor.execute('d = a - b', scope);
      executor.execute('s = a ^ b', scope);
      // Operands unchanged.
      expect(store['a'], {1, 2, 3});
      expect(store['b'], {2});
      expect(store['d'], {1, 3});
      expect(store['s'], {1, 3});
    });

    test('union (|) and intersection (&) for sets still work', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('u = {1, 2} | {2, 3}', scope);
      executor.execute('i = {1, 2, 3} & {2, 3, 4}', scope);
      expect(store['u'], {1, 2, 3});
      expect(store['i'], {2, 3});
    });
  });

  group('FIX C - collection-literal per-element degradation', () {
    test('a bad list element (1/0) is dropped, good ones kept', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('xs = [1, 1 / 0, 3]', scope);
      final xs = store['xs'];
      expect(xs, isA<List>());
      expect(xs, [1, 3]);
    });

    test('a bad set element is dropped, good ones kept', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('s = {1, 1 / 0, 3}', scope);
      expect(store['s'], isA<Set>());
      expect(store['s'], {1, 3});
    });

    test('a dict entry with a bad value is dropped, good entries kept', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('d = {"a": 1, "b": 1 / 0, "c": 3}', scope);
      expect(store['d'], isA<Map>());
      expect(store['d'], {'a': 1, 'c': 3});
    });

    test('a dict entry with a bad key is dropped, good entries kept', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('d = {"a": 1, (1 / 0): 2, "c": 3}', scope);
      expect(store['d'], {'a': 1, 'c': 3});
    });

    test('an undefined name mid-literal is dropped', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('xs = [1, not_a_defined_name, 3]', scope);
      expect(store['xs'], [1, 3]);
    });
  });
}
