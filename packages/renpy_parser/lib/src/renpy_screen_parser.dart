import 'models/renpy_screen.dart';
import 'renpy_parser_base.dart' show GroupedLine;

/// Parsers for the bodies of `screen`, `style`, and `transform`(ATL)
/// declarations. These descend into the grouped child lines that the base
/// parser otherwise keeps only as raw text.
///
/// Property values are kept as raw expression text; the core Python evaluator
/// resolves them at render time.
class RenPyBodyParser {
  /// Displayables and layout statements that take a body and/or arguments.
  static const _displayableKeywords = <String>{
    'vbox',
    'hbox',
    'fixed',
    'frame',
    'window',
    'grid',
    'side',
    'text',
    'label',
    'textbutton',
    'imagebutton',
    'button',
    'bar',
    'vbar',
    'viewport',
    'vpgrid',
    'null',
    'add',
    'key',
    'timer',
    'input',
    'image',
    'imagemap',
    'hotspot',
    'hotbar',
    'mousearea',
    'drag',
    'draggroup',
  };

  /// Parses the top-level nodes of a screen body.
  List<RenPyScreenNode> parseScreenBody(List<GroupedLine> block) {
    return _parseScreenBody(block, null);
  }

  /// Parses a screen body. Standalone bare-property lines (e.g. `id "window"`,
  /// `spacing 10`) are folded into [ownerProperties] when a parent owner is
  /// present rather than emitted as child nodes, matching the screen grammar
  /// where such lines configure the enclosing displayable.
  List<RenPyScreenNode> _parseScreenBody(
    List<GroupedLine> block,
    Map<String, String>? ownerProperties,
  ) {
    final nodes = <RenPyScreenNode>[];
    for (var i = 0; i < block.length; i += 1) {
      final line = block[i];
      final text = _clean(line.text);
      if (text.isEmpty || text.startsWith('#')) continue;

      if (text.startsWith('if ')) {
        final consumed = _parseScreenIf(block, i, nodes, ownerProperties);
        i += consumed;
        continue;
      }

      // A screen keyword-statement (e.g. `style_prefix "input"`, `zorder 100`,
      // `tag menu`, `modal True`, `showif cond:`). These configure the screen
      // rather than the enclosing displayable, so they are first-class nodes
      // even when an owner is present.
      final keywordNode = _tryParseKeywordStatement(line, text);
      if (keywordNode != null) {
        nodes.add(keywordNode);
        continue;
      }

      // A standalone property line attached to the enclosing displayable, e.g.
      // `id "window"` or `spacing 10` (no trailing colon, leading token is a
      // known property, not a displayable keyword).
      if (ownerProperties != null && _isStandaloneProperty(line, text)) {
        _foldProperty(text, ownerProperties);
        continue;
      }

      nodes.add(_parseScreenLine(line, ownerProperties));
    }
    return nodes;
  }

  /// Recognizes a screen keyword-statement and returns its node, or null if
  /// [text] is not one. Keyword-statements ([renPyScreenKeywords]) configure the
  /// enclosing screen; their argument is preserved as a raw expression. The
  /// `showif cond:` form additionally carries a body of child nodes.
  RenPyScreenNode? _tryParseKeywordStatement(GroupedLine line, String text) {
    final hasBody = text.endsWith(':');
    final header = hasBody ? text.substring(0, text.length - 1).trim() : text;
    final space = _firstTopLevelSpace(header);
    final keyword = space == -1 ? header : header.substring(0, space).trim();
    if (!renPyScreenKeywords.contains(keyword)) return null;
    // `default`/`showif` only ever appear with an argument; a bare `default`
    // (no value) is not a screen-local default, so leave it to other handlers.
    final value = space == -1 ? null : header.substring(space + 1).trim();
    if ((keyword == 'default' || keyword == 'showif') && value == null) {
      return null;
    }
    return RenPyScreenNode(
      kind: keyword,
      nodeKind: RenPyScreenNodeKind.keyword,
      keyword: keyword,
      value: value,
      children: hasBody ? parseScreenBody(line.block) : const [],
    );
  }

  /// Whether [text] is a bare property line (not a control construct, not a
  /// block header, and not a displayable keyword).
  bool _isStandaloneProperty(GroupedLine line, String text) {
    if (line.block.isNotEmpty || text.endsWith(':')) return false;
    if (text.startsWith(r'$') ||
        text.startsWith('for ') ||
        text.startsWith('if ') ||
        text.startsWith('use ') ||
        text == 'transclude' ||
        text == 'has' ||
        text.startsWith('has ')) {
      return false;
    }
    final tokens = _tokenize(text);
    if (tokens.isEmpty) return false;
    final head = tokens.first;
    if (_displayableKeywords.contains(head)) return false;
    return _isIdentifier(head) || _topLevelEquals(head) != -1;
  }

  void _foldProperty(String text, Map<String, String> properties) {
    final eq = _topLevelEquals(_tokenize(text).first);
    if (eq != -1) {
      // `name=value` written without a space.
      final token = _tokenize(text).first;
      properties[token.substring(0, eq).trim()] =
          token.substring(eq + 1).trim();
      return;
    }
    final space = _firstTopLevelSpace(text);
    if (space == -1) {
      properties[text] = '';
      return;
    }
    properties[text.substring(0, space).trim()] =
        text.substring(space + 1).trim();
  }

  /// Parses an `if`/`elif`/`else` chain starting at [index]. Returns the number
  /// of *extra* lines consumed beyond the leading `if`.
  int _parseScreenIf(
    List<GroupedLine> block,
    int index,
    List<RenPyScreenNode> out,
    Map<String, String>? ownerProperties,
  ) {
    final branches = <RenPyScreenConditionalBranch>[];
    final ifLine = block[index];
    final ifMatch = RegExp(r'^if\s+(.+?)\s*:$').firstMatch(_clean(ifLine.text));
    branches.add(
      RenPyScreenConditionalBranch(
        ifMatch != null ? ifMatch.group(1)!.trim() : 'True',
        _parseScreenBody(ifLine.block, ownerProperties),
      ),
    );

    var consumed = 0;
    for (var j = index + 1; j < block.length; j += 1) {
      final text = _clean(block[j].text);
      final elifMatch = RegExp(r'^elif\s+(.+?)\s*:$').firstMatch(text);
      if (elifMatch != null) {
        branches.add(
          RenPyScreenConditionalBranch(
            elifMatch.group(1)!.trim(),
            _parseScreenBody(block[j].block, ownerProperties),
          ),
        );
        consumed += 1;
        continue;
      }
      if (RegExp(r'^else\s*:$').hasMatch(text)) {
        branches.add(
          RenPyScreenConditionalBranch(
            'True',
            _parseScreenBody(block[j].block, ownerProperties),
          ),
        );
        consumed += 1;
        break;
      }
      break;
    }

    out.add(
      RenPyScreenNode(
        kind: 'if',
        nodeKind: RenPyScreenNodeKind.ifChain,
        branches: branches,
      ),
    );
    return consumed;
  }

  RenPyScreenNode _parseScreenLine(
    GroupedLine line,
    Map<String, String>? ownerProperties,
  ) {
    final text = _clean(line.text);

    // `for target in iterable:`
    final forMatch = RegExp(r'^for\s+(.+?)\s+in\s+(.+?)\s*:$').firstMatch(text);
    if (forMatch != null) {
      return RenPyScreenNode(
        kind: 'for',
        nodeKind: RenPyScreenNodeKind.forLoop,
        forTarget: forMatch.group(1)!.trim(),
        forIterable: forMatch.group(2)!.trim(),
        children: _parseScreenBody(line.block, ownerProperties),
      );
    }

    // `$ inline python`
    if (text.startsWith(r'$')) {
      return RenPyScreenNode(
        kind: r'$',
        nodeKind: RenPyScreenNodeKind.python,
        pythonCode: text.substring(1).trim(),
      );
    }

    // `python:` block
    if (text == 'python:' || text.startsWith('python ')) {
      return RenPyScreenNode(
        kind: 'python',
        nodeKind: RenPyScreenNodeKind.pythonBlock,
        pythonCode: _joinBlock(line.block),
      );
    }

    // `on "event":`
    final onMatch = RegExp(r'^on\s+(.+?)\s*:$').firstMatch(text);
    if (onMatch != null) {
      return RenPyScreenNode(
        kind: 'on',
        nodeKind: RenPyScreenNodeKind.on,
        event: onMatch.group(1)!.trim(),
        children: _parseScreenBody(line.block, ownerProperties),
      );
    }

    // `use other_screen[(args)]` / `use screen: ...` (transcluded body)
    final useMatch = RegExp(r'^use\s+(.+?)\s*:?$').firstMatch(text);
    if (useMatch != null && text.startsWith('use ')) {
      final body = stripTrailingColon(useMatch.group(1)!.trim());
      return RenPyScreenNode(
        kind: 'use',
        nodeKind: RenPyScreenNodeKind.use,
        positionalArgs: [body],
        children: parseScreenBody(line.block),
      );
    }

    // `transclude`
    if (text == 'transclude' || text == 'transclude:') {
      return RenPyScreenNode(
        kind: 'transclude',
        nodeKind: RenPyScreenNodeKind.transclude,
      );
    }

    // `has layout` - a layout-substitution statement inside a button.
    if (text == 'has' || text.startsWith('has ')) {
      final rest = text == 'has' ? '' : text.substring('has '.length).trim();
      return RenPyScreenNode(
        kind: 'has',
        nodeKind: RenPyScreenNodeKind.has,
        positionalArgs: rest.isEmpty ? const [] : [stripTrailingColon(rest)],
      );
    }

    // A displayable / layout statement, possibly with a trailing `:` body and a
    // run of positional args and properties on the header line.
    return _parseDisplayable(line, text);
  }

  RenPyScreenNode _parseDisplayable(GroupedLine line, String text) {
    final hasBody = text.endsWith(':');
    final header = hasBody ? text.substring(0, text.length - 1).trim() : text;

    final tokens = _tokenize(header);
    final kind = tokens.isEmpty ? header : tokens.first;
    final rest = tokens.skip(1).toList();

    final positional = <String>[];
    final properties = <String, String>{};

    // Some displayables take a leading positional expression (the value/label),
    // e.g. `text who`, `textbutton _("Back")`, `add SideImage()`, `use name`.
    // Everything after that is properties: either `name=value`, or a bare
    // `prop value` pair (style/layout property), or a lone style keyword.
    var i = 0;
    // `grid cols rows` / `vpgrid cols rows` take two leading positional
    // dimensions, which may be dotted/expr (e.g. `gui.file_slot_cols`) rather
    // than plain identifiers. Capture them before property parsing.
    final positionalDims = _positionalDimensionCount(kind);
    while (positionalDims > positional.length &&
        i < rest.length &&
        _topLevelEquals(rest[i]) == -1 &&
        !(_isIdentifier(rest[i]) && _isKnownProperty(rest[i]))) {
      positional.add(rest[i]);
      i += 1;
    }

    final takesLeadingPositional = _takesLeadingPositional(kind);
    if (takesLeadingPositional &&
        positional.isEmpty &&
        i < rest.length &&
        !_looksLikeProperty(rest, i)) {
      positional.add(rest[i]);
      i += 1;
    }

    while (i < rest.length) {
      final token = rest[i];

      // `name=value` keyword argument (tokenizer keeps it as one token).
      final eq = _topLevelEquals(token);
      if (eq != -1) {
        final name = token.substring(0, eq).trim();
        final value = token.substring(eq + 1).trim();
        properties[name] = value;
        i += 1;
        continue;
      }

      // Bare `property value` pair, e.g. `xalign 0.5`, `action Foo()`,
      // `spacing 10`, `text_color h.who_args["color"]`. The property name is an
      // identifier; the value is the next token whatever its shape (string,
      // number, dotted expression, call, ...).
      if (_isIdentifier(token) && i + 1 < rest.length) {
        properties[token] = rest[i + 1];
        i += 2;
        continue;
      }

      // A trailing bare keyword (e.g. a flag) with no value.
      properties[token] = '';
      i += 1;
    }

    final children =
        hasBody
            ? _parseScreenBody(line.block, properties)
            : const <RenPyScreenNode>[];

    return RenPyScreenNode(
      kind: kind,
      nodeKind: RenPyScreenNodeKind.displayable,
      positionalArgs: positional,
      properties: properties,
      children: children,
    );
  }

  /// Number of leading positional *dimension* expressions a layout statement
  /// takes (e.g. `grid cols rows`). These precede any properties and may be
  /// arbitrary expressions, not just plain identifiers.
  int _positionalDimensionCount(String kind) => kind == 'grid' ? 2 : 0;

  bool _takesLeadingPositional(String kind) {
    const noLeading = <String>{
      'vbox',
      'hbox',
      'fixed',
      'frame',
      'window',
      'grid',
      'side',
      'null',
      'viewport',
      'vpgrid',
      'button',
    };
    return _displayableKeywords.contains(kind) && !noLeading.contains(kind);
  }

  /// Whether the token run at [index] looks like a property rather than a
  /// leading positional expression. A property is either `name=value` or a bare
  /// identifier followed by another token (`prop value`).
  bool _looksLikeProperty(List<String> tokens, int index) {
    final token = tokens[index];
    if (_topLevelEquals(token) != -1) return true;
    if (_isIdentifier(token) && _isKnownProperty(token)) return true;
    return false;
  }

  /// Property names that may appear immediately after the keyword and so must
  /// not be mistaken for the leading positional argument.
  static const _knownProperties = <String>{
    'action',
    'alternate',
    'hovered',
    'unhovered',
    'selected',
    'sensitive',
    'style',
    'id',
    'at',
    'xalign',
    'yalign',
    'align',
    'xpos',
    'ypos',
    'pos',
    'xanchor',
    'yanchor',
    'anchor',
    'xsize',
    'ysize',
    'xysize',
    'size',
    'xfill',
    'yfill',
    'spacing',
    'text_align',
    'background',
    'foreground',
    'padding',
    'margin',
    'value',
    'range',
    'idle',
    'hover',
    'auto',
  };

  bool _isKnownProperty(String token) => _knownProperties.contains(token);

  /// Splits a header into top-level tokens, keeping bracketed groups, quoted
  /// strings, and `name=value` pairs intact.
  List<String> _tokenize(String text) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    String? quote;
    var escaped = false;

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) tokens.add(value);
      buffer.clear();
    }

    for (var i = 0; i < text.length; i += 1) {
      final c = text[i];
      if (quote != null) {
        buffer.write(c);
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == quote) {
          quote = null;
        }
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
      if (depth == 0 && (c == ' ' || c == '\t')) {
        // A `=` keyword argument may be written `name = value`; rejoin it.
        flush();
        continue;
      }
      buffer.write(c);
    }
    flush();

    return _rejoinKeywordArgs(tokens);
  }

  /// Rejoins token runs that were split around a top-level `=` so that
  /// `name = value` and `name =value` collapse into a single `name=value`
  /// token, matching the `name=value` form.
  List<String> _rejoinKeywordArgs(List<String> tokens) {
    final result = <String>[];
    for (var i = 0; i < tokens.length; i += 1) {
      final token = tokens[i];
      if (token == '=' && result.isNotEmpty && i + 1 < tokens.length) {
        result[result.length - 1] = '${result.last}=${tokens[i + 1]}';
        i += 1;
        continue;
      }
      if (token.startsWith('=') && result.isNotEmpty) {
        result[result.length - 1] = '${result.last}$token';
        continue;
      }
      if (token.endsWith('=') && i + 1 < tokens.length) {
        result.add('$token${tokens[i + 1]}');
        i += 1;
        continue;
      }
      result.add(token);
    }
    return result;
  }

  /// Returns the index of a top-level `=` in [token] that is an assignment
  /// (not `==`, `<=`, `>=`, `!=`), or -1.
  int _topLevelEquals(String token) {
    var depth = 0;
    String? quote;
    var escaped = false;
    for (var i = 0; i < token.length; i += 1) {
      final c = token[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth += 1;
        continue;
      }
      if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) depth -= 1;
        continue;
      }
      if (depth != 0) continue;
      if (c == '=') {
        final prev = i > 0 ? token[i - 1] : '';
        final next = i + 1 < token.length ? token[i + 1] : '';
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

  bool _isIdentifier(String token) => RegExp(r'^[A-Za-z_]\w*$').hasMatch(token);

  /// Parses a `style name [is parent]:` body into a [RenPyStyle]. [declaration]
  /// is the raw text after `style ` (without a trailing colon). [block] is the
  /// indented body (empty for the single-line `style x is y` form).
  RenPyStyle parseStyle(String declaration, List<GroupedLine> block) {
    final clean = stripTrailingColon(declaration.trim());
    final isMatch = RegExp(r'^(\S+)\s+is\s+(\S+)$').firstMatch(clean);
    final String name;
    final String? parent;
    if (isMatch != null) {
      name = isMatch.group(1)!;
      parent = isMatch.group(2)!;
    } else {
      // May still be `name property value` on one line; keep just the name.
      name = clean.split(RegExp(r'\s+')).first;
      parent = null;
    }

    final properties = <String, String>{};
    for (final line in block) {
      final text = _clean(line.text);
      if (text.isEmpty || text.startsWith('#')) continue;
      final spaceIndex = _firstTopLevelSpace(text);
      if (spaceIndex == -1) {
        properties[text] = '';
        continue;
      }
      final prop = text.substring(0, spaceIndex).trim();
      final value = text.substring(spaceIndex + 1).trim();
      properties[prop] = value;
    }

    return RenPyStyle(name: name, parent: parent, properties: properties);
  }

  /// Parses an ATL/transform body into a node sequence.
  List<RenPyAtlNode> parseAtl(List<GroupedLine> block) {
    final nodes = <RenPyAtlNode>[];
    for (final line in block) {
      final text = _clean(line.text);
      if (text.isEmpty || text.startsWith('#')) continue;
      final node = _parseAtlLine(line, text);
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  static const _warpers = <String>{
    'linear',
    'ease',
    'easein',
    'easeout',
    'easein_quad',
    'easeout_quad',
  };

  RenPyAtlNode? _parseAtlLine(GroupedLine line, String text) {
    // Block groups.
    if (text == 'block:') {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.block,
        children: parseAtl(line.block),
      );
    }
    if (text == 'parallel:') {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.parallel,
        children: parseAtl(line.block),
      );
    }
    final choiceMatch = RegExp(r'^choice(?:\s+(.+?))?\s*:$').firstMatch(text);
    if (choiceMatch != null) {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.choice,
        duration: choiceMatch.group(1)?.trim(),
        children: parseAtl(line.block),
      );
    }
    final onMatch = RegExp(r'^on\s+(.+?)\s*:$').firstMatch(text);
    if (onMatch != null) {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.on,
        event: onMatch.group(1)!.trim(),
        children: parseAtl(line.block),
      );
    }

    final tokens = _tokenize(stripTrailingColon(text));
    if (tokens.isEmpty) return null;
    final head = tokens.first;

    // `pause <duration>`
    if (head == 'pause') {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.pause,
        duration: tokens.length > 1 ? tokens.sublist(1).join(' ') : null,
      );
    }

    // `repeat [count]`
    if (head == 'repeat') {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.repeat,
        repeatCount: tokens.length > 1 ? tokens.sublist(1).join(' ') : null,
      );
    }

    // `contains <expr>`
    if (head == 'contains') {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.contains,
        containsExpression: tokens.sublist(1).join(' '),
      );
    }

    // `<warper> <duration> [prop value]...`
    if (_warpers.contains(head) && tokens.length >= 2) {
      final duration = tokens[1];
      final props = _propertyPairs(tokens.sublist(2));
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.interpolation,
        warper: head,
        duration: duration,
        properties: props,
      );
    }

    // Bare property assignment(s), e.g. `xpos 0.5` or `xpos 0.5 ypos 1.0`.
    if (tokens.length >= 2) {
      return RenPyAtlNode(
        nodeKind: RenPyAtlNodeKind.property,
        properties: _propertyPairs(tokens),
      );
    }

    // A lone token (e.g. a transform name applied as `contains`-less ref) is
    // captured raw rather than dropped.
    return RenPyAtlNode(nodeKind: RenPyAtlNodeKind.raw, raw: text);
  }

  /// Folds a token list into `property -> value` pairs. Each property consumes
  /// the next token as its value.
  Map<String, String> _propertyPairs(List<String> tokens) {
    final props = <String, String>{};
    for (var i = 0; i < tokens.length; i += 2) {
      final name = tokens[i];
      final value = i + 1 < tokens.length ? tokens[i + 1] : '';
      props[name] = value;
    }
    return props;
  }

  int _firstTopLevelSpace(String text) {
    var depth = 0;
    String? quote;
    var escaped = false;
    for (var i = 0; i < text.length; i += 1) {
      final c = text[i];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'") {
        quote = c;
        continue;
      }
      if (c == '(' || c == '[' || c == '{') {
        depth += 1;
        continue;
      }
      if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) depth -= 1;
        continue;
      }
      if (depth == 0 && (c == ' ' || c == '\t')) return i;
    }
    return -1;
  }

  /// Joins a grouped Python block back into source lines, preserving relative
  /// indentation.
  String _joinBlock(List<GroupedLine> block) {
    if (block.isEmpty) return '';
    final base = block.first.indent;
    final out = <String>[];
    void append(List<GroupedLine> lines) {
      for (final line in lines) {
        final relative = (line.indent - base).clamp(0, 9999);
        out.add('${' ' * relative}${line.text.trim()}');
        append(line.block);
      }
    }

    append(block);
    return out.join('\n');
  }

  String _clean(String text) => text.trim().replaceFirst('\u{FEFF}', '');

  /// Strips a single trailing colon (used for block headers).
  static String stripTrailingColon(String text) {
    final trimmed = text.trim();
    if (trimmed.endsWith(':')) {
      return trimmed.substring(0, trimmed.length - 1).trim();
    }
    return trimmed;
  }
}
