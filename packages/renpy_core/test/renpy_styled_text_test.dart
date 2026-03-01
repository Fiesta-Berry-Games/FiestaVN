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
