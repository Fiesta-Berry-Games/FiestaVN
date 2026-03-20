import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  group('RenPyStyledText', () {
    test('parses bold style runs without exposing tags', () {
      final styled = RenPyStyledText.parse('{b}Good Ending{/b}.');

      expect(styled.plainText, 'Good Ending.');
      expect(styled.runs, [
        const RenPyTextRun('Good Ending', bold: true),
        const RenPyTextRun('.'),
      ]);
    });

    test('parses italic style runs', () {
      final styled = RenPyStyledText.parse('This is {i}important{/i}.');

      expect(styled.plainText, 'This is important.');
      expect(styled.runs, [
        const RenPyTextRun('This is '),
        const RenPyTextRun('important', italic: true),
        const RenPyTextRun('.'),
      ]);
    });

    test('parses color style runs', () {
      final styled = RenPyStyledText.parse(
        'This is {color=#ff0000}red{/color}.',
      );

      expect(styled.plainText, 'This is red.');
      expect(styled.runs, [
        const RenPyTextRun('This is '),
        const RenPyTextRun('red', color: '#ff0000'),
        const RenPyTextRun('.'),
      ]);
    });

    test('parses displayable text size font and outline style runs', () {
      final styled = RenPyStyledText.parse(
        '{size=96}{font=UglyQua.ttf}{outlinecolor=#000000}Title{/outlinecolor}{/font}{/size}',
      );

      expect(styled.plainText, 'Title');
      expect(styled.runs, [
        const RenPyTextRun(
          'Title',
          size: 96,
          font: 'UglyQua.ttf',
          outlineColor: '#000000',
        ),
      ]);
    });

    test('omits RenPy control tags from plain text', () {
      final styled = RenPyStyledText.parse('Huh?{p=0.3}{nw}');

      expect(styled.plainText, 'Huh?');
      expect(styled.runs, [const RenPyTextRun('Huh?')]);
    });

    test('preserves unknown text outside tags', () {
      final styled = RenPyStyledText.parse('A {unknown}B{/unknown} C');

      expect(styled.plainText, 'A B C');
      expect(styled.runs, [const RenPyTextRun('A B C')]);
    });
  });
}
