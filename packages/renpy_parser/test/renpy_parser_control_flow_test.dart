import 'package:renpy_parser/renpy_parser.dart';
import 'package:test/test.dart';

void main() {
  group('named menus', () {
    test('menu <name>: captures the name as a jump target', () {
      final result = RenPyParser().parse('''
label start:
    menu stage4_guess_name:
        "Anna":
            jump stage4_guess_name
        "Beth":
            "Correct."
''', 'menu.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final menu = label.block.first as RenPyMenuStatement;
      expect(menu.name, 'stage4_guess_name');
      expect(menu.items, hasLength(2));
      expect(result.warnings, isEmpty);
    });

    test('anonymous menu: leaves the name null', () {
      final result = RenPyParser().parse('''
label start:
    menu:
        "One":
            "First."
        "Two":
            "Second."
''', 'menu.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final menu = label.block.first as RenPyMenuStatement;
      expect(menu.name, isNull);
      expect(menu.items, hasLength(2));
    });
  });

  group('top-level while loop', () {
    test('while <cond>: parses to a block statement with its block', () {
      final result = RenPyParser().parse('''
label start:
    while count < 3:
        \$ count += 1
        "Tick."
''', 'while.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final loop = label.block.first as RenPyWhileStatement;
      expect(loop.condition, 'count < 3');
      expect(loop.block, hasLength(2));
      expect(loop.block.first, isA<RenPyPythonStatement>());
      expect(loop.block.last, isA<RenPySayStatement>());
    });

    test('break / continue inside a while body parse to loop control', () {
      final result = RenPyParser().parse('''
label start:
    while True:
        continue
        break
''', 'while.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final loop = label.block.first as RenPyWhileStatement;
      expect(
        (loop.block[0] as RenPyLoopControlStatement).action,
        RenPyLoopControlAction.continueLoop,
      );
      expect(
        (loop.block[1] as RenPyLoopControlStatement).action,
        RenPyLoopControlAction.breakLoop,
      );
    });
  });

  group('top-level for loop', () {
    test('for q in qs: parses variable, iterable and block', () {
      final result = RenPyParser().parse('''
label start:
    for q in questions:
        "Question."
''', 'for.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final loop = label.block.first as RenPyForStatement;
      expect(loop.variable, 'q');
      expect(loop.iterable, 'questions');
      expect(loop.block, hasLength(1));
    });

    test('for over a list literal keeps the bracketed iterable intact', () {
      final result = RenPyParser().parse('''
label start:
    for i in [1, 2, 3]:
        "Item."
''', 'for.rpy');

      final label = result.script.statements.first as RenPyLabelStatement;
      final loop = label.block.first as RenPyForStatement;
      expect(loop.variable, 'i');
      expect(loop.iterable, '[1, 2, 3]');
    });
  });
}
