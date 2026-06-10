import 'dart:io';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('The Question script', () {
    late RenPyParseResult result;

    setUpAll(() async {
      final source =
          await File(
            '../../apps/renfly_player/assets/games/the_question/game/script.rpy',
          ).readAsString();
      result = RenPyParser().parse(source, 'the_question/game/script.rpy');
    });

    test('parses without warnings', () {
      expect(result.warnings, isEmpty);
      expect(result.script.findLabel('start'), isNotNull);
    });

    test('parses modern RenPy statements used by the sample', () {
      expect(
        result.script.findStatements<RenPyDefaultStatement>(
          (statement) => statement.name == 'book',
        ),
        hasLength(1),
      );
      expect(
        result.script.findStatements<RenPyWithStatement>((_) => true),
        isNotEmpty,
      );
      expect(
        result.script.findStatements<RenPyReturnStatement>((_) => true),
        hasLength(2),
      );
    });

    test('keeps menu captions and choices', () {
      final menus = result.script.findStatements<RenPyMenuStatement>(
        (_) => true,
      );

      expect(menus, hasLength(2));
      expect(menus.first.caption, 'As soon as she catches my eye, I decide...');
      expect(menus.first.items.map((item) => item.text), [
        'To ask her right away.',
        'To ask her later.',
      ]);
      expect(menus.last.caption, 'Sure, but what\'s a "visual novel?"');
    });
  });
}
