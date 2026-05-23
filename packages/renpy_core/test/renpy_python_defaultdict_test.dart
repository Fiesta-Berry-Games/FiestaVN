import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  const executor = RenPyPythonExecutor();

  Map<String, Object?> run(String source, [Map<String, Object?>? store]) {
    final s = store ?? <String, Object?>{};
    executor.execute(
      source,
      RenPyMapScope(store: s, persistent: <String, Object?>{}),
    );
    return s;
  }

  group('collections.defaultdict', () {
    test('defaultdict(int) missing-key read returns 0 and inserts', () {
      final store = run('''
from collections import defaultdict
d = defaultdict(int)
zero = d["missing"]
present = "missing" in d
''');
      expect(store['zero'], 0);
      expect(store['present'], true);
    });

    test('defaultdict(int) supports the counter increment pattern', () {
      final store = run('''
from collections import defaultdict
counts = defaultdict(int)
counts["apple"] += 1
counts["apple"] += 1
counts["pear"] += 3
a = counts["apple"]
p = counts["pear"]
total = len(counts)
''');
      expect(store['a'], 2);
      expect(store['p'], 3);
      expect(store['total'], 2);
    });

    test('defaultdict(list) supports the append pattern', () {
      final store = run('''
from collections import defaultdict
groups = defaultdict(list)
groups["a"].append(1)
groups["a"].append(2)
groups["b"].append(3)
a = groups["a"]
b = groups["b"]
''');
      expect(store['a'], [1, 2]);
      expect(store['b'], [3]);
    });

    test('import collections then collections.defaultdict', () {
      final store = run('''
import collections
d = collections.defaultdict(int)
d["x"] += 5
x = d["x"]
''');
      expect(store['x'], 5);
    });

    test(
      'a class whose __init__ uses defaultdict instantiates and mutates',
      () {
        final store = run('''
from collections import defaultdict
class PlayerStats:
    def __init__(self):
        self.food_inventory = defaultdict(int)
    def change_stats(self, item, amount):
        self.food_inventory[item] += amount
player_stats = PlayerStats()
player_stats.change_stats("berry", 2)
player_stats.change_stats("berry", 3)
player_stats.change_stats("apple", 1)
berry = player_stats.food_inventory["berry"]
apple = player_stats.food_inventory["apple"]
''');
        expect(store['berry'], 5);
        expect(store['apple'], 1);
      },
    );

    test('dict machinery (get / items / iteration) works on a defaultdict', () {
      final store = run('''
from collections import defaultdict
d = defaultdict(int)
d["a"] = 1
d["b"] = 2
g = d.get("a")
missing = d.get("z", -1)
present = "z" in d
keys = sorted(d.keys())
''');
      expect(store['g'], 1);
      expect(store['missing'], -1);
      // .get with a default must NOT auto-insert the key.
      expect(store['present'], false);
      expect(store['keys'], ['a', 'b']);
    });

    test('graceful fallback: an unsupported collections member raises', () {
      // `Counter` is not implemented; using it must raise RenPyPythonError
      // (graceful skip) rather than crash with a stray Dart exception.
      expect(
        () => run('''
from collections import Counter
c = Counter()
'''),
        throwsA(isA<RenPyPythonError>()),
      );
    });
  });
}
