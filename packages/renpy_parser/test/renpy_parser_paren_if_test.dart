import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  test('if with parenthesized condition parses', () {
    final result = RenPyParser().parse('''
label start:
    if (_in_replay and foo):
        "in replay"
    elif (_in_replay):
        "just replay"
    else:
        "normal"
''', 'test.rpy');
    expect(result.warnings, isEmpty);
    final label = result.script.statements.first as RenPyLabelStatement;
    final ifStmt = label.block.first;
    expect(ifStmt, isA<RenPyIfStatement>());
    final entries = (ifStmt as RenPyIfStatement).entries;
    expect(entries, hasLength(3));
    expect(entries[0].condition, '(_in_replay and foo)');
    expect(entries[1].condition, '(_in_replay)');
    expect(entries[2].condition, 'True');
  });

  test('multi-line parenthesized elif condition parses', () {
    final result = RenPyParser().parse('''
label start:
    if foo:
        "foo"
    elif (current_timeline_item.expired
        and not current_timeline_item.played
        and bar):
        "expired"
    else:
        "other"
''', 'test.rpy');
    expect(result.warnings, isEmpty);
    final label = result.script.statements.first as RenPyLabelStatement;
    final ifStmt = label.block.first as RenPyIfStatement;
    expect(ifStmt.entries, hasLength(3));
    expect(ifStmt.entries[0].condition, 'foo');
    expect(
      ifStmt.entries[1].condition,
      contains('current_timeline_item.expired'),
    );
    expect(ifStmt.entries[2].condition, 'True');
  });

  test('multi-line parenthesized if condition parses', () {
    final result = RenPyParser().parse('''
label start:
    if (some_var
        and other_var):
        "yes"
    else:
        "no"
''', 'test.rpy');
    expect(result.warnings, isEmpty);
    final label = result.script.statements.first as RenPyLabelStatement;
    final ifStmt = label.block.first as RenPyIfStatement;
    expect(ifStmt.entries, hasLength(2));
    expect(ifStmt.entries[0].condition, contains('some_var'));
    expect(ifStmt.entries[0].condition, contains('other_var'));
  });

  test('parenthesized condition preserves inner parens', () {
    final result = RenPyParser().parse('''
label start:
    if (a and (b or c)):
        "yes"
''', 'test.rpy');
    expect(result.warnings, isEmpty);
    final label = result.script.statements.first as RenPyLabelStatement;
    final ifStmt = label.block.first as RenPyIfStatement;
    expect(ifStmt.entries[0].condition, '(a and (b or c))');
  });
}
