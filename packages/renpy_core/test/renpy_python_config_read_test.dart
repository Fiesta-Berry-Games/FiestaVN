import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// An unset `config.X` attribute reads as null instead of throwing (Ren'Py's
/// `config` is a module whose built-in attributes a game reads defensively,
/// e.g. `config.gamedir`). This unblocks LearnToCodeRPG's `read_beatmap_file`,
/// which does `os.path.join(config.gamedir, beatmap_path)` while constructing
/// `rhythm_game_songs`. `store.`/bare names are deliberately unaffected.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  test('an unset config attribute reads as null', () {
    expect(evaluator.evaluate('config.gamedir', scope()), isNull);
  });

  test('a set config attribute still reads its value', () {
    final s = scope();
    executor.execute('config.screen_width = 1280', s);
    expect(evaluator.evaluate('config.screen_width', s), 1280);
  });

  test('os.path.join(config.gamedir, x) does not throw', () {
    final s = scope();
    executor.execute("import os\np = os.path.join(config.gamedir, 'a.txt')", s);
    expect(s.read('p'), isNotNull);
  });

  test('an unset store attribute still throws (contract preserved)', () {
    expect(
      () => evaluator.evaluate('store.never_set_xyz', scope()),
      throwsA(isA<RenPyPythonError>()),
    );
  });

  test('a genuinely unknown bare name still throws', () {
    expect(
      () => evaluator.evaluate('totally_unknown_name', scope()),
      throwsA(isA<RenPyPythonError>()),
    );
  });

  test('the rhythm-game Song cascade builds end to end', () {
    final s = scope();
    executor.execute('''
import os
def read_beatmap_file(beatmap_path):
    beatmap_path_full = os.path.join(config.gamedir, beatmap_path)
    with renpy.open_file(beatmap_path) as f:
        text = f.read()
    return [float(x) for x in text.split('\\n') if x != '']
class Song(object):
    def __init__(self, name, beatmap_path):
        self.name = name
        self.onset_times = read_beatmap_file(beatmap_path)[::2]
songs = [Song("a", "a.txt"), Song("b", "b.txt")]
scores = {s.name: 0 for s in songs}
''', s);
    expect((s.read('songs') as List).length, 2);
    expect(s.read('scores'), {'a': 0, 'b': 0});
  });
}
