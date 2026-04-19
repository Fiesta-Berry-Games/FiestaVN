import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses dotted config definitions and init offset statements', () {
    final result = RenPyParser().parse('''
init offset = -2
define gui.text_color = '#ffffff'
define config.window_show_transition = Dissolve(.2)
default preferences.text_cps = 40
define gui.about = _p("""First paragraph.

Second paragraph.
""")

style default:
    properties gui.text_properties()
style window is default

screen say(who, what):
    style_prefix "say"

transform delayed_blink(delay, cycle):
    alpha 0.0

label start:
    "Ready."
''', 'config.rpy');

    expect(result.warnings, isEmpty);
    expect(
      result.script.findStatements<RenPyInitOffsetStatement>((_) => true),
      [
        isA<RenPyInitOffsetStatement>().having(
          (stmt) => stmt.offset,
          'offset',
          -2,
        ),
      ],
    );
    expect(
      result.script
          .findStatements<RenPyDefineStatement>((_) => true)
          .map((stmt) => stmt.name),
      containsAll(['gui.text_color', 'config.window_show_transition']),
    );
    expect(
      result.script
          .findStatements<RenPyDefaultStatement>((_) => true)
          .single
          .name,
      'preferences.text_cps',
    );
    expect(
      result.script
          .findStatements<RenPyStyleStatement>((_) => true)
          .map((stmt) => stmt.declaration),
      containsAll(['default', 'window is default']),
    );
    expect(
      result.script
          .findStatements<RenPyScreenStatement>((_) => true)
          .single
          .signature,
      'say(who, what)',
    );
    expect(
      result.script
          .findStatements<RenPyTransformStatement>((_) => true)
          .single
          .signature,
      'delayed_blink(delay, cycle)',
    );
  });
}
