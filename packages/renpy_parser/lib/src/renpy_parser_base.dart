import 'package:renpy_parser/src/models/renpy_script.dart';
import 'package:renpy_parser/src/models/renpy_statement.dart';
import 'package:renpy_parser/src/renpy_lexer.dart';
import 'package:renpy_parser/src/renpy_screen_parser.dart';
import 'package:renpy_parser/src/errors/parse_error.dart';

/// The main RenPy parser class responsible for parsing .rpy files.
class RenPyParser {
  final RenPyBodyParser _bodyParser = RenPyBodyParser();

  /// Parses the content of a RenPy script file.
  RenPyParseResult parse(String content, String filename) {
    final lexer = RenPyLexer(content, filename);
    final statements = <RenPyStatement>[];
    final warnings = <String>[];

    try {
      // First, break the content into logical lines and lexical tokens.
      final logicalLines = lexer.listLogicalLines();

      // Group the logical lines into blocks based on indentation.
      final groupedLines = lexer.groupLogicalLines(logicalLines);

      // Parse each statement in the root block.
      final rootBlock = _parseBlock(groupedLines, warnings);
      statements.addAll(rootBlock);
    } catch (e) {
      if (e is RenPyParseError) {
        throw e;
      } else {
        throw RenPyParseError(
          'Unexpected error while parsing: $e',
          filename,
          1,
          0,
        );
      }
    }

    return RenPyParseResult(
      script: RenPyScript(statements),
      warnings: warnings,
    );
  }

  /// Parse a block of grouped logical lines into statements.
  List<RenPyStatement> _parseBlock(
    List<GroupedLine> lines,
    List<String> warnings,
  ) {
    final statements = <RenPyStatement>[];

    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index];
      try {
        final statement =
            _isIfLine(line)
                ? _parseIfStatement(
                  line,
                  warnings,
                  branches: _collectIfBranches(lines, index),
                )
                : _parseStatement(line, warnings);
        if (statement != null) {
          statements.add(statement);
        }
        if (statement is RenPyIfStatement) {
          index += _collectIfBranches(lines, index).length;
        }
      } catch (e) {
        warnings.add(
          'Warning: Could not parse line ${line.number} in ${line.filename}: $e',
        );
      }
    }

    return statements;
  }

  List<GroupedLine> _collectIfBranches(List<GroupedLine> lines, int ifIndex) {
    final branches = <GroupedLine>[];
    for (var index = ifIndex + 1; index < lines.length; index += 1) {
      final line = lines[index];
      if (!_isElifOrElseLine(line)) break;
      branches.add(line);
    }
    return branches;
  }

  bool _isIfLine(GroupedLine line) {
    return line.text.trim().replaceFirst('\uFEFF', '').startsWith('if ');
  }

  bool _isElifOrElseLine(GroupedLine line) {
    final text = line.text.trim().replaceFirst('\uFEFF', '');
    return text.startsWith('elif ') || text == 'else:';
  }

  /// Parse a single statement from a grouped logical line
  RenPyStatement? _parseStatement(GroupedLine line, List<String> warnings) {
    final text = line.text.trim().replaceFirst('\uFEFF', '');

    // Skip empty lines and comments.
    if (text.isEmpty || text.startsWith('#')) {
      return null;
    }

    // Dollar-prefixed single-line statements.
    if (text.startsWith('\$')) {
      final code = text.substring(1).trim(); // drop leading $
      // `dotAll` so a right-hand side that spans several physical lines (a
      // collection literal joined across newlines while inside brackets) is
      // captured whole rather than rejected.
      final assign = RegExp(
        r'^([a-zA-Z_]\w*)\s*=\s*(.+)$',
        dotAll: true,
      ).firstMatch(code);

      // If it looks like a plain assignment, treat it as a "define".
      if (assign != null) {
        final name = assign.group(1)!;
        final expr = assign.group(2)!.trim();
        return RenPyDefineStatement(name, expr, line.filename, line.number);
      }

      // Otherwise keep treating it as normal inline Python.
      return _parsePythonStatement(line, warnings);
    }

    // Parse label statement.
    if (text.startsWith('label ')) {
      return _parseLabelStatement(line, warnings);
    }

    // Parse init statement.
    if (text == 'init' ||
        text.startsWith('init ') ||
        text.startsWith('init:')) {
      return _parseInitStatement(line, warnings);
    }

    // Parse image statement
    if (text.startsWith('image ')) {
      return _parseImageStatement(line, warnings);
    }

    // Parse say statement (dialogue).
    if (_isSayStatement(text)) {
      return _parseSayStatement(line, warnings);
    }

    // Parse menu statement.
    if (text == 'menu' ||
        text.startsWith('menu ') ||
        text.startsWith('menu:')) {
      return _parseMenuStatement(line, warnings);
    }

    // Parse jump statement.
    if (text.startsWith('jump ')) {
      return _parseJumpStatement(line, warnings);
    }

    // Parse call statement.
    if (text.startsWith('call ')) {
      return _parseCallStatement(line, warnings);
    }

    // Parse show statement.
    if (text.startsWith('show ')) {
      return _parseShowStatement(line, warnings);
    }

    // Parse scene statement.
    if (text == 'scene' ||
        text.startsWith('scene ') ||
        text.startsWith('scene:')) {
      return _parseSceneStatement(line, warnings);
    }

    if (text.startsWith('play ')) {
      return _parsePlayStatement(line, warnings);
    }

    if (text.startsWith('stop ')) {
      return _parseStopStatement(line, warnings);
    }

    if (text.startsWith('hide ')) {
      return _parseHideStatement(line, warnings);
    }

    if (text.startsWith('with ')) {
      return _parseWithStatement(line, warnings);
    }

    if (text.startsWith('nvl ')) {
      return _parseNvlStatement(line, warnings);
    }

    // Parse bare window control statements (window show / hide / auto).
    if (text == 'window' ||
        text.startsWith('window show') ||
        text.startsWith('window hide') ||
        text.startsWith('window auto')) {
      return _parseWindowStatement(line, warnings);
    }

    // Parse pause statements (pause, pause 1.0, pause .25).
    if (text == 'pause' || text.startsWith('pause ')) {
      return _parsePauseStatement(line, warnings);
    }

    // Parse python statement.
    if (text.startsWith('python') || text.startsWith('\$')) {
      return _parsePythonStatement(line, warnings);
    }

    if (text.startsWith('screen ')) {
      return _parseScreenStatement(line, warnings);
    }

    if (text.startsWith('style ')) {
      return _parseStyleStatement(line, warnings);
    }

    if (text.startsWith('transform ')) {
      return _parseTransformStatement(line, warnings);
    }

    // Parse define statement.
    if (text.startsWith('define ')) {
      return _parseDefineStatement(line, warnings);
    }

    // Parse default statement.
    if (text.startsWith('default ')) {
      return _parseDefaultStatement(line, warnings);
    }

    // Parse if statement.
    if (text.startsWith('if ')) {
      return _parseIfStatement(line, warnings);
    }

    // Parse pass statement.
    if (text == 'pass') {
      return RenPyPassStatement(line.filename, line.number);
    }

    if (text == 'return' || text.startsWith('return ')) {
      return _parseReturnStatement(line, warnings);
    }

    // If we couldn't identify the statement type, create a generic statement.
    warnings.add(
      'Warning: Unknown statement type at ${line.filename}:${line.number}: $text',
    );
    return RenPyGenericStatement(text, line.filename, line.number);
  }

  RenPyImageStatement _parseImageStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();

    // Handles the assignment forms:
    // 1. image name = expression
    // 2. image name = Image("path")
    final imageRegex = RegExp(r'^image\s+(.+?)\s*=\s*(.+)$', dotAll: true);
    final match = imageRegex.firstMatch(text);

    if (match != null) {
      return RenPyImageStatement(
        match.group(1)!.trim(), // full image name (may contain spaces)
        match.group(2)!.trim(), // right-hand expression
        line.filename,
        line.number,
      );
    }

    // Block form: `image name:` with an indented ATL body. Capture the body
    // as text like transform does rather than crashing on it.
    final blockMatch = RegExp(r'^image\s+(.+?)\s*:$').firstMatch(text);
    if (blockMatch != null) {
      return RenPyImageStatement(
        blockMatch.group(1)!.trim(),
        '',
        line.filename,
        line.number,
        body: _transformBodyLines(line.block),
      );
    }

    throw RenPyParseError(
      'Invalid image statement syntax',
      line.filename,
      line.number,
      0,
    );
  }

  RenPyNvlStatement _parseNvlStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    if (text == 'nvl clear') {
      return RenPyNvlStatement(
        RenPyNvlAction.clear,
        line.filename,
        line.number,
      );
    }

    throw RenPyParseError(
      'Invalid NVL statement syntax',
      line.filename,
      line.number,
      0,
    );
  }

  RenPyWindowStatement _parseWindowStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final match = RegExp(
      r'^window(?:\s+(show|hide|auto))?(?:\s+(.+))?$',
    ).firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid window statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final action = switch (match.group(1)) {
      'hide' => RenPyWindowAction.hide,
      'auto' => RenPyWindowAction.auto,
      _ => RenPyWindowAction.show,
    };
    final transition = match.group(2)?.trim();

    return RenPyWindowStatement(
      action,
      line.filename,
      line.number,
      transition: transition == null || transition.isEmpty ? null : transition,
    );
  }

  RenPyPauseStatement _parsePauseStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    if (text == 'pause') {
      return RenPyPauseStatement(null, line.filename, line.number);
    }

    final argument = text.substring('pause'.length).trim();
    return RenPyPauseStatement(
      argument.isEmpty ? null : argument,
      line.filename,
      line.number,
    );
  }

  RenPyStatement _parseInitStatement(GroupedLine line, List<String> warnings) {
    final text = line.text.trim();
    final offsetMatch = RegExp(
      r'''^init\s+offset\s*=\s*(-?\d+)\s*$''',
    ).firstMatch(text);
    if (offsetMatch != null) {
      return RenPyInitOffsetStatement(
        int.parse(offsetMatch.group(1)!),
        line.filename,
        line.number,
      );
    }

    final initMatch = RegExp(
      r'''^init(\s+(-?\d+))?(\s+python(\s+in\s+[a-zA-Z_]\w*)?)?\s*:''',
    ).firstMatch(text);

    if (initMatch == null) {
      throw RenPyParseError(
        'Invalid init statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final priority =
        initMatch.group(2) != null ? int.parse(initMatch.group(2)!) : 0;
    final isPython = initMatch.group(3) != null;

    // Check if init block has content
    List<RenPyStatement> innerBlock = [];

    // Parse the block
    if (line.block.isNotEmpty) {
      innerBlock =
          isPython
              ? _parsePythonBlockLines(line.block)
              : _parseBlock(line.block, warnings);
    } else {
      // Init blocks require indented content
      throw RenPyParseError(
        'init block requires an indented block',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyInitStatement(
      priority: priority,
      isPython: isPython,
      block: innerBlock,
      filename: line.filename,
      linenumber: line.number,
    );
  }

  List<RenPyStatement> _parsePythonBlockLines(List<GroupedLine> lines) {
    return [
      for (final line in lines)
        if (line.text.trim().isNotEmpty && !line.text.trim().startsWith('#'))
          RenPyPythonStatement(
            line.text.trim(),
            true,
            line.filename,
            line.number,
          ),
    ];
  }

  // For say statements, match:
  // - Character variable followed by quoted text: e "Hello"
  // - Character variable with sprite attributes: e happy "Hello", e -happy "Hi"
  // - Quoted text with no character: "Hello"
  // - Character literal (quoted) followed by quoted text: "Character" "Hello"
  //
  // The leading character group is an identifier optionally followed by
  // attribute tokens (`\w+`, `-word`, `+word`); the attributes are captured
  // together in group 2 and split apart in _parseSayStatement.
  static final _sayPattern = RegExp(
    r'''^(?:([a-zA-Z_]\w*)((?:\s+[-+]?\w+)*)|"([^"]+)"|\'([^\']+)\'|`([^`]+)`)?''' // Optional speaker + attributes
    r'\s*' // Optional whitespace
    r'''(["\'])((?:\\.|[^\\])*?)\6''', // Quoted text
    dotAll: true,
  );

  // Matches a triple-quoted say body, optionally preceded by a speaker and
  // sprite attributes. Group 1 is the identifier speaker, group 2 the
  // attribute run, group 3 the triple-quote delimiter and group 4 the body.
  static final _tripleQuotedSayPattern = RegExp(
    r'''^(?:([a-zA-Z_]\w*)((?:\s+[-+]?\w+)*))?'''
    r'\s*'
    r'''("""|\'\'\')([\s\S]*?)\3''',
    dotAll: true,
  );

  // Statement keywords that may be followed by a quoted argument but must not
  // be mistaken for a say speaker now that the say pattern accepts attribute
  // tokens after the leading identifier (e.g. `show text "..."`).
  static final _sayKeywordGuard = RegExp(
    r'''^(?:show|scene|hide|play|stop|jump|call|with|nvl|window|pause|menu|label|image|define|default|screen|style|transform|init|python|return|pass|if|elif|else)\b''',
  );

  bool _isSayStatement(String text) {
    if (_sayKeywordGuard.hasMatch(text)) return false;
    return _tripleQuotedSayPattern.hasMatch(text) || _sayPattern.hasMatch(text);
  }

  RenPyLabelStatement _parseLabelStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final labelRegex = RegExp(r'''^label\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*:''');
    final match = labelRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid label syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final labelName = match.group(1)!;

    // Parse the block if it exists.
    List<RenPyStatement> block = [];
    if (line.block.isNotEmpty) {
      block = _parseBlock(line.block, warnings);
    }

    return RenPyLabelStatement(labelName, block, line.filename, line.number);
  }

  RenPySayStatement _parseSayStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();

    // Triple-quoted bodies must be handled before the single/double quote
    // pattern, which would otherwise close on the second quote and capture
    // an empty string.
    final tripleMatch = _tripleQuotedSayPattern.firstMatch(text);
    if (tripleMatch != null) {
      final speaker = tripleMatch.group(1);
      final attributes = _splitSayAttributes(tripleMatch.group(2));
      final speech = _unescapeString(tripleMatch.group(4) ?? '');
      return RenPySayStatement(
        speaker,
        speech,
        line.filename,
        line.number,
        attributes: attributes,
      );
    }

    final match = _sayPattern.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid say statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    // Groups 1/3/4/5 are different ways to specify the speaker; group 2 holds
    // the optional sprite attribute run for the identifier form.
    final speaker =
        match.group(1) ?? match.group(3) ?? match.group(4) ?? match.group(5);
    final attributes = _splitSayAttributes(match.group(2));

    // Group 7 is the quoted text content.
    final speech = _unescapeString(match.group(7) ?? '');

    return RenPySayStatement(
      speaker,
      speech,
      line.filename,
      line.number,
      attributes: attributes,
    );
  }

  List<String> _splitSayAttributes(String? raw) {
    if (raw == null) return const [];
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    return trimmed.split(RegExp(r'\s+'));
  }

  String _unescapeString(String value) {
    // Single left-to-right scan so an escaped backslash is consumed as one
    // unit and its following character is not re-interpreted as an escape.
    final buffer = StringBuffer();
    for (var i = 0; i < value.length; i += 1) {
      final character = value[i];
      if (character != r'\' || i + 1 >= value.length) {
        buffer.write(character);
        continue;
      }

      final next = value[i + 1];
      switch (next) {
        case r'\':
          buffer.write(r'\');
          break;
        case '"':
          buffer.write('"');
          break;
        case "'":
          buffer.write("'");
          break;
        case 'n':
          buffer.write('\n');
          break;
        case 't':
          buffer.write('\t');
          break;
        default:
          // Unknown escape: keep the backslash and the following character.
          buffer.write(character);
          buffer.write(next);
      }
      i += 1;
    }
    return buffer.toString();
  }

  RenPyMenuStatement _parseMenuStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    // Parse menu block.
    if (line.block.isEmpty) {
      throw RenPyParseError(
        'Menu requires a block',
        line.filename,
        line.number,
        0,
      );
    }

    final items = <MenuChoice>[];
    String? caption;
    String? setVariable;

    // Parse the menu items (choices).
    for (final choiceLine in line.block) {
      final choiceText = choiceLine.text.trim();

      // Skip menu statements that aren't choices.
      if (choiceText.isEmpty || choiceText.startsWith('#')) {
        continue;
      }

      if (!choiceText.endsWith(':') && _isSayStatement(choiceText)) {
        final say = _parseSayStatement(choiceLine, warnings);
        caption ??= say.text;
        continue;
      }

      final setMatch = RegExp(
        r'^set\s+([a-zA-Z_][a-zA-Z0-9_]*)$',
      ).firstMatch(choiceText);
      if (setMatch != null) {
        setVariable = setMatch.group(1);
        continue;
      }

      // Parse choice text.
      final choiceRegex = RegExp(r'''^["'`](.+?)["'`](?:\s+if\s+(.+?))?\s*:''');
      final match = choiceRegex.firstMatch(choiceText);

      if (match == null) {
        warnings.add(
          'Warning: Invalid menu choice syntax at ${choiceLine.filename}:${choiceLine.number}: $choiceText',
        );
        continue;
      }

      final choiceLabel = _unescapeString(match.group(1)!);
      final condition = match.group(2)?.trim() ?? 'True';
      List<RenPyStatement> choiceBlock = [];

      // Parse the block for this choice if it exists.
      if (choiceLine.block.isNotEmpty) {
        choiceBlock = _parseBlock(choiceLine.block, warnings);
      }

      items.add(
        MenuChoice(text: choiceLabel, condition: condition, block: choiceBlock),
      );
    }

    return RenPyMenuStatement(
      items,
      line.filename,
      line.number,
      caption: caption,
      setVariable: setVariable,
    );
  }

  RenPyJumpStatement _parseJumpStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();

    // jump expression <expr> jumps to a dynamically evaluated target.
    final expressionMatch = RegExp(
      r'^jump\s+expression\s+(.+)$',
    ).firstMatch(text);
    if (expressionMatch != null) {
      return RenPyJumpStatement(
        expressionMatch.group(1)!.trim(),
        line.filename,
        line.number,
        isExpression: true,
      );
    }

    final jumpRegex = RegExp(r'^jump\s+([a-zA-Z_][a-zA-Z0-9_]*)');
    final match = jumpRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid jump syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final target = match.group(1)!;
    return RenPyJumpStatement(target, line.filename, line.number);
  }

  RenPyCallStatement _parseCallStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();

    // call screen <name>(<args>) calls an interactive screen that blocks for a
    // Return value. The screen name and the raw argument string are captured
    // distinctly; the literal `screen` token stays in `target` for back-compat.
    final screenMatch = RegExp(
      r'^call\s+screen\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*(\((.*)\))?'
      r'(?:\s+from\s+[a-zA-Z_][a-zA-Z0-9_]*)?\s*$',
    ).firstMatch(text);
    if (screenMatch != null) {
      return RenPyCallStatement(
        'screen',
        line.filename,
        line.number,
        isScreen: true,
        screenName: screenMatch.group(1),
        screenArgs: screenMatch.group(2) == null ? null : screenMatch.group(3),
      );
    }

    // call expression <expr> calls a dynamically evaluated target. The
    // optional `from <label>` clause is consumed but not retained here.
    final expressionMatch = RegExp(
      r'^call\s+expression\s+(.+?)(?:\s+from\s+[a-zA-Z_][a-zA-Z0-9_]*)?$',
    ).firstMatch(text);
    if (expressionMatch != null) {
      return RenPyCallStatement(
        expressionMatch.group(1)!.trim(),
        line.filename,
        line.number,
        isExpression: true,
      );
    }

    final callRegex = RegExp(
      r'^call\s+([a-zA-Z_][a-zA-Z0-9_]*)(?:\s+from\s+[a-zA-Z_][a-zA-Z0-9_]*)?',
    );
    final match = callRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid call syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyCallStatement(match.group(1)!, line.filename, line.number);
  }

  RenPyShowStatement _parseShowStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final textDisplayable = _tryParseShowTextStatement(line);
    if (textDisplayable != null) return textDisplayable;

    const prefix = 'show ';
    if (!text.startsWith(prefix) ||
        text.substring(prefix.length).trim().isEmpty) {
      throw RenPyParseError(
        'Invalid show syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final parts = _parseImageStatementParts(
      text.substring(prefix.length),
      line,
      'show',
      const ['at', 'onlayer', 'zorder', 'behind', 'with'],
    );

    return RenPyShowStatement(
      parts.imageName,
      parts.clauses['at'],
      parts.clauses['with'],
      line.filename,
      line.number,
      behindExpression: parts.clauses['behind'],
      onLayerExpression: parts.clauses['onlayer'],
      zOrderExpression: parts.clauses['zorder'],
    );
  }

  RenPyShowStatement? _tryParseShowTextStatement(GroupedLine line) {
    final text = line.text.trim();
    const prefix = 'show text ';
    if (!text.startsWith(prefix)) return null;

    final rest = text.substring(prefix.length).trimLeft();
    if (rest.isEmpty || (rest[0] != '"' && rest[0] != "'")) return null;

    final quoted = _parseQuotedPrefix(rest);
    if (quoted == null) {
      throw RenPyParseError(
        'Invalid show text syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final suffix = quoted.remainder.trim();
    final parts = _parseImageStatementParts(suffix, line, 'show text', const [
      'as',
      'at',
      'onlayer',
      'zorder',
      'behind',
      'with',
    ], requireImageName: false);

    return RenPyShowStatement(
      parts.clauses['as'] ?? 'text',
      parts.clauses['at'],
      parts.clauses['with'],
      line.filename,
      line.number,
      behindExpression: parts.clauses['behind'],
      onLayerExpression: parts.clauses['onlayer'],
      zOrderExpression: parts.clauses['zorder'],
      displayableText: _unescapeString(quoted.value),
    );
  }

  _ImageStatementParts _parseImageStatementParts(
    String text,
    GroupedLine line,
    String statementName,
    List<String> keywords, {
    bool requireImageName = true,
  }) {
    final trimmed = text.trim();
    final clauseStarts = _findTopLevelClauseStarts(trimmed, keywords);
    final imageEnd =
        clauseStarts.isEmpty ? trimmed.length : clauseStarts.first.index;
    final imageName = trimmed.substring(0, imageEnd).trim();
    if (requireImageName && imageName.isEmpty) {
      throw RenPyParseError(
        'Invalid $statementName syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final clauses = <String, String>{};
    for (var i = 0; i < clauseStarts.length; i += 1) {
      final start = clauseStarts[i];
      final valueStart = start.index + start.keyword.length;
      final valueEnd =
          i + 1 < clauseStarts.length
              ? clauseStarts[i + 1].index
              : trimmed.length;
      final value = trimmed.substring(valueStart, valueEnd).trim();
      if (value.isEmpty) {
        throw RenPyParseError(
          'Invalid $statementName syntax',
          line.filename,
          line.number,
          0,
        );
      }
      clauses[start.keyword] =
          start.keyword == 'with'
              ? _normalizeTransitionExpression(value)
              : value;
    }

    return _ImageStatementParts(imageName, clauses);
  }

  List<_ClauseStart> _findTopLevelClauseStarts(
    String text,
    List<String> keywords,
  ) {
    final starts = <_ClauseStart>[];
    var depth = 0;
    String? quote;
    var escaped = false;

    for (var i = 0; i < text.length; i += 1) {
      final character = text[i];
      if (quote != null) {
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
      if (depth != 0) continue;
      if (i != 0 && !_isWhitespace(text.codeUnitAt(i - 1))) continue;

      for (final keyword in keywords) {
        if (!_startsWithKeyword(text, i, keyword)) continue;
        starts.add(_ClauseStart(i, keyword));
        i += keyword.length - 1;
        break;
      }
    }
    return starts;
  }

  bool _startsWithKeyword(String text, int index, String keyword) {
    if (!text.startsWith(keyword, index)) return false;
    final end = index + keyword.length;
    return end < text.length && _isWhitespace(text.codeUnitAt(end));
  }

  bool _isWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0a ||
        codeUnit == 0x0d;
  }

  _QuotedPrefix? _parseQuotedPrefix(String text) {
    final quote = text[0];
    final buffer = StringBuffer();
    var escaped = false;

    for (var i = 1; i < text.length; i += 1) {
      final character = text[i];
      if (escaped) {
        buffer.write('\\');
        buffer.write(character);
        escaped = false;
        continue;
      }

      if (character == r'\') {
        escaped = true;
        continue;
      }

      if (character == quote) {
        return _QuotedPrefix(buffer.toString(), text.substring(i + 1));
      }

      buffer.write(character);
    }

    return null;
  }

  RenPySceneStatement _parseSceneStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();

    // Check if it's just 'scene' without an image.
    if (text == 'scene') {
      return RenPySceneStatement(null, null, null, line.filename, line.number);
    }

    const prefix = 'scene ';
    if (!text.startsWith(prefix) ||
        text.substring(prefix.length).trim().isEmpty) {
      throw RenPyParseError(
        'Invalid scene syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final parts = _parseImageStatementParts(
      text.substring(prefix.length),
      line,
      'scene',
      const ['at', 'onlayer', 'zorder', 'with'],
    );

    return RenPySceneStatement(
      parts.imageName,
      parts.clauses['at'],
      parts.clauses['with'],
      line.filename,
      line.number,
      onLayerExpression: parts.clauses['onlayer'],
      zOrderExpression: parts.clauses['zorder'],
    );
  }

  RenPyHideStatement _parseHideStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    const prefix = 'hide ';
    if (!text.startsWith(prefix) ||
        text.substring(prefix.length).trim().isEmpty) {
      throw RenPyParseError(
        'Invalid hide syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final parts = _parseImageStatementParts(
      text.substring(prefix.length),
      line,
      'hide',
      const ['onlayer', 'with'],
    );

    return RenPyHideStatement(
      parts.imageName,
      parts.clauses['with'],
      line.filename,
      line.number,
      onLayerExpression: parts.clauses['onlayer'],
    );
  }

  RenPyWithStatement _parseWithStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final withRegex = RegExp(r'^with\s+(.+)$');
    final match = withRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid with syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyWithStatement(
      _normalizeTransitionExpression(match.group(1)!.trim()),
      line.filename,
      line.number,
    );
  }

  String _normalizeTransitionExpression(String expression) {
    final value = expression.trim();
    if (value.endsWith(':')) return value.substring(0, value.length - 1).trim();
    return value;
  }

  RenPyPythonStatement _parsePythonStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    String code;

    if (text.startsWith('\$')) {
      // Single-line Python.
      code = text.substring(1).trim();
      return RenPyPythonStatement(code, false, line.filename, line.number);
    } else {
      // Multi-line Python block. The grouping step strips each line's
      // indentation and nests deeper lines under their parent, so reconstruct
      // the body recursively and re-indent it relative to the block's own
      // first line. This preserves the nested structure that `for`/`if`/`def`
      // bodies rely on when the statement interpreter later executes them.
      final pythonBlock = <String>[];
      final baseIndent = line.block.isEmpty ? 0 : line.block.first.indent;
      _collectPythonBlockLines(line.block, baseIndent, pythonBlock);

      code = pythonBlock.join('\n');
      // Only `python early:` runs in the early init phase; match `early` as a
      // whole word rather than a substring.
      final isInit = RegExp(r'^python\s+early\b').hasMatch(text);

      return RenPyPythonStatement(code, isInit, line.filename, line.number);
    }
  }

  /// Flattens a grouped Python block back into indented source lines. Each
  /// line is re-indented by `(line.indent - baseIndent)` spaces so the body
  /// keeps its relative nesting while starting at column zero.
  void _collectPythonBlockLines(
    List<GroupedLine> lines,
    int baseIndent,
    List<String> out,
  ) {
    for (final line in lines) {
      final relative = line.indent - baseIndent;
      final padding = relative > 0 ? ' ' * relative : '';
      out.add('$padding${line.text}');
      if (line.block.isNotEmpty) {
        _collectPythonBlockLines(line.block, baseIndent, out);
      }
    }
  }

  RenPyDefineStatement _parseDefineStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final defineRegex = RegExp(
      r'^define\s+(?:-?\d+\s+)?([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*=\s*(.+)$',
      dotAll: true,
    );
    final match = defineRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid define syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final variableName = match.group(1)!;
    final value = match.group(2)!;

    return RenPyDefineStatement(
      variableName,
      value,
      line.filename,
      line.number,
    );
  }

  RenPyDefaultStatement _parseDefaultStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final defaultRegex = RegExp(
      r'^default\s+(?:-?\d+\s+)?([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*=\s*(.+)$',
      dotAll: true,
    );
    final match = defaultRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid default syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyDefaultStatement(
      match.group(1)!,
      match.group(2)!.trim(),
      line.filename,
      line.number,
    );
  }

  RenPyIfStatement _parseIfStatement(
    GroupedLine line,
    List<String> warnings, {
    List<GroupedLine> branches = const [],
  }) {
    final text = line.text.trim();
    final ifRegex = RegExp(r'^if\s+(.+?)\s*:');
    final match = ifRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError('Invalid if syntax', line.filename, line.number, 0);
    }

    final condition = match.group(1)!;

    final entries = <IfEntry>[];
    entries.add(IfEntry(condition, _parseBlock(line.block, warnings)));

    for (final branch in branches) {
      final branchText = branch.text.trim();
      final elifMatch = RegExp(r'^elif\s+(.+?)\s*:').firstMatch(branchText);
      if (elifMatch != null) {
        entries.add(
          IfEntry(elifMatch.group(1)!, _parseBlock(branch.block, warnings)),
        );
        continue;
      }
      if (RegExp(r'^else\s*:').hasMatch(branchText)) {
        entries.add(IfEntry('True', _parseBlock(branch.block, warnings)));
        continue;
      }
      throw RenPyParseError(
        'Invalid if branch syntax',
        branch.filename,
        branch.number,
        0,
      );
    }

    return RenPyIfStatement(entries, line.filename, line.number);
  }

  /// Stub for `play sound/music/voice ...`.
  ///
  /// Syntax accepted:
  ///   play sound "file.ogg"
  ///   play music my_sound
  RenPyPlayStatement _parsePlayStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final rx = RegExp(r'^play\s+(\w+)\s+(.+)$');
    final m = rx.firstMatch(text);
    if (m == null) {
      throw RenPyParseError(
        'Invalid play-sound syntax',
        line.filename,
        line.number,
        0,
      );
    }
    return RenPyPlayStatement(
      m.group(1)!, // Channel.
      m.group(2)!.trim(), // Expression.
      line.filename,
      line.number,
    );
  }

  RenPyStopStatement _parseStopStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final rx = RegExp(r'^stop\s+(\w+)(?:\s+fadeout\s+(.+))?$');
    final m = rx.firstMatch(text);
    if (m == null) {
      throw RenPyParseError(
        'Invalid stop-audio syntax',
        line.filename,
        line.number,
        0,
      );
    }
    return RenPyStopStatement(
      m.group(1)!,
      m.group(2)?.trim(),
      line.filename,
      line.number,
    );
  }

  RenPyReturnStatement _parseReturnStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final expression = text == 'return' ? null : text.substring(6).trim();
    return RenPyReturnStatement(
      expression == '' ? null : expression,
      line.filename,
      line.number,
    );
  }

  RenPyScreenStatement _parseScreenStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final match = RegExp(r'^screen\s+(.+?)\s*:$').firstMatch(text);
    if (match == null) {
      throw RenPyParseError(
        'Invalid screen statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyScreenStatement(
      match.group(1)!.trim(),
      line.filename,
      line.number,
      children: _bodyParser.parseScreenBody(line.block),
    );
  }

  RenPyStyleStatement _parseStyleStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final match = RegExp(r'^style\s+(.+?)(?::)?$').firstMatch(text);
    if (match == null) {
      throw RenPyParseError(
        'Invalid style statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final declaration = match.group(1)!.trim();
    return RenPyStyleStatement(
      declaration,
      line.filename,
      line.number,
      style: _bodyParser.parseStyle(declaration, line.block),
    );
  }

  RenPyTransformStatement _parseTransformStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final match = RegExp(r'^transform\s+(.+?)\s*:$').firstMatch(text);
    if (match == null) {
      throw RenPyParseError(
        'Invalid transform statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyTransformStatement(
      match.group(1)!.trim(),
      line.filename,
      line.number,
      body: _transformBodyLines(line.block),
      atl: _bodyParser.parseAtl(line.block),
    );
  }

  List<String> _transformBodyLines(List<GroupedLine> block) {
    if (block.isEmpty) return const [];
    final baseIndent = block.first.indent;
    final lines = <String>[];

    void append(List<GroupedLine> currentBlock) {
      for (final blockLine in currentBlock) {
        final relativeIndent = (blockLine.indent - baseIndent).clamp(0, 9999);
        lines.add('${''.padLeft(relativeIndent)}${blockLine.text.trim()}');
        append(blockLine.block);
      }
    }

    append(block);
    return lines;
  }
}

/// Represents the result of parsing a RenPy script.
class RenPyParseResult {
  final RenPyScript script;
  final List<String> warnings;

  RenPyParseResult({required this.script, required this.warnings});
}

/// Represents a grouped logical line with its block.
class GroupedLine {
  final String filename;
  final int number;
  final int indent;
  final String text;
  final List<GroupedLine> block;

  GroupedLine({
    required this.filename,
    required this.number,
    required this.indent,
    required this.text,
    required this.block,
  });
}

class _QuotedPrefix {
  const _QuotedPrefix(this.value, this.remainder);

  final String value;
  final String remainder;
}

/// Represents an init block statement.
class RenPyInitStatement extends RenPyBlockStatement {
  final int priority; // "init -1 python:" -> priority -1, etc.
  final bool isPython; // `init python:` or `init -2 python:` ...

  RenPyInitStatement({
    required this.priority,
    required this.isPython,
    required List<RenPyStatement> block,
    required String filename,
    required int linenumber,
  }) : super(block, filename, linenumber);
}

class _ImageStatementParts {
  const _ImageStatementParts(this.imageName, this.clauses);

  final String imageName;
  final Map<String, String> clauses;
}

class _ClauseStart {
  const _ClauseStart(this.index, this.keyword);

  final int index;
  final String keyword;
}
