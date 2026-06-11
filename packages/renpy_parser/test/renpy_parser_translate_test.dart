import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  RenPyTranslateStatement parseSingle(String source) {
    final result = RenPyParser().parse(source, 'tl.rpy');
    expect(
      result.warnings.where((w) => w.contains('Unknown statement type')),
      isEmpty,
    );
    expect(result.script.statements, hasLength(1));
    return result.script.statements.single as RenPyTranslateStatement;
  }

  group('translate blocks are structured', () {
    test('translate <lang> <label>: parses its body as statements', () {
      final translate = parseSingle('''
translate french start_a1b2c3d4:
    e "Bonjour le monde."
''');
      expect(translate.language, 'french');
      expect(translate.label, 'start_a1b2c3d4');
      expect(translate.isStrings, isFalse);
      expect(translate.strings, isEmpty);
      expect(translate.block, hasLength(1));
      final say = translate.block.single as RenPySayStatement;
      expect(say.character, 'e');
      expect(say.text, 'Bonjour le monde.');
      expect(translate.filename, 'tl.rpy');
      expect(translate.linenumber, 1);
    });

    test('a translate body may hold any statements, nested', () {
      final translate = parseSingle('''
translate spanish chapter_one:
    show eileen happy at left with dissolve
    if brave:
        "¡Adelante!"
    else:
        "Quizás no."
''');
      expect(translate.language, 'spanish');
      expect(translate.label, 'chapter_one');
      expect(translate.block, hasLength(2));
      expect(translate.block[0], isA<RenPyShowStatement>());
      final branch = translate.block[1] as RenPyIfStatement;
      expect(branch.entries, hasLength(2));
      expect(branch.entries[0].block.single, isA<RenPySayStatement>());
    });

    test('translate <lang> strings: keeps the body as raw lines', () {
      final translate = parseSingle('''
translate french strings:
    old "Hello"
    new "Bonjour"

    old "Goodbye"
    new "Au revoir"
''');
      expect(translate.language, 'french');
      expect(translate.label, 'strings');
      expect(translate.isStrings, isTrue);
      expect(translate.block, isEmpty);
      expect(translate.strings, [
        'old "Hello"',
        'new "Bonjour"',
        'old "Goodbye"',
        'new "Au revoir"',
      ]);
    });

    test('translate <lang> python: holds one python statement', () {
      final translate = parseSingle('''
translate english python:
    style.default.font = "english.ttf"
    if config.developer:
        pass
''');
      expect(translate.language, 'english');
      expect(translate.label, 'python');
      expect(translate.strings, isEmpty);
      expect(translate.block, hasLength(1));
      final python = translate.block.single as RenPyPythonStatement;
      expect(python.isInit, isFalse);
      expect(
        python.code,
        'style.default.font = "english.ttf"\n'
        'if config.developer:\n'
        '    pass',
      );
    });

    test('single-line translate <lang> <label> has an empty block', () {
      final translate = parseSingle('''
translate english start_screen
''');
      expect(translate.language, 'english');
      expect(translate.label, 'start_screen');
      expect(translate.block, isEmpty);
      expect(translate.strings, isEmpty);
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
        expect(result.script.statements[0], isA<RenPyTranslateStatement>());
        expect(result.script.statements[1], isA<RenPyDefineStatement>());
      },
    );

    test('consecutive translate blocks for different languages', () {
      final result = RenPyParser().parse('''
translate french start_1:
    "Bonjour."

translate german start_1:
    "Hallo."
''', 'tl.rpy');
      expect(result.warnings, isEmpty);
      expect(result.script.statements, hasLength(2));
      final french = result.script.statements[0] as RenPyTranslateStatement;
      final german = result.script.statements[1] as RenPyTranslateStatement;
      expect(french.language, 'french');
      expect(german.language, 'german');
      expect(german.label, 'start_1');
    });

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
