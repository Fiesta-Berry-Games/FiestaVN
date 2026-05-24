import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('translate blocks are no-ops', () {
    test('translate <lang> python: yields a pass and emits no warning', () {
      final result = RenPyParser().parse('''
translate english python:
    old = "Hello"
    new = "Hello"
''', 'tl.rpy');

      expect(
        result.warnings.where((w) => w.contains('Unknown statement type')),
        isEmpty,
      );
      expect(result.script.statements, hasLength(1));
      expect(result.script.statements.single, isA<RenPyPassStatement>());
    });

    test('translate <lang> strings: yields a pass and drops the body', () {
      final result = RenPyParser().parse('''
translate french strings:
    old "Hello"
    new "Bonjour"
''', 'tl.rpy');

      expect(
        result.warnings.where((w) => w.contains('Unknown statement type')),
        isEmpty,
      );
      expect(result.script.statements, hasLength(1));
      expect(result.script.statements.single, isA<RenPyPassStatement>());
    });

    test('translate <lang> <identifier>: (say block) yields a pass', () {
      final result = RenPyParser().parse('''
translate spanish start_screen:
    "Hola, mundo."
''', 'tl.rpy');

      expect(
        result.warnings.where((w) => w.contains('Unknown statement type')),
        isEmpty,
      );
      expect(result.script.statements, hasLength(1));
      expect(result.script.statements.single, isA<RenPyPassStatement>());
    });

    test('single-line translate <lang> <identifier> yields a pass', () {
      final result = RenPyParser().parse('''
translate english start_screen
''', 'tl.rpy');

      expect(
        result.warnings.where((w) => w.contains('Unknown statement type')),
        isEmpty,
      );
      expect(result.script.statements, hasLength(1));
      expect(result.script.statements.single, isA<RenPyPassStatement>());
    });

    test(
      'a statement after a translate block still parses (block consumed)',
      () {
        final result = RenPyParser().parse('''
translate english python:
    old = "Hello"
    new = "Hello"

define greeting = "Hi"
''', 'tl.rpy');

        expect(
          result.warnings.where((w) => w.contains('Unknown statement type')),
          isEmpty,
        );
        expect(result.script.statements, hasLength(2));
        expect(result.script.statements[0], isA<RenPyPassStatement>());
        expect(result.script.statements[1], isA<RenPyDefineStatement>());
      },
    );

    test('a script with no translate blocks is unaffected', () {
      final result = RenPyParser().parse('''
define greeting = "Hi"

label start:
    "Hello there."
''', 'plain.rpy');

      expect(result.warnings, isEmpty);
      expect(result.script.statements, hasLength(2));
      expect(result.script.statements[0], isA<RenPyDefineStatement>());
      expect(result.script.statements[1], isA<RenPyLabelStatement>());
    });
  });
}
