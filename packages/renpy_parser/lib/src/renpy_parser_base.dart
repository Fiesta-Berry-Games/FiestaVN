import 'package:renpy_parser/src/models/renpy_script.dart';
import 'package:renpy_parser/src/models/renpy_statement.dart';
import 'package:renpy_parser/src/renpy_lexer.dart';
import 'package:renpy_parser/src/errors/parse_error.dart';

/// The main RenPy parser class responsible for parsing .rpy files.
class RenPyParser {
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
      final assign = RegExp(r'^([a-zA-Z_]\w*)\s*=\s*(.+)$').firstMatch(code);

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
    if (text.startsWith('init')) {
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
    if (text.startsWith('menu')) {
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
    if (text.startsWith('scene')) {
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

    // Modified to handle both formats:
    // 1. image name = expression
    // 2. image name = Image("path")
    final imageRegex = RegExp(r'^image\s+(.+?)\s*=\s*(.+)$');
    final match = imageRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid image statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyImageStatement(
      match.group(1)!.trim(), // full image name (may contain spaces)
      match.group(2)!.trim(), // right-hand expression
      line.filename,
      line.number,
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
      r'''^init(\s+(-?\d+))?(\s+python)?\s*:''',
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
  // - Quoted text with no character: "Hello"
  // - Character literal (quoted) followed by quoted text: "Character" "Hello"
  static final _sayPattern = RegExp(
    r'''^(?:([a-zA-Z_]\w*)|"([^"]+)"|\'([^\']+)\'|`([^`]+)`)?''' // Optional speaker
    r'\s*' // Optional whitespace
    r'''(["\'])((?:\\.|[^\\])*?)\5''', // Quoted text
    dotAll: true,
  );

  bool _isSayStatement(String text) {
    return _sayPattern.hasMatch(text);
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
    final match = _sayPattern.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid say statement syntax',
        line.filename,
        line.number,
        0,
      );
    }

    // Group 1-4 are different ways to specify the speaker
    final speaker =
        match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);

    // Group 6 is the quoted text content
    final speech = _unescapeString(match.group(6) ?? '');

    return RenPySayStatement(speaker, speech, line.filename, line.number);
  }

  String _unescapeString(String value) {
    return value
        .replaceAll(r'\"', '"')
        .replaceAll(r"\'", "'")
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\t', '\t')
        .replaceAll(r'\\', '\\');
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
      clauses[start.keyword] = value;
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
      match.group(1)!.trim(),
      line.filename,
      line.number,
    );
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
      // Multi-line Python block.
      final pythonBlock = <String>[];

      // Get code from the block.
      for (final pythonLine in line.block) {
        pythonBlock.add(pythonLine.text);
      }

      code = pythonBlock.join('\n');
      final isInit = text.contains('early');

      return RenPyPythonStatement(code, isInit, line.filename, line.number);
    }
  }

  RenPyDefineStatement _parseDefineStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final defineRegex = RegExp(
      r'^define\s+([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*=\s*(.+)$',
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
      r'^default\s+([a-zA-Z_]\w*(?:\.[a-zA-Z_]\w*)*)\s*=\s*(.+)$',
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

    return RenPyStyleStatement(
      match.group(1)!.trim(),
      line.filename,
      line.number,
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
    );
  }

  List<String> _transformBodyLines(List<GroupedLine> block) {
    if (block.isEmpty) return const [];
    final baseIndent = block.first.indent;
    final lines = <String>[];

    void append(List<GroupedLine> currentBlock) {
      for (final blockLine in currentBlock) {
        final relativeIndent =
            (blockLine.indent - baseIndent).clamp(0, 9999) as int;
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
