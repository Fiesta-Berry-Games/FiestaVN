import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for the `regex` module stub and `ExtendedMusicRoom` builtin.
///
/// The `regex` third-party Python module is always available in the RenPy
/// runtime (like `re`).  Games use `regex.compile(...).match(...)` chains in
/// `init python:` blocks.  The stub mirrors the existing `re` stub: every
/// function returns an inert [_GuiPlaceholder] so the chain evaluates without
/// throwing instead of being classified as a `skippedPython` diagnostic.
///
/// `ExtendedMusicRoom` is a game-defined subclass of `MusicRoom`.  The game
/// instantiates it before the `for` loop that populates the music room, so the
/// builtin must be callable without throwing.
void main() {
  const executor = RenPyPythonExecutor();
  const evaluator = RenPyPythonEvaluator();

  RenPyMapScope scope([Map<String, Object?>? store]) => RenPyMapScope(
    store: store ?? <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('regex module stub', () {
    test('regex is available as a builtin constant', () {
      final result = evaluator.evaluate('regex', scope());
      expect(result, isNotNull);
    });

    test('regex.compile returns an inert placeholder', () {
      final result = evaluator.evaluate(
        r'regex.compile("audio\/music\/\d?\d? ?(.*)\.\w+")',
        scope(),
      );
      expect(result, isNotNull);
    });

    test('regex.compile(...).match(...) chain does not throw', () {
      final s = scope({'key': 'audio/music/01 Track.ogg'});
      Object? result;
      expect(
        () {
          result = evaluator.evaluate(
            r'regex.compile("audio\/music\/(.*)\.\w+").match(key)',
            s,
          );
        },
        returnsNormally,
      );
      // Match result is whatever the stub returns - not null-checked by the
      // caller but must be truthy enough for `if match:` to branch into the
      // `match.group(1)` path (the inert placeholder is truthy).
      expect(result, isNotNull);
    });

    test('match.group(n) on compiled placeholder does not throw', () {
      final s = scope({'key': 'audio/music/01 Track.ogg'});
      expect(
        () {
          executor.execute(r'''
pattern = regex.compile("audio\/music\/\d?\d? ?(.*)\.\w+")
match = pattern.match(key)
if match:
    mr_name = match.group(1)
else:
    mr_name = key
''', s);
        },
        returnsNormally,
      );
      // mr_name is set (either the placeholder or the key itself).
      expect(s.read('mr_name'), isNotNull);
    });

    test('regex.sub does not throw', () {
      final s = scope();
      expect(
        () => evaluator.evaluate(
          r'regex.sub("^[0-9]+ ", "", "01 Track")',
          s,
        ),
        returnsNormally,
      );
    });

    test('regex module constants (UNICODE, MULTILINE) do not throw', () {
      final s = scope({'text': 'hello world'});
      expect(
        () {
          executor.execute(r'''
pattern = regex.compile('[\\W]+', regex.UNICODE)
result = pattern.sub('', text)
''', s);
        },
        returnsNormally,
      );
    });
  });

  group('ExtendedMusicRoom builtin', () {
    test('ExtendedMusicRoom() returns a non-null value', () {
      final result = evaluator.evaluate(
        "ExtendedMusicRoom(channel='music', fadeout=0.0, fadein=0.0, "
        "loop=True, single_track=False, shuffle=False, "
        "stop_action=None, alphabetical=True)",
        scope(),
      );
      expect(result, isNotNull);
    });

    test('ExtendedMusicRoom() does not throw with keyword arguments', () {
      expect(
        () => executor.execute(
          "mm_mr = ExtendedMusicRoom(channel='music', loop=True)",
          scope(),
        ),
        returnsNormally,
      );
    });
  });

  group('super().__init__ stores kwargs as instance attributes', () {
    test(
      'subclass body reads attrs set by super().__init__() kwargs',
      () {
        final s = scope();
        executor.execute(r'''
class Base(object):
    pass
class Derived(Base):
    def __init__(self, shuffle=False, loop=True):
        super(Derived, self).__init__(shuffle=shuffle, loop=loop)
        self.old_shuffle = self.shuffle
d = Derived(shuffle=False, loop=True)
''', s);
        // self.old_shuffle = self.shuffle should succeed because super.__init__
        // stored shuffle as an instance attribute.
        expect(s.has('d'), isTrue);
      },
    );
  });

  group('super().method() on opaque base degrades to no-op', () {
    test(
      'super().add() on a stub base returns without throwing',
      () {
        final s = scope();
        executor.execute(r'''
class MusicBase(object):
    pass
class Lib(MusicBase):
    def add(self, path):
        super(Lib, self).add(path)
        self.count = getattr(self, "count", 0) + 1
lib = Lib()
lib.add("audio/track.ogg")
''', s);
        // The super().add() call should return a no-op, not throw.
        expect(s.has('lib'), isTrue);
      },
    );
  });

  group('Null and SetScreenVariable builtins', () {
    test('Null() returns a non-null placeholder', () {
      final result = evaluator.evaluate('Null()', scope());
      expect(result, isNotNull);
    });

    test('SetScreenVariable() returns a non-null placeholder', () {
      final result = evaluator.evaluate(
        "SetScreenVariable('current_track', None)",
        scope(),
      );
      expect(result, isNotNull);
    });
  });

  group('for-loop over dict.keys() with regex body does not skip', () {
    test('music-room init loop pattern executes without throwing', () {
      final s = scope({
        'music_dictionary': <Object?, Object?>{
          'audio/music/01 Track.ogg': 'Track description',
          'audio/music/02 Another.ogg': 'Another description',
        },
      });
      expect(
        () {
          executor.execute(r'''
for key in music_dictionary.keys():
    pattern = regex.compile("audio\/music\/\d?\d? ?(.*)\.\w+")
    match = pattern.match(key)
    if match:
        mr_name = match.group(1)
    else:
        mr_name = key
''', s);
        },
        returnsNormally,
      );
      // mr_name should be set after iterating.
      expect(s.read('mr_name'), isNotNull);
    });
  });
}
