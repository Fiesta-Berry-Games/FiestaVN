import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests. Each case below was a real `skippedPython`
/// diagnostic from the LearnToCodeRPG wild-game e2e and threw before the fix.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope scope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('Task 1: built-in evaluable constant names', () {
    // PRE: `evaluate('dissolve')` threw RenPyPythonNameError.
    // POST: resolves to an inert opaque placeholder value.
    test('built-in transitions evaluate to a non-null value', () {
      for (final name in ['dissolve', 'fade', 'pixellate']) {
        final value = evaluator.evaluate(name, scope());
        expect(value, isNotNull, reason: name);
      }
    });

    // PRE: `evaluate('truecenter')` threw RenPyPythonNameError.
    test('built-in positions evaluate to a non-null value', () {
      for (final name in [
        'truecenter',
        'center',
        'left',
        'right',
        'top',
        'bottom',
        'topleft',
        'topright',
        'bottomleft',
        'bottomright',
        'offscreenleft',
        'offscreenright',
        'reset',
      ]) {
        final value = evaluator.evaluate(name, scope());
        expect(value, isNotNull, reason: name);
      }
    });

    // PRE: the statement path threw and the assignment was skipped.
    // POST: the assignment stores the placeholder.
    test('example_transition = dissolve assigns', () {
      final s = scope();
      executor.execute('example_transition = dissolve', s);
      expect(s.read('example_transition'), isNotNull);
    });

    test('renpy.show at_list referencing truecenter evaluates', () {
      // The at_list expression must merely evaluate (we do not render).
      final value = evaluator.evaluate('[truecenter, center]', scope());
      expect(value, isA<List<Object?>>());
      expect((value as List).length, 2);
    });
  });

  group('Task 2: module stubs re and os', () {
    // PRE/POST note: `import re; re.compile(...)` already happened to work via
    // the generic opaque stub, but we now back it with a concrete reModule().
    test('re.compile returns an inert value (import re)', () {
      final s = scope();
      executor.execute('import re\nregex = re.compile("x")', s);
      expect(s.read('regex'), isNotNull);
    });

    test('re member functions are inert and never throw', () {
      final s = scope();
      executor.execute(
        'import re\n'
        'a = re.match("p", "s")\n'
        'b = re.search("p", "s")\n'
        'c = re.sub("p", "r", "s")\n'
        'd = re.findall("p", "s")\n'
        'e = re.escape("s")',
        s,
      );
      for (final name in ['a', 'b', 'c', 'd', 'e']) {
        expect(s.read(name), isNotNull, reason: name);
      }
    });

    // PRE: `"X" not in os.environ` threw "argument is not iterable" because the
    // generic os stub resolved os.environ to another opaque stub, not a Map.
    // POST: os.environ is an empty Map, so membership evaluates to true.
    test('os.environ membership test evaluates (import os)', () {
      final s = scope();
      executor.execute(
        'import os\nSHOW = ("RENPY_LESS_EXAMPLES" not in os.environ)',
        s,
      );
      expect(s.read('SHOW'), isTrue);
    });

    test('from os import environ binds an empty dict', () {
      final s = scope();
      executor.execute('from os import environ\nx = ("Y" not in environ)', s);
      expect(s.read('x'), isTrue);
    });

    test('os.getenv returns default or null', () {
      final s = scope();
      executor.execute(
        'import os\n'
        'a = os.getenv("MISSING")\n'
        'b = os.getenv("MISSING", "fallback")',
        s,
      );
      expect(s.read('a'), isNull);
      expect(s.read('b'), 'fallback');
    });
  });

  group('Task 3: raw-string escaped-quote correctness', () {
    // ROOT CAUSE: in `_readString`, raw strings skipped the backslash-escape
    // scan (`if (!isRaw && ch == '\\' ...)`). So inside `r"a\"b"` the lexer saw
    // the backslash, wrote it, then treated the following `"` as the closing
    // delimiter and kept scanning until EOF -> "unterminated string literal".
    //
    // In CPython a backslash in a raw string still prevents the next quote from
    // terminating the string (`r"a\"b"` is a 4-char string: a \ " b), with the
    // backslash retained literally. The fix lets the backslash-defer logic run
    // for raw strings too, so the quote no longer terminates early.
    //
    // PRE: evaluate(r'r"a\"b"') threw "unterminated string literal".
    test('raw string keeps backslash and quote, does not terminate early', () {
      final value = evaluator.evaluate(r'r"a\"b"', scope());
      // Raw: backslash is retained literally -> 4 chars: a, \, ", b.
      expect(value, r'a\"b');
    });

    test('cooked string still unescapes the quote', () {
      final value = evaluator.evaluate(r'"a\"b"', scope());
      expect(value, 'a"b');
    });

    // PRE: the multi-line raw-string `+` concatenation skipped because the first
    // raw string with an escaped quote terminated early and corrupted the parse.
    // POST: each raw chunk lexes correctly and concatenates.
    test('multi-line raw-string concatenation with escaped quotes', () {
      final s = scope();
      executor.execute(r'regex = r"(?P<word>\b)" + r"|(?P<string>\"x\")"', s);
      expect(s.read('regex'), r'(?P<word>\b)|(?P<string>\"x\")');
    });

    // The exact LearnToCodeRPG offender (trimmed): raw strings with escaped
    // quotes joined across multiple `+` continuation lines.
    test('LearnToCodeRPG-style raw regex assembly evaluates', () {
      final s = scope();
      executor.execute(
        r'regex = r"(?P<word>\b(\$|[_a-zA-Z0-9]+)\b)" + '
        r'r"|(?P<string>\"([^\"]|\\.)*(?<!\\)\")"',
        s,
      );
      expect(s.read('regex'), isA<String>());
      expect((s.read('regex') as String).contains('?P<word>'), isTrue);
      expect((s.read('regex') as String).contains('?P<string>'), isTrue);
    });
  });
}
