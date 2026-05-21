import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

/// Regression tests for the `init python:` body-dropping bug.
///
/// Previously the init-python path iterated only the TOP-LEVEL lines of the
/// block and kept just their trimmed text, silently dropping every nested
/// child line (class bodies, `def` bodies, `if`/`for` bodies, ...). These
/// tests assert the FULL indented body survives, and that the plain `python:`
/// path is unchanged.
void main() {
  RenPyPythonStatement initPythonBodyOf(RenPyScript script) {
    final init = script.statements.first as RenPyInitStatement;
    expect(init.isPython, isTrue);
    expect(init.block, hasLength(1));
    return init.block.first as RenPyPythonStatement;
  }

  group('init python: preserves the full nested body', () {
    test(
      'multi-line class with __init__ and a method keeps its whole body',
      () {
        final result = RenPyParser().parse('''
init python:
    class PlayerStats:
        def __init__(self):
            self.hp = 10
            self.mp = 5

        def heal(self, amount):
            self.hp += amount
''', 'init_python.rpy');

        final python = initPythonBodyOf(result.script);
        final code = python.code;

        // Top-level line preserved (and would have been the ONLY survivor
        // pre-fix).
        expect(code, contains('class PlayerStats:'));

        // The indented body that the pre-fix code DROPPED.
        expect(code, contains('    def __init__(self):'));
        expect(code, contains('        self.hp = 10'));
        expect(code, contains('        self.mp = 5'));
        expect(code, contains('    def heal(self, amount):'));
        expect(code, contains('        self.hp += amount'));

        expect(python.isInit, isTrue);
        expect(result.warnings, isEmpty);
      },
    );

    test('nested if/def inside init python keeps the full indented body', () {
      final result = RenPyParser().parse('''
init python:
    def configure(flag):
        if flag:
            value = 1
        else:
            value = 2
        return value
''', 'init_python_if.rpy');

      final code = initPythonBodyOf(result.script).code;

      expect(code, contains('def configure(flag):'));
      expect(code, contains('    if flag:'));
      expect(code, contains('        value = 1'));
      expect(code, contains('    else:'));
      expect(code, contains('        value = 2'));
      expect(code, contains('    return value'));
    });

    test('init python in <store> preserves its body', () {
      final result = RenPyParser().parse('''
init python in mystore:
    class Thing:
        def __init__(self):
            self.x = 42
''', 'init_python_store.rpy');

      final code = initPythonBodyOf(result.script).code;

      expect(code, contains('class Thing:'));
      expect(code, contains('    def __init__(self):'));
      expect(code, contains('        self.x = 42'));
    });
  });

  group('plain python: path is unchanged (regression guard)', () {
    test('multi-line python: block keeps its full nested body', () {
      final result = RenPyParser().parse('''
label start:
    python:
        class Helper:
            def __init__(self):
                self.y = 7
''', 'plain_python.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final python = label.block.first as RenPyPythonStatement;
      final code = python.code;

      expect(code, contains('class Helper:'));
      expect(code, contains('    def __init__(self):'));
      expect(code, contains('        self.y = 7'));
      // Non-init python is not an init-phase statement.
      expect(python.isInit, isFalse);
    });
  });
}
