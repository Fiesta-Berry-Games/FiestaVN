import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('if statements include following elif and else blocks', () {
    final script =
        RenPyParser().parse('''
label start:
    if mood == "happy":
        "Happy."
    elif mood == "sad":
        "Sad."
    else:
        "Other."
''', 'if.rpy').script;

    final statement =
        script.findStatements<RenPyIfStatement>((_) => true).single;

    expect(statement.entries.map((entry) => entry.condition), [
      'mood == "happy"',
      'mood == "sad"',
      'True',
    ]);
    expect(
      statement.entries.map(
        (entry) => (entry.block.single as RenPySayStatement).text,
      ),
      ['Happy.', 'Sad.', 'Other.'],
    );
    expect(
      script
          .findStatements<RenPySayStatement>((_) => true)
          .map((say) => say.text),
      ['Happy.', 'Sad.', 'Other.'],
    );
  });
}
