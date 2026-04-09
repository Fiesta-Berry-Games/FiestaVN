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
