import 'package:renpy_core/src/renpy_arithmetic.dart';
import 'package:renpy_core/src/renpy_expression_evaluator.dart';
import 'package:test/test.dart';

void main() {
  group('RenPyExpressionEvaluator', () {
    test('evaluates nested boolean and comparison expressions', () {
      final evaluator = _evaluatorFor({'book': true, 'persistent.unlock': 2});

      expect(
        evaluator.evaluateCondition(
          '(book and persistent.unlock >= 2) or False',
        ),
        isTrue,
      );
      expect(
        evaluator.evaluateCondition(
          '(book == False) or not persistent.unlock < 2',
        ),
        isTrue,
      );
      expect(
        evaluator.evaluateCondition(
          '(book and persistent.unlock < 2) or False',
        ),
        isFalse,
      );
    });

    test('compares parenthesized condition results', () {
      final evaluator = _evaluatorFor({'book': true, 'persistent.unlock': 2});

      expect(
        evaluator.evaluateCondition('(persistent.unlock >= 2) == True'),
        isTrue,
      );
      expect(
        evaluator.evaluateCondition(
          '(book and persistent.unlock >= 2) != False',
        ),
        isTrue,
      );
    });

    test('does not split operators inside quoted literals', () {
      final evaluator = _evaluatorFor({
        'answer': 'yes or no',
        'comparison': 'a == b',
      });

      expect(evaluator.evaluateCondition('answer == "yes or no"'), isTrue);
      expect(evaluator.evaluateCondition('comparison == "a == b"'), isTrue);
    });

    test('evaluates arithmetic in comparison operands', () {
      final evaluator = _evaluatorFor({
        'x': 1,
        'points': 7,
        'bonus': 4,
        'n': 1,
      });

      expect(evaluator.evaluateCondition('x + 1 == 2'), isTrue);
      expect(evaluator.evaluateCondition('x + 1 == 3'), isFalse);
      expect(evaluator.evaluateCondition('points + bonus >= 10'), isTrue);
      expect(evaluator.evaluateCondition('points + bonus < 10'), isFalse);
      expect(evaluator.evaluateCondition('n - 1 == 0'), isTrue);
      expect(evaluator.evaluateCondition('x * (bonus - 2) == 2'), isTrue);
      expect(evaluator.evaluateCondition('points % 4 == 3'), isTrue);
    });

    test('keeps strict equality between int and string', () {
      final evaluator = _evaluatorFor({});

      expect(evaluator.evaluateCondition('2 == "2"'), isFalse);
      expect(evaluator.evaluateCondition('2 != "2"'), isTrue);
    });

    test('evaluates membership against strings, lists and sets', () {
      final evaluator = _evaluatorFor({
        'items': ['apple', 'pear'],
        'unlocked': {'gold', 'silver'},
        'sentence': 'the quick brown fox',
      });

      expect(evaluator.evaluateCondition('"apple" in items'), isTrue);
      expect(evaluator.evaluateCondition('"plum" in items'), isFalse);
      expect(evaluator.evaluateCondition('"gold" in unlocked'), isTrue);
      expect(evaluator.evaluateCondition('"quick" in sentence'), isTrue);
      expect(evaluator.evaluateCondition('"slow" in sentence'), isFalse);
    });

    test('evaluates not in membership', () {
      final evaluator = _evaluatorFor({
        'items': ['apple', 'pear'],
      });

      expect(evaluator.evaluateCondition('"plum" not in items'), isTrue);
      expect(evaluator.evaluateCondition('"apple" not in items'), isFalse);
    });

    test('does not match in inside identifiers', () {
      final evaluator = _evaluatorFor({'window': true, 'inventory': true});

      expect(evaluator.evaluateCondition('window'), isTrue);
      expect(evaluator.evaluateCondition('inventory'), isTrue);
    });
  });

  group('RenPyArithmetic', () {
    test('evaluates expressions with precedence and variables', () {
      final variables = <String, dynamic>{'points': 7, 'bonus': 4};

      expect(RenPyArithmetic.evaluate('1 + 2 * 3', variables), 7);
      expect(RenPyArithmetic.evaluate('(1 + 2) * 3', variables), 9);
      expect(RenPyArithmetic.evaluate('points + bonus', variables), 11);
      expect(RenPyArithmetic.evaluate('points / bonus', variables), 1.75);
      expect(RenPyArithmetic.evaluate('points % bonus', variables), 3);
      expect(RenPyArithmetic.evaluate('-points + 10', variables), 3);
    });

    test('resolves bare literals and variables', () {
      final variables = <String, dynamic>{'name': 'Eve'};

      expect(RenPyArithmetic.evaluate('42', variables), 42);
      expect(RenPyArithmetic.evaluate('name', variables), 'Eve');
    });

    test('returns null for unparseable expressions', () {
      final variables = <String, dynamic>{};

      expect(RenPyArithmetic.evaluate('1 / 0', variables), isNull);
      expect(RenPyArithmetic.evaluate('+', variables), isNull);
      expect(RenPyArithmetic.evaluate('unknown + 1', variables), isNull);
    });
  });
}

RenPyExpressionEvaluator _evaluatorFor(Map<String, dynamic> variables) {
  return RenPyExpressionEvaluator(
    lookupVariable: (name) {
      return RenPyExpressionVariable(
        variables.containsKey(name),
        variables[name],
      );
    },
    evaluateLiteral: _evaluateLiteral,
  );
}

dynamic _evaluateLiteral(String expression) {
  final value = expression.trim();
  if (value == 'True' || value == 'true') return true;
  if (value == 'False' || value == 'false') return false;
  if (value == 'None' || value == 'null') return null;

  final quoted = RegExp(r'''^["'](.*)["']$''').firstMatch(value);
  if (quoted != null) return quoted.group(1);

  final integer = int.tryParse(value);
  if (integer != null) return integer;

  final decimal = double.tryParse(value);
  if (decimal != null) return decimal;

  return value;
}
