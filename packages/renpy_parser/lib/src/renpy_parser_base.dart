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

    for (final line in lines) {
      try {
        final statement = _parseStatement(line, warnings);
        if (statement != null) {
          statements.add(statement);
        }
      } catch (e) {
        warnings.add(
          'Warning: Could not parse line ${line.number} in ${line.filename}: $e',
        );
      }
    }

    return statements;
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

    // Parse python statement.
    if (text.startsWith('python') || text.startsWith('\$')) {
      return _parsePythonStatement(line, warnings);
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

  RenPyInitStatement _parseInitStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
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
      innerBlock = _parseBlock(line.block, warnings);
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
    final showRegex = RegExp(
      r'^show\s+(.+?)(?:\s+at\s+(.+?))?(?:\s+with\s+(.+?))?$',
    );
    final match = showRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid show syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final imageName = match.group(1)!;
    final atExpression = match.group(2);
    final withExpression = match.group(3);

    return RenPyShowStatement(
      imageName,
      atExpression,
      withExpression,
      line.filename,
      line.number,
    );
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

    final sceneRegex = RegExp(
      r'^scene\s+(.+?)(?:\s+at\s+(.+?))?(?:\s+with\s+(.+?))?$',
    );
    final match = sceneRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid scene syntax',
        line.filename,
        line.number,
        0,
      );
    }

    final imageName = match.group(1)!;
    final atExpression = match.group(2);
    final withExpression = match.group(3);

    return RenPySceneStatement(
      imageName,
      atExpression,
      withExpression,
      line.filename,
      line.number,
    );
  }

  RenPyHideStatement _parseHideStatement(
    GroupedLine line,
    List<String> warnings,
  ) {
    final text = line.text.trim();
    final hideRegex = RegExp(r'^hide\s+(.+?)(?:\s+with\s+(.+?))?$');
    final match = hideRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError(
        'Invalid hide syntax',
        line.filename,
        line.number,
        0,
      );
    }

    return RenPyHideStatement(
      match.group(1)!.trim(),
      match.group(2),
      line.filename,
      line.number,
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
      r'^define\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$',
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
      r'^default\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(.+)$',
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

  RenPyIfStatement _parseIfStatement(GroupedLine line, List<String> warnings) {
    final text = line.text.trim();
    final ifRegex = RegExp(r'^if\s+(.+?)\s*:');
    final match = ifRegex.firstMatch(text);

    if (match == null) {
      throw RenPyParseError('Invalid if syntax', line.filename, line.number, 0);
    }

    final condition = match.group(1)!;

    // Parse the if block
    final entries = <IfEntry>[];

    if (line.block.isNotEmpty) {
      final ifBlock = _parseBlock(line.block, warnings);
      entries.add(IfEntry(condition, ifBlock));
    }

    // TODO: Parse elif and else blocks

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
