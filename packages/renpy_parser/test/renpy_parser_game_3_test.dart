import 'dart:io';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('Reference Game 3 parses without fatal indentation errors', () {
    final source = File('test/games/3/game/script.rpy').readAsStringSync();

    final script = RenPyParser().parse(source, 'script3.rpy').script;

    expect(script.findLabel('start'), isNotNull);
    expect(script.findLabel('writing'), isNotNull);
    expect(
      script
          .findStatements<RenPyMenuStatement>(
            (menu) => menu.setVariable != null,
          )
          .single
          .setVariable,
      'seen_set',
    );
  });
}
