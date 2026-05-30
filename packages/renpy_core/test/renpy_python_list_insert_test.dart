import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Coverage for `list.insert(i, x)` matching Python's clamping index semantics.
///
/// Python's `list.insert` NEVER raises for an out-of-range index - it clamps:
///   * `i >= len`  -> append at end
///   * `i < 0`     -> effective index is `max(0, len + i)`
///   * otherwise   -> insert at `i`
///
/// Dart's `List.insert` throws a `RangeError` for `i > len` or `i < 0`, which
/// (before the fix) escaped as an unguarded crash / skipped definition. This
/// cascade is what emptied LearnToCodeRPG's quiz lists: `QuizQuestion.__init__`
/// does `choices.insert(renpy.random.randint(0, len(false) + 1), ...)`, where
/// `randint` can return `len + 1` (out of range).
void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope mk(Map<String, Object?> store) =>
      RenPyMapScope(store: store, persistent: <String, Object?>{});

  group('list.insert clamps out-of-range indices like Python', () {
    test('past-end index appends instead of throwing RangeError', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1]', scope);
      executor.execute('a.insert(5, 99)', scope);
      expect(evaluator.evaluate('a', scope), [1, 99]);
    });

    test('exactly-at-length index appends', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1, 2, 3]', scope);
      executor.execute('a.insert(3, 4)', scope);
      expect(evaluator.evaluate('a', scope), [1, 2, 3, 4]);
    });

    test('negative index inserts before the last element', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1, 2]', scope);
      executor.execute('a.insert(-1, 9)', scope);
      expect(evaluator.evaluate('a', scope), [1, 9, 2]);
    });

    test('negative-too-far index clamps to 0 (prepend)', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1, 2]', scope);
      executor.execute('a.insert(-100, 9)', scope);
      expect(evaluator.evaluate('a', scope), [9, 1, 2]);
    });

    test('in-range insert is unchanged', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1, 3]', scope);
      executor.execute('a.insert(1, 2)', scope);
      expect(evaluator.evaluate('a', scope), [1, 2, 3]);
    });

    test('insert into empty list at any index appends', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = []', scope);
      executor.execute('a.insert(7, 1)', scope);
      expect(evaluator.evaluate('a', scope), [1]);
    });
  });

  group('LearnToCodeRPG QuizQuestion shape materializes fully', () {
    test(
      'class whose __init__ inserts past-end, built in a list comprehension',
      () {
        final store = <String, Object?>{};
        final scope = mk(store);
        // Mirrors QuizQuestion.__init__ doing an out-of-range insert; before
        // the fix the RangeError aborted the whole comprehension and left an
        // empty list.
        executor.execute('''
class QuizQuestion:
    def __init__(self, n):
        self.choices = [n, n + 1]
        self.choices.insert(len(self.choices) + 1, n + 2)
''', scope);
        executor.execute(
          'trivia_questions = [QuizQuestion(i) for i in range(4)]',
          scope,
        );

        // All four constructions succeed - no skipped/empty list.
        expect(evaluator.evaluate('len(trivia_questions)', scope), 4);
        // Each instance got its out-of-range insert appended.
        expect(evaluator.evaluate('trivia_questions[0].choices', scope), [
          0,
          1,
          2,
        ]);
        expect(evaluator.evaluate('trivia_questions[3].choices', scope), [
          3,
          4,
          5,
        ]);
      },
    );
  });

  group('list.pop is graceful (no Dart RangeError escapes)', () {
    test('pop() removes last; pop(-1) removes last', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1, 2, 3]', scope);
      expect(evaluator.evaluate('a.pop()', scope), 3);
      expect(evaluator.evaluate('a.pop(-1)', scope), 2);
      expect(evaluator.evaluate('a', scope), [1]);
    });

    test('pop(i) at a valid index removes that element', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [10, 20, 30]', scope);
      expect(evaluator.evaluate('a.pop(1)', scope), 20);
      expect(evaluator.evaluate('a', scope), [10, 30]);
    });

    test('out-of-range pop is a graceful RenPyPythonError, not RangeError', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('a = [1]', scope);
      expect(
        () => evaluator.evaluate('a.pop(5)', scope),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });
}
