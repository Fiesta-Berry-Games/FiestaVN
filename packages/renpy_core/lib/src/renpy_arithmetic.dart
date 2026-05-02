/// Resolves a bare token (a variable name or literal) to a value.
///
/// Returns `null` when the token cannot be resolved. A `null` literal such
/// as `None` is reported through [RenPyArithmeticValue] rather than this
/// return value so the parser can tell "no value" apart from "value is null".
typedef RenPyArithmeticResolver = RenPyArithmeticValue Function(String token);

/// A resolved arithmetic operand.
///
/// [resolved] is `false` when the token is neither a known variable nor a
/// recognizable literal, letting the parser abort and the caller fall back.
class RenPyArithmeticValue {
  const RenPyArithmeticValue(this.resolved, this.value);

  const RenPyArithmeticValue.unresolved() : this(false, null);

  final bool resolved;
  final dynamic value;
}

/// Evaluates RenPy arithmetic expressions such as `points + bonus * 2`.
///
/// Supports the `+ - * / %` operators with standard precedence,
/// parentheses, integer and double literals, string literals and variable
/// substitution. The layer is intentionally small: anything it does not
/// understand yields `null` so callers can fall back to their own handling.
class RenPyArithmetic {
  /// Evaluates [expression] against [variables].
  ///
  /// Supports `+ - * / %` and parentheses, integer/double literals, string
  /// literals, and variable substitution. Returns the computed value
  /// (int/double/String/bool/null). For a bare literal or variable reference
  /// (no operators) returns its resolved value. Returns `null` if the
  /// expression cannot be parsed as arithmetic so the caller can fall back.
  static Object? evaluate(String expression, Map<String, dynamic> variables) {
    return evaluateWith(expression, (token) {
      if (variables.containsKey(token)) {
        return RenPyArithmeticValue(true, variables[token]);
      }
      return _resolveLiteral(token);
    });
  }

  /// Evaluates [expression] using [resolver] to look up bare tokens.
  ///
  /// This is the entry point used by callers that already own variable
  /// lookup and literal parsing (such as the expression evaluator). Returns
  /// `null` when [expression] cannot be parsed as arithmetic.
  static Object? evaluateWith(
    String expression,
    RenPyArithmeticResolver resolver,
  ) {
    final tokens = _tokenize(expression);
    if (tokens == null || tokens.isEmpty) return null;

    final parser = _ArithmeticParser(tokens, resolver);
    final result = parser.parse();
    if (result == null || !parser.atEnd) return null;
    return result.resolved ? result.value : null;
  }

  static RenPyArithmeticValue _resolveLiteral(String token) {
    final value = token.trim();
    if (value == 'True' || value == 'true') {
      return const RenPyArithmeticValue(true, true);
    }
    if (value == 'False' || value == 'false') {
      return const RenPyArithmeticValue(true, false);
    }
    if (value == 'None' || value == 'null') {
      return const RenPyArithmeticValue(true, null);
    }

    final quoted = RegExp(r'''^["'](.*)["']$''').firstMatch(value);
    if (quoted != null) return RenPyArithmeticValue(true, quoted.group(1));

    final integer = int.tryParse(value);
    if (integer != null) return RenPyArithmeticValue(true, integer);

    final decimal = double.tryParse(value);
    if (decimal != null) return RenPyArithmeticValue(true, decimal);

    return const RenPyArithmeticValue.unresolved();
  }

  static List<_Token>? _tokenize(String expression) {
    final tokens = <_Token>[];
    final operand = StringBuffer();

    void flush() {
      final text = operand.toString().trim();
      if (text.isNotEmpty) tokens.add(_Token(_TokenKind.operand, text));
      operand.clear();
    }

    String? quote;
    var escaped = false;
    for (var index = 0; index < expression.length; index += 1) {
      final character = expression[index];
      if (quote != null) {
        operand.write(character);
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == quote) {
          quote = null;
        }
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
        operand.write(character);
        continue;
      }
      switch (character) {
        case '+':
        case '-':
        case '*':
        case '/':
        case '%':
        case '(':
        case ')':
          flush();
          tokens.add(_Token(_TokenKind.operatorOrParen, character));
        default:
          operand.write(character);
      }
    }
    if (quote != null) return null;
    flush();
    return tokens;
  }
}

enum _TokenKind { operand, operatorOrParen }

class _Token {
  const _Token(this.kind, this.text);

  final _TokenKind kind;
  final String text;
}

/// Recursive descent parser implementing standard arithmetic precedence.
class _ArithmeticParser {
  _ArithmeticParser(this._tokens, this._resolver);

  final List<_Token> _tokens;
  final RenPyArithmeticResolver _resolver;
  int _index = 0;

  bool get atEnd => _index >= _tokens.length;

  _Token? get _current => atEnd ? null : _tokens[_index];

  RenPyArithmeticValue? parse() => _parseAdditive();

  RenPyArithmeticValue? _parseAdditive() {
    var left = _parseMultiplicative();
    if (left == null) return null;

    while (_current?.kind == _TokenKind.operatorOrParen &&
        (_current!.text == '+' || _current!.text == '-')) {
      final operator = _current!.text;
      _index += 1;
      final right = _parseMultiplicative();
      if (right == null) return null;
      final combined = _apply(left!, operator, right);
      if (combined == null) return null;
      left = combined;
    }
    return left;
  }

  RenPyArithmeticValue? _parseMultiplicative() {
    var left = _parseUnary();
    if (left == null) return null;

    while (_current?.kind == _TokenKind.operatorOrParen &&
        (_current!.text == '*' ||
            _current!.text == '/' ||
            _current!.text == '%')) {
      final operator = _current!.text;
      _index += 1;
      final right = _parseUnary();
      if (right == null) return null;
      final combined = _apply(left!, operator, right);
      if (combined == null) return null;
      left = combined;
    }
    return left;
  }

  RenPyArithmeticValue? _parseUnary() {
    if (_current?.kind == _TokenKind.operatorOrParen &&
        (_current!.text == '-' || _current!.text == '+')) {
      final operator = _current!.text;
      _index += 1;
      final operand = _parseUnary();
      if (operand == null || !operand.resolved) return null;
      final value = operand.value;
      if (value is! num) return null;
      return RenPyArithmeticValue(true, operator == '-' ? -value : value);
    }
    return _parsePrimary();
  }

  RenPyArithmeticValue? _parsePrimary() {
    final token = _current;
    if (token == null) return null;

    if (token.kind == _TokenKind.operatorOrParen) {
      if (token.text != '(') return null;
      _index += 1;
      final inner = _parseAdditive();
      if (inner == null) return null;
      if (_current?.text != ')') return null;
      _index += 1;
      return inner;
    }

    _index += 1;
    return _resolver(token.text);
  }

  RenPyArithmeticValue? _apply(
    RenPyArithmeticValue left,
    String operator,
    RenPyArithmeticValue right,
  ) {
    if (!left.resolved || !right.resolved) return null;
    final a = left.value;
    final b = right.value;

    if (operator == '+' && a is String && b is String) {
      return RenPyArithmeticValue(true, a + b);
    }
    if (operator == '*' && a is String && b is int) {
      return RenPyArithmeticValue(true, a * b);
    }
    if (operator == '*' && a is int && b is String) {
      return RenPyArithmeticValue(true, b * a);
    }

    if (a is! num || b is! num) return null;
    switch (operator) {
      case '+':
        return RenPyArithmeticValue(true, a + b);
      case '-':
        return RenPyArithmeticValue(true, a - b);
      case '*':
        return RenPyArithmeticValue(true, a * b);
      case '/':
        if (b == 0) return null;
        return RenPyArithmeticValue(true, a / b);
      case '%':
        if (b == 0) return null;
        return RenPyArithmeticValue(true, a % b);
      default:
        return null;
    }
  }
}
