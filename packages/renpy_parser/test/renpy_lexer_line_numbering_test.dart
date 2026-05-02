import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('logical line numbers across blank and comment gaps', () {
    test(
      'blank lines before a statement are not credited to the previous one',
      () {
        final lines =
            RenPyLexer(
              'label start:\n\n\n\n    "first"\n',
              'blank.rpy',
            ).listLogicalLines();

        expect(lines.map((line) => line.text.trim()), [
          'label start:',
          '"first"',
        ]);
        expect(lines.map((line) => line.number), [1, 5]);
      },
    );

    test(
      'full-line comments before a statement do not shift its line number',
      () {
        final lines =
            RenPyLexer(
              'label start:\n# c1\n# c2\n    "first"\n',
              'comment.rpy',
            ).listLogicalLines();

        expect(lines.map((line) => line.text.trim()), [
          'label start:',
          '"first"',
        ]);
        expect(lines.map((line) => line.number), [1, 4]);
      },
    );

    test('mixed blank and comment gaps keep later statements aligned', () {
      final lines =
          RenPyLexer(
            'label start:\n'
                '\n'
                '# a comment\n'
                '\n'
                '    "first"\n'
                '\n'
                '    "second"\n',
            'mixed.rpy',
          ).listLogicalLines();

      expect(lines.map((line) => line.text.trim()), [
        'label start:',
        '"first"',
        '"second"',
      ]);
      expect(lines.map((line) => line.number), [1, 5, 7]);
    });
  });

  group('backslash line continuation', () {
    test('splices the continued line without leaving a literal backslash', () {
      final lines =
          RenPyLexer('define x = 1 + \\\n2\n', 'cont.rpy').listLogicalLines();

      expect(lines, hasLength(1));
      expect(lines.single.text, 'define x = 1 + 2');
      expect(lines.single.number, 1);
    });

    test('a backslash inside a string is preserved', () {
      final lines =
          RenPyLexer(
            r'e "a\nb"'
                '\n',
            'escape.rpy',
          ).listLogicalLines();

      expect(lines.single.text, r'e "a\nb"');
    });
  });
}
