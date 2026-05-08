import 'dart:math' as math;

/// A namespace the [RenPyPythonEvaluator] reads variables from and writes
/// mutations back to.
///
/// RenPy organizes runtime state into a handful of scopes: the default
/// `store` (bare names such as `points`), plus the `persistent.`, `config.`
/// and `gui.` prefixed scopes. An implementation maps each of those onto its
/// own backing maps so the evaluator never forks engine state - reads and
/// in-place mutations (`list.append`, `dict[...] = ...` via method calls) flow
/// straight through to the runner's existing variable storage.
abstract class RenPyPythonScope {
  /// Whether [name] resolves to a value in any scope.
  ///
  /// [name] may carry a scope prefix such as `persistent.flag`.
  bool has(String name);

  /// Reads [name] from the appropriate scope, returning `null` when absent.
  Object? read(String name);

  /// Writes [value] to [name] in the appropriate scope.
  void write(String name, Object? value);
}

/// A scope backed by plain Dart maps, one per RenPy namespace.
///
/// The runner passes in the maps it already uses for `store` and `persistent`
/// state so the two views stay in sync; `config` and `gui` default to fresh
/// maps when a caller does not supply them.
class RenPyMapScope implements RenPyPythonScope {
  RenPyMapScope({
    required Map<String, Object?> store,
    required Map<String, Object?> persistent,
    Map<String, Object?>? config,
    Map<String, Object?>? gui,
  }) : _store = store,
       _persistent = persistent,
       _config = config ?? <String, Object?>{},
       _gui = gui ?? <String, Object?>{};

  final Map<String, Object?> _store;
  final Map<String, Object?> _persistent;
  final Map<String, Object?> _config;
  final Map<String, Object?> _gui;

  Map<String, Object?> _mapFor(String name) {
    if (name.startsWith('persistent.')) return _persistent;
    if (name.startsWith('config.')) return _config;
    if (name.startsWith('gui.')) return _gui;
    return _store;
  }

  String _fieldFor(String name) {
    final dot = name.indexOf('.');
    if (dot < 0) return name;
    final prefix = name.substring(0, dot);
    if (prefix == 'persistent' || prefix == 'config' || prefix == 'gui') {
      return name.substring(dot + 1);
    }
    return name;
  }

  @override
  bool has(String name) {
    final field = _fieldFor(name);
    if (field.isEmpty) return false;
    return _mapFor(name).containsKey(field);
  }

  @override
  Object? read(String name) {
    final field = _fieldFor(name);
    return _mapFor(name)[field];
  }

  @override
  void write(String name, Object? value) {
    final field = _fieldFor(name);
    if (field.isEmpty) return;
    _mapFor(name)[field] = value;
  }
}

/// Thrown when the evaluator meets a name, syntax or operation it does not
/// support. Callers catch this and fall back to their previous handling so a
/// partial Python subset never regresses behavior that used to work.
class RenPyPythonError implements Exception {
  RenPyPythonError(this.message);

  final String message;

  @override
  String toString() => 'RenPyPythonError: $message';
}

/// Raised specifically for an unknown name, so a caller can tell a genuine
/// `NameError` apart from unsupported syntax if it wants to.
class RenPyPythonNameError extends RenPyPythonError {
  RenPyPythonNameError(String name) : super('name `$name` is not defined');
}

/// A recursive-descent evaluator for a Python EXPRESSION subset.
///
/// It tokenizes, parses with correct operator precedence, then walks the tree
/// against a [RenPyPythonScope]. Anything outside the supported subset throws
/// a [RenPyPythonError] rather than guessing, which lets the runner degrade to
/// its older regex/arithmetic handling. Statement execution (assignment
/// targets, control flow, `def`, `python:` blocks) is intentionally out of
/// scope here - only expressions, including expression-statements with side
/// effects such as `items.append(x)`.
class RenPyPythonEvaluator {
  const RenPyPythonEvaluator();

  /// Evaluates [expression] against [scope] and returns its Dart value.
  ///
  /// Throws [RenPyPythonError] (or [RenPyPythonNameError]) when the expression
  /// falls outside the supported subset so the caller can fall back.
  Object? evaluate(String expression, RenPyPythonScope scope) {
    try {
      final tokens = _Lexer(expression).tokenize();
      final parser = _Parser(tokens);
      final node = parser.parseExpression();
      parser.expectEnd();
      return node.eval(_Interpreter(scope));
    } on RenPyPythonError {
      rethrow;
    } catch (e) {
      // Argument coercion and similar operations can throw plain Dart errors
      // (TypeError, RangeError, ...). Normalize them so callers see a single
      // RenPyPythonError and fall back instead of aborting on an unguarded
      // exception.
      throw RenPyPythonError('evaluation failed: $e');
    }
  }

  /// Applies Python truthiness to a Dart value, matching the rules used for
  /// `if`/`while` conditions: `None`, `0`, empty string/collection are falsy.
  static bool truthy(Object? value) => _Interpreter.truthy(value);
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

enum _TokenType { number, string, fstring, name, op, eof }

class _Token {
  _Token(this.type, this.value, {this.fstring});

  final _TokenType type;
  final String value;

  /// For an f-string token, the parsed [_FStringPart] list.
  final List<_FStringPart>? fstring;
}

/// A literal chunk or an embedded expression within an f-string.
class _FStringPart {
  _FStringPart.text(this.text) : expression = null, conversion = null;
  _FStringPart.expression(this.expression, this.conversion) : text = null;

  final String? text;
  final String? expression;

  /// The `!r` / `!s` conversion or a `:spec` format, kept as a raw suffix.
  final String? conversion;
}

const _twoCharOps = {'==', '!=', '<=', '>=', '//', '**', '<<', '>>'};

class _Lexer {
  _Lexer(this._source);

  final String _source;
  int _pos = 0;

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (true) {
      _skipWhitespace();
      if (_pos >= _source.length) break;
      tokens.add(_next());
    }
    tokens.add(_Token(_TokenType.eof, ''));
    return tokens;
  }

  void _skipWhitespace() {
    while (_pos < _source.length) {
      final ch = _source[_pos];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        _pos += 1;
      } else {
        break;
      }
    }
  }

  _Token _next() {
    final ch = _source[_pos];

    // String prefixes: f"", r"", plain quotes.
    if (ch == 'f' ||
        ch == 'F' ||
        ch == 'r' ||
        ch == 'R' ||
        ch == 'b' ||
        ch == 'B') {
      final next = _pos + 1 < _source.length ? _source[_pos + 1] : '';
      if (next == '"' || next == "'") {
        final isFString = ch == 'f' || ch == 'F';
        final isRaw = ch == 'r' || ch == 'R';
        _pos += 1;
        return _readString(isFString: isFString, isRaw: isRaw);
      }
    }
    if (ch == '"' || ch == "'") {
      return _readString(isFString: false, isRaw: false);
    }
    if (_isDigit(ch) ||
        (ch == '.' &&
            _pos + 1 < _source.length &&
            _isDigit(_source[_pos + 1]))) {
      return _readNumber();
    }
    if (_isNameStart(ch)) {
      return _readName();
    }
    return _readOperator();
  }

  bool _isDigit(String ch) => ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;

  bool _isNameStart(String ch) =>
      ch == '_' ||
      (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
      (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0);

  bool _isNameChar(String ch) => _isNameStart(ch) || _isDigit(ch);

  _Token _readName() {
    final start = _pos;
    while (_pos < _source.length && _isNameChar(_source[_pos])) {
      _pos += 1;
    }
    return _Token(_TokenType.name, _source.substring(start, _pos));
  }

  _Token _readNumber() {
    // The scanner is deliberately permissive: int/float and the radix prefixes
    // are all one `number` token, and the parser decides the concrete value
    // from the text in [_Parser._parseNumber].
    final start = _pos;
    while (_pos < _source.length) {
      final ch = _source[_pos];
      if (_isDigit(ch) || ch == '_' || ch == '.') {
        _pos += 1;
      } else if (ch == 'e' || ch == 'E') {
        _pos += 1;
        if (_pos < _source.length &&
            (_source[_pos] == '+' || _source[_pos] == '-')) {
          _pos += 1;
        }
      } else if (ch == 'x' ||
          ch == 'X' ||
          ch == 'o' ||
          ch == 'O' ||
          ch == 'b' ||
          ch == 'B') {
        _pos += 1;
      } else {
        break;
      }
    }
    return _Token(_TokenType.number, _source.substring(start, _pos));
  }

  _Token _readString({required bool isFString, required bool isRaw}) {
    final quote = _source[_pos];
    final triple = _source.startsWith('$quote$quote$quote', _pos);
    final delimiter = triple ? '$quote$quote$quote' : quote;
    _pos += delimiter.length;

    final buffer = StringBuffer();
    while (_pos < _source.length) {
      if (_source.startsWith(delimiter, _pos)) {
        _pos += delimiter.length;
        final raw = buffer.toString();
        if (isFString) {
          return _Token(_TokenType.fstring, raw, fstring: _parseFString(raw));
        }
        return _Token(_TokenType.string, isRaw ? raw : _unescape(raw));
      }
      final ch = _source[_pos];
      if (!isRaw && ch == r'\' && _pos + 1 < _source.length) {
        buffer.write(ch);
        buffer.write(_source[_pos + 1]);
        _pos += 2;
        continue;
      }
      buffer.write(ch);
      _pos += 1;
    }
    throw RenPyPythonError('unterminated string literal');
  }

  String _unescape(String raw) {
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i += 1) {
      final ch = raw[i];
      if (ch == r'\' && i + 1 < raw.length) {
        final next = raw[i + 1];
        i += 1;
        switch (next) {
          case 'n':
            buffer.write('\n');
          case 't':
            buffer.write('\t');
          case 'r':
            buffer.write('\r');
          case r'\':
            buffer.write(r'\');
          case "'":
            buffer.write("'");
          case '"':
            buffer.write('"');
          case '0':
            buffer.write(' ');
          default:
            buffer.write(r'\');
            buffer.write(next);
        }
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  /// Splits an f-string body into literal text and `{expr}` parts. The inner
  /// expression text is handed back to the parser later, so this only needs to
  /// find the matching braces while respecting nested brackets and quotes.
  List<_FStringPart> _parseFString(String raw) {
    final parts = <_FStringPart>[];
    final text = StringBuffer();
    var i = 0;
    while (i < raw.length) {
      final ch = raw[i];
      if (ch == '{' && i + 1 < raw.length && raw[i + 1] == '{') {
        text.write('{');
        i += 2;
        continue;
      }
      if (ch == '}' && i + 1 < raw.length && raw[i + 1] == '}') {
        text.write('}');
        i += 2;
        continue;
      }
      if (ch == '{') {
        if (text.isNotEmpty) {
          parts.add(_FStringPart.text(_unescape(text.toString())));
          text.clear();
        }
        final exprStart = i + 1;
        var depth = 1;
        String? quote;
        var j = exprStart;
        while (j < raw.length && depth > 0) {
          final c = raw[j];
          if (quote != null) {
            if (c == quote) quote = null;
          } else if (c == '"' || c == "'") {
            quote = c;
          } else if (c == '{' || c == '(' || c == '[') {
            depth += 1;
          } else if (c == '}' || c == ')' || c == ']') {
            depth -= 1;
            if (depth == 0) break;
          }
          j += 1;
        }
        final inner = raw.substring(exprStart, j);
        i = j + 1;
        // Separate an optional !conversion / :format spec.
        var expr = inner;
        String? conversion;
        final bang = _topLevelIndex(inner, '!');
        final colon = _topLevelIndex(inner, ':');
        final cut = [if (bang >= 0) bang, if (colon >= 0) colon];
        if (cut.isNotEmpty) {
          final at = cut.reduce(math.min);
          expr = inner.substring(0, at);
          conversion = inner.substring(at);
        }
        parts.add(_FStringPart.expression(expr.trim(), conversion));
        continue;
      }
      text.write(ch);
      i += 1;
    }
    if (text.isNotEmpty) {
      parts.add(_FStringPart.text(_unescape(text.toString())));
    }
    return parts;
  }

  int _topLevelIndex(String s, String target) {
    var depth = 0;
    String? quote;
    for (var i = 0; i < s.length; i += 1) {
      final c = s[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
      } else if (c == '(' || c == '[' || c == '{') {
        depth += 1;
      } else if (c == ')' || c == ']' || c == '}') {
        depth -= 1;
      } else if (depth == 0 && c == target) {
        return i;
      }
    }
    return -1;
  }

  _Token _readOperator() {
    if (_pos + 1 < _source.length) {
      final two = _source.substring(_pos, _pos + 2);
      if (_twoCharOps.contains(two)) {
        _pos += 2;
        return _Token(_TokenType.op, two);
      }
    }
    final ch = _source[_pos];
    _pos += 1;
    return _Token(_TokenType.op, ch);
  }
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

abstract class _Node {
  Object? eval(_Interpreter interp);
}

class _LiteralNode implements _Node {
  _LiteralNode(this.value);
  final Object? value;
  @override
  Object? eval(_Interpreter interp) => value;
}

class _NameNode implements _Node {
  _NameNode(this.name);
  final String name;
  @override
  Object? eval(_Interpreter interp) => interp.readName(name);
}

class _FStringNode implements _Node {
  _FStringNode(this.parts);
  final List<_FStringPart> parts;
  @override
  Object? eval(_Interpreter interp) => interp.evalFString(parts);
}

class _ListNode implements _Node {
  _ListNode(this.elements);
  final List<_Node> elements;
  @override
  Object? eval(_Interpreter interp) => [
    for (final element in elements) element.eval(interp),
  ];
}

class _TupleNode implements _Node {
  _TupleNode(this.elements);
  final List<_Node> elements;
  @override
  Object? eval(_Interpreter interp) => [
    for (final element in elements) element.eval(interp),
  ];
}

class _SetNode implements _Node {
  _SetNode(this.elements);
  final List<_Node> elements;
  @override
  Object? eval(_Interpreter interp) => {
    for (final element in elements) element.eval(interp),
  };
}

class _DictNode implements _Node {
  _DictNode(this.entries);
  final List<MapEntry<_Node, _Node>> entries;
  @override
  Object? eval(_Interpreter interp) => {
    for (final entry in entries)
      entry.key.eval(interp): entry.value.eval(interp),
  };
}

class _UnaryNode implements _Node {
  _UnaryNode(this.op, this.operand);
  final String op;
  final _Node operand;
  @override
  Object? eval(_Interpreter interp) => interp.unary(op, operand.eval(interp));
}

class _BinaryNode implements _Node {
  _BinaryNode(this.op, this.left, this.right);
  final String op;
  final _Node left;
  final _Node right;
  @override
  Object? eval(_Interpreter interp) =>
      interp.binary(op, left.eval(interp), right.eval(interp));
}

class _BoolNode implements _Node {
  _BoolNode(this.op, this.left, this.right);
  final String op; // 'and' | 'or'
  final _Node left;
  final _Node right;
  @override
  Object? eval(_Interpreter interp) {
    final leftValue = left.eval(interp);
    if (op == 'and') {
      return _Interpreter.truthy(leftValue) ? right.eval(interp) : leftValue;
    }
    return _Interpreter.truthy(leftValue) ? leftValue : right.eval(interp);
  }
}

class _NotNode implements _Node {
  _NotNode(this.operand);
  final _Node operand;
  @override
  Object? eval(_Interpreter interp) =>
      !_Interpreter.truthy(operand.eval(interp));
}

class _CompareNode implements _Node {
  _CompareNode(this.operands, this.operators);
  final List<_Node> operands;
  final List<String> operators;
  @override
  Object? eval(_Interpreter interp) => interp.compare(operands, operators);
}

class _TernaryNode implements _Node {
  _TernaryNode(this.body, this.condition, this.orElse);
  final _Node body;
  final _Node condition;
  final _Node orElse;
  @override
  Object? eval(_Interpreter interp) =>
      _Interpreter.truthy(condition.eval(interp))
          ? body.eval(interp)
          : orElse.eval(interp);
}

class _AttributeNode implements _Node {
  _AttributeNode(this.target, this.attribute, {this.fullName});
  final _Node target;
  final String attribute;

  /// The dotted source text (e.g. `persistent.flag`) when [target] is a name
  /// chain, letting scoped namespaces resolve in one lookup.
  final String? fullName;
  @override
  Object? eval(_Interpreter interp) => interp.attribute(this);
}

class _SubscriptNode implements _Node {
  _SubscriptNode(this.target, this.index);
  final _Node target;
  final _Node index;
  @override
  Object? eval(_Interpreter interp) =>
      interp.subscript(target.eval(interp), index.eval(interp));
}

class _SliceNode implements _Node {
  _SliceNode(this.start, this.stop, this.step);
  final _Node? start;
  final _Node? stop;
  final _Node? step;
  @override
  Object? eval(_Interpreter interp) =>
      _Slice(start?.eval(interp), stop?.eval(interp), step?.eval(interp));
}

class _CallNode implements _Node {
  _CallNode(this.target, this.positional, this.keywords);
  final _Node target;
  final List<_Node> positional;
  final Map<String, _Node> keywords;
  @override
  Object? eval(_Interpreter interp) => interp.call(this);
}

class _ComprehensionNode implements _Node {
  _ComprehensionNode({
    required this.kind,
    required this.element,
    required this.value,
    required this.variable,
    required this.iterable,
    required this.condition,
  });
  final String kind; // 'list' | 'set' | 'dict'
  final _Node element; // key for dict, element otherwise
  final _Node? value; // dict value
  final List<String> variable; // target names (supports tuple unpack)
  final _Node iterable;
  final _Node? condition;
  @override
  Object? eval(_Interpreter interp) => interp.comprehension(this);
}

/// A slice produced by a `[a:b:c]` subscript, resolved against a sequence.
class _Slice {
  _Slice(this.start, this.stop, this.step);
  final Object? start;
  final Object? stop;
  final Object? step;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class _Parser {
  _Parser(this._tokens);

  final List<_Token> _tokens;
  int _index = 0;

  _Token get _current => _tokens[_index];

  _Token _advance() => _tokens[_index++];

  bool _isOp(String value) =>
      _current.type == _TokenType.op && _current.value == value;

  bool _isKeyword(String value) =>
      _current.type == _TokenType.name && _current.value == value;

  void _expectOp(String value) {
    if (!_isOp(value)) {
      throw RenPyPythonError('expected `$value`, found `${_current.value}`');
    }
    _advance();
  }

  void expectEnd() {
    if (_current.type != _TokenType.eof) {
      throw RenPyPythonError('unexpected trailing `${_current.value}`');
    }
  }

  _Node parseExpression() => _parseTernary();

  _Node _parseTernary() {
    final body = _parseOr();
    if (_isKeyword('if')) {
      _advance();
      final condition = _parseOr();
      if (!_isKeyword('else')) {
        throw RenPyPythonError('expected `else` in conditional expression');
      }
      _advance();
      final orElse = _parseTernary();
      return _TernaryNode(body, condition, orElse);
    }
    return body;
  }

  _Node _parseOr() {
    var node = _parseAnd();
    while (_isKeyword('or')) {
      _advance();
      node = _BoolNode('or', node, _parseAnd());
    }
    return node;
  }

  _Node _parseAnd() {
    var node = _parseNot();
    while (_isKeyword('and')) {
      _advance();
      node = _BoolNode('and', node, _parseNot());
    }
    return node;
  }

  _Node _parseNot() {
    if (_isKeyword('not')) {
      _advance();
      return _NotNode(_parseNot());
    }
    return _parseComparison();
  }

  _Node _parseComparison() {
    final operands = <_Node>[_parseBitOr()];
    final operators = <String>[];
    while (true) {
      final op = _matchComparisonOperator();
      if (op == null) break;
      operators.add(op);
      operands.add(_parseBitOr());
    }
    if (operators.isEmpty) return operands.first;
    return _CompareNode(operands, operators);
  }

  String? _matchComparisonOperator() {
    if (_current.type == _TokenType.op) {
      const ops = {'==', '!=', '<', '<=', '>', '>='};
      if (ops.contains(_current.value)) {
        return _advance().value;
      }
    }
    if (_isKeyword('in')) {
      _advance();
      return 'in';
    }
    if (_isKeyword('not')) {
      // `not in`
      if (_tokens[_index + 1].type == _TokenType.name &&
          _tokens[_index + 1].value == 'in') {
        _advance();
        _advance();
        return 'not in';
      }
      return null;
    }
    if (_isKeyword('is')) {
      _advance();
      if (_isKeyword('not')) {
        _advance();
        return 'is not';
      }
      return 'is';
    }
    return null;
  }

  _Node _parseBitOr() {
    var node = _parseBitXor();
    while (_isOp('|')) {
      _advance();
      node = _BinaryNode('|', node, _parseBitXor());
    }
    return node;
  }

  _Node _parseBitXor() {
    var node = _parseBitAnd();
    while (_isOp('^')) {
      _advance();
      node = _BinaryNode('^', node, _parseBitAnd());
    }
    return node;
  }

  _Node _parseBitAnd() {
    var node = _parseShift();
    while (_isOp('&')) {
      _advance();
      node = _BinaryNode('&', node, _parseShift());
    }
    return node;
  }

  _Node _parseShift() {
    var node = _parseAdditive();
    while (_isOp('<<') || _isOp('>>')) {
      final op = _advance().value;
      node = _BinaryNode(op, node, _parseAdditive());
    }
    return node;
  }

  _Node _parseAdditive() {
    var node = _parseMultiplicative();
    while (_isOp('+') || _isOp('-')) {
      final op = _advance().value;
      node = _BinaryNode(op, node, _parseMultiplicative());
    }
    return node;
  }

  _Node _parseMultiplicative() {
    var node = _parseUnary();
    while (_isOp('*') || _isOp('/') || _isOp('//') || _isOp('%')) {
      final op = _advance().value;
      node = _BinaryNode(op, node, _parseUnary());
    }
    return node;
  }

  _Node _parseUnary() {
    if (_isOp('-') || _isOp('+') || _isOp('~')) {
      final op = _advance().value;
      return _UnaryNode(op, _parseUnary());
    }
    return _parsePower();
  }

  _Node _parsePower() {
    final base = _parsePostfix();
    if (_isOp('**')) {
      _advance();
      // ** is right associative and binds tighter than a unary on its right.
      return _BinaryNode('**', base, _parseUnary());
    }
    return base;
  }

  _Node _parsePostfix() {
    var node = _parsePrimary();
    while (true) {
      if (_isOp('.')) {
        _advance();
        if (_current.type != _TokenType.name) {
          throw RenPyPythonError('expected attribute name after `.`');
        }
        final attribute = _advance().value;
        node = _AttributeNode(
          node,
          attribute,
          fullName: _dottedName(node, attribute),
        );
      } else if (_isOp('(')) {
        node = _parseCall(node);
      } else if (_isOp('[')) {
        node = _parseSubscript(node);
      } else {
        break;
      }
    }
    return node;
  }

  /// Builds the dotted source text for a name chain so scoped namespaces
  /// (`persistent.x`, `config.y`) resolve in a single lookup.
  String? _dottedName(_Node target, String attribute) {
    if (target is _NameNode) return '${target.name}.$attribute';
    if (target is _AttributeNode && target.fullName != null) {
      return '${target.fullName}.$attribute';
    }
    return null;
  }

  _Node _parseCall(_Node target) {
    _expectOp('(');
    final positional = <_Node>[];
    final keywords = <String, _Node>{};
    while (!_isOp(')')) {
      // Keyword argument: name=value.
      if (_current.type == _TokenType.name &&
          _tokens[_index + 1].type == _TokenType.op &&
          _tokens[_index + 1].value == '=') {
        final name = _advance().value;
        _advance(); // =
        keywords[name] = parseExpression();
      } else {
        positional.add(parseExpression());
      }
      if (_isOp(',')) {
        _advance();
      } else {
        break;
      }
    }
    _expectOp(')');
    return _CallNode(target, positional, keywords);
  }

  _Node _parseSubscript(_Node target) {
    _expectOp('[');
    final index = _parseSubscriptIndex();
    _expectOp(']');
    return _SubscriptNode(target, index);
  }

  _Node _parseSubscriptIndex() {
    _Node? start;
    if (!_isOp(':')) {
      start = parseExpression();
      if (!_isOp(':')) return start;
    }
    // A slice: collect up to two more colon-separated parts.
    _expectOp(':');
    _Node? stop;
    if (!_isOp(':') && !_isOp(']')) {
      stop = parseExpression();
    }
    _Node? step;
    if (_isOp(':')) {
      _advance();
      if (!_isOp(']')) step = parseExpression();
    }
    return _SliceNode(start, stop, step);
  }

  _Node _parsePrimary() {
    final token = _current;
    switch (token.type) {
      case _TokenType.number:
        _advance();
        return _LiteralNode(_parseNumber(token.value));
      case _TokenType.string:
        return _parseAdjacentStrings();
      case _TokenType.fstring:
        _advance();
        return _FStringNode(token.fstring!);
      case _TokenType.name:
        if (token.value == 'True') {
          _advance();
          return _LiteralNode(true);
        }
        if (token.value == 'False') {
          _advance();
          return _LiteralNode(false);
        }
        if (token.value == 'None') {
          _advance();
          return _LiteralNode(null);
        }
        if (token.value == 'not') {
          return _parseNot();
        }
        if (token.value == 'lambda') {
          throw RenPyPythonError('lambda is not supported');
        }
        _advance();
        return _NameNode(token.value);
      case _TokenType.op:
        if (token.value == '(') return _parseParenOrTuple();
        if (token.value == '[') return _parseListOrComprehension();
        if (token.value == '{') return _parseDictOrSet();
        throw RenPyPythonError('unexpected token `${token.value}`');
      case _TokenType.eof:
        throw RenPyPythonError('unexpected end of expression');
    }
  }

  /// Concatenates adjacent string literals (`"a" "b"` -> `"ab"`).
  _Node _parseAdjacentStrings() {
    final buffer = StringBuffer();
    while (_current.type == _TokenType.string) {
      buffer.write(_advance().value);
    }
    return _LiteralNode(buffer.toString());
  }

  Object _parseNumber(String text) {
    final clean = text.replaceAll('_', '');
    if (clean.startsWith('0x') || clean.startsWith('0X')) {
      return int.parse(clean.substring(2), radix: 16);
    }
    if (clean.startsWith('0o') || clean.startsWith('0O')) {
      return int.parse(clean.substring(2), radix: 8);
    }
    if (clean.startsWith('0b') || clean.startsWith('0B')) {
      return int.parse(clean.substring(2), radix: 2);
    }
    if (clean.contains('.') || clean.contains('e') || clean.contains('E')) {
      return double.parse(clean);
    }
    return int.parse(clean);
  }

  _Node _parseParenOrTuple() {
    _expectOp('(');
    if (_isOp(')')) {
      _advance();
      return _TupleNode(const []);
    }
    final first = parseExpression();
    if (_isOp(',')) {
      final elements = <_Node>[first];
      while (_isOp(',')) {
        _advance();
        if (_isOp(')')) break;
        elements.add(parseExpression());
      }
      _expectOp(')');
      return _TupleNode(elements);
    }
    _expectOp(')');
    return first;
  }

  _Node _parseListOrComprehension() {
    _expectOp('[');
    if (_isOp(']')) {
      _advance();
      return _ListNode(const []);
    }
    final first = parseExpression();
    if (_isKeyword('for')) {
      final comp = _parseComprehensionTail('list', first, null);
      _expectOp(']');
      return comp;
    }
    final elements = <_Node>[first];
    while (_isOp(',')) {
      _advance();
      if (_isOp(']')) break;
      elements.add(parseExpression());
    }
    _expectOp(']');
    return _ListNode(elements);
  }

  _Node _parseDictOrSet() {
    _expectOp('{');
    if (_isOp('}')) {
      _advance();
      return _DictNode(const []);
    }
    final first = parseExpression();
    if (_isOp(':')) {
      _advance();
      final firstValue = parseExpression();
      if (_isKeyword('for')) {
        final comp = _parseComprehensionTail('dict', first, firstValue);
        _expectOp('}');
        return comp;
      }
      final entries = <MapEntry<_Node, _Node>>[MapEntry(first, firstValue)];
      while (_isOp(',')) {
        _advance();
        if (_isOp('}')) break;
        final key = parseExpression();
        _expectOp(':');
        entries.add(MapEntry(key, parseExpression()));
      }
      _expectOp('}');
      return _DictNode(entries);
    }
    if (_isKeyword('for')) {
      final comp = _parseComprehensionTail('set', first, null);
      _expectOp('}');
      return comp;
    }
    final elements = <_Node>[first];
    while (_isOp(',')) {
      _advance();
      if (_isOp('}')) break;
      elements.add(parseExpression());
    }
    _expectOp('}');
    return _SetNode(elements);
  }

  _ComprehensionNode _parseComprehensionTail(
    String kind,
    _Node element,
    _Node? value,
  ) {
    if (!_isKeyword('for')) {
      throw RenPyPythonError('expected `for` in comprehension');
    }
    _advance();
    final variable = _parseTargetNames();
    if (!_isKeyword('in')) {
      throw RenPyPythonError('expected `in` in comprehension');
    }
    _advance();
    final iterable = _parseOr();
    _Node? condition;
    if (_isKeyword('if')) {
      _advance();
      condition = _parseOr();
    }
    return _ComprehensionNode(
      kind: kind,
      element: element,
      value: value,
      variable: variable,
      iterable: iterable,
      condition: condition,
    );
  }

  List<String> _parseTargetNames() {
    final names = <String>[];
    final parenthesized = _isOp('(');
    if (parenthesized) _advance();
    while (true) {
      if (_current.type != _TokenType.name) {
        throw RenPyPythonError('expected name in comprehension target');
      }
      names.add(_advance().value);
      if (_isOp(',')) {
        _advance();
      } else {
        break;
      }
    }
    if (parenthesized) _expectOp(')');
    return names;
  }
}

// ---------------------------------------------------------------------------
// Interpreter
// ---------------------------------------------------------------------------

class _Interpreter {
  _Interpreter(this.scope);

  final RenPyPythonScope scope;

  /// Per-evaluation lexical bindings for comprehension targets, searched
  /// before the namespace.
  final List<Map<String, Object?>> _locals = [];

  static bool truthy(Object? value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) return value.isNotEmpty;
    if (value is Iterable) return value.isNotEmpty;
    if (value is Map) return value.isNotEmpty;
    return true;
  }

  Object? readName(String name) {
    for (var i = _locals.length - 1; i >= 0; i -= 1) {
      if (_locals[i].containsKey(name)) return _locals[i][name];
    }
    if (scope.has(name)) return scope.read(name);
    final builtin = _builtins[name];
    if (builtin != null) return _BuiltinFunction(name, builtin);
    throw RenPyPythonNameError(name);
  }

  Object? attribute(_AttributeNode node) {
    // Scoped names such as persistent.x / config.y resolve as a unit.
    final full = node.fullName;
    if (full != null && _isScopedName(full)) {
      if (scope.has(full)) return scope.read(full);
    }
    final target = node.target.eval(this);
    return _BoundMethod(target, node.attribute);
  }

  bool _isScopedName(String name) =>
      name.startsWith('persistent.') ||
      name.startsWith('config.') ||
      name.startsWith('gui.');

  Object? unary(String op, Object? value) {
    switch (op) {
      case '-':
        if (value is num) return -value;
        throw RenPyPythonError('bad operand for unary -');
      case '+':
        if (value is num) return value;
        throw RenPyPythonError('bad operand for unary +');
      case '~':
        if (value is int) return ~value;
        throw RenPyPythonError('bad operand for unary ~');
      default:
        throw RenPyPythonError('unsupported unary `$op`');
    }
  }

  Object? binary(String op, Object? a, Object? b) {
    switch (op) {
      case '+':
        return _add(a, b);
      case '-':
        return _numeric(a, b, (x, y) => x - y);
      case '*':
        return _multiply(a, b);
      case '/':
        if (a is num && b is num) {
          if (b == 0) throw RenPyPythonError('division by zero');
          return a / b;
        }
        throw RenPyPythonError('unsupported operands for /');
      case '//':
        if (a is num && b is num) {
          if (b == 0) throw RenPyPythonError('division by zero');
          final q = (a / b).floorToDouble();
          return a is int && b is int ? q.toInt() : q;
        }
        throw RenPyPythonError('unsupported operands for //');
      case '%':
        return _modulo(a, b);
      case '**':
        if (a is num && b is num) {
          final r = math.pow(a, b);
          return a is int && b is int && b >= 0 ? r.toInt() : r.toDouble();
        }
        throw RenPyPythonError('unsupported operands for **');
      case '|':
        if (a is int && b is int) return a | b;
        if (a is Set && b is Set) return {...a, ...b};
        throw RenPyPythonError('unsupported operands for |');
      case '&':
        if (a is int && b is int) return a & b;
        if (a is Set && b is Set) return a.intersection(b.cast());
        throw RenPyPythonError('unsupported operands for &');
      case '^':
        if (a is int && b is int) return a ^ b;
        throw RenPyPythonError('unsupported operands for ^');
      case '<<':
        if (a is int && b is int) return a << b;
        throw RenPyPythonError('unsupported operands for <<');
      case '>>':
        if (a is int && b is int) return a >> b;
        throw RenPyPythonError('unsupported operands for >>');
      default:
        throw RenPyPythonError('unsupported operator `$op`');
    }
  }

  Object? _add(Object? a, Object? b) {
    if (a is String && b is String) return a + b;
    if (a is num && b is num) return a + b;
    if (a is List && b is List) return [...a, ...b];
    throw RenPyPythonError('unsupported operands for +');
  }

  Object? _multiply(Object? a, Object? b) {
    if (a is num && b is num) return a * b;
    if (a is String && b is int) return a * b;
    if (a is int && b is String) return b * a;
    if (a is List && b is int) return [for (var i = 0; i < b; i += 1) ...a];
    if (a is int && b is List) return [for (var i = 0; i < a; i += 1) ...b];
    throw RenPyPythonError('unsupported operands for *');
  }

  Object? _numeric(Object? a, Object? b, num Function(num, num) f) {
    if (a is num && b is num) return f(a, b);
    throw RenPyPythonError('unsupported numeric operands');
  }

  Object? _modulo(Object? a, Object? b) {
    // String formatting: "Hi %s" % value / "%d/%d" % (a, b).
    if (a is String) return _percentFormat(a, b);
    if (a is num && b is num) {
      if (b == 0) throw RenPyPythonError('modulo by zero');
      return a % b;
    }
    throw RenPyPythonError('unsupported operands for %');
  }

  Object? compare(List<_Node> operands, List<String> operators) {
    var left = operands.first.eval(this);
    for (var i = 0; i < operators.length; i += 1) {
      final right = operands[i + 1].eval(this);
      if (!_compareOne(left, operators[i], right)) return false;
      left = right;
    }
    return true;
  }

  bool _compareOne(Object? a, String op, Object? b) {
    switch (op) {
      case '==':
        return _equals(a, b);
      case '!=':
        return !_equals(a, b);
      case 'is':
        return identical(a, b) || (a == null && b == null);
      case 'is not':
        return !(identical(a, b) || (a == null && b == null));
      case 'in':
        return _contains(b, a);
      case 'not in':
        return !_contains(b, a);
      case '<':
      case '<=':
      case '>':
      case '>=':
        return _ordered(a, op, b);
      default:
        throw RenPyPythonError('unsupported comparison `$op`');
    }
  }

  bool _equals(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i += 1) {
        if (!_equals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  bool _ordered(Object? a, String op, Object? b) {
    if (a is num && b is num) {
      return switch (op) {
        '<' => a < b,
        '<=' => a <= b,
        '>' => a > b,
        '>=' => a >= b,
        _ => false,
      };
    }
    if (a is String && b is String) {
      final c = a.compareTo(b);
      return switch (op) {
        '<' => c < 0,
        '<=' => c <= 0,
        '>' => c > 0,
        '>=' => c >= 0,
        _ => false,
      };
    }
    throw RenPyPythonError('unorderable operands for `$op`');
  }

  bool _contains(Object? container, Object? element) {
    if (container is String) {
      return element is String && container.contains(element);
    }
    if (container is Map) return container.containsKey(element);
    if (container is Iterable) return container.contains(element);
    throw RenPyPythonError('argument is not iterable');
  }

  Object? subscript(Object? target, Object? index) {
    if (index is _Slice) return _applySlice(target, index);
    if (target is List) {
      final i = _intIndex(index, target.length);
      return target[i];
    }
    if (target is String) {
      final i = _intIndex(index, target.length);
      return target[i];
    }
    if (target is Map) {
      if (!target.containsKey(index)) {
        throw RenPyPythonError('key error: $index');
      }
      return target[index];
    }
    throw RenPyPythonError('object is not subscriptable');
  }

  int _intIndex(Object? index, int length) {
    if (index is! int) throw RenPyPythonError('index is not an integer');
    final i = index < 0 ? length + index : index;
    if (i < 0 || i >= length) throw RenPyPythonError('index out of range');
    return i;
  }

  Object? _applySlice(Object? target, _Slice slice) {
    final length =
        target is List
            ? target.length
            : target is String
            ? target.length
            : throw RenPyPythonError('object is not sliceable');
    final step = (slice.step as int?) ?? 1;
    if (step == 0) throw RenPyPythonError('slice step cannot be zero');

    int clamp(int value) =>
        value < 0 ? math.max(0, length + value) : math.min(value, length);

    int start;
    int stop;
    if (step > 0) {
      start = slice.start == null ? 0 : clamp(slice.start as int);
      stop = slice.stop == null ? length : clamp(slice.stop as int);
    } else {
      start =
          slice.start == null
              ? length - 1
              : (slice.start as int) < 0
              ? length + (slice.start as int)
              : math.min(slice.start as int, length - 1);
      stop =
          slice.stop == null
              ? -1
              : (slice.stop as int) < 0
              ? length + (slice.stop as int)
              : math.min(slice.stop as int, length - 1);
    }

    final indices = <int>[];
    if (step > 0) {
      for (var i = start; i < stop; i += step) {
        indices.add(i);
      }
    } else {
      for (var i = start; i > stop; i += step) {
        indices.add(i);
      }
    }

    if (target is String) {
      return [for (final i in indices) target[i]].join();
    }
    final list = target as List;
    return [for (final i in indices) list[i]];
  }

  Object? call(_CallNode node) {
    final positional = [for (final arg in node.positional) arg.eval(this)];
    final keywords = {
      for (final entry in node.keywords.entries)
        entry.key: entry.value.eval(this),
    };

    final target = node.target;
    if (target is _AttributeNode) {
      // Method call: only resolve the receiver, not the attribute, since
      // methods are not first-class values here.
      final full = target.fullName;
      if (full != null && _isScopedName(full) && scope.has(full)) {
        return _callMethod(
          scope.read(full),
          target.attribute,
          positional,
          keywords,
        );
      }
      final receiver = target.target.eval(this);
      return _callMethod(receiver, target.attribute, positional, keywords);
    }

    final callee = target.eval(this);
    if (callee is _BuiltinFunction) {
      return callee.invoke(this, positional, keywords);
    }
    if (callee is _BoundMethod) {
      return _callMethod(callee.receiver, callee.name, positional, keywords);
    }
    throw RenPyPythonError('object is not callable');
  }

  Object? comprehension(_ComprehensionNode node) {
    final iterable = _asIterable(node.iterable.eval(this));
    final scopeMap = <String, Object?>{};
    _locals.add(scopeMap);
    try {
      if (node.kind == 'dict') {
        final result = <Object?, Object?>{};
        for (final item in iterable) {
          _bindTarget(node.variable, item, scopeMap);
          if (node.condition != null && !truthy(node.condition!.eval(this))) {
            continue;
          }
          result[node.element.eval(this)] = node.value!.eval(this);
        }
        return result;
      }
      final result = <Object?>[];
      for (final item in iterable) {
        _bindTarget(node.variable, item, scopeMap);
        if (node.condition != null && !truthy(node.condition!.eval(this))) {
          continue;
        }
        result.add(node.element.eval(this));
      }
      if (node.kind == 'set') return result.toSet();
      return result;
    } finally {
      _locals.removeLast();
    }
  }

  void _bindTarget(
    List<String> names,
    Object? item,
    Map<String, Object?> into,
  ) {
    if (names.length == 1) {
      into[names.first] = item;
      return;
    }
    final values = _asIterable(item).toList();
    if (values.length != names.length) {
      throw RenPyPythonError(
        'cannot unpack iterable into ${names.length} names',
      );
    }
    for (var i = 0; i < names.length; i += 1) {
      into[names[i]] = values[i];
    }
  }

  Iterable<Object?> _asIterable(Object? value) {
    if (value is Iterable) return value;
    if (value is Map) return value.keys;
    if (value is String) return value.split('');
    throw RenPyPythonError('object is not iterable');
  }

  // -- f-strings & % formatting --------------------------------------------

  String evalFString(List<_FStringPart> parts) {
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part.text != null) {
        buffer.write(part.text);
        continue;
      }
      final tokens = _Lexer(part.expression!).tokenize();
      final parser = _Parser(tokens);
      final node = parser.parseExpression();
      parser.expectEnd();
      final value = node.eval(this);
      buffer.write(_formatValue(value, part.conversion));
    }
    return buffer.toString();
  }

  String _formatValue(Object? value, String? conversion) {
    if (conversion == null || conversion.isEmpty) return _str(value);
    if (conversion.startsWith('!r')) return _repr(value);
    if (conversion.startsWith('!s')) return _str(value);
    if (conversion.startsWith(':')) {
      return _applyFormatSpec(value, conversion.substring(1));
    }
    return _str(value);
  }

  /// Handles the small slice of format specs seen in real games: a fixed
  /// number of fraction digits (`.2f`), an integer width and zero padding.
  String _applyFormatSpec(Object? value, String spec) {
    final match = RegExp(r'^0?(\d+)?(?:\.(\d+))?([dfsx])?$').firstMatch(spec);
    if (match == null) return _str(value);
    final width = match.group(1);
    final precision = match.group(2);
    final type = match.group(3);
    var text = _str(value);
    if (type == 'f' && value is num) {
      text = value.toStringAsFixed(
        precision == null ? 6 : int.parse(precision),
      );
    } else if (type == 'd' && value is num) {
      text = value.toInt().toString();
    } else if (type == 'x' && value is int) {
      text = value.toRadixString(16);
    }
    if (width != null) {
      final pad = spec.startsWith('0') ? '0' : ' ';
      while (text.length < int.parse(width)) {
        text = '$pad$text';
      }
    }
    return text;
  }

  String _percentFormat(String format, Object? arg) {
    final args = arg is List ? arg : [arg];
    var index = 0;
    final buffer = StringBuffer();
    for (var i = 0; i < format.length; i += 1) {
      final ch = format[i];
      if (ch != '%') {
        buffer.write(ch);
        continue;
      }
      // Read a conversion spec: %[flags][width][.precision]type.
      final spec = StringBuffer('%');
      i += 1;
      while (i < format.length && '-+ 0#'.contains(format[i])) {
        spec.write(format[i]);
        i += 1;
      }
      while (i < format.length && _isDigit(format[i])) {
        spec.write(format[i]);
        i += 1;
      }
      if (i < format.length && format[i] == '.') {
        spec.write('.');
        i += 1;
        while (i < format.length && _isDigit(format[i])) {
          spec.write(format[i]);
          i += 1;
        }
      }
      if (i >= format.length) break;
      final type = format[i];
      if (type == '%') {
        buffer.write('%');
        continue;
      }
      final value = index < args.length ? args[index++] : null;
      buffer.write(_percentConvert(spec.toString(), type, value));
    }
    return buffer.toString();
  }

  bool _isDigit(String ch) => ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0;

  String _percentConvert(String spec, String type, Object? value) {
    final precisionMatch = RegExp(r'\.(\d+)').firstMatch(spec);
    final precision =
        precisionMatch == null ? null : int.parse(precisionMatch.group(1)!);
    final widthMatch = RegExp(r'%[-+ 0#]*(\d+)').firstMatch(spec);
    final width = widthMatch == null ? null : int.parse(widthMatch.group(1)!);
    final zeroPad = RegExp(r'%[-+ #]*0').hasMatch(spec);
    final leftAlign = spec.contains('-');

    String text;
    switch (type) {
      case 'd':
      case 'i':
        text =
            (value is num ? value.toInt() : int.tryParse('$value') ?? 0)
                .toString();
      case 'f':
      case 'F':
        final n = value is num ? value : double.tryParse('$value') ?? 0;
        text = n.toStringAsFixed(precision ?? 6);
      case 's':
        text = _str(value);
      case 'r':
        text = _repr(value);
      case 'x':
        text = (value is int ? value : int.tryParse('$value') ?? 0)
            .toRadixString(16);
      case 'X':
        text =
            (value is int ? value : int.tryParse('$value') ?? 0)
                .toRadixString(16)
                .toUpperCase();
      default:
        text = _str(value);
    }
    if (width != null && text.length < width) {
      final pad = zeroPad && !leftAlign ? '0' : ' ';
      final padding = pad * (width - text.length);
      text = leftAlign ? '$text$padding' : '$padding$text';
    }
    return text;
  }

  // -- builtins & methods ---------------------------------------------------

  Object? _callMethod(
    Object? receiver,
    String name,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    if (receiver is String) return _stringMethod(receiver, name, positional);
    if (receiver is List) return _listMethod(receiver, name, positional);
    if (receiver is Map) return _dictMethod(receiver, name, positional);
    if (receiver is Set) return _setMethod(receiver, name, positional);
    throw RenPyPythonError('no method `$name` on ${_typeName(receiver)}');
  }

  Object? _stringMethod(String s, String name, List<Object?> args) {
    switch (name) {
      case 'upper':
        return s.toUpperCase();
      case 'lower':
        return s.toLowerCase();
      case 'strip':
        return args.isEmpty
            ? s.trim()
            : _stripChars(s, '${args[0]}', both: true);
      case 'lstrip':
        return args.isEmpty
            ? s.trimLeft()
            : _stripChars(s, '${args[0]}', left: true);
      case 'rstrip':
        return args.isEmpty
            ? s.trimRight()
            : _stripChars(s, '${args[0]}', right: true);
      case 'split':
        if (args.isEmpty) {
          return s
              .trim()
              .split(RegExp(r'\s+'))
              .where((p) => p.isNotEmpty)
              .toList();
        }
        return s.split('${args[0]}');
      case 'join':
        final parts = _asIterable(args[0]).map(_str);
        return parts.join(s);
      case 'replace':
        return s.replaceAll('${args[0]}', '${args[1]}');
      case 'startswith':
        return s.startsWith('${args[0]}');
      case 'endswith':
        return s.endsWith('${args[0]}');
      case 'find':
        return s.indexOf('${args[0]}');
      case 'count':
        return '${args[0]}'.isEmpty
            ? s.length + 1
            : '${args[0]}'.allMatches(s).length;
      case 'capitalize':
        return s.isEmpty
            ? s
            : s[0].toUpperCase() + s.substring(1).toLowerCase();
      case 'title':
        return s.replaceAllMapped(
          RegExp(r'\w+'),
          (m) => m[0]![0].toUpperCase() + m[0]!.substring(1).toLowerCase(),
        );
      case 'format':
        return _strFormat(s, args);
      case 'zfill':
        final width = args[0] as int;
        return s.length >= width ? s : '0' * (width - s.length) + s;
      case 'isdigit':
        return s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s);
      default:
        throw RenPyPythonError('no str method `$name`');
    }
  }

  String _stripChars(
    String s,
    String chars, {
    bool left = false,
    bool right = false,
    bool both = false,
  }) {
    var start = 0;
    var end = s.length;
    if (left || both) {
      while (start < end && chars.contains(s[start])) {
        start += 1;
      }
    }
    if (right || both) {
      while (end > start && chars.contains(s[end - 1])) {
        end -= 1;
      }
    }
    return s.substring(start, end);
  }

  String _strFormat(String template, List<Object?> args) {
    final buffer = StringBuffer();
    var auto = 0;
    for (var i = 0; i < template.length; i += 1) {
      final ch = template[i];
      if (ch == '{' && i + 1 < template.length && template[i + 1] == '{') {
        buffer.write('{');
        i += 1;
        continue;
      }
      if (ch == '}' && i + 1 < template.length && template[i + 1] == '}') {
        buffer.write('}');
        i += 1;
        continue;
      }
      if (ch == '{') {
        final close = template.indexOf('}', i);
        if (close < 0) throw RenPyPythonError('unmatched `{` in format string');
        final field = template.substring(i + 1, close);
        i = close;
        final colon = field.indexOf(':');
        final name = colon < 0 ? field : field.substring(0, colon);
        final spec = colon < 0 ? null : field.substring(colon + 1);
        Object? value;
        if (name.isEmpty) {
          value = auto < args.length ? args[auto++] : null;
        } else {
          final position = int.tryParse(name);
          value =
              position != null && position < args.length
                  ? args[position]
                  : null;
        }
        buffer.write(
          spec == null ? _str(value) : _applyFormatSpec(value, spec),
        );
        continue;
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  Object? _listMethod(List list, String name, List<Object?> args) {
    switch (name) {
      case 'append':
        list.add(args[0]);
        return null;
      case 'pop':
        if (list.isEmpty) throw RenPyPythonError('pop from empty list');
        final index =
            args.isEmpty ? list.length - 1 : _intIndex(args[0], list.length);
        return list.removeAt(index);
      case 'remove':
        final removed = list.remove(args[0]);
        if (!removed) throw RenPyPythonError('value not in list');
        return null;
      case 'index':
        final i = list.indexOf(args[0]);
        if (i < 0) throw RenPyPythonError('value not in list');
        return i;
      case 'count':
        return list.where((e) => _equals(e, args[0])).length;
      case 'insert':
        list.insert(args[0] as int, args[1]);
        return null;
      case 'extend':
        list.addAll(_asIterable(args[0]));
        return null;
      case 'sort':
        list.sort((a, b) => _defaultCompare(a, b));
        return null;
      case 'reverse':
        final reversed = list.reversed.toList();
        list
          ..clear()
          ..addAll(reversed);
        return null;
      case 'clear':
        list.clear();
        return null;
      default:
        throw RenPyPythonError('no list method `$name`');
    }
  }

  Object? _dictMethod(Map map, String name, List<Object?> args) {
    switch (name) {
      case 'get':
        return map.containsKey(args[0])
            ? map[args[0]]
            : (args.length > 1 ? args[1] : null);
      case 'keys':
        return map.keys.toList();
      case 'values':
        return map.values.toList();
      case 'items':
        return [
          for (final e in map.entries) [e.key, e.value],
        ];
      case 'setdefault':
        if (map.containsKey(args[0])) return map[args[0]];
        final value = args.length > 1 ? args[1] : null;
        map[args[0]] = value;
        return value;
      case 'pop':
        if (map.containsKey(args[0])) return map.remove(args[0]);
        if (args.length > 1) return args[1];
        throw RenPyPythonError('key error: ${args[0]}');
      case 'update':
        map.addAll((args[0] as Map).cast());
        return null;
      case 'clear':
        map.clear();
        return null;
      default:
        throw RenPyPythonError('no dict method `$name`');
    }
  }

  Object? _setMethod(Set set, String name, List<Object?> args) {
    switch (name) {
      case 'add':
        set.add(args[0]);
        return null;
      case 'discard':
        set.remove(args[0]);
        return null;
      case 'remove':
        if (!set.remove(args[0])) throw RenPyPythonError('element not in set');
        return null;
      case 'clear':
        set.clear();
        return null;
      default:
        throw RenPyPythonError('no set method `$name`');
    }
  }

  int _defaultCompare(Object? a, Object? b) {
    if (a is num && b is num) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    if (a is Comparable && b is Comparable) {
      try {
        return a.compareTo(b);
      } catch (_) {
        throw RenPyPythonError('values are not orderable');
      }
    }
    throw RenPyPythonError('values are not orderable');
  }

  String _typeName(Object? value) {
    if (value == null) return 'None';
    if (value is bool) return 'bool';
    if (value is int) return 'int';
    if (value is double) return 'float';
    if (value is String) return 'str';
    if (value is List) return 'list';
    if (value is Map) return 'dict';
    if (value is Set) return 'set';
    return value.runtimeType.toString();
  }

  String _str(Object? value) {
    if (value == null) return 'None';
    if (value is bool) return value ? 'True' : 'False';
    if (value is double) {
      if (value == value.roundToDouble() && value.isFinite) {
        return '${value.toInt()}.0';
      }
      return value.toString();
    }
    if (value is String) return value;
    if (value is List) return '[${value.map(_repr).join(', ')}]';
    if (value is Set) return '{${value.map(_repr).join(', ')}}';
    if (value is Map) {
      return '{${value.entries.map((e) => '${_repr(e.key)}: ${_repr(e.value)}').join(', ')}}';
    }
    return value.toString();
  }

  String _repr(Object? value) {
    if (value is String) return "'$value'";
    return _str(value);
  }

  late final Map<String, _BuiltinImpl> _builtins = {
    'len': (a, k) {
      final v = a[0];
      if (v is String) return v.length;
      if (v is Iterable) return v.length;
      if (v is Map) return v.length;
      throw RenPyPythonError('object has no len()');
    },
    'str': (a, k) => a.isEmpty ? '' : _str(a[0]),
    'repr': (a, k) => _repr(a[0]),
    'int': (a, k) {
      if (a.isEmpty) return 0;
      final v = a[0];
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is bool) return v ? 1 : 0;
      if (v is String) {
        final radix = a.length > 1 ? a[1] as int : 10;
        final parsed = int.tryParse(v.trim(), radix: radix);
        if (parsed != null) return parsed;
        final d = double.tryParse(v.trim());
        if (d != null) return d.toInt();
      }
      throw RenPyPythonError('cannot convert to int');
    },
    'float': (a, k) {
      if (a.isEmpty) return 0.0;
      final v = a[0];
      if (v is num) return v.toDouble();
      if (v is String) {
        final d = double.tryParse(v.trim());
        if (d != null) return d;
      }
      throw RenPyPythonError('cannot convert to float');
    },
    'bool': (a, k) => a.isEmpty ? false : truthy(a[0]),
    'list': (a, k) => a.isEmpty ? <Object?>[] : _asIterable(a[0]).toList(),
    'tuple': (a, k) => a.isEmpty ? <Object?>[] : _asIterable(a[0]).toList(),
    'dict': (a, k) {
      final result = <Object?, Object?>{};
      if (a.isNotEmpty) {
        final source = a[0];
        if (source is Map) result.addAll(source);
      }
      result.addAll(k);
      return result;
    },
    'set': (a, k) => a.isEmpty ? <Object?>{} : _asIterable(a[0]).toSet(),
    'sorted': (a, k) {
      final items = _asIterable(a[0]).toList();
      final reverse = k['reverse'] == true;
      items.sort((x, y) => _defaultCompare(x, y));
      if (reverse) return items.reversed.toList();
      return items;
    },
    'reversed': (a, k) => _asIterable(a[0]).toList().reversed.toList(),
    'min': (a, k) => _minMax(a, isMin: true),
    'max': (a, k) => _minMax(a, isMin: false),
    'abs': (a, k) {
      final v = a[0];
      if (v is num) return v.abs();
      throw RenPyPythonError('bad operand for abs()');
    },
    'round': (a, k) {
      final v = a[0];
      if (v is! num) throw RenPyPythonError('bad operand for round()');
      if (a.length > 1) {
        final digits = a[1] as int;
        final factor = math.pow(10, digits);
        return (v * factor).round() / factor;
      }
      return v.round();
    },
    'sum': (a, k) {
      num total = a.length > 1 ? a[1] as num : 0;
      for (final item in _asIterable(a[0])) {
        if (item is num) {
          total += item;
        } else {
          throw RenPyPythonError('unsupported operand in sum()');
        }
      }
      return total;
    },
    'any': (a, k) => _asIterable(a[0]).any(truthy),
    'all': (a, k) => _asIterable(a[0]).every(truthy),
    'range': (a, k) => _range(a),
    'enumerate': (a, k) {
      final start = a.length > 1 ? a[1] as int : 0;
      final result = <Object?>[];
      var i = start;
      for (final item in _asIterable(a[0])) {
        result.add([i, item]);
        i += 1;
      }
      return result;
    },
    'zip': (a, k) {
      final lists = [for (final arg in a) _asIterable(arg).toList()];
      if (lists.isEmpty) return <Object?>[];
      final shortest = lists.map((l) => l.length).reduce(math.min);
      return [
        for (var i = 0; i < shortest; i += 1) [for (final l in lists) l[i]],
      ];
    },
    'isinstance': (a, k) => _isinstance(a[0], a[1]),
    'type': (a, k) => _typeName(a[0]),
  };

  Object? _minMax(List<Object?> args, {required bool isMin}) {
    final items = args.length == 1 ? _asIterable(args[0]).toList() : args;
    if (items.isEmpty) throw RenPyPythonError('min()/max() of empty sequence');
    var best = items.first;
    for (final item in items.skip(1)) {
      final cmp = _defaultCompare(item, best);
      if (isMin ? cmp < 0 : cmp > 0) best = item;
    }
    return best;
  }

  List<int> _range(List<Object?> args) {
    int start;
    int stop;
    int step;
    if (args.length == 1) {
      start = 0;
      stop = args[0] as int;
      step = 1;
    } else if (args.length == 2) {
      start = args[0] as int;
      stop = args[1] as int;
      step = 1;
    } else {
      start = args[0] as int;
      stop = args[1] as int;
      step = args[2] as int;
    }
    if (step == 0) throw RenPyPythonError('range() step cannot be zero');
    final result = <int>[];
    if (step > 0) {
      for (var i = start; i < stop; i += step) {
        result.add(i);
      }
    } else {
      for (var i = start; i > stop; i += step) {
        result.add(i);
      }
    }
    return result;
  }

  bool _isinstance(Object? value, Object? type) {
    final types = type is List ? type : [type];
    for (final t in types) {
      if (t is _BuiltinFunction) {
        final matched = switch (t.name) {
          'int' => value is int,
          'float' => value is double,
          'str' => value is String,
          'bool' => value is bool,
          'list' || 'tuple' => value is List,
          'dict' => value is Map,
          'set' => value is Set,
          _ => false,
        };
        if (matched) return true;
      }
    }
    return false;
  }
}

typedef _BuiltinImpl =
    Object? Function(List<Object?> positional, Map<String, Object?> keywords);

/// A whitelisted builtin function resolved as a first-class value so it can be
/// passed around (e.g. as the second argument to `isinstance`).
class _BuiltinFunction {
  _BuiltinFunction(this.name, this._impl);

  final String name;
  final _BuiltinImpl _impl;

  Object? invoke(
    _Interpreter interp,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) => _impl(positional, keywords);
}

/// A method looked up as an attribute but not yet called. Method dispatch is
/// resolved at the call site, so a bare `obj.method` reference that is never
/// invoked simply carries the receiver and name.
class _BoundMethod {
  _BoundMethod(this.receiver, this.name);

  final Object? receiver;
  final String name;
}
