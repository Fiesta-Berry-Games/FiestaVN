import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('parses nvl clear as an explicit NVL statement', () {
    final result = RenPyParser().parse('''
label start:
    "Before."
    nvl clear
    "After."
''', 'nvl.rpy');

    expect(result.warnings, isEmpty);

    final nvlStatements = result.script.findStatements<RenPyNvlStatement>(
      (_) => true,
    );
    expect(nvlStatements, hasLength(1));
    expect(nvlStatements.single.action, RenPyNvlAction.clear);
  });
}
