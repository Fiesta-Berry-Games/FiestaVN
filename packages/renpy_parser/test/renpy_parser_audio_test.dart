import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses stop audio statements with fadeout', () {
    final result = RenPyParser().parse('''
label start:
    stop music fadeout 1.5
    stop sound
''', 'audio.rpy');

    final stops = result.script.findStatements<RenPyStopStatement>((_) => true);

    expect(stops, hasLength(2));
    expect(stops.first.channel, 'music');
    expect(stops.first.fadeout, '1.5');
    expect(stops.last.channel, 'sound');
    expect(stops.last.fadeout, isNull);
  });
}
