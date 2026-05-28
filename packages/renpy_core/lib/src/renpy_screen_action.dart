import 'renpy_python.dart';

/// The kind of a parsed screen [RenPyScreenAction].
enum RenPyScreenActionKind {
  /// `Return(value)` - end a `call screen` with a result.
  returnValue,

  /// `Jump("label")` - jump script execution to a label.
  jump,

  /// `Call("label")` - call a label, returning afterwards.
  call,

  /// `Show("screen", ...)` - show a screen on the screen layer.
  showScreen,

  /// `Hide("screen")` - hide a shown screen.
  hideScreen,

  /// `ShowMenu("name")` - show a built-in menu screen.
  showMenu,

  /// `SetVariable("name", value)` - set a store variable.
  setVariable,

  /// `SetField(object, "field", value)` - set a field on an object expression.
  setField,

  /// `SetScreenVariable("name", value)` - set a screen-local variable.
  setScreenVariable,

  /// `ToggleVariable("name")` - toggle a store variable's truthiness.
  toggleVariable,

  /// `ToggleField(object, "field")` - toggle a field on an object expression.
  toggleField,

  /// `ToggleScreenVariable("name")` - toggle a screen-local variable.
  toggleScreenVariable,

  /// `AddToSet(set, value)` - add a value to a set/list expression.
  addToSet,

  /// `RemoveFromSet(set, value)` - remove a value from a set/list expression.
  removeFromSet,

  /// `NullAction()` - do nothing (also the fallback for an unparsed action).
  nullAction,

  /// `Function(callable, ...)` - best-effort call of a store function.
  function,

  /// `[A, B, ...]` - a list literal of actions, executed in order. Carried in
  /// [RenPyScreenAction.actions].
  multiple,
}

/// A platform-neutral descriptor for a RenPy screen action.
///
/// A screen `action`/`alternate` property string is parsed into one of these by
/// [RenPyScreenAction.parse]. The UI invokes the action through the runner's
/// `executeScreenAction`, which routes it against engine state. Argument
/// expressions that can be evaluated up front (values, screen names) are stored
/// already-evaluated; targets that must be resolved at execution time (the
/// variable/field name, the object expression for Set/ToggleField) are kept as
/// raw text.
class RenPyScreenAction {
  RenPyScreenAction({
    required this.kind,
    this.target,
    this.field,
    this.value,
    this.hasValue = false,
    this.screenName,
    this.label,
    this.functionName,
    this.positional = const [],
    this.keywords = const {},
    this.actions = const [],
    this.raw,
  });

  final RenPyScreenActionKind kind;

  /// For Set/Toggle variable actions, the variable name. For SetField/
  /// ToggleField and AddToSet/RemoveFromSet, the raw object/collection
  /// expression.
  final String? target;

  /// For SetField/ToggleField, the field name.
  final String? field;

  /// The already-evaluated value for Set/Return/AddToSet/RemoveFromSet, when
  /// [hasValue] is true.
  final Object? value;

  /// Whether [value] was supplied (distinguishes a literal `null`/`None` value
  /// from an absent one).
  final bool hasValue;

  /// For Show/Hide/ShowMenu, the screen (or menu) name.
  final String? screenName;

  /// For Jump/Call, the label name.
  final String? label;

  /// For Function, the callable's name.
  final String? functionName;

  /// For Function/Show, the already-evaluated positional arguments.
  final List<Object?> positional;

  /// For Function/Show, the already-evaluated keyword arguments.
  final Map<String, Object?> keywords;

  /// For [RenPyScreenActionKind.multiple], the ordered sub-actions parsed from a
  /// list literal `[A, B, ...]`. Empty for every other kind.
  final List<RenPyScreenAction> actions;

  /// The raw action source, kept for diagnostics and fallthrough.
  final String? raw;

  static const RenPyPythonEvaluator _defaultEvaluator = RenPyPythonEvaluator();

  /// Parses an action expression [source] into a descriptor.
  ///
  /// [scope] is used to evaluate value arguments eagerly. An action that cannot
  /// be recognized becomes a [RenPyScreenActionKind.nullAction] carrying the raw
  /// source, mirroring the engine's fallback contract (never throw on an
  /// unsupported construct).
  static RenPyScreenAction parse(
    String source,
    RenPyPythonEvaluator evaluator,
    RenPyPythonScope scope,
  ) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return RenPyScreenAction(kind: RenPyScreenActionKind.nullAction);
    }

    // A top-level list literal `[A, B, ...]` is a sequence of actions executed
    // in order (e.g. `timer 3.0 action [Hide("foo"), Return()]`).
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      final inner = trimmed.substring(1, trimmed.length - 1);
      final elements = _splitTopLevel(inner);
      final actions = <RenPyScreenAction>[
        for (final element in elements)
          if (element.trim().isNotEmpty)
            RenPyScreenAction.parse(element, evaluator, scope),
      ];
      return RenPyScreenAction(
        kind: RenPyScreenActionKind.multiple,
        actions: actions,
        raw: trimmed,
      );
    }

    final open = trimmed.indexOf('(');
    // A bare `NullAction` without parentheses.
    if (open < 0) {
      if (trimmed == 'NullAction') {
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.nullAction,
          raw: trimmed,
        );
      }
      // A bare name that isn't a recognized action keyword may be a screen
      // parameter bound to an action that was passed into the screen, e.g.
      // `screen confirm(yes_action): textbutton "Yes" action yes_action`
      // invoked as `call screen confirm(yes_action=Return("ok"))`. The runner
      // binds such an argument as the RAW action-expression string (the Python
      // evaluator has no `Return`/`Jump`/`ShowMenu` constructors, so it falls
      // through to a literal passthrough). Re-parse that bound string through
      // this same parser so the button executes the passed action instead of a
      // no-op. Anything else stays a nullAction.
      final bound = _resolveBoundAction(trimmed, evaluator, scope);
      if (bound != null) return bound;
      return RenPyScreenAction(
        kind: RenPyScreenActionKind.nullAction,
        raw: trimmed,
      );
    }
    if (!trimmed.endsWith(')')) {
      return RenPyScreenAction(
        kind: RenPyScreenActionKind.nullAction,
        raw: trimmed,
      );
    }

    final name = trimmed.substring(0, open).trim();
    final argSource = trimmed.substring(open + 1, trimmed.length - 1);
    final args = _splitTopLevel(argSource);

    String? rawArg(int index) =>
        index < args.length ? args[index].trim() : null;

    Object? evalArg(int index) {
      final raw = rawArg(index);
      if (raw == null || raw.isEmpty) return null;
      try {
        return evaluator.evaluate(raw, scope);
      } on RenPyPythonError {
        return raw;
      }
    }

    switch (name) {
      case 'Return':
        final has = args.isNotEmpty && (rawArg(0)?.isNotEmpty ?? false);
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.returnValue,
          value: has ? evalArg(0) : null,
          hasValue: has,
          raw: trimmed,
        );
      case 'Jump':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.jump,
          label: _asLabel(evalArg(0), rawArg(0)),
          raw: trimmed,
        );
      case 'Call':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.call,
          label: _asLabel(evalArg(0), rawArg(0)),
          raw: trimmed,
        );
      case 'Show':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.showScreen,
          screenName: evalArg(0)?.toString(),
          positional: [
            for (var i = 1; i < args.length; i += 1)
              if (!_isKeyword(args[i])) evalArg(i),
          ],
          keywords: _keywordArgs(args, evaluator, scope, skip: 1),
          raw: trimmed,
        );
      case 'Hide':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.hideScreen,
          screenName: evalArg(0)?.toString(),
          raw: trimmed,
        );
      case 'ShowMenu':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.showMenu,
          screenName: evalArg(0)?.toString(),
          raw: trimmed,
        );
      case 'SetVariable':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.setVariable,
          target: _asName(evalArg(0), rawArg(0)),
          value: evalArg(1),
          hasValue: args.length > 1,
          raw: trimmed,
        );
      case 'SetScreenVariable':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.setScreenVariable,
          target: _asName(evalArg(0), rawArg(0)),
          value: evalArg(1),
          hasValue: args.length > 1,
          raw: trimmed,
        );
      case 'SetField':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.setField,
          target: rawArg(0),
          field: _asName(evalArg(1), rawArg(1)),
          value: evalArg(2),
          hasValue: args.length > 2,
          raw: trimmed,
        );
      case 'ToggleVariable':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.toggleVariable,
          target: _asName(evalArg(0), rawArg(0)),
          raw: trimmed,
        );
      case 'ToggleScreenVariable':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.toggleScreenVariable,
          target: _asName(evalArg(0), rawArg(0)),
          raw: trimmed,
        );
      case 'ToggleField':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.toggleField,
          target: rawArg(0),
          field: _asName(evalArg(1), rawArg(1)),
          raw: trimmed,
        );
      case 'AddToSet':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.addToSet,
          target: rawArg(0),
          value: evalArg(1),
          hasValue: args.length > 1,
          raw: trimmed,
        );
      case 'RemoveFromSet':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.removeFromSet,
          target: rawArg(0),
          value: evalArg(1),
          hasValue: args.length > 1,
          raw: trimmed,
        );
      case 'NullAction':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.nullAction,
          raw: trimmed,
        );
      case 'Function':
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.function,
          functionName: rawArg(0),
          positional: [
            for (var i = 1; i < args.length; i += 1)
              if (!_isKeyword(args[i])) evalArg(i),
          ],
          keywords: _keywordArgs(args, evaluator, scope, skip: 1),
          raw: trimmed,
        );
      default:
        return RenPyScreenAction(
          kind: RenPyScreenActionKind.nullAction,
          raw: trimmed,
        );
    }
  }

  /// Convenience overload using the shared evaluator instance.
  static RenPyScreenAction parseWith(String source, RenPyPythonScope scope) =>
      parse(source, _defaultEvaluator, scope);

  /// A simple Python identifier (the only shape that can name a screen
  /// parameter we should try to resolve as a passed-in action).
  static final RegExp _identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');

  /// Resolves a bare [name] against [scope] to see if it is a screen parameter
  /// bound to a passed-in action expression, and if so re-parses that
  /// expression into a real action.
  ///
  /// The runner binds an action passed as a `call screen`/`use` argument as its
  /// raw source string (e.g. `Return("ok")`, `[ShowMenu('save'), Return()]`),
  /// because the evaluator has no action constructors. Re-parsing that string
  /// here keeps the resolution entirely screen-side. Returns null when the name
  /// is not a simple identifier, is not bound, is not bound to a string, would
  /// recurse onto itself, or does not parse to a recognized action - leaving
  /// the caller to fall back to a nullAction. Never throws.
  static RenPyScreenAction? _resolveBoundAction(
    String name,
    RenPyPythonEvaluator evaluator,
    RenPyPythonScope scope,
  ) {
    if (!_identifier.hasMatch(name)) return null;
    Object? bound;
    try {
      if (!scope.has(name)) return null;
      bound = scope.read(name);
    } on Object {
      return null;
    }
    if (bound is! String) return null;
    final boundExpr = bound.trim();
    // A real action expression is a call or list (e.g. `Return("ok")`,
    // `[ShowMenu('save'), Return()]`), never a bare identifier. Rejecting a
    // bare-identifier binding both guards the self-referential case
    // (`name` -> `name`) and stops a chain of name-to-name bindings
    // (`a` -> `b` -> `a`) from recursing through `parse` without a bound.
    if (boundExpr.isEmpty || _identifier.hasMatch(boundExpr)) return null;
    RenPyScreenAction parsed;
    try {
      parsed = parse(boundExpr, evaluator, scope);
    } on Object {
      return null;
    }
    // Only substitute when the bound string actually named an action; a bound
    // string that is just data (and parses to nullAction) should leave the
    // original bare-name nullAction in place.
    if (parsed.kind == RenPyScreenActionKind.nullAction) return null;
    return parsed;
  }

  static Map<String, Object?> _keywordArgs(
    List<String> args,
    RenPyPythonEvaluator evaluator,
    RenPyPythonScope scope, {
    required int skip,
  }) {
    final keywords = <String, Object?>{};
    for (var i = skip; i < args.length; i += 1) {
      final part = args[i].trim();
      final eq = _topLevelAssignment(part);
      if (eq < 0) continue;
      final name = part.substring(0, eq).trim();
      final expression = part.substring(eq + 1).trim();
      try {
        keywords[name] = evaluator.evaluate(expression, scope);
      } on RenPyPythonError {
        keywords[name] = expression;
      }
    }
    return keywords;
  }

  static bool _isKeyword(String arg) => _topLevelAssignment(arg.trim()) >= 0;

  static String? _asLabel(Object? evaluated, String? raw) {
    if (evaluated is String) return evaluated;
    return raw;
  }

  static String? _asName(Object? evaluated, String? raw) {
    if (evaluated is String) return evaluated;
    return raw;
  }

  static int _topLevelAssignment(String text) {
    var depth = 0;
    String? quote;
    for (var i = 0; i < text.length; i += 1) {
      final c = text[i];
      if (quote != null) {
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth += 1;
      } else if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) depth -= 1;
      } else if (depth == 0 && c == '=') {
        final prev = i > 0 ? text[i - 1] : '';
        final next = i + 1 < text.length ? text[i + 1] : '';
        if (next == '=' ||
            prev == '=' ||
            prev == '<' ||
            prev == '>' ||
            prev == '!') {
          continue;
        }
        return i;
      }
    }
    return -1;
  }

  static List<String> _splitTopLevel(String text) {
    if (text.trim().isEmpty) return const [];
    final parts = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    String? quote;
    for (var i = 0; i < text.length; i += 1) {
      final c = text[i];
      if (quote != null) {
        buffer.write(c);
        if (c == quote) quote = null;
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        buffer.write(c);
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth += 1;
        buffer.write(c);
        continue;
      }
      if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) depth -= 1;
        buffer.write(c);
        continue;
      }
      if (depth == 0 && c == ',') {
        parts.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(c);
    }
    parts.add(buffer.toString());
    return parts;
  }

  @override
  String toString() =>
      'RenPyScreenAction(${kind.name}${raw == null ? '' : ', $raw'})';
}
