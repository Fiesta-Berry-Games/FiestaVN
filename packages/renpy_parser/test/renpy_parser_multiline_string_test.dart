import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses narrator strings that continue on a less-indented line', () {
    final script =
        RenPyParser().parse('''
label start:
    "I somehow remember that strings by themselves are displayed as
     thoughts or narration."
    "Next."
''', 'multiline.rpy').script;

    final dialogue = script.findStatements<RenPySayStatement>((_) => true);

    expect(dialogue.map((statement) => statement.text), [
      'I somehow remember that strings by themselves are displayed as\n     thoughts or narration.',
      'Next.',
    ]);
  });

  test('keeps consecutive multiline dialogue at the parent block indent', () {
    final script =
        RenPyParser().parse('''
label start:
    e "For example, a line of dialogue is expressed by putting the
       character's name next to the dialogue string."
    "I somehow remember that strings by themselves are displayed as
     thoughts or narration."
    e "Next."
''', 'multiline.rpy').script;

    final dialogue = script.findStatements<RenPySayStatement>((_) => true);

    expect(dialogue.map((statement) => statement.character), ['e', null, 'e']);
  });
}
