import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// `with` statement (context manager) support.
///
/// Previously a `with` statement was rejected outright, so any `def`/
/// `init python` body that used one failed to parse and the whole definition
/// was skipped. These exercise the parse + execution path: file-like handles
/// returned by `renpy.open_file`/`notl_file`, user context managers with
/// `__enter__`/`__exit__`, the no-`as` form, iteration, and multiple managers.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('renpy file handles', () {
    test('renpy.open_file(...).read() yields an empty string', () {
      expect(evaluator.evaluate("renpy.open_file('a.txt').read()", scope()), '');
    });

    test('renpy.notl_file(...).read() yields an empty string', () {
      expect(evaluator.evaluate("renpy.notl_file('a.txt').read()", scope()), '');
    });

    test('a file handle readlines() yields an empty list', () {
      expect(
        evaluator.evaluate("renpy.open_file('a').readlines()", scope()),
        <Object?>[],
      );
    });
  });

  group('with statement', () {
    test('a def whose body uses `with ... as` registers and runs', () {
      final s = scope();
      executor.execute('''
def read_beatmap_file(beatmap_path):
    with renpy.open_file(beatmap_path) as f:
        text = f.read()
    onset_times = [float(x) for x in text.split('\\n') if x != '']
    return onset_times
result = read_beatmap_file('x.txt')
''', s);
      expect(s.read('result'), <Object?>[]);
    });

    test('the `as` target binds the file handle so reads resolve', () {
      final s = scope();
      executor.execute('''
with renpy.open_file('version.txt') as f:
    version = f.read().strip()
''', s);
      expect(s.read('version'), '');
    });

    test('the no-`as` form runs its body', () {
      final s = scope();
      executor.execute('''
with renpy.open_file('a'):
    flag = 7
''', s);
      expect(s.read('flag'), 7);
    });

    test('iterating an (empty) file handle yields nothing', () {
      final s = scope();
      executor.execute('''
count = 0
with renpy.open_file('a') as f:
    for line in f:
        count = count + 1
''', s);
      expect(s.read('count'), 0);
    });

    test('multiple managers on one header all bind', () {
      final s = scope();
      executor.execute('''
with renpy.open_file('a') as f, renpy.open_file('b') as g:
    combined = f.read() + g.read()
''', s);
      expect(s.read('combined'), '');
    });

    test('a user context manager invokes __enter__/__exit__', () {
      final s = scope();
      executor.execute('''
class CM:
    def __init__(self):
        self.exited = False
    def __enter__(self):
        return 42
    def __exit__(self, a, b, c):
        self.exited = True
cm = CM()
with cm as value:
    captured = value
''', s);
      expect(s.read('captured'), 42);
      final cm = s.read('cm');
      expect((cm as dynamic).attributes['exited'], true);
    });

    test('__exit__ runs even when the body raises, and the error propagates',
        () {
      final s = scope();
      executor.execute('''
class CM:
    def __init__(self):
        self.exited = False
    def __enter__(self):
        return self
    def __exit__(self, a, b, c):
        self.exited = True
cm = CM()
try:
    with cm:
        raise ValueError("boom")
        reached = True
except ValueError:
    caught = True
''', s);
      // The body's statement after `raise` must not run; the except clause does.
      expect(s.read('reached'), isNull);
      expect(s.read('caught'), true);
      expect((s.read('cm') as dynamic).attributes['exited'], true);
    });
  });
}
