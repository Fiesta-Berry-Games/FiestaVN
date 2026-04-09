typedef RenPyExpressionVariableLookup =
    RenPyExpressionVariable Function(String name);

typedef RenPyLiteralEvaluator = dynamic Function(String expression);

class RenPyExpressionVariable {
  const RenPyExpressionVariable(this.found, this.value);

  final bool found;
  final dynamic value;
}

class RenPyExpressionEvaluator {
  const RenPyExpressionEvaluator({
    required this.lookupVariable,
    required this.evaluateLiteral,
  });

  final RenPyExpressionVariableLookup lookupVariable;
  final RenPyLiteralEvaluator evaluateLiteral;

  bool evaluateCondition(String condition) {
    final value = _stripOuterParentheses(condition.trim());
    if (value == 'True' || value == 'true') return true;
    if (value == 'False' || value == 'false') return false;

    final orParts = _splitBooleanExpression(value, 'or');
    if (orParts != null) {
      return orParts.any(evaluateCondition);
    }

    final andParts = _splitBooleanExpression(value, 'and');
    if (andParts != null) {
      return andParts.every(evaluateCondition);
    }

    if (value.startsWith('not ')) {
      return !evaluateCondition(value.substring(4));
    }
    if (value.startsWith('!')) return !evaluateCondition(value.substring(1));

    final equality = _splitComparison(value, '==');
    if (equality != null) {
      return _evaluateComparable(equality.left) ==
          _evaluateComparable(equality.right);
    }

    final inequality = _splitComparison(value, '!=');
    if (inequality != null) {
      return _evaluateComparable(inequality.left) !=
          _evaluateComparable(inequality.right);
    }

    for (final operator in const ['>=', '<=', '>', '<']) {
      final comparison = _splitComparison(value, operator);
      if (comparison != null) {
        return _evaluateOrderedComparison(comparison, operator);
      }
    }

    final variable = lookupVariable(value);
    if (!variable.found) return false;

    final variableValue = variable.value;
    if (variableValue is bool) return variableValue;
    if (variableValue is num) return variableValue != 0;
    if (variableValue is String) return variableValue.isNotEmpty;
    if (variableValue is Iterable) return variableValue.isNotEmpty;
    return variableValue != null;
  }

  dynamic _evaluateComparable(String expression) {
    final value = expression.trim();
    final parenthesized = _parenthesizedExpression(value);
    if (parenthesized != null) {
      if (_isConditionExpression(parenthesized)) {
        return evaluateCondition(parenthesized);
      }
      return _evaluateComparable(parenthesized);
    }
    final variable = lookupVariable(value);
    if (variable.found) return variable.value;
    return evaluateLiteral(value);
  }

  bool _evaluateOrderedComparison(
    _ConditionComparison comparison,
    String operator,
  ) {
    final left = _evaluateComparable(comparison.left);
    final right = _evaluateComparable(comparison.right);

    if (left is num && right is num) {
      return switch (operator) {
        '>=' => left >= right,
        '<=' => left <= right,
        '>' => left > right,
        '<' => left < right,
        _ => false,
      };
    }

    return false;
  }

  String? _parenthesizedExpression(String value) {
    final current = value.trim();
    if (!current.startsWith('(') || !current.endsWith(')')) return null;

    final close = _matchingCloseParenthesis(current, 0);
    if (close != current.length - 1) return null;
    return current.substring(1, current.length - 1).trim();
  }

  bool _isConditionExpression(String value) {
    final current = _stripOuterParentheses(value.trim());
    if (current == 'True' || current == 'true') return true;
    if (current == 'False' || current == 'false') return true;
    if (current.startsWith('not ') || current.startsWith('!')) return true;
    if (_splitBooleanExpression(current, 'or') != null) return true;
    if (_splitBooleanExpression(current, 'and') != null) return true;

    for (final operator in const ['==', '!=', '>=', '<=', '>', '<']) {
      if (_splitComparison(current, operator) != null) return true;
    }

    return false;
  }

  String _stripOuterParentheses(String value) {
    var current = value.trim();
    while (current.startsWith('(') && current.endsWith(')')) {
      final close = _matchingCloseParenthesis(current, 0);
      if (close != current.length - 1) return current;
      current = current.substring(1, current.length - 1).trim();
    }
    return current;
  }

  int? _matchingCloseParenthesis(String value, int openIndex) {
    String? quote;
    var escaped = false;
    var depth = 0;
    for (var index = openIndex; index < value.length; index += 1) {
      final character = value[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (character == quote) quote = null;
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (character == '(') {
        depth += 1;
        continue;
      }
      if (character == ')') {
        depth -= 1;
        if (depth == 0) return index;
      }
    }
    return null;
  }

  List<String>? _splitBooleanExpression(String value, String operator) {
    final parts = <String>[];
    var start = 0;
    String? quote;
    var escaped = false;
    var depth = 0;
    for (var index = 0; index < value.length; index += 1) {
      final character = value[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (character == quote) quote = null;
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (character == '(' || character == '[' || character == '{') {
        depth += 1;
        continue;
      }
      if (character == ')' || character == ']' || character == '}') {
        if (depth > 0) depth -= 1;
        continue;
      }
      if (depth == 0 && _isWordAt(value, operator, index)) {
        parts.add(value.substring(start, index).trim());
        start = index + operator.length;
        index += operator.length - 1;
      }
    }

    if (parts.isEmpty) return null;
    parts.add(value.substring(start).trim());
    return parts;
  }

  bool _isWordAt(String value, String word, int index) {
    if (!value.startsWith(word, index)) return false;
    final before = index == 0 ? null : value[index - 1];
    final afterIndex = index + word.length;
    final after = afterIndex >= value.length ? null : value[afterIndex];
    return !_isIdentifierCharacter(before) && !_isIdentifierCharacter(after);
  }

  bool _isIdentifierCharacter(String? character) {
    return character != null && RegExp(r'[A-Za-z0-9_]').hasMatch(character);
  }

  _ConditionComparison? _splitComparison(String condition, String operator) {
    String? quote;
    var escaped = false;
    var depth = 0;

    for (var index = 0; index <= condition.length - operator.length; index++) {
      final character = condition[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (character == r'\') {
        escaped = true;
        continue;
      }
      if (quote != null) {
        if (character == quote) quote = null;
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        continue;
      }
      if (character == '(' || character == '[' || character == '{') {
        depth += 1;
        continue;
      }
      if (character == ')' || character == ']' || character == '}') {
        if (depth > 0) depth -= 1;
        continue;
      }
      if (depth == 0 && condition.startsWith(operator, index)) {
        return _ConditionComparison(
          condition.substring(0, index),
          condition.substring(index + operator.length),
        );
      }
    }

    return null;
  }
}

class _ConditionComparison {
  const _ConditionComparison(this.left, this.right);

  final String left;
  final String right;
}
