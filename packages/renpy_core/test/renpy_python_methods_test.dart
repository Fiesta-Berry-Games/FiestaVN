import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Coverage for string, list, and dict built-in methods added to the Python
/// evaluator: isalpha, encode (string); copy (list); copy (dict).
///
/// Also exercises pre-existing methods (join, count, strip, lstrip, rstrip,
/// isdigit, title, zfill, list.index, list.count, list.clear, list.reverse,
/// dict.pop, dict.setdefault, dict.clear) to ensure they remain correct.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope mk(Map<String, Object?> store) =>
      RenPyMapScope(store: store, persistent: <String, Object?>{});

  // ---- String methods ----

  group('str.join', () {
    test('joins a list of strings', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('", ".join(["a", "b", "c"])', scope),
          'a, b, c');
    });

    test('joins with empty separator', () {
      final scope = mk(<String, Object?>{});
      expect(
          evaluator.evaluate('"".join(["x", "y", "z"])', scope), 'xyz');
    });
  });

  group('str.count', () {
    test('counts non-overlapping occurrences', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"hello".count("l")', scope), 2);
    });

    test('returns 0 when substring not found', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"hello".count("z")', scope), 0);
    });
  });

  group('str.strip / lstrip / rstrip', () {
    test('strip removes leading and trailing whitespace', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"  hello  ".strip()', scope), 'hello');
    });

    test('lstrip removes leading whitespace', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"  hello  ".lstrip()', scope), 'hello  ');
    });

    test('rstrip removes trailing whitespace', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"  hello  ".rstrip()', scope), '  hello');
    });
  });

  group('str.isdigit', () {
    test('returns true for digit-only string', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"123".isdigit()', scope), true);
    });

    test('returns false for mixed string', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"12a".isdigit()', scope), false);
    });

    test('returns false for empty string', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"".isdigit()', scope), false);
    });
  });

  group('str.isalpha', () {
    test('returns true for alpha-only string', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"abc".isalpha()', scope), true);
    });

    test('returns false for string with digits', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"abc1".isalpha()', scope), false);
    });

    test('returns false for empty string', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"".isalpha()', scope), false);
    });

    test('returns true for uppercase letters', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"ABC".isalpha()', scope), true);
    });
  });

  group('str.title', () {
    test('capitalizes first letter of each word', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"hello world".title()', scope),
          'Hello World');
    });

    test('handles already-capitalized input', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"HELLO WORLD".title()', scope),
          'Hello World');
    });
  });

  group('str.zfill', () {
    test('pads with zeros on the left', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"42".zfill(5)', scope), '00042');
    });

    test('no padding when string is already long enough', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"12345".zfill(3)', scope), '12345');
    });
  });

  group('str.encode', () {
    test('returns the string itself (stub)', () {
      final scope = mk(<String, Object?>{});
      expect(
          evaluator.evaluate('"hello".encode("utf-8")', scope), 'hello');
    });

    test('works without arguments', () {
      final scope = mk(<String, Object?>{});
      expect(evaluator.evaluate('"hello".encode()', scope), 'hello');
    });
  });

  // ---- List methods ----

  group('list.index', () {
    test('returns the index of the first occurrence', () {
      final scope = mk(<String, Object?>{});
      executor.execute('a = [1, 2, 3, 2]', scope);
      expect(evaluator.evaluate('a.index(2)', scope), 1);
    });
  });

  group('list.count', () {
    test('counts occurrences of an element', () {
      final scope = mk(<String, Object?>{});
      executor.execute('a = [1, 2, 2, 3]', scope);
      expect(evaluator.evaluate('a.count(2)', scope), 2);
    });

    test('returns 0 when element is absent', () {
      final scope = mk(<String, Object?>{});
      executor.execute('a = [1, 2, 3]', scope);
      expect(evaluator.evaluate('a.count(9)', scope), 0);
    });
  });

  group('list.copy', () {
    test('creates a shallow copy', () {
      final scope = mk(<String, Object?>{});
      executor.execute('a = [1, 2, 3]', scope);
      executor.execute('b = a.copy()', scope);
      // b should equal a.
      expect(evaluator.evaluate('b', scope), [1, 2, 3]);
      // Mutating original should not affect copy.
      executor.execute('a.append(4)', scope);
      expect(evaluator.evaluate('a', scope), [1, 2, 3, 4]);
      expect(evaluator.evaluate('b', scope), [1, 2, 3]);
    });
  });

  group('list.clear', () {
    test('empties the list in place', () {
      final scope = mk(<String, Object?>{});
      executor.execute('a = [1, 2, 3]', scope);
      executor.execute('a.clear()', scope);
      expect(evaluator.evaluate('a', scope), <Object?>[]);
    });
  });

  group('list.reverse', () {
    test('reverses in place', () {
      final scope = mk(<String, Object?>{});
      executor.execute('a = [1, 2, 3]', scope);
      executor.execute('a.reverse()', scope);
      expect(evaluator.evaluate('a', scope), [3, 2, 1]);
    });
  });

  // ---- Dict methods ----

  group('dict.pop', () {
    test('removes and returns value for existing key', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"a": 1, "b": 2}', scope);
      expect(evaluator.evaluate('d.pop("a")', scope), 1);
      // Key should be removed.
      expect(evaluator.evaluate('"a" in d', scope), false);
    });

    test('returns default when key missing', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"a": 1}', scope);
      expect(evaluator.evaluate('d.pop("b", 99)', scope), 99);
    });
  });

  group('dict.setdefault', () {
    test('returns existing value without modifying', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"a": 1}', scope);
      expect(evaluator.evaluate('d.setdefault("a", 99)', scope), 1);
      expect(evaluator.evaluate('d["a"]', scope), 1);
    });

    test('sets and returns default when key missing', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"a": 1}', scope);
      expect(evaluator.evaluate('d.setdefault("b", 42)', scope), 42);
      expect(evaluator.evaluate('d["b"]', scope), 42);
    });
  });

  group('dict.copy', () {
    test('creates a shallow copy', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"a": 1, "b": 2}', scope);
      executor.execute('e = d.copy()', scope);
      expect(evaluator.evaluate('e["a"]', scope), 1);
      expect(evaluator.evaluate('e["b"]', scope), 2);
      // Mutating original should not affect copy.
      executor.execute('d["c"] = 3', scope);
      expect(evaluator.evaluate('"c" in d', scope), true);
      expect(evaluator.evaluate('"c" in e', scope), false);
    });
  });

  group('dict.clear', () {
    test('empties the dict in place', () {
      final scope = mk(<String, Object?>{});
      executor.execute('d = {"a": 1, "b": 2}', scope);
      executor.execute('d.clear()', scope);
      expect(evaluator.evaluate('len(d)', scope), 0);
    });
  });
}
