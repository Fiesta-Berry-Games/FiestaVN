import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Interpreter-level coverage for `obj.method(args)` calls on user-defined
/// class instances whose methods mutate `self`, exercised the way the runner
/// does it: a class defined via the statement [RenPyPythonExecutor] (an
/// `init python:` block), then instances created and method calls dispatched
/// via the expression [RenPyPythonEvaluator] (a `$ ...` statement). Both share
/// one [RenPyMapScope] so mutations must persist on the live instance.
void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope mk(Map<String, Object?> store) =>
      RenPyMapScope(store: store, persistent: <String, Object?>{});

  group('method mutation persists across evaluate() calls', () {
    test('augmented assignment on self.field (calendar.next style)', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class Calendar:
    def __init__(self):
        self.day = 1
    def next(self):
        self.day += 1
''', scope);
      store['calendar'] = evaluator.evaluate('Calendar()', scope);

      evaluator.evaluate('calendar.next()', scope);
      evaluator.evaluate('calendar.next()', scope);

      expect(evaluator.evaluate('calendar.day', scope), 3);
    });

    test('subscript assignment on self.dict (change_stats style)', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class PlayerStats:
    def __init__(self):
        self.stats = {"knowledge": 0, "charisma": 0}
    def change_stats(self, kind, amount):
        self.stats[kind] = self.stats[kind] + amount
''', scope);
      store['player_stats'] = evaluator.evaluate('PlayerStats()', scope);

      evaluator.evaluate('player_stats.change_stats("knowledge", 1)', scope);
      evaluator.evaluate('player_stats.change_stats("knowledge", 2)', scope);
      evaluator.evaluate('player_stats.change_stats("charisma", 5)', scope);

      expect(evaluator.evaluate('player_stats.stats["knowledge"]', scope), 3);
      expect(evaluator.evaluate('player_stats.stats["charisma"]', scope), 5);
    });

    test('method calling another method on self', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class PlayerStats:
    def __init__(self):
        self.stats = {"knowledge": 0}
    def change_stats(self, kind, amount):
        self.stats[kind] = self.stats[kind] + amount
        self.clamp(kind)
    def clamp(self, kind):
        if self.stats[kind] > 100:
            self.stats[kind] = 100
''', scope);
      store['player_stats'] = evaluator.evaluate('PlayerStats()', scope);

      evaluator.evaluate('player_stats.change_stats("knowledge", 250)', scope);

      expect(evaluator.evaluate('player_stats.stats["knowledge"]', scope), 100);
    });

    test('keyword arguments to a mutating method', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class Counter:
    def __init__(self):
        self.value = 0
    def bump(self, amount=1):
        self.value += amount
''', scope);
      store['c'] = evaluator.evaluate('Counter()', scope);

      evaluator.evaluate('c.bump(amount=4)', scope);
      evaluator.evaluate('c.bump()', scope);

      expect(evaluator.evaluate('c.value', scope), 5);
    });

    test('inherited mutating method runs against the subclass instance', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class Base:
    def __init__(self):
        self.n = 0
    def inc(self, by):
        self.n += by
class Derived(Base):
    pass
''', scope);
      store['d'] = evaluator.evaluate('Derived()', scope);

      evaluator.evaluate('d.inc(7)', scope);

      expect(evaluator.evaluate('d.n', scope), 7);
    });
  });

  group('store. namespace prefix', () {
    test('store.obj.method() mutates the same live instance as bare obj', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class C:
    def __init__(self):
        self.n = 0
    def inc(self):
        self.n += 1
''', scope);
      store['c'] = evaluator.evaluate('C()', scope);

      evaluator.evaluate('store.c.inc()', scope);

      // The explicit store-qualified read and the bare read see the mutation.
      expect(evaluator.evaluate('store.c.n', scope), 1);
      expect(evaluator.evaluate('c.n', scope), 1);
    });

    test('a method body reading/writing store.<global> resolves', () {
      final store = <String, Object?>{'total': 0};
      final scope = mk(store);
      executor.execute('''
class C:
    def __init__(self):
        self.n = 0
    def inc(self):
        self.n += 1
        store.total += 1
''', scope);
      store['c'] = evaluator.evaluate('C()', scope);

      evaluator.evaluate('c.inc()', scope);
      evaluator.evaluate('c.inc()', scope);

      expect(evaluator.evaluate('c.n', scope), 2);
      // The store-qualified global write landed on the live store.
      expect(store['total'], 2);
      expect(evaluator.evaluate('store.total', scope), 2);
    });

    test('store.x reads and writes alias the bare store name', () {
      final store = <String, Object?>{'points': 10};
      final scope = mk(store);

      expect(evaluator.evaluate('store.points', scope), 10);
      // store.points is the same slot as bare points.
      expect(evaluator.evaluate('store.points == points', scope), true);
    });
  });

  group('graceful fallback contract is preserved', () {
    test('calling an unknown method on an instance still throws', () {
      final store = <String, Object?>{};
      final scope = mk(store);
      executor.execute('''
class C:
    def __init__(self):
        self.n = 0
''', scope);
      store['c'] = evaluator.evaluate('C()', scope);

      expect(
        () => evaluator.evaluate('c.missing()', scope),
        throwsA(isA<RenPyPythonError>()),
      );
    });

    test('an undefined store-qualified name still throws NameError', () {
      final store = <String, Object?>{};
      final scope = mk(store);

      expect(
        () => evaluator.evaluate('store.nope.method()', scope),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });
}
