import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// A `def` (or `class` method) body whose FIRST statement is a
/// triple-quoted docstring must parse and execute. The docstring -- which may
/// span many physical lines and contain text that looks like code, comments or
/// assignments -- has to be kept as ONE logical bare-expression statement (and
/// then ignored) so the REST of the body runs and the function/class registers.
///
/// This is the real LearnToCodeRPG `read_example` shape that previously caused a
/// `skippedPython` because the whole `def` failed to parse.
void main() {
  const evaluator = RenPyPythonEvaluator();
  const executor = RenPyPythonExecutor();

  RenPyMapScope newScope() => RenPyMapScope(
    store: <String, Object?>{},
    persistent: <String, Object?>{},
  );

  group('def with a leading triple-quoted docstring', () {
    test(
      'multi-line docstring is ignored and the real body runs (LTC shape)',
      () {
        final scope = newScope();
        // Pre-fix hypothesis: the multi-line triple-quote was split across
        // physical lines, so the def failed to parse and `read_example` never
        // registered. Post-fix: the docstring is one logical statement, ignored,
        // and the function returns from its real body.
        executor.execute('''
def read_example(name, fn, line, outdent):
    """
        This reads an example from an example statement, and places it
        into the the examples dict.

        `name`
            The name of the example.
    """
    result = name
    return result
''', scope);
        final r = evaluator.evaluate(
          'read_example("ex", "f.rpy", 3, 1)',
          scope,
        );
        expect(r, 'ex');
      },
    );

    test('single-line """doc""" docstring then body works', () {
      final scope = newScope();
      executor.execute('''
def h(a):
    """One line doc."""
    return a * 2
''', scope);
      expect(evaluator.evaluate('h(3)', scope), 6);
    });

    test("triple-single-quote ''' docstring then body works", () {
      final scope = newScope();
      executor.execute("""
def g(a):
    '''
    a multi-line docstring
    using single quotes
    '''
    return a + 1
""", scope);
      expect(evaluator.evaluate('g(4)', scope), 5);
    });

    test(
      'docstring containing code-like text is treated as text, not code',
      () {
        final scope = newScope();
        // Lines that look like an assignment, a comment, and `def`/`return`
        // keywords live INSIDE the triple-quotes and must not be parsed.
        executor.execute('''
def f(a):
    """
        usage: f(a)  # returns a + 1
        formula = a + 1
        def nope():
        return wrong
    """
    return a + 1
''', scope);
        expect(evaluator.evaluate('f(5)', scope), 6);
      },
    );

    test(
      'a # in the docstring sharing the closing """ line is kept (regression)',
      () {
        // Root-cause regression: a `#` on the continuation line that also carries
        // the closing `"""` made the per-line comment stripper delete the `#` AND
        // the closing delimiter, leaving the string permanently unterminated and
        // the whole def skipping. The `#` must be treated as docstring text.
        final scope = newScope();
        executor.execute('''
def f(a):
    """doc line
    a trailing note # not a comment, closes here"""
    return a + 1
''', scope);
        expect(evaluator.evaluate('f(9)', scope), 10);
      },
    );
  });

  group('class method with a leading triple-quoted docstring', () {
    test('docstring-first method registers and is callable', () {
      final scope = newScope();
      executor.execute('''
class C(object):
    def m(self):
        """method doc
        spanning multiple lines
        with a # hash and value = 1"""
        return 42
''', scope);
      expect(evaluator.evaluate('C().m()', scope), 42);
    });
  });

  group('graceful fallback', () {
    test(
      'an unterminated triple-quote degrades to RenPyPythonError, no hang',
      () {
        expect(
          () => executor.execute('''
def bad(a):
    """ never closed
    return a
''', newScope()),
          throwsA(isA<RenPyPythonError>()),
        );
      },
    );
  });
}
