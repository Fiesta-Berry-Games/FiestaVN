import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// The init-python statement splitter must track bracket depth and triple-quote
/// state, so a multi-line list/dict literal whose continuation lines sit at
/// column 0 (after the parser dedents the block) is kept as ONE statement
/// instead of being shredded into unparseable fragments. This is the real cause
/// of LearnToCodeRPG's `rhythm_game_songs = [Song(...), ...]` skip and the
/// `persistent.rhythm_game_high_scores = {... for ...}` cascade.
void main() {
  ({
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'multiline.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return (diagnostics: diagnostics, runner: runner);
  }

  List<RenPyDiagnostic> skipped(List<RenPyDiagnostic> diagnostics) => diagnostics
      .where(
        (d) =>
            d.code == RenPyDiagnosticCode.skippedPython ||
            d.code == RenPyDiagnosticCode.skippedDefinition,
      )
      .toList();

  group('multi-line literals in init python', () {
    test('a list literal with column-0 continuation lines is one statement', () {
      // After dedent, `Song(` lands at column 0 - same indent as the assignment.
      final result = play('''
init python:
    class Song(object):
        def __init__(self, name):
            self.name = name

    songs = [
    Song("a"),
    Song("b"),
    Song("c"),
    ]
    song_count = len(songs)

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['song_count'], 3);
    });

    test('a dict comprehension spanning lines after the list resolves', () {
      final result = play('''
init python:
    class Song(object):
        def __init__(self, name):
            self.name = name

    songs = [
    Song("a"),
    Song("b"),
    ]
    scores = {
    s.name: 0
    for s in songs
    }
    score_count = len(scores)

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['score_count'], 2);
    });

    test('a bracket inside a string does not affect statement splitting', () {
      final result = play('''
init python:
    a = 1
    s = "this ] is not a close bracket"
    b = 2

label start:
    "done"
''');
      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['a'], 1);
      expect(result.runner.snapshot().variables['b'], 2);
    });
  });
}
