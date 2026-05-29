import 'dart:collection';
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

  /// The handler backing `renpy.*` calls. Defaults to a no-op handler so a
  /// scope that does not wire one still evaluates `renpy.*` references.
  RenPyApi get renpy => const _NoOpRenPyApi();
}

/// The subset of the `renpy.*` module surface the evaluator can call.
///
/// A `$ ...` statement or `python:` block that calls, say, `renpy.variant(...)`
/// or `renpy.random.randint(...)` reaches these methods through the scope. An
/// implementation maps each onto engine behavior (audio events, notifications)
/// or a safe stub; the default [_NoOpRenPyApi] makes every call a no-op so the
/// evaluator never aborts on a `renpy.*` reference. Screen-dependent functions
/// (`show_screen`, `call_screen`, `display_menu`, ...) are intentionally absent
/// so they keep falling back until the screen language lands.
abstract class RenPyApi {
  /// `renpy.variant(name)` - whether a platform/size variant is active.
  bool variant(Object? name);

  /// `renpy.random.random()` - a float in `[0.0, 1.0)`.
  double randomRandom();

  /// `renpy.random.randint(a, b)` - an int in `[a, b]` inclusive.
  int randomRandint(int a, int b);

  /// `renpy.random.choice(seq)` - one element drawn from [sequence].
  Object? randomChoice(List<Object?> sequence);

  /// `renpy.notify(message)` - surface a transient notification.
  void notify(Object? message);

  /// `renpy.input(prompt, ...)` - text input; returns the entered string.
  String input(Object? prompt);

  /// `renpy.with_statement(transition)` - apply a transition.
  void withStatement(Object? transition);

  /// `renpy.music.queue(...)` / `renpy.sound.play(...)`, `renpy.voice(...)` /
  /// `renpy.voice_sustain()`, and the volume setters. [function] is the dotted
  /// suffix after `renpy.`, e.g. `music.queue` or `voice`.
  void audio(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  );

  /// `renpy.call(label, ...)` - transfer control to [label], returning to the
  /// caller afterwards. A host that drives a call stack throws a
  /// [RenPyControlFlowSignal] so the transfer escapes the Python interpreter;
  /// the no-op host does nothing.
  void call(String label, {List<Object?> args, Map<String, Object?> kwargs});

  /// `renpy.jump(label)` - transfer control to [label] without a return frame.
  /// A driving host throws a [RenPyControlFlowSignal]; the no-op host does
  /// nothing.
  void jump(String label);

  /// `renpy.show_screen(name, ...)` - best-effort, NON-blocking screen show.
  /// A no-op host ignores it; a driving host routes to its screen layer. Never
  /// starts a blocking modal.
  void showScreen(
    String name,
    List<Object?> positional,
    Map<String, Object?> keywords,
  );

  /// `renpy.hide_screen(name)` - best-effort screen hide. A no-op host ignores
  /// it; a driving host removes the screen from its layer.
  void hideScreen(String name);
}

/// A [RenPyApi] whose every method is a no-op (or a neutral return). Used when
/// no host wires real behavior, so `renpy.*` calls still evaluate cleanly.
class _NoOpRenPyApi implements RenPyApi {
  const _NoOpRenPyApi();

  @override
  bool variant(Object? name) => false;

  @override
  double randomRandom() => 0.0;

  @override
  int randomRandint(int a, int b) => a;

  @override
  Object? randomChoice(List<Object?> sequence) =>
      sequence.isEmpty ? null : sequence.first;

  @override
  void notify(Object? message) {}

  @override
  String input(Object? prompt) => '';

  @override
  void withStatement(Object? transition) {}

  @override
  void audio(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {}

  @override
  void call(
    String label, {
    List<Object?> args = const [],
    Map<String, Object?> kwargs = const {},
  }) {}

  @override
  void jump(String label) {}

  @override
  void showScreen(
    String name,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {}

  @override
  void hideScreen(String name) {}
}

/// A scope backed by plain Dart maps, one per RenPy namespace.
///
/// The runner passes in the maps it already uses for `store` and `persistent`
/// state so the two views stay in sync; `config` and `gui` default to fresh
/// maps when a caller does not supply them. An optional [renpy] handler backs
/// the `renpy.*` shims; absent one, a no-op handler is used.
class RenPyMapScope implements RenPyPythonScope {
  RenPyMapScope({
    required Map<String, Object?> store,
    required Map<String, Object?> persistent,
    Map<String, Object?>? config,
    Map<String, Object?>? gui,
    RenPyApi? renpy,
  }) : _store = store,
       _persistent = persistent,
       _config = config ?? <String, Object?>{},
       _gui = gui ?? <String, Object?>{},
       renpy = renpy ?? const _NoOpRenPyApi();

  final Map<String, Object?> _store;
  final Map<String, Object?> _persistent;
  final Map<String, Object?> _config;
  final Map<String, Object?> _gui;

  /// Handler for `renpy.*` calls encountered while evaluating expressions.
  @override
  final RenPyApi renpy;

  Map<String, Object?> _mapFor(String name) {
    if (name.startsWith('persistent.')) return _persistent;
    if (name.startsWith('config.')) return _config;
    if (name.startsWith('gui.')) return _gui;
    // `store.x` is the explicit spelling of the default namespace, so it maps
    // onto the same backing store as the bare name `x`.
    return _store;
  }

  String _fieldFor(String name) {
    final dot = name.indexOf('.');
    if (dot < 0) return name;
    final prefix = name.substring(0, dot);
    if (prefix == 'persistent' ||
        prefix == 'config' ||
        prefix == 'gui' ||
        prefix == 'store') {
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

/// A non-error control-transfer signal raised by `renpy.call(...)` /
/// `renpy.jump(...)` evaluated from a `$` statement or `python:` block.
///
/// This is deliberately NOT a [RenPyPythonError]: the interpreter's entry
/// points rethrow it intact so it escapes the Python subset and the runner can
/// perform a real label call/jump. The runner's host shim throws this from its
/// [RenPyApi.call] / [RenPyApi.jump] implementation; the no-op host never does.
class RenPyControlFlowSignal implements Exception {
  RenPyControlFlowSignal.call(
    this.label, {
    List<Object?>? args,
    Map<String, Object?>? kwargs,
  }) : kind = 'call',
       args = args ?? const [],
       kwargs = kwargs ?? const {};

  RenPyControlFlowSignal.jump(this.label)
    : kind = 'jump',
      args = const [],
      kwargs = const {};

  /// Either `'call'` or `'jump'`.
  final String kind;

  /// The target label name.
  final String label;

  /// Positional arguments passed to `renpy.call(label, ...)`.
  final List<Object?> args;

  /// Keyword arguments passed to `renpy.call(label, ...)`.
  final Map<String, Object?> kwargs;

  @override
  String toString() => 'RenPyControlFlowSignal($kind -> $label)';
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
    } on RenPyControlFlowSignal {
      // A `renpy.call`/`renpy.jump` requested control transfer. Let it escape
      // the interpreter intact so the runner can perform a real label change;
      // it is NOT an error and must not be normalized into a skip diagnostic.
      rethrow;
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

/// Executes a Python STATEMENT subset on top of [RenPyPythonEvaluator].
///
/// It reuses the evaluator's lexer and expression parser/interpreter for every
/// expression fragment (right-hand sides, conditions, iterables, call
/// arguments) and adds a thin statement layer: indentation-based block parsing,
/// assignment targets (name, attribute, subscript, tuple and chained), `for` /
/// `while` / `if`-`elif`-`else`, `break` / `continue`, `def` / `return` and
/// `pass` / `global`. Anything outside that subset throws a [RenPyPythonError]
/// so the runner can fall back to skipping the block.
class RenPyPythonExecutor {
  const RenPyPythonExecutor();

  /// Parses and executes [source] against [scope].
  ///
  /// Writes to bare names and scoped names (`persistent.x`, ...) flow straight
  /// through [scope], so the runner's live store sees every mutation. Throws
  /// [RenPyPythonError] on an unsupported construct or runtime failure.
  void execute(String source, RenPyPythonScope scope) {
    try {
      final statements = _StatementParser(source).parseModule();
      final interp = _Interpreter(scope);
      for (final statement in statements) {
        statement.exec(interp);
      }
    } on RenPyControlFlowSignal {
      // A `renpy.call`/`renpy.jump` requested control transfer mid-block. Let
      // it escape intact so the runner performs the transfer; the remaining
      // statements in this block are intentionally abandoned, matching RenPy.
      rethrow;
    } on RenPyPythonError {
      rethrow;
    } on _ReturnSignal {
      // `return` at module level is meaningless in real RenPy too; ignore it
      // rather than letting the control-flow signal escape.
    } on _LoopSignal {
      // A stray break/continue outside a loop: treat as a no-op rather than a
      // fatal error so the surrounding script keeps running.
    } on _RaisedException catch (e) {
      // An uncaught `raise` surfaces as a RenPyPythonError so the runner falls
      // back gracefully rather than aborting on the control-flow signal.
      throw RenPyPythonError('uncaught exception: ${e.value}');
    } catch (e) {
      throw RenPyPythonError('execution failed: $e');
    }
  }
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

    // String prefixes: f"", r"", b"", u"", plain quotes.
    // A `u`/`U` prefix is a plain Python 3 string (just `str`), so it is
    // neither an f-string nor raw.
    if (ch == 'f' ||
        ch == 'F' ||
        ch == 'r' ||
        ch == 'R' ||
        ch == 'b' ||
        ch == 'B' ||
        ch == 'u' ||
        ch == 'U') {
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
            buffer.write('\u0000');
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

  /// Whether the parser has consumed every token.
  bool get atEnd => _current.type == _TokenType.eof;

  /// The current token's raw value, for the statement layer to peek at.
  String get currentValue => _current.value;

  bool get currentIsName => _current.type == _TokenType.name;

  bool isOp(String value) => _isOp(value);

  bool isKeyword(String value) => _isKeyword(value);

  void advance() => _advance();

  void expectOp(String value) => _expectOp(value);

  /// Parses one or more comma-separated assignment targets, returning a single
  /// target node or a synthetic tuple when several appear. A trailing comma
  /// (`a, = ...`) still yields a tuple target.
  _Node parseTargetList() {
    final first = parseExpression();
    if (!_isOp(',')) return first;
    final elements = <_Node>[first];
    while (_isOp(',')) {
      _advance();
      if (_isOp('=') || atEnd) break;
      elements.add(parseExpression());
    }
    return _TupleNode(elements);
  }

  /// Parses a `def` parameter list (already positioned after `(`), supporting
  /// positional params, defaults and `*args` / `**kwargs`.
  _ParamSpec parseParamSpec() {
    _expectOp('(');
    final params = <String>[];
    final defaults = <String, _Node>{};
    String? varargs;
    String? kwargs;
    while (!_isOp(')')) {
      if (_isOp('**')) {
        _advance();
        kwargs = _expectName();
      } else if (_isOp('*')) {
        _advance();
        varargs = _expectName();
      } else {
        final name = _expectName();
        if (_isOp('=')) {
          _advance();
          defaults[name] = parseExpression();
        } else if (defaults.isNotEmpty) {
          throw RenPyPythonError(
            'non-default argument `$name` follows default argument',
          );
        }
        params.add(name);
      }
      if (_isOp(',')) {
        _advance();
      } else {
        break;
      }
    }
    _expectOp(')');
    return _ParamSpec(params, defaults, varargs, kwargs);
  }

  String _expectName() {
    if (_current.type != _TokenType.name) {
      throw RenPyPythonError('expected a name, found `${_current.value}`');
    }
    return _advance().value;
  }

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
    final exceptionType = _builtinExceptions[name];
    if (exceptionType != null) return exceptionType;
    throw RenPyPythonNameError(name);
  }

  Object? attribute(_AttributeNode node) {
    // Scoped names such as persistent.x / config.y resolve as a unit.
    final full = node.fullName;
    if (full != null && _isScopedName(full)) {
      if (scope.has(full)) return scope.read(full);
    }
    final target = node.target.eval(this);
    return getAttribute(target, node.attribute);
  }

  /// Reads attribute [name] off [target], resolving instance attributes, bound
  /// methods, class attributes and module stubs before falling back to a
  /// [_BoundMethod] for the builtin collection methods.
  Object? getAttribute(Object? target, String name) {
    if (target is _PythonInstance) {
      if (target.attributes.containsKey(name)) return target.attributes[name];
      final lookup = target.cls.findMethodWithOwner(name);
      if (lookup != null) {
        return _BoundUserMethod(target, lookup.function, lookup.owner);
      }
      if (target.cls.hasClassAttribute(name)) {
        return target.cls.readClassAttribute(name);
      }
      throw RenPyPythonError(
        '${target.cls.name} object has no attribute `$name`',
      );
    }
    if (target is _PythonClass) {
      final method = target.findMethod(name);
      if (method != null) return method;
      if (target.hasClassAttribute(name)) {
        return target.readClassAttribute(name);
      }
      throw RenPyPythonError('${target.name} has no attribute `$name`');
    }
    if (target is _SuperProxy) {
      return _superAttribute(target, name);
    }
    if (target is _StubModule) {
      if (target.attributes.containsKey(name)) return target.attributes[name];
      final fn = target.functions[name];
      if (fn != null) return _BuiltinFunction('${target.name}.$name', fn);
      // Unknown module member: an opaque stub keeps deeper chains alive.
      return _StubModule('${target.name}.$name');
    }
    if (target is _UnsupportedMember) target.raise();
    if (target is _PythonDate) {
      switch (name) {
        case 'year':
          return target.year;
        case 'month':
          return target.month;
        case 'day':
          return target.day;
      }
    }
    return _BoundMethod(target, name);
  }

  bool _isScopedName(String name) =>
      name.startsWith('persistent.') ||
      name.startsWith('config.') ||
      name.startsWith('gui.') ||
      // `store.x` is the explicit spelling of the default namespace.
      name.startsWith('store.');

  /// Whether the dotted call target [full] is a runtime-irrelevant build/gui
  /// config directive that should execute as a silent no-op returning None.
  ///
  /// `build.<anything>(...)` is the packaging configuration object, which has
  /// no effect inside the player, so every method on it is treated as a no-op.
  /// `gui.init(...)` is likewise a config-time call (the rest of the `gui.`
  /// namespace stays a live scope for `gui.foo = x` reads/writes - only the
  /// `init` *call* is special-cased here). Anything else returns false so the
  /// caller keeps its normal resolution and the unknown-name fallback fires.
  bool _isConfigNoOpCall(String full) {
    if (full.startsWith('build.')) return true;
    if (full == 'gui.init') return true;
    return false;
  }

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
        return _subtract(a, b);
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
    // date + timedelta / timedelta + date.
    if (a is _PythonDate && b is _TimeDelta) {
      return _PythonDate(a.ordinal + b.wholeDays);
    }
    if (a is _TimeDelta && b is _PythonDate) {
      return _PythonDate(b.ordinal + a.wholeDays);
    }
    if (a is _TimeDelta && b is _TimeDelta) return _TimeDelta(a.days + b.days);
    throw RenPyPythonError('unsupported operands for +');
  }

  Object? _subtract(Object? a, Object? b) {
    if (a is num && b is num) return a - b;
    // date - timedelta -> date; date - date -> timedelta.
    if (a is _PythonDate && b is _TimeDelta) {
      return _PythonDate(a.ordinal - b.wholeDays);
    }
    if (a is _PythonDate && b is _PythonDate) {
      return _TimeDelta(a.ordinal - b.ordinal);
    }
    if (a is _TimeDelta && b is _TimeDelta) return _TimeDelta(a.days - b.days);
    throw RenPyPythonError('unsupported numeric operands');
  }

  Object? _multiply(Object? a, Object? b) {
    if (a is num && b is num) return a * b;
    if (a is String && b is int) return a * b;
    if (a is int && b is String) return b * a;
    if (a is List && b is int) return [for (var i = 0; i < b; i += 1) ...a];
    if (a is int && b is List) return [for (var i = 0; i < a; i += 1) ...b];
    throw RenPyPythonError('unsupported operands for *');
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
    if (a is _PythonDate && b is _PythonDate) {
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
    if (target is _DefaultDict) {
      // A missing-key read auto-creates and inserts the factory default.
      return target[index];
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
      // `renpy.*` calls route to the host shim before any name resolution, so
      // an unhandled name in the chain (there is no `renpy` value in scope)
      // never raises NameError for a function we do support.
      if (full != null && full.startsWith('renpy.')) {
        return _callRenpy(
          full.substring('renpy.'.length),
          positional,
          keywords,
        );
      }
      // Build/packaging and `gui.init` config directives have no runtime
      // gameplay effect in Ren'Py's player. They appear in real games'
      // `init python:` blocks (build.classify/archive/documentation, etc.)
      // and must execute as silent no-ops returning None rather than raising
      // a NameError on the `build`/`gui` namespace. This is deliberately
      // narrow: only these known config surfaces are stubbed; any other
      // unknown call still falls through and throws.
      if (full != null && _isConfigNoOpCall(full)) {
        return null;
      }
      if (full != null && _isScopedName(full) && scope.has(full)) {
        return _callMethod(
          scope.read(full),
          target.attribute,
          positional,
          keywords,
        );
      }
      final receiver = target.target.eval(this);
      if (receiver is _PythonInstance ||
          receiver is _PythonClass ||
          receiver is _SuperProxy ||
          receiver is _StubModule) {
        // Resolve the member as a value (bound method, stub function, ...) and
        // dispatch through the unified callable path.
        return invoke(
          getAttribute(receiver, target.attribute),
          positional,
          keywords,
        );
      }
      return _callMethod(receiver, target.attribute, positional, keywords);
    }

    return invoke(target.eval(this), positional, keywords);
  }

  /// Invokes [callee] with already-evaluated arguments, dispatching across the
  /// callable value kinds: builtins, user functions, bound instance methods,
  /// class constructors and opaque module stubs.
  Object? invoke(
    Object? callee,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    if (callee is _BuiltinFunction) {
      return callee.invoke(this, positional, keywords);
    }
    if (callee is _UserFunction) {
      return callee.invoke(positional, keywords);
    }
    if (callee is _BoundUserMethod) {
      return callee.invoke(positional, keywords);
    }
    if (callee is _PythonClass) {
      return _instantiate(callee, positional, keywords);
    }
    if (callee is _SuperFactory) {
      return _makeSuperProxy(callee, positional);
    }
    if (callee is _NoOpCallable) {
      // e.g. super().__init__(...) where the base defines no __init__.
      return null;
    }
    if (callee is _UnsupportedMember) callee.raise();
    if (callee is _DefaultDictType) {
      _DefaultDictType._factoryInterp = this;
      return callee.construct(positional);
    }
    if (callee is _DateType) {
      return callee.construct(positional);
    }
    if (callee is _TimeDeltaType) {
      return callee.construct(positional, keywords);
    }
    if (callee is _StubModule) {
      // Calling an opaque stub yields another opaque stub.
      return _StubModule('${callee.name}()');
    }
    if (callee is _BoundMethod) {
      if (callee.receiver is _UserFunction) {
        throw RenPyPythonError('object is not callable');
      }
      return _callMethod(callee.receiver, callee.name, positional, keywords);
    }
    throw RenPyPythonError('object is not callable');
  }

  /// Builds the `super()` proxy from a [_SuperFactory]. Supports the no-arg
  /// `super()` (using the factory's threaded defining class + receiver) and the
  /// explicit `super(ClassName, self)` form. Resolution starts at the parent of
  /// the relevant class; with no parent the proxy degrades to no-op/throwing
  /// lookups. Single inheritance only.
  _SuperProxy _makeSuperProxy(_SuperFactory factory, List<Object?> positional) {
    if (positional.isEmpty) {
      // No-arg form: parent of the class that declared the running method.
      if (factory.self == null) {
        throw RenPyPythonError('super(): no bound instance in scope');
      }
      return _SuperProxy(factory.definingClass?.base, factory.self!);
    }
    // Explicit super(ClassName, self): start at the parent of ClassName, bound
    // to the given instance. Tolerated for fidelity; MRO is not modelled.
    final cls = positional[0];
    final self = positional.length > 1 ? positional[1] : factory.self;
    if (cls is! _PythonClass) {
      throw RenPyPythonError('super(): first argument must be a class');
    }
    if (self is! _PythonInstance) {
      throw RenPyPythonError('super(): second argument must be an instance');
    }
    return _SuperProxy(cls.base, self);
  }

  /// Resolves attribute [name] on a `super()` proxy: looks the method up
  /// starting at the proxy's start class (the parent of the defining class) and
  /// binds it to the proxy's receiver. A missing method throws so callers fall
  /// back gracefully; the common `super().__init__(...)` with no base
  /// `__init__` is handled as a no-op at the call site.
  Object? _superAttribute(_SuperProxy proxy, String name) {
    final lookup = proxy.startClass?.findMethodWithOwner(name);
    if (lookup != null) {
      return _BoundUserMethod(proxy.self, lookup.function, lookup.owner);
    }
    // No base implementation: `super().__init__(...)` is a no-op (an inert
    // bound method that ignores its arguments); any other missing attribute
    // throws so the caller can fall back.
    if (name == '__init__') {
      return _NoOpCallable();
    }
    throw RenPyPythonError("'super' object has no attribute `$name`");
  }

  /// Constructs an instance of [cls], running `__init__` (resolved up the base
  /// chain) with the receiver bound as the first parameter.
  _PythonInstance _instantiate(
    _PythonClass cls,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    final instance = _PythonInstance(cls);
    final init = cls.findMethodWithOwner('__init__');
    if (init != null) {
      init.function.invoke(
        [instance, ...positional],
        keywords,
        definingClass: init.owner,
        selfReceiver: instance,
      );
    } else if (cls.isExceptionLike) {
      // Exception stubs keep their message as `message` for `except ... as e`.
      instance.attributes['message'] =
          positional.isEmpty ? '' : _str(positional.first);
    } else if (positional.isNotEmpty || keywords.isNotEmpty) {
      throw RenPyPythonError('${cls.name}() takes no arguments');
    }
    return instance;
  }

  /// Dispatches a `renpy.<function>(...)` call to the scope's [RenPyApi].
  ///
  /// [function] is the dotted suffix after `renpy.` (e.g. `variant`,
  /// `random.randint`, `music.queue`). Only the safe, host-shimmable subset is
  /// handled; screen-dependent functions (`show_screen`, `call_screen`,
  /// `display_menu`, `image`, `show`, `hide`, ...) deliberately throw a
  /// [RenPyPythonError] so the runner keeps falling back rather than faking
  /// behavior that needs the screen language.
  Object? _callRenpy(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    final api = scope.renpy;
    switch (function) {
      case 'variant':
        return api.variant(positional.isEmpty ? null : positional.first);
      case 'random.random':
        return api.randomRandom();
      case 'random.randint':
        if (positional.length < 2) {
          throw RenPyPythonError('renpy.random.randint expects (a, b)');
        }
        return api.randomRandint(_asInt(positional[0]), _asInt(positional[1]));
      case 'random.choice':
        // Accept both the positional form `choice(seq)` and the keyword form
        // `choice(seq=seq)` (the latter is common in real games, ~96x in
        // LearnToCodeRPG). The RenPyApi takes a positional List, so coerce
        // whichever the caller supplied into one.
        final choiceSeq =
            positional.isNotEmpty ? positional.first : keywords['seq'];
        if (choiceSeq == null && !keywords.containsKey('seq')) {
          throw RenPyPythonError('renpy.random.choice expects a sequence');
        }
        return api.randomChoice(_asIterable(choiceSeq).toList());
      case 'notify':
        api.notify(positional.isEmpty ? null : positional.first);
        return null;
      case 'input':
        return api.input(positional.isEmpty ? null : positional.first);
      case 'with_statement':
        api.withStatement(positional.isEmpty ? null : positional.first);
        return null;
      case 'restart_interaction':
      case 'block_rollback':
      case 'checkpoint':
        // Interaction/rollback bookkeeping has no analogue in this runner.
        return null;
      case 'get_screen':
        // No screen system yet; matches RenPy returning None for an absent one.
        return null;
      case 'music.queue':
      case 'music.play':
      case 'music.set_volume':
      case 'music.stop':
      case 'sound.play':
      case 'sound.set_volume':
      case 'sound.queue':
      case 'sound.stop':
      case 'voice':
      case 'voice_sustain':
        api.audio(function, positional, keywords);
        return null;
      case 'call':
        {
          final label = _renpyLabelArgument(function, positional, keywords);
          // Pull positional args meant for the called label. RenPy passes any
          // extra positionals/keywords through; we forward all but the label.
          final args =
              positional.length > 1 ? positional.sublist(1) : const <Object?>[];
          api.call(label, args: args, kwargs: keywords);
          return null;
        }
      case 'jump':
        {
          final label = _renpyLabelArgument(function, positional, keywords);
          api.jump(label);
          return null;
        }
      case 'show_screen':
        {
          final name = _renpyScreenNameArgument(function, positional, keywords);
          final rest =
              positional.length > 1 ? positional.sublist(1) : const <Object?>[];
          api.showScreen(name, rest, keywords);
          return null;
        }
      case 'hide_screen':
        {
          final name = _renpyScreenNameArgument(function, positional, keywords);
          api.hideScreen(name);
          return null;
        }
      default:
        throw RenPyPythonError('unsupported renpy.$function');
    }
  }

  /// Coerces the label argument of `renpy.call`/`renpy.jump` to a non-empty
  /// String. A missing/null/non-string label throws a [RenPyPythonError] so the
  /// runner falls back to a graceful skip rather than transferring control to a
  /// bogus target.
  String _renpyLabelArgument(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    final raw = positional.isNotEmpty ? positional.first : keywords['label'];
    if (raw is String && raw.isNotEmpty) return raw;
    throw RenPyPythonError('renpy.$function expects a string label');
  }

  /// Coerces the screen-name argument of `renpy.show_screen`/`renpy.hide_screen`
  /// to a non-empty String, throwing a [RenPyPythonError] otherwise so the
  /// runner falls back to a graceful skip.
  String _renpyScreenNameArgument(
    String function,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    final raw =
        positional.isNotEmpty
            ? positional.first
            : (keywords['_screen_name'] ?? keywords['name']);
    if (raw is String && raw.isNotEmpty) return raw;
    throw RenPyPythonError('renpy.$function expects a screen name');
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw RenPyPythonError('expected an integer, got ${_typeName(value)}');
  }

  /// Assigns [value] to the target expression [target], supporting bare names,
  /// attribute targets, subscript targets and tuple/list unpacking. Used by the
  /// statement executor for `=` and the resolved result of augmented `+=` etc.
  void assign(_Node target, Object? value) {
    if (target is _NameNode) {
      scope.write(target.name, value);
      return;
    }
    if (target is _AttributeNode) {
      final full = target.fullName;
      if (full != null && _isScopedName(full)) {
        scope.write(full, value);
        return;
      }
      final receiver = target.target.eval(this);
      if (receiver is _PythonInstance) {
        receiver.attributes[target.attribute] = value;
        return;
      }
      if (receiver is _PythonClass) {
        receiver.attributes[target.attribute] = value;
        return;
      }
      if (receiver is Map) {
        receiver[target.attribute] = value;
        return;
      }
      throw RenPyPythonError(
        'cannot assign attribute `${target.attribute}` on ${_typeName(receiver)}',
      );
    }
    if (target is _SubscriptNode) {
      final receiver = target.target.eval(this);
      final index = target.index.eval(this);
      if (index is _Slice) {
        throw RenPyPythonError('slice assignment is not supported');
      }
      if (receiver is List) {
        final i = _intIndex(index, receiver.length);
        receiver[i] = value;
        return;
      }
      if (receiver is Map) {
        receiver[index] = value;
        return;
      }
      throw RenPyPythonError('object does not support item assignment');
    }
    if (target is _TupleNode || target is _ListNode) {
      final targets =
          target is _TupleNode
              ? target.elements
              : (target as _ListNode).elements;
      final values = _asIterable(value).toList();
      if (values.length != targets.length) {
        throw RenPyPythonError(
          'cannot unpack ${values.length} values into ${targets.length} targets',
        );
      }
      for (var i = 0; i < targets.length; i += 1) {
        assign(targets[i], values[i]);
      }
      return;
    }
    throw RenPyPythonError('invalid assignment target');
  }

  /// Reads the current value of an assignment target, for augmented assignment.
  Object? readTarget(_Node target) => target.eval(this);

  /// Exposes Python iteration semantics for the statement executor's `for`.
  Iterable<Object?> iterableFor(Object? value) => _asIterable(value);

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
    if (receiver is _DateType) {
      if (name == 'today') return receiver.today();
      throw RenPyPythonError('no date method `$name`');
    }
    if (receiver is _PythonDate) {
      if (name == 'weekday') return receiver.weekday();
      throw RenPyPythonError('no date method `$name`');
    }
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
    if (value is _PythonInstance) return value.cls.name;
    if (value is _PythonClass) return 'type';
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
    if (value is _PythonInstance) {
      final str = value.cls.findMethod('__str__');
      if (str != null) return _str(str.invoke([value], const {}));
      if (value.cls.isExceptionLike) {
        return '${value.attributes['message'] ?? ''}';
      }
      return '<${value.cls.name} object>';
    }
    if (value is _PythonClass) return "<class '${value.name}'>";
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
    // gettext translation marker: returns the string unchanged.
    '_': (a, k) => a.isEmpty ? '' : a[0],
    // Ren'Py paragraph/translatable-string marker (e.g.
    // `define gui.about = _p("""...""")`). Identity on its first argument so the
    // string is stored unchanged; returns null gracefully if called with no
    // args. Never throws.
    '_p': (a, k) => a.isEmpty ? null : a[0],
    // Cosmetic Ren'Py GUI displayable-region helper. We don't render, so this
    // is a best-effort builtin that accepts any args and returns an inert,
    // opaque marker so `define gui.x = Borders(...)` evaluates and stores a
    // value instead of being skipped. Never throws.
    'Borders': (a, k) => _GuiPlaceholder('Borders', a, k),
    // Cosmetic Ren'Py GUI displayable (e.g. `define bubble.frame = Frame(...)`).
    // Same best-effort inert marker as Borders: accepts any args, returns an
    // opaque value, never throws.
    'Frame': (a, k) => _GuiPlaceholder('Frame', a, k),
    // Cosmetic Ren'Py transform displayable (e.g. nested in a
    // `define bubble.properties` dict as `Transform(...)`). Same inert marker
    // as Borders/Frame: accepts any args/kwargs, returns an opaque value, never
    // throws, so the enclosing define evaluates instead of being skipped.
    'Transform': (a, k) => _GuiPlaceholder('Transform', a, k),
  };

  /// A small set of builtin exception classes so `raise ValueError("...")` and
  /// `except ValueError as e:` work without a real exception hierarchy. They
  /// all descend (by name only) from `Exception`, which a bare except already
  /// covers; matching is by exact type name.
  static final Map<String, _PythonClass> _builtinExceptions = {
    for (final name in const [
      'Exception',
      'ValueError',
      'KeyError',
      'IndexError',
      'TypeError',
      'RuntimeError',
      'StopIteration',
      'AttributeError',
      'ZeroDivisionError',
      'NotImplementedError',
    ])
      name: _PythonClass(name, null, {}, {}, isException: true),
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
      if (t is _PythonClass && value is _PythonInstance) {
        if (value.cls.isSubclassOf(t)) return true;
      }
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

/// An inert, opaque marker returned by cosmetic Ren'Py GUI displayable
/// constructors (e.g. `Borders(...)`) that we do not actually render. It simply
/// captures its name and arguments so a `define` evaluates to a non-null value
/// instead of failing with `name '...' is not defined`.
class _GuiPlaceholder {
  _GuiPlaceholder(this.name, this.args, this.kwargs);

  final String name;
  final List<Object?> args;
  final Map<String, Object?> kwargs;

  @override
  String toString() => '<$name>';
}

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

// ---------------------------------------------------------------------------
// Classes & instances
// ---------------------------------------------------------------------------

/// A user-defined class value, produced by a `class Name(Base):` statement and
/// callable to construct an instance.
///
/// Methods are stored as [_UserFunction]s closing over the scope the class was
/// defined in, and class-level attributes (plain assignments in the body) are
/// stored alongside them. Single inheritance is supported through [base]:
/// attribute and method lookups that miss this class walk up the base chain.
/// `super()`, multiple bases and metaclasses are out of scope and the parser
/// rejects them so the runner falls back.
class _PythonClass {
  _PythonClass(
    this.name,
    this.base,
    this.methods,
    this.attributes, {
    this.isException = false,
  });

  final String name;
  final _PythonClass? base;
  final Map<String, _UserFunction> methods;
  final Map<String, Object?> attributes;

  /// Whether this is a builtin exception stub, which tolerates constructor
  /// arguments (stored as the instance's message) without a `__init__`.
  final bool isException;

  /// Whether this class or any base is an exception type, so a user subclass
  /// of `Exception` also accepts a message argument.
  bool get isExceptionLike => isException || (base?.isExceptionLike ?? false);

  /// Resolves [name] to a method anywhere on the class chain, or `null`.
  _UserFunction? findMethod(String name) {
    final local = methods[name];
    if (local != null) return local;
    return base?.findMethod(name);
  }

  /// Resolves [name] to a method anywhere on the class chain, reporting both
  /// the function and the class that actually declares it (so `super()` can be
  /// bound to the parent of the declaring class). Returns `null` if not found.
  _MethodLookup? findMethodWithOwner(String name) {
    final local = methods[name];
    if (local != null) return _MethodLookup(this, local);
    return base?.findMethodWithOwner(name);
  }

  /// Whether [name] names a class-level attribute on this class or a base.
  bool hasClassAttribute(String name) {
    if (attributes.containsKey(name)) return true;
    return base?.hasClassAttribute(name) ?? false;
  }

  /// Reads a class-level attribute from this class or a base.
  Object? readClassAttribute(String name) {
    if (attributes.containsKey(name)) return attributes[name];
    return base?.readClassAttribute(name);
  }

  /// Whether this class is [other] or descends from it, for `isinstance`.
  bool isSubclassOf(_PythonClass other) {
    if (identical(this, other)) return true;
    return base?.isSubclassOf(other) ?? false;
  }
}

/// An instance of a [_PythonClass], holding its own attribute map plus a link
/// back to its class for method and class-attribute resolution.
class _PythonInstance {
  _PythonInstance(this.cls);

  final _PythonClass cls;
  final Map<String, Object?> attributes = {};
}

/// The result of resolving a method up a class chain: the [function] and the
/// [owner] class that actually declares it, so `super()` inside that method can
/// be bound to the parent of [owner].
class _MethodLookup {
  _MethodLookup(this.owner, this.function);

  final _PythonClass owner;
  final _UserFunction function;
}

/// A method bound to a receiver instance, so the receiver is passed as the
/// first parameter (`self`) when the method is finally invoked.
///
/// [definingClass] records the class that declared [function] so the method
/// body can build a `super()` proxy bound to that class's parent.
class _BoundUserMethod {
  _BoundUserMethod(this.receiver, this.function, [this.definingClass]);

  final _PythonInstance receiver;
  final _UserFunction function;
  final _PythonClass? definingClass;

  Object? invoke(List<Object?> positional, Map<String, Object?> keywords) =>
      function.invoke(
        [receiver, ...positional],
        keywords,
        definingClass: definingClass,
        selfReceiver: receiver,
      );
}

/// The value bound to the name `super` inside a method body. Calling it (the
/// no-arg `super()` or the explicit `super(Class, self)` form) yields a
/// [_SuperProxy] that dispatches attribute/method access starting at the parent
/// of the class that declared the running method (single inheritance only).
class _SuperFactory {
  _SuperFactory(this.definingClass, this.self);

  /// The class whose method is currently executing; `super()` resolves to its
  /// [base]. May be null if the method's defining class could not be threaded.
  final _PythonClass? definingClass;
  final _PythonInstance? self;
}

/// A proxy over an instance whose attribute/method lookups begin at a base
/// class, implementing Python 3's `super()` for single inheritance.
class _SuperProxy {
  _SuperProxy(this.startClass, this.self);

  /// The class at which method resolution begins (the parent of the defining
  /// class). May be null when there is no base class.
  final _PythonClass? startClass;
  final _PythonInstance self;
}

/// A callable that ignores its arguments and returns null. Used so a
/// `super().__init__(...)` call against a base class with no `__init__`
/// degrades to a no-op rather than throwing.
class _NoOpCallable {
  const _NoOpCallable();
}

// ---------------------------------------------------------------------------
// Imports
// ---------------------------------------------------------------------------

/// An opaque value standing in for an imported module or name.
///
/// No real module system exists; `import` only needs to keep referencing the
/// name from crashing. A bare stub resolves any attribute to another stub and
/// is callable to another stub, so chains like `os.path.join(...)` evaluate
/// without aborting (returning opaque values). The `math` module is given a
/// small concrete [functions]/[attributes] table so the common constants and
/// functions behave; anything outside it falls back to opaque behavior.
class _StubModule {
  _StubModule(
    this.name, {
    Map<String, Object?>? attributes,
    Map<String, _BuiltinImpl>? functions,
  }) : attributes = attributes ?? const {},
       functions = functions ?? const {};

  final String name;
  final Map<String, Object?> attributes;
  final Map<String, _BuiltinImpl> functions;

  /// The `math` module subset commonly seen in real games.
  static _StubModule mathModule() => _StubModule(
    'math',
    attributes: {'pi': math.pi, 'e': math.e},
    functions: {
      'floor': (a, k) => (a[0] as num).floor(),
      'ceil': (a, k) => (a[0] as num).ceil(),
      'sqrt': (a, k) => math.sqrt(a[0] as num),
      'sin': (a, k) => math.sin(a[0] as num),
      'cos': (a, k) => math.cos(a[0] as num),
    },
  );

  /// The `collections` module subset. Only `defaultdict` is concrete; every
  /// other member resolves to an opaque stub whose *use* raises (graceful skip)
  /// rather than crashing.
  static _StubModule collectionsModule() => _StubModule(
    'collections',
    attributes: {'defaultdict': const _DefaultDictType()},
  );

  /// The `datetime` module subset: `date`, `timedelta` and `datetime` itself.
  /// Members beyond these resolve to an opaque stub.
  static _StubModule datetimeModule() => _StubModule(
    'datetime',
    attributes: {
      'date': const _DateType(),
      'datetime': const _DateType(),
      'timedelta': const _TimeDeltaType(),
    },
  );
}

/// A known module's member that this interpreter does not implement.
///
/// Unlike an opaque [_StubModule] (which keeps deep `os.path.join(...)` chains
/// alive), this poisons on *use*: calling it, reading an attribute or invoking a
/// method raises [RenPyPythonError] so the runner skips the block instead of
/// threading a meaningless stub through gameplay state.
class _UnsupportedMember {
  _UnsupportedMember(this.name);

  final String name;

  Never raise() => throw RenPyPythonError('`$name` is not supported');
}

// ---------------------------------------------------------------------------
// collections.defaultdict
// ---------------------------------------------------------------------------

/// The `collections.defaultdict` type, callable to build a [_DefaultDict].
///
/// `defaultdict(int)` / `defaultdict(list)` / `defaultdict(dict)` (and a bare
/// `defaultdict()` with no factory) are the patterns seen in real games. The
/// factory is captured as a Dart closure so missing-key reads can synthesize a
/// default without re-entering the interpreter.
class _DefaultDictType {
  const _DefaultDictType();

  _DefaultDict construct(List<Object?> positional) {
    final factoryArg = positional.isEmpty ? null : positional.first;
    return _DefaultDict(_factoryFor(factoryArg));
  }

  /// Maps a Python factory value onto a Dart default-producing closure.
  /// `int`->0, `float`->0.0, `list`->[], `dict`->{}, `set`->{}; a builtin or
  /// user callable is invoked with no arguments; `None`/absent yields `null`
  /// (matching `defaultdict()` raising only on missing-key access in CPython,
  /// but we degrade to `null` to stay non-fatal).
  Object? Function()? _factoryFor(Object? factory) {
    if (factory == null) return null;
    if (factory is _BuiltinFunction) {
      switch (factory.name) {
        case 'int':
          return () => 0;
        case 'float':
          return () => 0.0;
        case 'str':
          return () => '';
        case 'list':
        case 'tuple':
          return () => <Object?>[];
        case 'dict':
          return () => <Object?, Object?>{};
        case 'set':
          return () => <Object?>{};
        case 'bool':
          return () => false;
      }
      return () => factory.invoke(_factoryInterp!, const [], const {});
    }
    if (factory is _UserFunction) {
      return () => factory.invoke(const [], const {});
    }
    if (factory is _PythonClass) {
      throw RenPyPythonError(
        'defaultdict with a class factory is not supported',
      );
    }
    throw RenPyPythonError('defaultdict factory is not callable');
  }

  /// Interpreter used to invoke a builtin factory closure (e.g. a stray
  /// callable). Set transiently while constructing; the common `int`/`list`
  /// cases never need it.
  static _Interpreter? _factoryInterp;
}

/// A `defaultdict`: a real [Map] (so every existing dict path - subscript set,
/// `in`, `.get`, `.items`, `len`, iteration, update - works unchanged) that
/// auto-creates and inserts a default value on a missing-key READ.
class _DefaultDict extends MapBase<Object?, Object?> {
  _DefaultDict(this.defaultFactory);

  /// Produces a fresh default for a missing key, or `null` when none was given.
  final Object? Function()? defaultFactory;

  final Map<Object?, Object?> _backing = {};

  @override
  Object? operator [](Object? key) {
    if (_backing.containsKey(key)) return _backing[key];
    final value = defaultFactory == null ? null : defaultFactory!();
    _backing[key] = value;
    return value;
  }

  @override
  void operator []=(Object? key, Object? value) => _backing[key] = value;

  @override
  void clear() => _backing.clear();

  @override
  Iterable<Object?> get keys => _backing.keys;

  @override
  Object? remove(Object? key) => _backing.remove(key);

  // containsKey is delegated to the backing map so membership tests and `.get`
  // never trigger the auto-insert behavior reserved for `[]`.
  @override
  bool containsKey(Object? key) => _backing.containsKey(key);
}

// ---------------------------------------------------------------------------
// datetime
// ---------------------------------------------------------------------------

/// The `datetime.date` (and, as a loose alias, `datetime.datetime`) type.
///
/// `date.today()` is the only constructor exercised in the wild here; the
/// direct `date(y, m, d)` form is also accepted. Dates are modeled by an
/// integer day-count (proleptic ordinal) so arithmetic with [_TimeDelta] and
/// ordering work; the calendar fields are derived approximately - exact
/// correctness is secondary to "advances monotonically and never throws".
class _DateType {
  const _DateType();

  /// `date.today()` - a fixed reference date so runs are deterministic. The
  /// absolute value is unimportant; only relative arithmetic/ordering matters.
  _PythonDate today() => _PythonDate.fromYmd(2020, 1, 1);

  _PythonDate construct(List<Object?> positional) {
    if (positional.length >= 3) {
      return _PythonDate.fromYmd(
        (positional[0] as num).toInt(),
        (positional[1] as num).toInt(),
        (positional[2] as num).toInt(),
      );
    }
    throw RenPyPythonError('date() expects (year, month, day)');
  }
}

/// The `datetime.timedelta` type, callable as `timedelta(days=, weeks=, ...)`.
class _TimeDeltaType {
  const _TimeDeltaType();

  _TimeDelta construct(
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    num days = 0;
    if (positional.isNotEmpty) days += (positional.first as num);
    days += ((keywords['days'] as num?) ?? 0);
    days += ((keywords['weeks'] as num?) ?? 0) * 7;
    days += ((keywords['hours'] as num?) ?? 0) / 24;
    return _TimeDelta(days);
  }
}

/// A date value backed by an integer day-count, supporting `+`/`-` with a
/// [_TimeDelta], `-` between dates (yielding a [_TimeDelta]), comparison and
/// the `.year`/`.month`/`.day`/`.weekday()` reads used in practice.
class _PythonDate implements Comparable<_PythonDate> {
  _PythonDate(this.ordinal);

  /// Builds an ordinal from a y/m/d via Dart's [DateTime], which keeps the
  /// derived `.year`/`.month`/`.day` exact for in-range dates.
  factory _PythonDate.fromYmd(int year, int month, int day) {
    final dt = DateTime.utc(year, month, day);
    return _PythonDate(
      dt.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay,
    );
  }

  /// Days since the Unix epoch (1970-01-01). Negative is allowed.
  final int ordinal;

  DateTime get _dt => DateTime.fromMillisecondsSinceEpoch(
    ordinal * Duration.millisecondsPerDay,
    isUtc: true,
  );

  int get year => _dt.year;
  int get month => _dt.month;
  int get day => _dt.day;

  /// Python's `date.weekday()`: Monday is 0 .. Sunday is 6. Dart's
  /// `DateTime.weekday` is Monday 1 .. Sunday 7.
  int weekday() => _dt.weekday - 1;

  @override
  int compareTo(_PythonDate other) => ordinal.compareTo(other.ordinal);

  @override
  bool operator ==(Object other) =>
      other is _PythonDate && other.ordinal == ordinal;

  @override
  int get hashCode => ordinal.hashCode;

  @override
  String toString() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }
}

/// A `timedelta`, modeled as a (possibly fractional) number of days.
class _TimeDelta {
  _TimeDelta(this.days);

  final num days;

  int get wholeDays => days.floor();

  @override
  String toString() => '$days days';
}

// ---------------------------------------------------------------------------
// Statement execution: control-flow signals
// ---------------------------------------------------------------------------

/// Thrown by `return` to unwind a function body up to its call frame.
class _ReturnSignal {
  _ReturnSignal(this.value);
  final Object? value;
}

/// Thrown by `break` / `continue` and caught by the nearest enclosing loop.
class _LoopSignal {
  _LoopSignal(this.isBreak);
  final bool isBreak;
}

/// Thrown by a `raise` statement to unwind up to the nearest `try`/`except`.
///
/// [value] is whatever the program raised - typically a string, an exception
/// instance ([_PythonInstance]) or its class ([_PythonClass]). [typeName] is
/// the best-effort name used to match `except <Type>` clauses.
class _RaisedException {
  _RaisedException(this.value, this.typeName);
  final Object? value;
  final String typeName;
}

// ---------------------------------------------------------------------------
// Statement execution: scopes
// ---------------------------------------------------------------------------

/// A scope layering a function's locals over its enclosing (closure) scope.
///
/// Reads fall through to the parent when a name is not local, so a function
/// body sees the store's globals; writes land in the local map unless the name
/// was declared `global`, in which case they pass through to the parent so
/// stat-tracking functions can update the live store.
class _LocalsScope implements RenPyPythonScope {
  _LocalsScope(this._parent);

  final RenPyPythonScope _parent;
  final Map<String, Object?> _locals = {};
  final Set<String> _globals = {};

  /// Marks [name] as referring to the enclosing scope rather than a local.
  void declareGlobal(String name) => _globals.add(name);

  /// Seeds a parameter binding directly into the local map.
  void bindLocal(String name, Object? value) => _locals[name] = value;

  bool _isLocal(String name) =>
      !_globals.contains(name) && _locals.containsKey(name);

  @override
  RenPyApi get renpy => _parent.renpy;

  @override
  bool has(String name) {
    if (_isLocal(name)) return true;
    return _parent.has(name);
  }

  @override
  Object? read(String name) {
    if (_isLocal(name)) return _locals[name];
    return _parent.read(name);
  }

  @override
  void write(String name, Object? value) {
    // Scoped names (persistent.x, ...) and explicitly-global names always
    // resolve against the store; everything else is a function local.
    if (_globals.contains(name) ||
        name.startsWith('persistent.') ||
        name.startsWith('config.') ||
        name.startsWith('gui.') ||
        name.startsWith('store.')) {
      _parent.write(name, value);
      return;
    }
    _locals[name] = value;
  }
}

// ---------------------------------------------------------------------------
// Statement execution: user functions
// ---------------------------------------------------------------------------

/// The parsed signature of a `def`: positional names, their defaults and the
/// optional `*args` / `**kwargs` collectors.
class _ParamSpec {
  _ParamSpec(this.params, this.defaults, this.varargs, this.kwargs);

  final List<String> params;
  final Map<String, _Node> defaults;
  final String? varargs;
  final String? kwargs;
}

/// A user-defined function value, callable from the expression evaluator.
///
/// It closes over the scope in which it was defined so nested helpers and
/// store access keep working, and binds a fresh [_LocalsScope] per call.
class _UserFunction {
  _UserFunction(this.name, this.spec, this.body, this.closure);

  final String name;
  final _ParamSpec spec;
  final List<_Statement> body;
  final RenPyPythonScope closure;

  Object? invoke(
    List<Object?> positional,
    Map<String, Object?> keywords, {
    _PythonClass? definingClass,
    _PythonInstance? selfReceiver,
  }) {
    final locals = _LocalsScope(closure);
    _bindArguments(locals, positional, keywords);
    // Inside a method, bind `super` to a factory that knows the class whose
    // method is running and the active receiver, so `super().__init__(...)`
    // can resolve against the parent class. Bound as a local so an outer
    // `super` (there is none in practice) cannot shadow store reads.
    if (definingClass != null && selfReceiver != null) {
      locals.bindLocal('super', _SuperFactory(definingClass, selfReceiver));
    }
    final interp = _Interpreter(locals);
    try {
      for (final statement in body) {
        statement.exec(interp);
      }
    } on _ReturnSignal catch (signal) {
      return signal.value;
    }
    return null;
  }

  void _bindArguments(
    _LocalsScope locals,
    List<Object?> positional,
    Map<String, Object?> keywords,
  ) {
    final remainingKeywords = Map<String, Object?>.of(keywords);
    final defaultsInterp = _Interpreter(closure);

    for (var i = 0; i < spec.params.length; i += 1) {
      final paramName = spec.params[i];
      if (i < positional.length) {
        locals.bindLocal(paramName, positional[i]);
      } else if (remainingKeywords.containsKey(paramName)) {
        locals.bindLocal(paramName, remainingKeywords.remove(paramName));
      } else if (spec.defaults.containsKey(paramName)) {
        locals.bindLocal(
          paramName,
          spec.defaults[paramName]!.eval(defaultsInterp),
        );
      } else {
        throw RenPyPythonError(
          "$name() missing required argument '$paramName'",
        );
      }
    }

    final extraPositional =
        positional.length > spec.params.length
            ? positional.sublist(spec.params.length)
            : const <Object?>[];
    if (spec.varargs != null) {
      locals.bindLocal(spec.varargs!, List<Object?>.of(extraPositional));
    } else if (extraPositional.isNotEmpty) {
      throw RenPyPythonError('$name() takes too many positional arguments');
    }

    if (spec.kwargs != null) {
      locals.bindLocal(spec.kwargs!, remainingKeywords);
    } else if (remainingKeywords.isNotEmpty) {
      throw RenPyPythonError(
        "$name() got an unexpected keyword argument "
        "'${remainingKeywords.keys.first}'",
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Statement AST
// ---------------------------------------------------------------------------

abstract class _Statement {
  void exec(_Interpreter interp);
}

class _PassStatement implements _Statement {
  const _PassStatement();
  @override
  void exec(_Interpreter interp) {}
}

class _ExpressionStatement implements _Statement {
  _ExpressionStatement(this.expression);
  final _Node expression;
  @override
  void exec(_Interpreter interp) {
    expression.eval(interp);
  }
}

class _AssignStatement implements _Statement {
  _AssignStatement(this.targets, this.value);

  /// One or more targets; `a = b = expr` records both `a` and `b`.
  final List<_Node> targets;
  final _Node value;
  @override
  void exec(_Interpreter interp) {
    final result = value.eval(interp);
    for (final target in targets) {
      interp.assign(target, result);
    }
  }
}

class _AugmentedAssignStatement implements _Statement {
  _AugmentedAssignStatement(this.target, this.op, this.value);
  final _Node target;
  final String op; // '+', '-', '*', '/', '//', '%', '**'
  final _Node value;
  @override
  void exec(_Interpreter interp) {
    final current = interp.readTarget(target);
    final operand = value.eval(interp);
    interp.assign(target, interp.binary(op, current, operand));
  }
}

class _GlobalStatement implements _Statement {
  _GlobalStatement(this.names);
  final List<String> names;
  @override
  void exec(_Interpreter interp) {
    final scope = interp.scope;
    if (scope is _LocalsScope) {
      for (final name in names) {
        scope.declareGlobal(name);
      }
    }
  }
}

class _ReturnStatement implements _Statement {
  _ReturnStatement(this.value);
  final _Node? value;
  @override
  void exec(_Interpreter interp) {
    throw _ReturnSignal(value?.eval(interp));
  }
}

class _BreakStatement implements _Statement {
  const _BreakStatement();
  @override
  void exec(_Interpreter interp) => throw _LoopSignal(true);
}

class _ContinueStatement implements _Statement {
  const _ContinueStatement();
  @override
  void exec(_Interpreter interp) => throw _LoopSignal(false);
}

class _DefStatement implements _Statement {
  _DefStatement(this.name, this.spec, this.body);
  final String name;
  final _ParamSpec spec;
  final List<_Statement> body;
  @override
  void exec(_Interpreter interp) {
    interp.scope.write(name, _UserFunction(name, spec, body, interp.scope));
  }
}

class _IfStatement implements _Statement {
  _IfStatement(this.branches, this.orElse);

  /// Ordered `if` / `elif` branches, each a condition and its body.
  final List<MapEntry<_Node, List<_Statement>>> branches;
  final List<_Statement>? orElse;
  @override
  void exec(_Interpreter interp) {
    for (final branch in branches) {
      if (_Interpreter.truthy(branch.key.eval(interp))) {
        _execBody(branch.value, interp);
        return;
      }
    }
    if (orElse != null) _execBody(orElse!, interp);
  }
}

class _WhileStatement implements _Statement {
  _WhileStatement(this.condition, this.body, this.orElse);
  final _Node condition;
  final List<_Statement> body;
  final List<_Statement>? orElse;
  @override
  void exec(_Interpreter interp) {
    var broke = false;
    while (_Interpreter.truthy(condition.eval(interp))) {
      try {
        _execBody(body, interp);
      } on _LoopSignal catch (signal) {
        if (signal.isBreak) {
          broke = true;
          break;
        }
        continue;
      }
    }
    if (!broke && orElse != null) _execBody(orElse!, interp);
  }
}

class _ForStatement implements _Statement {
  _ForStatement(this.target, this.iterable, this.body, this.orElse);
  final _Node target;
  final _Node iterable;
  final List<_Statement> body;
  final List<_Statement>? orElse;
  @override
  void exec(_Interpreter interp) {
    final items = interp.iterableFor(iterable.eval(interp));
    var broke = false;
    for (final item in items) {
      interp.assign(target, item);
      try {
        _execBody(body, interp);
      } on _LoopSignal catch (signal) {
        if (signal.isBreak) {
          broke = true;
          break;
        }
        continue;
      }
    }
    if (!broke && orElse != null) _execBody(orElse!, interp);
  }
}

void _execBody(List<_Statement> body, _Interpreter interp) {
  for (final statement in body) {
    statement.exec(interp);
  }
}

/// A `class Name(Base):` definition.
///
/// The body is a mix of `def` methods, class-level attribute assignments and
/// `pass`. At exec time the methods become [_UserFunction]s closing over the
/// defining scope, the attribute assignments run into a fresh map, an optional
/// single base name resolves to its [_PythonClass], and the resulting class is
/// written into the scope.
class _ClassStatement implements _Statement {
  _ClassStatement(this.name, this.baseName, this.body);
  final String name;
  final String? baseName;
  final List<_Statement> body;

  @override
  void exec(_Interpreter interp) {
    _PythonClass? base;
    if (baseName != null) {
      final resolved = interp.readName(baseName!);
      if (resolved is! _PythonClass) {
        throw RenPyPythonError('base class `$baseName` is not a class');
      }
      base = resolved;
    }

    final methods = <String, _UserFunction>{};
    final attributes = <String, Object?>{};
    for (final statement in body) {
      if (statement is _DefStatement) {
        methods[statement.name] = _UserFunction(
          statement.name,
          statement.spec,
          statement.body,
          interp.scope,
        );
      } else if (statement is _AssignStatement) {
        final value = statement.value.eval(interp);
        for (final target in statement.targets) {
          if (target is! _NameNode) {
            throw RenPyPythonError('unsupported class-level assignment target');
          }
          attributes[target.name] = value;
        }
      } else if (statement is _PassStatement) {
        // Nothing to do.
      } else {
        throw RenPyPythonError('unsupported statement in class body');
      }
    }

    interp.scope.write(name, _PythonClass(name, base, methods, attributes));
  }
}

/// An `import`, `import X as Y` or `from X import a, b` statement.
///
/// There is no real module system: each imported name is bound to an opaque
/// [_StubModule] so referencing it never crashes, with `math` given a concrete
/// stub. The names bound are recorded so exec can write them all into scope.
class _ImportStatement implements _Statement {
  _ImportStatement(this.bindings);

  /// Local name -> the module path it stands for (used to special-case `math`).
  final Map<String, String> bindings;

  @override
  void exec(_Interpreter interp) {
    bindings.forEach((local, module) {
      interp.scope.write(local, _moduleFor(module));
    });
  }

  static Object? _moduleFor(String module) {
    if (module == 'math') return _StubModule.mathModule();
    if (module == 'collections') return _StubModule.collectionsModule();
    if (module == 'datetime') return _StubModule.datetimeModule();
    final concrete = _memberOf(module, 'math', _StubModule.mathModule());
    if (concrete != _absent) return concrete;
    final collected = _memberOf(
      module,
      'collections',
      _StubModule.collectionsModule(),
    );
    if (collected != _absent) return collected;
    final dated = _memberOf(module, 'datetime', _StubModule.datetimeModule());
    if (dated != _absent) return dated;
    return _StubModule(module);
  }

  /// Resolves `from <prefix> import <member>` against a concrete [stub],
  /// returning the bound value or the [_absent] sentinel when [module] is not a
  /// member of [prefix]. An unknown member of a known module yields an opaque
  /// stub, so referencing it is fine but *using* it raises (graceful skip).
  static Object? _memberOf(String module, String prefix, _StubModule stub) {
    final dotted = '$prefix.';
    if (!module.startsWith(dotted)) return _absent;
    final member = module.substring(dotted.length);
    if (stub.attributes.containsKey(member)) return stub.attributes[member];
    final fn = stub.functions[member];
    if (fn != null) return _BuiltinFunction('$prefix.$member', fn);
    // An unimplemented member of a *known* module: bind a poison value so the
    // name resolves, but *using* it raises RenPyPythonError (graceful skip)
    // rather than silently producing a stub and corrupting state.
    return _UnsupportedMember(module);
  }

  static const Object _absent = Object();
}

/// A `raise` statement.
///
/// `raise Type(...)`, `raise Type` and `raise <value>` are supported; a bare
/// `raise` is rejected (no exception context is tracked). The raised value is
/// wrapped in a [_RaisedException] so `try`/`except` can match and catch it.
class _RaiseStatement implements _Statement {
  _RaiseStatement(this.value);
  final _Node value;

  @override
  void exec(_Interpreter interp) {
    final raised = value.eval(interp);
    throw _RaisedException(raised, _typeNameOf(raised));
  }

  static String _typeNameOf(Object? value) {
    if (value is _PythonInstance) return value.cls.name;
    if (value is _PythonClass) return value.name;
    return '';
  }
}

/// A single `except [Type [as name]]:` clause.
class _ExceptClause {
  _ExceptClause(this.typeName, this.alias, this.body);

  /// The matched exception type name, or `null` for a bare `except:`.
  final String? typeName;
  final String? alias;
  final List<_Statement> body;
}

/// A `try: ... except ...: ... [else:] [finally:]` statement.
///
/// The try body runs; on a [_RaisedException] (or a [RenPyPythonError]
/// surfaced from an unsupported/failed operation) the first matching except
/// clause runs, with a bare `except` catching anything. `else` runs only when
/// the body completed without an exception, and `finally` always runs last.
class _TryStatement implements _Statement {
  _TryStatement(this.body, this.handlers, this.orElse, this.finalBody);
  final List<_Statement> body;
  final List<_ExceptClause> handlers;
  final List<_Statement>? orElse;
  final List<_Statement>? finalBody;

  @override
  void exec(_Interpreter interp) {
    try {
      var raised = false;
      try {
        _execBody(body, interp);
      } on _RaisedException catch (e) {
        raised = true;
        _handle(interp, e.value, e.typeName);
      } on RenPyPythonError catch (e) {
        // A failure inside the try body is catchable too, so a `try/except`
        // around unsupported operations degrades within the script.
        raised = true;
        _handle(interp, e.message, '');
      }
      if (!raised && orElse != null) _execBody(orElse!, interp);
    } finally {
      if (finalBody != null) _execBody(finalBody!, interp);
    }
  }

  void _handle(_Interpreter interp, Object? value, String typeName) {
    for (final handler in handlers) {
      if (_matches(handler.typeName, value, typeName)) {
        if (handler.alias != null) {
          interp.scope.write(handler.alias!, value);
        }
        _execBody(handler.body, interp);
        return;
      }
    }
    // No clause matched: re-raise so an outer handler (or the executor's
    // normalization) can deal with it.
    throw _RaisedException(value, typeName);
  }

  bool _matches(String? clauseType, Object? value, String typeName) {
    if (clauseType == null) return true; // bare except catches anything
    if (clauseType == typeName) return true;
    // A user instance matches any base class on its chain by name.
    if (value is _PythonInstance) {
      for (_PythonClass? c = value.cls; c != null; c = c.base) {
        if (c.name == clauseType) return true;
      }
    }
    // Builtin exceptions are all conceptually `Exception` subclasses.
    if (clauseType == 'Exception' &&
        value is _PythonInstance &&
        value.cls.isExceptionLike) {
      return true;
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Statement parser
// ---------------------------------------------------------------------------

/// A single source line with its indentation depth, used to build the block
/// structure before each line is handed to the expression tokenizer.
class _SourceLine {
  _SourceLine(this.indent, this.text);
  final int indent;
  final String text;
}

/// Parses an indentation-structured Python statement body into [_Statement]s.
///
/// It works line by line: it splits the source into logical lines (joining
/// bracket/quote continuations), tracks indentation, and reuses [_Lexer] /
/// [_Parser] for every expression fragment so the expression grammar is never
/// duplicated.
class _StatementParser {
  _StatementParser(String source) : _lines = _splitLines(source);

  final List<_SourceLine> _lines;
  int _index = 0;

  List<_Statement> parseModule() {
    if (_lines.isEmpty) return const [];
    return _parseBlockAt(_lines.first.indent);
  }

  /// Parses consecutive lines at exactly [blockIndent] into statements,
  /// stopping when indentation drops below it. A deeper line with no compound
  /// header above it is malformed and aborts parsing.
  List<_Statement> _parseBlockAt(int blockIndent) {
    final statements = <_Statement>[];
    while (_index < _lines.length) {
      final line = _lines[_index];
      if (line.indent < blockIndent) break;
      if (line.indent != blockIndent) {
        throw RenPyPythonError('unexpected indentation');
      }
      statements.addAll(_parseLine());
    }
    return statements;
  }

  /// Parses the indented body of a compound statement whose header sat at
  /// [headerIndent]. The body's own indentation is taken from its first line.
  List<_Statement> _parseBody(int headerIndent) {
    if (_index >= _lines.length || _lines[_index].indent <= headerIndent) {
      throw RenPyPythonError('expected an indented block');
    }
    return _parseBlockAt(_lines[_index].indent);
  }

  /// Parses the line at [_index], advancing past it (and any nested block for a
  /// compound statement). Returns the statements it produced; a simple line
  /// joined with `;` yields several.
  List<_Statement> _parseLine() {
    final line = _lines[_index];
    final text = line.text;

    // A decorator line (`@name`, `@dotted.name`, `@name(args)`) sits on its own
    // line immediately above the `def`/`class` it decorates. Real games use
    // decorators such as `@gui.variant` whose effect is irrelevant to headless
    // logic, so any stack of decorators is consumed and DISCARDED and the
    // following function/class is defined undecorated. This avoids the
    // decorator falling through to the simple-statement path (where `@name`
    // is not valid syntax and would abort the whole block).
    if (text.trimLeft().startsWith('@')) {
      return _parseDecorated(line.indent);
    }

    final keyword = _leadingKeyword(text);

    switch (keyword) {
      case 'if':
        return [_parseIf(line.indent)];
      case 'while':
        return [_parseWhile(line.indent)];
      case 'for':
        return [_parseFor(line.indent)];
      case 'def':
        return [_parseDef(line.indent)];
      case 'class':
        return [_parseClass(line.indent)];
      case 'try':
        return [_parseTry(line.indent)];
    }

    // A simple (non-compound) statement, possibly several split by `;`.
    _index += 1;
    final result = <_Statement>[];
    for (final piece in _splitSimpleStatements(text)) {
      result.add(_parseSimpleStatement(piece));
    }
    return result;
  }

  /// Consumes one or more stacked decorator lines (already known to start with
  /// `@`) at [indent] and parses the `def`/`class` they decorate, returning it
  /// undecorated. The decorators themselves are discarded - their call/registry
  /// semantics are irrelevant to headless logic. A decorator not followed by a
  /// `def`/`class` (or by a deeper-indented line) is malformed; throwing here is
  /// caught by the normal graceful fallback rather than corrupting the block.
  List<_Statement> _parseDecorated(int indent) {
    while (_index < _lines.length &&
        _lines[_index].indent == indent &&
        _lines[_index].text.trimLeft().startsWith('@')) {
      // Discard the decorator line.
      _index += 1;
    }
    if (_index >= _lines.length || _lines[_index].indent != indent) {
      throw RenPyPythonError('decorator is not followed by a definition');
    }
    final keyword = _leadingKeyword(_lines[_index].text);
    switch (keyword) {
      case 'def':
        return [_parseDef(indent)];
      case 'class':
        return [_parseClass(indent)];
      default:
        throw RenPyPythonError('decorator must precede a `def` or `class`');
    }
  }

  _Statement _parseIf(int indent) {
    final branches = <MapEntry<_Node, List<_Statement>>>[];
    List<_Statement>? orElse;

    // First `if`.
    branches.add(_parseConditionalHeader('if', indent));
    while (_index < _lines.length && _lines[_index].indent == indent) {
      final text = _lines[_index].text;
      final keyword = _leadingKeyword(text);
      if (keyword == 'elif') {
        branches.add(_parseConditionalHeader('elif', indent));
      } else if (keyword == 'else') {
        orElse = _parseElse(indent);
        break;
      } else {
        break;
      }
    }
    return _IfStatement(branches, orElse);
  }

  MapEntry<_Node, List<_Statement>> _parseConditionalHeader(
    String keyword,
    int indent,
  ) {
    final header = _lines[_index].text;
    final condition = _parseHeaderExpression(header, keyword);
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `$keyword` body');
    return MapEntry(condition, body);
  }

  List<_Statement> _parseElse(int indent) {
    final header = _lines[_index].text.trim();
    if (header != 'else:') throw RenPyPythonError('malformed `else`');
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `else` body');
    return body;
  }

  _Statement _parseWhile(int indent) {
    final header = _lines[_index].text;
    final condition = _parseHeaderExpression(header, 'while');
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `while` body');
    final orElse = _parseOptionalElse(indent);
    return _WhileStatement(condition, body, orElse);
  }

  _Statement _parseFor(int indent) {
    final header = _stripColon(_lines[_index].text, 'for');
    // Split `<targets> in <iterable>` at the top-level `in` keyword. The
    // target side must be parsed without treating `in` as a comparison, so the
    // textual split happens before tokenizing each side.
    final split = _splitForHeader(header);
    final target = _parseTargetFragment(split.target);
    final iterable = _parseFragment(split.iterable);
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `for` body');
    final orElse = _parseOptionalElse(indent);
    return _ForStatement(target, iterable, body, orElse);
  }

  List<_Statement>? _parseOptionalElse(int indent) {
    if (_index < _lines.length &&
        _lines[_index].indent == indent &&
        _leadingKeyword(_lines[_index].text) == 'else') {
      return _parseElse(indent);
    }
    return null;
  }

  _Statement _parseDef(int indent) {
    final header = _lines[_index].text.trim();
    if (!header.endsWith(':')) {
      throw RenPyPythonError('expected `:` ending `def` header');
    }
    final signature = header.substring(0, header.length - 1).trim();
    final match = RegExp(r'^def\s+([A-Za-z_]\w*)\s*\(').firstMatch(signature);
    if (match == null) throw RenPyPythonError('malformed `def` header');
    final name = match.group(1)!;
    final paramText = signature.substring(match.end - 1);
    final parser = _Parser(_Lexer(paramText).tokenize());
    final spec = parser.parseParamSpec();
    if (!parser.atEnd) {
      throw RenPyPythonError('trailing tokens in `def` header');
    }
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `def` body');
    return _DefStatement(name, spec, body);
  }

  _Statement _parseClass(int indent) {
    final header = _lines[_index].text.trim();
    if (!header.endsWith(':')) {
      throw RenPyPythonError('expected `:` ending `class` header');
    }
    final signature = header.substring(0, header.length - 1).trim();
    final match = RegExp(
      r'^class\s+([A-Za-z_]\w*)\s*(?:\(([^)]*)\))?$',
    ).firstMatch(signature);
    if (match == null) throw RenPyPythonError('malformed `class` header');
    final name = match.group(1)!;
    final baseList = match.group(2)?.trim() ?? '';
    String? baseName;
    if (baseList.isNotEmpty) {
      final bases = baseList
          .split(',')
          .map((b) => b.trim())
          .where((b) => b.isNotEmpty);
      if (bases.length > 1) {
        throw RenPyPythonError('multiple inheritance is not supported');
      }
      final only = bases.first;
      // `object` is Python's implicit root; treat it as no explicit base.
      if (only.contains('=') || only.startsWith('metaclass')) {
        throw RenPyPythonError('class keyword arguments are not supported');
      }
      if (only != 'object') baseName = only;
    }
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `class` body');
    return _ClassStatement(name, baseName, body);
  }

  _Statement _parseTry(int indent) {
    final header = _lines[_index].text.trim();
    if (header != 'try:') throw RenPyPythonError('malformed `try` header');
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `try` body');

    final handlers = <_ExceptClause>[];
    while (_index < _lines.length &&
        _lines[_index].indent == indent &&
        _leadingKeyword(_lines[_index].text) == 'except') {
      handlers.add(_parseExcept(indent));
    }

    List<_Statement>? orElse;
    if (_index < _lines.length &&
        _lines[_index].indent == indent &&
        _leadingKeyword(_lines[_index].text) == 'else') {
      orElse = _parseElse(indent);
    }

    List<_Statement>? finalBody;
    if (_index < _lines.length &&
        _lines[_index].indent == indent &&
        _leadingKeyword(_lines[_index].text) == 'finally') {
      final headerText = _lines[_index].text.trim();
      if (headerText != 'finally:') {
        throw RenPyPythonError('malformed `finally`');
      }
      _index += 1;
      finalBody = _parseBody(indent);
      if (finalBody.isEmpty) throw RenPyPythonError('empty `finally` body');
    }

    if (handlers.isEmpty && finalBody == null) {
      throw RenPyPythonError('`try` needs an `except` or `finally`');
    }
    return _TryStatement(body, handlers, orElse, finalBody);
  }

  _ExceptClause _parseExcept(int indent) {
    final header = _lines[_index].text.trim();
    if (!header.endsWith(':')) {
      throw RenPyPythonError('expected `:` ending `except` header');
    }
    final spec = header.substring('except'.length, header.length - 1).trim();
    String? typeName;
    String? alias;
    if (spec.isNotEmpty) {
      final match = RegExp(
        r'^([A-Za-z_]\w*)(?:\s+as\s+([A-Za-z_]\w*))?$',
      ).firstMatch(spec);
      if (match == null) {
        // Tuples of types and dotted names are out of scope.
        throw RenPyPythonError('unsupported `except` clause `$spec`');
      }
      typeName = match.group(1);
      alias = match.group(2);
    }
    _index += 1;
    final body = _parseBody(indent);
    if (body.isEmpty) throw RenPyPythonError('empty `except` body');
    return _ExceptClause(typeName, alias, body);
  }

  _Statement _parseImport(String trimmed) {
    final bindings = <String, String>{};
    if (trimmed.startsWith('from ')) {
      final match = RegExp(
        r'^from\s+([\w.]+)\s+import\s+(.+)$',
      ).firstMatch(trimmed);
      if (match == null) throw RenPyPythonError('malformed `from import`');
      if (match.group(2)!.trim() == '*') {
        throw RenPyPythonError('`from import *` is not supported');
      }
      for (final piece in match.group(2)!.split(',')) {
        final name = piece.trim();
        if (name.isEmpty) continue;
        final asMatch = RegExp(r'^(\w+)(?:\s+as\s+(\w+))?$').firstMatch(name);
        if (asMatch == null) throw RenPyPythonError('malformed import name');
        final local = asMatch.group(2) ?? asMatch.group(1)!;
        bindings[local] = '${match.group(1)}.${asMatch.group(1)}';
      }
    } else {
      final spec = trimmed.substring('import'.length).trim();
      if (spec.isEmpty) throw RenPyPythonError('malformed `import`');
      for (final piece in spec.split(',')) {
        final name = piece.trim();
        if (name.isEmpty) continue;
        final asMatch = RegExp(
          r'^([\w.]+)(?:\s+as\s+(\w+))?$',
        ).firstMatch(name);
        if (asMatch == null) throw RenPyPythonError('malformed import name');
        final module = asMatch.group(1)!;
        // `import a.b.c` binds the top-level `a`; `import a.b as c` binds `c`.
        final local = asMatch.group(2) ?? module.split('.').first;
        bindings[local] = asMatch.group(2) != null ? module : local;
      }
    }
    if (bindings.isEmpty) throw RenPyPythonError('malformed `import`');
    return _ImportStatement(bindings);
  }

  _Statement _parseRaise(String trimmed) {
    final rest = trimmed.substring('raise'.length).trim();
    if (rest.isEmpty) {
      // A bare re-raise has no exception context to reuse here.
      throw RenPyPythonError('bare `raise` is not supported');
    }
    return _RaiseStatement(_parseFragment(rest));
  }

  _Statement _parseSimpleStatement(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed == 'pass') return const _PassStatement();
    if (trimmed == 'break') return const _BreakStatement();
    if (trimmed == 'continue') return const _ContinueStatement();

    if (trimmed == 'return' || trimmed.startsWith('return ')) {
      final rest = trimmed.substring('return'.length).trim();
      if (rest.isEmpty) return _ReturnStatement(null);
      return _ReturnStatement(_parseFragment(rest));
    }

    if (trimmed.startsWith('global ')) {
      final names =
          trimmed
              .substring('global '.length)
              .split(',')
              .map((n) => n.trim())
              .where((n) => n.isNotEmpty)
              .toList();
      return _GlobalStatement(names);
    }

    if (trimmed == 'import' ||
        trimmed.startsWith('import ') ||
        trimmed.startsWith('from ')) {
      return _parseImport(trimmed);
    }
    if (trimmed == 'raise' || trimmed.startsWith('raise ')) {
      return _parseRaise(trimmed);
    }

    if (trimmed.startsWith('with ') ||
        trimmed.startsWith('assert ') ||
        trimmed.startsWith('del ') ||
        trimmed.startsWith('yield') ||
        trimmed.startsWith('async ') ||
        trimmed.startsWith('nonlocal ')) {
      throw RenPyPythonError('unsupported statement `$trimmed`');
    }

    final augmented = _matchAugmented(trimmed);
    if (augmented != null) {
      final target = _parseTargetFragment(augmented.target);
      final value = _parseFragment(augmented.expression);
      return _AugmentedAssignStatement(target, augmented.op, value);
    }

    final assignParts = _splitAssignment(trimmed);
    if (assignParts != null) {
      final targets = [
        for (final part in assignParts.targets) _parseTargetFragment(part),
      ];
      final value = _parseValueFragment(assignParts.value);
      return _AssignStatement(targets, value);
    }

    return _ExpressionStatement(_parseFragment(trimmed));
  }

  // -- expression fragment helpers -----------------------------------------

  _Node _parseFragment(String text) {
    final parser = _Parser(_Lexer(text).tokenize());
    final node = parser.parseExpression();
    parser.expectEnd();
    return node;
  }

  /// Parses a right-hand-side value, allowing a bare top-level tuple such as
  /// `5, 6` (Python's `a, b = 5, 6`). The resulting [_TupleNode] evaluates to a
  /// list, which the unpacking assignment then distributes across its targets.
  _Node _parseValueFragment(String text) {
    final parser = _Parser(_Lexer(text).tokenize());
    final node = parser.parseTargetList();
    if (!parser.atEnd) {
      throw RenPyPythonError('invalid expression `$text`');
    }
    return node;
  }

  _Node _parseTargetFragment(String text) {
    final parser = _Parser(_Lexer(text).tokenize());
    final node = parser.parseTargetList();
    if (!parser.atEnd) {
      throw RenPyPythonError('invalid assignment target `$text`');
    }
    return node;
  }

  _Node _parseHeaderExpression(String header, String keyword) {
    final body = _stripColon(header, keyword);
    return _parseFragment(body);
  }

  _ForHeader _splitForHeader(String header) {
    var depth = 0;
    String? quote;
    for (var i = 0; i < header.length; i += 1) {
      final ch = header[i];
      if (quote != null) {
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth += 1;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth -= 1;
      } else if (depth == 0 &&
          header.startsWith('in', i) &&
          _isWordBoundary(header, i - 1) &&
          _isWordBoundary(header, i + 2)) {
        return _ForHeader(
          header.substring(0, i).trim(),
          header.substring(i + 2).trim(),
        );
      }
    }
    throw RenPyPythonError('expected `in` in `for` statement');
  }

  bool _isWordBoundary(String s, int index) {
    if (index < 0 || index >= s.length) return true;
    final ch = s[index];
    return !RegExp(r'[A-Za-z0-9_]').hasMatch(ch);
  }

  String _stripColon(String header, String keyword) {
    var text = header.trim();
    if (text.startsWith('$keyword ') || text.startsWith('$keyword:')) {
      text = text.substring(keyword.length).trim();
    }
    if (!text.endsWith(':')) {
      throw RenPyPythonError('expected `:` ending `$keyword` header');
    }
    return text.substring(0, text.length - 1).trim();
  }

  // -- assignment splitting -------------------------------------------------

  _AugmentedMatch? _matchAugmented(String text) {
    final match = RegExp(
      r'^(.+?)\s*(\/\/|\*\*|[+\-*/%])=\s*(.+)$',
      dotAll: true,
    ).firstMatch(text);
    if (match == null) return null;
    // Guard against matching `==`, `<=`, `!=` etc. - those are handled as
    // expressions, never as augmented assignment.
    return _AugmentedMatch(
      match.group(1)!.trim(),
      match.group(2)!,
      match.group(3)!.trim(),
    );
  }

  /// Splits `a = b = expr` into its target chain and the final value. Returns
  /// `null` when there is no top-level `=`, when it is really a comparison
  /// (`==`, `<=`, ...), or when an augmented operator precedes the `=`.
  _AssignSplit? _splitAssignment(String text) {
    final positions = _topLevelAssignPositions(text);
    if (positions.isEmpty) return null;
    final targets = <String>[];
    var start = 0;
    for (final pos in positions) {
      targets.add(text.substring(start, pos).trim());
      start = pos + 1;
    }
    final value = text.substring(start).trim();
    if (value.isEmpty) return null;
    return _AssignSplit(targets, value);
  }

  /// Returns the indices of every top-level `=` that is a real assignment
  /// (not part of `==`, `<=`, `>=`, `!=` or an augmented operator).
  List<int> _topLevelAssignPositions(String text) {
    final positions = <int>[];
    var depth = 0;
    String? quote;
    for (var i = 0; i < text.length; i += 1) {
      final ch = text[i];
      if (quote != null) {
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth += 1;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth -= 1;
      } else if (depth == 0 && ch == '=') {
        final prev = i > 0 ? text[i - 1] : '';
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (next == '=') {
          i += 1; // skip `==`
          continue;
        }
        if (prev == '=' ||
            prev == '!' ||
            prev == '<' ||
            prev == '>' ||
            prev == '+' ||
            prev == '-' ||
            prev == '*' ||
            prev == '/' ||
            prev == '%') {
          continue;
        }
        positions.add(i);
      }
    }
    return positions;
  }

  // -- line splitting -------------------------------------------------------

  List<String> _splitSimpleStatements(String text) {
    // Split on top-level semicolons so `a = 1; b = 2` becomes two statements.
    final pieces = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    String? quote;
    for (var i = 0; i < text.length; i += 1) {
      final ch = text[i];
      if (quote != null) {
        buffer.write(ch);
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
        buffer.write(ch);
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth += 1;
        buffer.write(ch);
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth -= 1;
        buffer.write(ch);
      } else if (depth == 0 && ch == ';') {
        pieces.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    if (buffer.toString().trim().isNotEmpty) pieces.add(buffer.toString());
    return pieces.isEmpty ? [''] : pieces;
  }

  String _leadingKeyword(String text) {
    final match = RegExp(r'^([A-Za-z_]\w*)').firstMatch(text.trimLeft());
    return match?.group(1) ?? '';
  }

  /// Splits [source] into logical lines, dropping blanks/comments and joining
  /// physical lines that continue inside brackets, across a trailing backslash,
  /// or within a triple-quoted string.
  static List<_SourceLine> _splitLines(String source) {
    final physical = source.split('\n');
    final result = <_SourceLine>[];
    var i = 0;
    while (i < physical.length) {
      var raw = physical[i];
      var indent = _indentOf(raw);
      var content = raw.substring(indent);
      i += 1;

      // Join continuations while brackets are open, a backslash trails, or a
      // triple-quoted string is unterminated.
      while (_needsContinuation(content) && i < physical.length) {
        if (content.endsWith('\\')) {
          content = content.substring(0, content.length - 1);
        }
        content = '$content\n${physical[i]}';
        i += 1;
      }

      final stripped = content.trimLeft();
      if (stripped.isEmpty || stripped.startsWith('#')) continue;
      result.add(_SourceLine(indent, _stripTrailingComment(content)));
    }
    return result;
  }

  static int _indentOf(String line) {
    var indent = 0;
    while (indent < line.length &&
        (line[indent] == ' ' || line[indent] == '\t')) {
      indent += 1;
    }
    return indent;
  }

  static bool _needsContinuation(String content) {
    if (content.trimRight().endsWith('\\')) return true;
    var depth = 0;
    String? quote;
    var tripleOpen = false;
    for (var i = 0; i < content.length; i += 1) {
      final ch = content[i];
      if (tripleOpen) {
        if (i + 2 < content.length + 1 && content.startsWith(quote! * 3, i)) {
          tripleOpen = false;
          quote = null;
          i += 2;
        }
        continue;
      }
      if (quote != null) {
        if (ch == quote) quote = null;
        continue;
      }
      if ((ch == '"' || ch == "'")) {
        if (content.startsWith(ch * 3, i)) {
          tripleOpen = true;
          quote = ch;
          i += 2;
        } else {
          quote = ch;
        }
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth += 1;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth -= 1;
      }
    }
    return depth > 0 || tripleOpen;
  }

  static String _stripTrailingComment(String content) {
    var depth = 0;
    String? quote;
    for (var i = 0; i < content.length; i += 1) {
      final ch = content[i];
      if (quote != null) {
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == '"' || ch == "'") {
        quote = ch;
      } else if (ch == '(' || ch == '[' || ch == '{') {
        depth += 1;
      } else if (ch == ')' || ch == ']' || ch == '}') {
        depth -= 1;
      } else if (ch == '#' && depth == 0) {
        return content.substring(0, i).trimRight();
      }
    }
    return content.trimRight();
  }
}

class _AugmentedMatch {
  _AugmentedMatch(this.target, this.op, this.expression);
  final String target;
  final String op;
  final String expression;
}

class _AssignSplit {
  _AssignSplit(this.targets, this.value);
  final List<String> targets;
  final String value;
}

class _ForHeader {
  _ForHeader(this.target, this.iterable);
  final String target;
  final String iterable;
}
