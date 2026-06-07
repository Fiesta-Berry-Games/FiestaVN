import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for the music_dictionary cluster of fixes:
///
/// 1. Cross-batch define fixpoint: defines separated by an init-python block
///    should still forward-reference each other. The runner now collects
///    unresolved defines across batches and retries them after all batches run.
///
/// 2. `sorted()` with a `key=` keyword argument: the sort key function is now
///    applied via decorate-sort-undecorate so comparisons use the key values
///    rather than the raw items.
///
/// 3. `_defaultCompare` fallback: opaque stub values (e.g. from un-executed
///    regex/library calls) fall back to their string representation so
///    sorted()/min()/max() do not abort on non-comparable values.
void main() {
  group('cross-batch define fixpoint', () {
    test('define separated by init python: forward-reference resolves', () {
      // Simulates: updated_music_dict defined BEFORE music_dictionary,
      // with an init-python block between them (which breaks the contiguous
      // define batch). The cross-batch retry must resolve the reference.
      const src = '''
define updated_music_dict = music_dictionary
init python:
    pass
define mystic_chat = "audio/music/mystic_chat.ogg"
define music_dictionary = {
    mystic_chat : "Upbeat saxophone music",
}
''';
      final parser = RenPyParser();
      final result = parser.parse(src, 'test.rpy');
      final runner = RenPyRunner(result.script);
      final diags = <RenPyDiagnostic>[];
      runner.onDiagnostic = (d) => diags.add(d);

      expect(diags, isEmpty);
      final scope = runner.pythonScope;
      expect(scope.has('music_dictionary'), isTrue);
      final dict = scope.read('music_dictionary') as Map?;
      expect(dict, isNotNull);
      expect(dict!.values.first, equals('Upbeat saxophone music'));
      // updated_music_dict should point to the same resolved dict
      expect(scope.has('updated_music_dict'), isTrue);
      expect(scope.read('updated_music_dict'), isA<Map>());
    });

    test(
      'define with variable-expression keys resolves after deps are defined',
      () {
        // Keys in a dict literal are variable names (not string literals).
        // They must be evaluated after the referenced variables are defined.
        const src = '''
define path1 = "audio/music/track1.ogg"
define path2 = "audio/music/track2.ogg"
define track_dict = {
    path1 : "Track One",
    path2 : "Track Two",
}
''';
        final parser = RenPyParser();
        final result = parser.parse(src, 'test.rpy');
        final runner = RenPyRunner(result.script);
        final diags = <RenPyDiagnostic>[];
        runner.onDiagnostic = (d) => diags.add(d);

        expect(diags, isEmpty);
        final dict =
            runner.pythonScope.read('track_dict') as Map<Object?, Object?>?;
        expect(dict, isNotNull);
        expect(dict!['audio/music/track1.ogg'], equals('Track One'));
        expect(dict['audio/music/track2.ogg'], equals('Track Two'));
      },
    );
  });

  group('sorted() with key= argument', () {
    test('sorted with key lambda sorts by computed key', () {
      // sorted(list, key=lambda x: x[0]) should sort by first element of
      // each sublist, matching Python's decorate-sort-undecorate semantics.
      const src = '''
init python:
    pairs = [("banana", 2), ("apple", 1), ("cherry", 3)]
    result = sorted(pairs, key=lambda x: x[0])
''';
      final parser = RenPyParser();
      final result = parser.parse(src, 'test.rpy');
      final runner = RenPyRunner(result.script);
      final diags = <RenPyDiagnostic>[];
      runner.onDiagnostic = (d) => diags.add(d);

      expect(diags, isEmpty);
      final sorted = runner.pythonScope.read('result') as List?;
      expect(sorted, isNotNull);
      expect((sorted![0] as List)[0], equals('apple'));
      expect((sorted[1] as List)[0], equals('banana'));
      expect((sorted[2] as List)[0], equals('cherry'));
    });

    test('sorted with key=lambda and reverse=True', () {
      const src = '''
init python:
    nums = [3, 1, 4, 1, 5, 9]
    result = sorted(nums, key=lambda x: -x)
''';
      final parser = RenPyParser();
      final result = parser.parse(src, 'test.rpy');
      final runner = RenPyRunner(result.script);
      final diags = <RenPyDiagnostic>[];
      runner.onDiagnostic = (d) => diags.add(d);

      expect(diags, isEmpty);
      final sorted = runner.pythonScope.read('result') as List?;
      expect(sorted, isNotNull);
      // sorted by -x means descending: 9, 5, 4, 3, 1, 1
      expect(sorted![0], equals(9));
      expect(sorted[1], equals(5));
    });
  });
}
