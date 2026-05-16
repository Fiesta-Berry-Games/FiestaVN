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

  test('parses play statements alongside voice and queue', () {
    final result = RenPyParser().parse('''
label start:
    play music "bgm1.ogg"
    queue music "bgm2.ogg"
    voice "v/line1.ogg"
    voice sustain
''', 'audio.rpy');

    final plays = result.script.findStatements<RenPyPlayStatement>((_) => true);
    final queues = result.script.findStatements<RenPyQueueStatement>(
      (_) => true,
    );
    final voices = result.script.findStatements<RenPyVoiceStatement>(
      (_) => true,
    );

    expect(plays, hasLength(1));
    expect(plays.first.channel, 'music');
    expect(plays.first.expression, '"bgm1.ogg"');

    expect(queues, hasLength(1));
    expect(queues.first.channel, 'music');
    expect(queues.first.expression, '"bgm2.ogg"');

    expect(voices, hasLength(2));
    expect(voices.first.expression, '"v/line1.ogg"');
    expect(voices.first.isSustain, isFalse);
    expect(voices.last.isSustain, isTrue);
  });
}
