import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_diagnostic.dart';
import 'renpy_python.dart';
import 'renpy_screen_action.dart';

/// A platform-neutral, fully resolved screen-language tree.
///
/// [resolveScreen] turns a parsed [RenPyScreenStatement] plus the current
/// engine state into one of these. Every property and positional expression has
/// already been evaluated against the live store, screen control flow
/// (`if`/`for`/`$`/`use`) has already run, and styles have been flattened, so a
/// renderer only has to walk the tree and draw. RenPy re-runs screen code on
/// every interaction, so callers should resolve on demand rather than cache the
/// result.
class RenPyResolvedScreen {
  RenPyResolvedScreen({
    required this.name,
    required this.children,
    this.diagnostics = const [],
  });

  /// The screen name (e.g. `main_menu`).
  final String name;

  /// The resolved top-level displayables.
  final List<RenPyResolvedDisplayable> children;

  /// Non-fatal issues recorded while resolving (an expression that failed to
  /// evaluate, an unknown `use` target, ...). Mirrors the engine's fallback
  /// contract: a failing node is skipped and a diagnostic is recorded rather
  /// than aborting the whole resolution.
  final List<RenPyDiagnostic> diagnostics;

  @override
  String toString() =>
      'ResolvedScreen($name, ${children.length} children, '
      '${diagnostics.length} diagnostics)';
}

/// A single resolved displayable (or layout container) in a resolved screen.
///
/// Everything here is already evaluated: [properties] map property names to
/// their concrete Dart values, [positional] holds the evaluated positional
/// arguments, [children] are nested resolved displayables, and [action] is a
/// parsed [RenPyScreenAction] descriptor when the node carries one. [styleName]
/// is the effective style this displayable resolves to (honoring an explicit
/// `style` property and the inherited `style_prefix`), and [style] is that
/// style flattened through its `is` parent chain.
class RenPyResolvedDisplayable {
  RenPyResolvedDisplayable({
    required this.kind,
    this.properties = const {},
    this.positional = const [],
    this.children = const [],
    this.action,
    this.alternateAction,
    this.text,
    this.styleName,
    this.style = const {},
    this.isHasLayout = false,
  });

  /// The displayable name (`vbox`, `text`, `textbutton`, `frame`, ...).
  final String kind;

  /// Property name -> evaluated value (e.g. `xalign` -> `0.5`).
  final Map<String, Object?> properties;

  /// Evaluated positional arguments, in order. For `text`/`label`/`textbutton`
  /// the first positional is the displayed string.
  final List<Object?> positional;

  /// Nested resolved displayables.
  final List<RenPyResolvedDisplayable> children;

  /// The parsed `action` descriptor, when present.
  final RenPyScreenAction? action;

  /// The parsed `alternate` action descriptor, when present.
  final RenPyScreenAction? alternateAction;

  /// The resolved text content for `text`/`label`/`textbutton`, when present.
  /// This is the first positional rendered as a string.
  final String? text;

  /// The effective style name this displayable resolves to, or null when none
  /// applies.
  final String? styleName;

  /// The flattened style property map (parent chain merged), evaluated values.
  final Map<String, Object?> style;

  /// Whether this node is a `has <layout>` hint rather than a real displayable.
  final bool isHasLayout;

  @override
  String toString() => 'ResolvedDisplayable($kind)';
}

/// A screen invocation currently on the screen layer.
///
/// [name] is the screen to resolve, [tag] is the layer slot it occupies (a
/// screen replaces a prior screen with the same tag - by default the name), and
/// [positional]/[keywords] are the already-evaluated invocation arguments to
/// pass when resolving it. [isCall] marks a blocking `call screen` request.
class RenPyShownScreen {
  const RenPyShownScreen({
    required this.name,
    required this.tag,
    this.positional = const [],
    this.keywords = const {},
    this.isCall = false,
  });

  final String name;
  final String tag;
  final List<Object?> positional;
  final Map<String, Object?> keywords;
  final bool isCall;

  @override
  String toString() =>
      'ShownScreen($name${isCall ? ', call' : ''}, '
      '${positional.length} args)';
}

/// Resolves a parsed style through its `is` parent chain into a flat,
/// evaluated property map.
///
/// Styles are registered by name; a style's parent properties are merged first
/// so the child overrides them. Property expressions are evaluated against the
/// supplied [scope] (most style properties are literals, but some reference
/// `gui.*`). A missing parent or a failing expression is skipped rather than
/// throwing.
class RenPyStyleResolver {
  RenPyStyleResolver(this._styles);

  final Map<String, RenPyStyle> _styles;

  static const RenPyPythonEvaluator _evaluator = RenPyPythonEvaluator();

  /// Whether a style named [name] is registered.
  bool has(String name) => _styles.containsKey(name);

  /// Flattens [name] through its parent chain into evaluated properties.
  /// Returns an empty map when the style is unknown.
  Map<String, Object?> resolve(String name, RenPyPythonScope scope) {
    final visited = <String>{};
    final result = <String, Object?>{};
    _merge(name, scope, visited, result);
    return result;
  }

  void _merge(
    String name,
    RenPyPythonScope scope,
    Set<String> visited,
    Map<String, Object?> into,
  ) {
    if (!visited.add(name)) return;
    final style = _styles[name];
    if (style == null) return;
    if (style.parent != null) {
      _merge(style.parent!, scope, visited, into);
    }
    style.properties.forEach((property, expression) {
      if (expression.isEmpty) {
        into[property] = true;
        return;
      }
      try {
        into[property] = _evaluator.evaluate(expression, scope);
      } on RenPyPythonError {
        // Keep the raw text so a renderer can still attempt to use it rather
        // than dropping the property entirely.
        into[property] = expression;
      }
    });
  }
}

/// A [RenPyPythonScope] that layers a screen's local bindings (parameters and
/// `for` loop targets) over an enclosing store scope.
///
/// Reads fall through to the parent when a name is not local, so screen code
/// sees the live store/config/gui/persistent state. Writes from screen-side
/// `$`/`python:` go to the parent (the real store) so side effects persist,
/// matching RenPy where screen `$` mutates the store; scoped names always pass
/// through. Loop and parameter bindings are seeded with [bindLocal] and are
/// shadowed copies pushed/popped around each scope.
class RenPyScreenScope implements RenPyPythonScope {
  RenPyScreenScope(this._parent, [Map<String, Object?>? locals])
    : _locals = locals ?? <String, Object?>{};

  final RenPyPythonScope _parent;
  final Map<String, Object?> _locals;

  /// Returns a child scope sharing this scope's parent but with a fresh locals
  /// map seeded from this scope's bindings, so a `for` body can add a loop
  /// variable without leaking it to siblings.
  RenPyScreenScope child() =>
      RenPyScreenScope(_parent, Map<String, Object?>.of(_locals));

  /// Seeds [name] as a local binding (screen parameter or loop target).
  void bindLocal(String name, Object? value) => _locals[name] = value;

  @override
  RenPyApi get renpy => _parent.renpy;

  @override
  bool has(String name) {
    if (_locals.containsKey(name)) return true;
    return _parent.has(name);
  }

  @override
  Object? read(String name) {
    if (_locals.containsKey(name)) return _locals[name];
    return _parent.read(name);
  }

  @override
  void write(String name, Object? value) {
    // A screen-local that already exists keeps taking the write (so a `$ x = y`
    // updating a loop/param local stays local); everything else flows to the
    // store, matching RenPy where screen `$` mutates the global store.
    if (_locals.containsKey(name)) {
      _locals[name] = value;
      return;
    }
    _parent.write(name, value);
  }
}

/// Resolves parsed screens into platform-neutral [RenPyResolvedScreen] trees.
///
/// Construct one with the screen and style registries the runner collected
/// during initialization plus the runner's Python scope, then call
/// [resolveScreen] for each shown screen. The resolver re-runs the screen body
/// every call, so it always reflects current engine state.
class RenPyScreenRuntime {
  RenPyScreenRuntime({
    required Map<String, RenPyScreenStatement> screens,
    required Map<String, RenPyStyle> styles,
    required RenPyPythonScope scope,
  }) : _screens = screens,
       _styleResolver = RenPyStyleResolver(styles),
       _scope = scope;

  final Map<String, RenPyScreenStatement> _screens;
  final RenPyStyleResolver _styleResolver;
  final RenPyPythonScope _scope;

  static const RenPyPythonEvaluator _evaluator = RenPyPythonEvaluator();
  static const RenPyPythonExecutor _executor = RenPyPythonExecutor();

  /// Whether a screen named [name] is registered.
  bool hasScreen(String name) => _screens.containsKey(name);

  /// Resolves the screen named [name] against the current engine state.
  ///
  /// [positional] and [keywords] supply the screen invocation arguments, which
  /// are layered over the store as screen-local parameters. Returns null when
  /// the screen is not registered. Any node that cannot be resolved is skipped
  /// and recorded in [RenPyResolvedScreen.diagnostics].
  RenPyResolvedScreen? resolveScreen(
    String name, {
    List<Object?> positional = const [],
    Map<String, Object?> keywords = const {},
  }) {
    final screen = _screens[name];
    if (screen == null) return null;

    final diagnostics = <RenPyDiagnostic>[];
    final scope = RenPyScreenScope(_scope);
    _bindParameters(screen.signature, positional, keywords, scope);

    final children = _resolveNodes(
      screen.children,
      scope,
      diagnostics,
      stylePrefix: null,
      transclude: const [],
    );

    return RenPyResolvedScreen(
      name: name,
      children: children,
      diagnostics: diagnostics,
    );
  }

  /// Binds the screen's declared parameters from the invocation arguments.
  ///
  /// The signature is the raw `name(a, b=default)` text. Positional arguments
  /// fill declared params in order; keywords fill by name; declared defaults are
  /// evaluated for any param left unfilled. Extra/unknown arguments are bound by
  /// their own name so screen code referencing them still resolves.
  void _bindParameters(
    String signature,
    List<Object?> positional,
    Map<String, Object?> keywords,
    RenPyScreenScope scope,
  ) {
    final params = _parseParameters(signature);
    final remainingKeywords = Map<String, Object?>.of(keywords);
    for (var i = 0; i < params.length; i += 1) {
      final param = params[i];
      if (i < positional.length) {
        scope.bindLocal(param.name, positional[i]);
      } else if (remainingKeywords.containsKey(param.name)) {
        scope.bindLocal(param.name, remainingKeywords.remove(param.name));
      } else if (param.defaultExpression != null) {
        try {
          scope.bindLocal(
            param.name,
            _evaluator.evaluate(param.defaultExpression!, scope),
          );
        } on RenPyPythonError {
          scope.bindLocal(param.name, null);
        }
      } else {
        scope.bindLocal(param.name, null);
      }
    }
    // Surface any leftover keyword that did not match a declared parameter so
    // screen code referencing it by name still sees a value.
    remainingKeywords.forEach(scope.bindLocal);
  }

  /// Parses the parameter list out of a screen signature `name(a, b=default)`.
  List<_ScreenParameter> _parseParameters(String signature) {
    final open = signature.indexOf('(');
    if (open < 0) return const [];
    final close = signature.lastIndexOf(')');
    if (close <= open) return const [];
    final inner = signature.substring(open + 1, close).trim();
    if (inner.isEmpty) return const [];

    final params = <_ScreenParameter>[];
    for (final raw in _splitTopLevel(inner)) {
      final part = raw.trim();
      if (part.isEmpty || part == '*' || part.startsWith('*')) continue;
      final eq = part.indexOf('=');
      if (eq < 0) {
        params.add(_ScreenParameter(part, null));
      } else {
        params.add(
          _ScreenParameter(
            part.substring(0, eq).trim(),
            part.substring(eq + 1).trim(),
          ),
        );
      }
    }
    return params;
  }

  List<RenPyResolvedDisplayable> _resolveNodes(
    List<RenPyScreenNode> nodes,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics, {
    required String? stylePrefix,
    required List<RenPyScreenNode> transclude,
  }) {
    final resolved = <RenPyResolvedDisplayable>[];
    var prefix = stylePrefix;
    for (final node in nodes) {
      switch (node.nodeKind) {
        case RenPyScreenNodeKind.displayable:
          final displayable = _resolveDisplayable(
            node,
            scope,
            diagnostics,
            prefix,
            transclude,
          );
          if (displayable != null) resolved.add(displayable);
        case RenPyScreenNodeKind.ifChain:
          resolved.addAll(
            _resolveIf(node, scope, diagnostics, prefix, transclude),
          );
        case RenPyScreenNodeKind.forLoop:
          resolved.addAll(
            _resolveFor(node, scope, diagnostics, prefix, transclude),
          );
        case RenPyScreenNodeKind.python:
          _runPython(node.pythonCode, scope, diagnostics, isExpression: true);
        case RenPyScreenNodeKind.pythonBlock:
          _runPython(node.pythonCode, scope, diagnostics, isExpression: false);
        case RenPyScreenNodeKind.use:
          resolved.addAll(
            _resolveUse(node, scope, diagnostics, prefix, transclude),
          );
        case RenPyScreenNodeKind.transclude:
          resolved.addAll(
            _resolveNodes(
              transclude,
              scope,
              diagnostics,
              stylePrefix: prefix,
              transclude: const [],
            ),
          );
        case RenPyScreenNodeKind.keyword:
          // `style_prefix "foo"` changes the effective style prefix for the
          // following siblings; other keywords are screen directives the
          // renderer does not need as displayables.
          if (node.keyword == 'style_prefix') {
            final value = node.value;
            if (value != null) {
              try {
                prefix = _evaluator.evaluate(value, scope)?.toString();
              } on RenPyPythonError {
                diagnostics.add(_skip('style_prefix', value));
              }
            }
          } else if (node.keyword == 'showif') {
            resolved.addAll(
              _resolveShowif(node, scope, diagnostics, prefix, transclude),
            );
          } else if (node.keyword == 'default') {
            _applyScreenDefault(node.value, scope, diagnostics);
          }
        case RenPyScreenNodeKind.on:
          // Event handlers are captured but produce no displayable this pass.
          break;
        case RenPyScreenNodeKind.has:
          resolved.add(
            RenPyResolvedDisplayable(
              kind:
                  node.positionalArgs.isEmpty
                      ? 'has'
                      : node.positionalArgs.first,
              isHasLayout: true,
            ),
          );
      }
    }
    return resolved;
  }

  RenPyResolvedDisplayable? _resolveDisplayable(
    RenPyScreenNode node,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String? stylePrefix,
    List<RenPyScreenNode> transclude,
  ) {
    final positional = <Object?>[];
    for (final expression in node.positionalArgs) {
      final value = _tryEvaluate(expression, scope, diagnostics, node.kind);
      positional.add(value);
    }

    final properties = <String, Object?>{};
    RenPyScreenAction? action;
    RenPyScreenAction? alternateAction;
    node.properties.forEach((name, expression) {
      if (name == 'action') {
        action = RenPyScreenAction.parse(expression, _evaluator, scope);
        return;
      }
      if (name == 'alternate') {
        alternateAction = RenPyScreenAction.parse(
          expression,
          _evaluator,
          scope,
        );
        return;
      }
      if (expression.isEmpty) {
        properties[name] = true;
        return;
      }
      properties[name] = _tryEvaluate(
        expression,
        scope,
        diagnostics,
        node.kind,
      );
    });

    final children = _resolveNodes(
      node.children,
      scope,
      diagnostics,
      stylePrefix: stylePrefix,
      transclude: transclude,
    );

    final styleName = _effectiveStyleName(node, properties, stylePrefix);
    final style =
        styleName == null
            ? const <String, Object?>{}
            : _styleResolver.resolve(styleName, scope);

    final text = _resolvedText(node.kind, positional);

    return RenPyResolvedDisplayable(
      kind: node.kind,
      properties: properties,
      positional: positional,
      children: children,
      action: action,
      alternateAction: alternateAction,
      text: text,
      styleName: styleName,
      style: style,
    );
  }

  String? _resolvedText(String kind, List<Object?> positional) {
    if (positional.isEmpty) return null;
    if (kind == 'text' || kind == 'label' || kind == 'textbutton') {
      return positional.first?.toString();
    }
    return null;
  }

  /// Resolves the effective style name. An explicit `style` property wins;
  /// otherwise a `style_prefix` produces `<prefix>_<kind>` for displayables
  /// that have a default style (button/text/label/frame/...).
  String? _effectiveStyleName(
    RenPyScreenNode node,
    Map<String, Object?> properties,
    String? stylePrefix,
  ) {
    final explicit = properties['style'];
    if (explicit is String && explicit.isNotEmpty) return explicit;
    if (stylePrefix == null || stylePrefix.isEmpty) return null;
    if (!_styledKinds.contains(node.kind)) return null;
    return '${stylePrefix}_${node.kind}';
  }

  static const _styledKinds = <String>{
    'text',
    'label',
    'button',
    'textbutton',
    'imagebutton',
    'frame',
    'window',
    'bar',
    'vbar',
    'vbox',
    'hbox',
    'fixed',
    'viewport',
    'input',
    'grid',
  };

  List<RenPyResolvedDisplayable> _resolveIf(
    RenPyScreenNode node,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String? stylePrefix,
    List<RenPyScreenNode> transclude,
  ) {
    for (final branch in node.branches) {
      bool matched;
      try {
        matched = RenPyPythonEvaluator.truthy(
          _evaluator.evaluate(branch.condition, scope),
        );
      } on RenPyPythonError {
        diagnostics.add(_skip('if', branch.condition));
        continue;
      }
      if (matched) {
        return _resolveNodes(
          branch.children,
          scope,
          diagnostics,
          stylePrefix: stylePrefix,
          transclude: transclude,
        );
      }
    }
    return const [];
  }

  List<RenPyResolvedDisplayable> _resolveShowif(
    RenPyScreenNode node,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String? stylePrefix,
    List<RenPyScreenNode> transclude,
  ) {
    final condition = node.value;
    if (condition == null) return const [];
    bool matched;
    try {
      matched = RenPyPythonEvaluator.truthy(
        _evaluator.evaluate(condition, scope),
      );
    } on RenPyPythonError {
      diagnostics.add(_skip('showif', condition));
      return const [];
    }
    if (!matched) return const [];
    return _resolveNodes(
      node.children,
      scope,
      diagnostics,
      stylePrefix: stylePrefix,
      transclude: transclude,
    );
  }

  List<RenPyResolvedDisplayable> _resolveFor(
    RenPyScreenNode node,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String? stylePrefix,
    List<RenPyScreenNode> transclude,
  ) {
    final iterableExpression = node.forIterable;
    final target = node.forTarget;
    if (iterableExpression == null || target == null) return const [];

    Object? iterableValue;
    try {
      iterableValue = _evaluator.evaluate(iterableExpression, scope);
    } on RenPyPythonError {
      diagnostics.add(_skip('for', iterableExpression));
      return const [];
    }

    final items = _asIterable(iterableValue);
    if (items == null) {
      diagnostics.add(_skip('for', iterableExpression));
      return const [];
    }

    final targets = _splitTopLevel(target).map((t) => t.trim()).toList();
    final resolved = <RenPyResolvedDisplayable>[];
    for (final item in items) {
      final loopScope = scope.child();
      _bindLoopTarget(
        targets,
        item,
        loopScope,
        diagnostics,
        iterableExpression,
      );
      resolved.addAll(
        _resolveNodes(
          node.children,
          loopScope,
          diagnostics,
          stylePrefix: stylePrefix,
          transclude: transclude,
        ),
      );
    }
    return resolved;
  }

  void _bindLoopTarget(
    List<String> targets,
    Object? item,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String iterableExpression,
  ) {
    if (targets.length == 1) {
      scope.bindLocal(targets.first, item);
      return;
    }
    final values = _asIterable(item)?.toList();
    if (values == null || values.length != targets.length) {
      diagnostics.add(_skip('for', iterableExpression));
      for (final name in targets) {
        scope.bindLocal(name, null);
      }
      return;
    }
    for (var i = 0; i < targets.length; i += 1) {
      scope.bindLocal(targets[i], values[i]);
    }
  }

  List<RenPyResolvedDisplayable> _resolveUse(
    RenPyScreenNode node,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String? stylePrefix,
    List<RenPyScreenNode> transclude,
  ) {
    final reference =
        node.positionalArgs.isEmpty ? '' : node.positionalArgs.first;
    final invocation = _parseInvocation(reference);
    final target = _screens[invocation.name];
    if (target == null) {
      diagnostics.add(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.skippedScreen,
          message: 'Skipped `use` of an unknown screen.',
          detail: reference,
        ),
      );
      return const [];
    }

    final positional = <Object?>[];
    for (final expression in invocation.positional) {
      positional.add(_tryEvaluate(expression, scope, diagnostics, 'use'));
    }
    final keywords = <String, Object?>{};
    invocation.keywords.forEach((name, expression) {
      keywords[name] = _tryEvaluate(expression, scope, diagnostics, 'use');
    });

    final useScope = RenPyScreenScope(_scope);
    _bindParameters(target.signature, positional, keywords, useScope);

    // The `use ...:` body becomes the transcluded content for the used screen.
    return _resolveNodes(
      target.children,
      useScope,
      diagnostics,
      stylePrefix: stylePrefix,
      transclude: node.children,
    );
  }

  void _applyScreenDefault(
    String? value,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
  ) {
    if (value == null) return;
    final eq = value.indexOf('=');
    if (eq < 0) return;
    final name = value.substring(0, eq).trim();
    if (scope.has(name)) return;
    final expression = value.substring(eq + 1).trim();
    try {
      scope.bindLocal(name, _evaluator.evaluate(expression, scope));
    } on RenPyPythonError {
      diagnostics.add(_skip('default', value));
    }
  }

  void _runPython(
    String? code,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics, {
    required bool isExpression,
  }) {
    if (code == null || code.trim().isEmpty) return;
    try {
      if (isExpression && !code.contains('\n')) {
        // A `$ name = expr` line is a statement; route anything with an
        // assignment or multiple statements through the executor.
        _executor.execute(code, scope);
      } else {
        _executor.execute(code, scope);
      }
    } on RenPyPythonError {
      diagnostics.add(
        RenPyDiagnostic(
          code: RenPyDiagnosticCode.skippedPython,
          message: 'Skipped unsupported screen Python.',
          detail: code,
        ),
      );
    }
  }

  Object? _tryEvaluate(
    String expression,
    RenPyScreenScope scope,
    List<RenPyDiagnostic> diagnostics,
    String kind,
  ) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) return null;
    try {
      return _evaluator.evaluate(trimmed, scope);
    } on RenPyPythonError {
      diagnostics.add(_skip(kind, trimmed));
      // Keep the raw expression so the renderer can still try to use a literal.
      return trimmed;
    }
  }

  RenPyDiagnostic _skip(String kind, String detail) => RenPyDiagnostic(
    code: RenPyDiagnosticCode.skippedScreen,
    message: 'Skipped unresolved screen `$kind` expression.',
    detail: detail,
  );

  Iterable<Object?>? _asIterable(Object? value) {
    if (value is Iterable) return value;
    if (value is Map) return value.keys;
    if (value is String) return value.split('');
    return null;
  }

  /// Parses a `name(arg, kw=expr)` invocation reference into its parts.
  _ScreenInvocation _parseInvocation(String reference) {
    final trimmed = reference.trim();
    final open = trimmed.indexOf('(');
    if (open < 0) {
      return _ScreenInvocation(trimmed, const [], const {});
    }
    final close = trimmed.lastIndexOf(')');
    final name = trimmed.substring(0, open).trim();
    if (close <= open) {
      return _ScreenInvocation(name, const [], const {});
    }
    final inner = trimmed.substring(open + 1, close).trim();
    if (inner.isEmpty) return _ScreenInvocation(name, const [], const {});

    final positional = <String>[];
    final keywords = <String, String>{};
    for (final raw in _splitTopLevel(inner)) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final eq = _topLevelAssignment(part);
      if (eq < 0) {
        positional.add(part);
      } else {
        keywords[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
      }
    }
    return _ScreenInvocation(name, positional, keywords);
  }

  /// Index of an assignment `=` (not `==`/`<=`/`>=`/`!=`) at top level, or -1.
  int _topLevelAssignment(String text) {
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

  /// Splits [text] on top-level commas, respecting brackets and quotes.
  List<String> _splitTopLevel(String text) {
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
}

/// A declared screen parameter: a name and an optional default expression.
class _ScreenParameter {
  _ScreenParameter(this.name, this.defaultExpression);

  final String name;
  final String? defaultExpression;
}

/// A parsed `use other_screen(args)` invocation.
class _ScreenInvocation {
  _ScreenInvocation(this.name, this.positional, this.keywords);

  final String name;
  final List<String> positional;
  final Map<String, String> keywords;
}
