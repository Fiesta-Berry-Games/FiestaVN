import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests for _stripTrailingComment handling of backslash-escaped
/// quotes inside Python strings. Before the fix, a `\"` inside a string made
/// the scanner think the string ended early, potentially stripping legitimate
/// code that looked like a `# comment`.
void main() {
  group('_stripTrailingComment escaped-quote handling', () {
    late RenPyPythonExecutor executor;
    late Map<String, Object?> store;

    setUp(() {
      executor = const RenPyPythonExecutor();
      store = <String, Object?>{};
    });

    RenPyPythonScope scope() =>
        RenPyMapScope(store: store, persistent: <String, Object?>{});

    test(r'string with \" followed by real # comment strips the comment', () {
      // The assignment should capture only the string value; the trailing
      // comment must be stripped, not included in the string or cause a parse
      // error.
      executor.execute(r'x = "say \"hello\"" # a comment', scope());
      expect(store['x'], equals('say "hello"'));
    });

    test(r"string with \' followed by real # comment strips the comment", () {
      executor.execute(r"x = 'say \'hi\'' # a comment", scope());
      expect(store['x'], equals("say 'hi'"));
    });

    test(r'string with \" followed by more code is not stripped', () {
      // The `+ " world"` after the escaped-quote string must NOT be mistaken
      // for a comment. It is legitimate code that must execute.
      executor.execute(r'x = "say \"hello\"" + " world"', scope());
      expect(store['x'], equals('say "hello" world'));
    });

    test(r'string containing \# is not stripped', () {
      // A backslash-escaped `#` inside a string is literal text; the comment
      // scanner must not treat it as a comment start.
      executor.execute(r'x = "foo \# bar"', scope());
      // Python treats `\#` as a literal `\#` (backslash is kept for unknown
      // escape sequences), but the key assertion is that the string is not
      // truncated at `#`.
      expect((store['x'] as String).contains('bar'), isTrue);
    });

    test(r'triple-quoted string with \" does not confuse comment stripping',
        () {
      // A triple-quoted string containing escaped quotes followed by a real
      // comment should strip the comment correctly without breaking the string.
      executor.execute('x = """say \\"hello\\"""" # comment', scope());
      expect(store['x'], equals('say "hello"'));
    });
  });
}
