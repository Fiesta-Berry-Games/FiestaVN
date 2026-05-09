import '../renpy_parser.dart';

/// A lexer for RenPy script files
class RenPyLexer {
  final String content;
  final String filename;

  /// Current position in the content
  int pos = 0;

  RenPyLexer(String content, this.filename)
    // Strip a leading UTF-8 BOM (U+FEFF). When present it precedes the first
    // statement and defeats the `^`-anchored statement matchers for the whole
    // file (e.g. `init`), which made BOM-prefixed files unparseable.
    : content = content.startsWith('\u{FEFF}') ? content.substring(1) : content;

  /// Lists the logical lines in the script
  ///
  /// A logical line may span multiple physical lines due to line continuations,
  /// triple-quoted strings, or parentheses/brackets/braces.
  List<LogicalLine> listLogicalLines() {
    final result = <LogicalLine>[];

    int lineNumber = 1;

    while (pos < content.length) {
      final skipStart = pos;

      // Skip whitespace and comments.
      _skipWhitespaceAndComments();

      // Account for any blank or comment lines that were skipped so the
      // logical line is reported at its true physical line.
      for (int i = skipStart; i < pos; i++) {
        if (content[i] == '\n') {
          lineNumber++;
        }
      }

      if (pos >= content.length) {
        break;
      }

      final startPos = pos;
      final startLine = lineNumber;

      // Process the logical line.
      final logicalLine = _readLogicalLine(lineNumber);

      // Count newlines consumed by the logical line itself.
      for (int i = startPos; i < pos; i++) {
        if (content[i] == '\n') {
          lineNumber++;
        }
      }

      if (logicalLine.text.isNotEmpty) {
        result.add(
          LogicalLine(
            filename: filename,
            number: startLine,
            text: logicalLine.text,
          ),
        );
      }
    }

    return result;
  }

  /// Groups logical lines into blocks based on indentation
  List<GroupedLine> groupLogicalLines(List<LogicalLine> lines) {
    if (lines.isEmpty) {
      return [];
    }

    // Check that the first line is not indented.
    final firstLine = lines[0];
    if (firstLine.text.startsWith(' ') &&
        !firstLine.text.trim().startsWith('#')) {
      throw RenPyParseError(
        'Unexpected indentation at start of file',
        firstLine.filename,
        firstLine.number,
        0,
      );
    }

    final result = <GroupedLine>[];
    final stack = <_IndentBlock>[]..add(_IndentBlock(0, result));

    for (final line in lines) {
      final indent = _getIndent(line.text);
      final trimmedLine = line.text.substring(indent);

      // Skip empty lines and comments when grouping
      if (trimmedLine.isEmpty || trimmedLine.startsWith('#')) {
        continue;
      }

      // 1 - Indentation **increases**
      if (indent > stack.last.indent) {
        // Use the already-allocated `block` list that belongs
        // to the parent line instead of inventing a new one.
        if (stack.last.block.isEmpty) {
          // If there's no parent line yet, this is an error
          throw RenPyParseError(
            'Unexpected indentation',
            line.filename,
            line.number,
            0,
          );
        }
        final parent = stack.last.block.last;
        stack.add(_IndentBlock(indent, parent.block));
      }
      // 2 - Indentation **decreases**
      else if (indent < stack.last.indent) {
        while (stack.length > 1 && indent < stack.last.indent) {
          stack.removeLast();
        }
        if (indent != stack.last.indent) {
          throw RenPyParseError(
            'Indentation mismatch',
            line.filename,
            line.number,
            0,
          );
        }
      }

      // 3 - Add this line to the current block
      GroupedLine newLine = GroupedLine(
        filename: line.filename,
        number: line.number,
        indent: indent,
        text: trimmedLine,
        block: [], // empty child list
      );

      stack.last.block.add(newLine);
    }

    return result;
  }

  /// Skip blank lines and full-line comments, **but keep the indentation**
  /// whitespace of every line that actually contains code - that whitespace
  /// is syntactically significant in Ren'Py.
  void _skipWhitespaceAndComments() {
    while (pos < content.length) {
      final char = content[pos];

      // -- 1  Empty physical lines --------------------------------------------
      if (char == '\n' || char == '\r') {
        pos++; // move to the next physical line
        continue;
      }

      // -- 2  Full-line comments starting in the first column ----------------
      if (char == '#') {
        // Skip to the end-of-line (and the trailing LF if present)
        while (pos < content.length && content[pos] != '\n') pos++;
        if (pos < content.length && content[pos] == '\n') pos++;
        continue;
      }

      // -- 3  Lines that are nothing but whitespace ---------------------------
      if (char == ' ' || char == '\t') {
        var look = pos;
        var onlyWs = true;
        while (look < content.length && content[look] != '\n') {
          final c = content[look];
          if (c != ' ' && c != '\t' && c != '\r') {
            onlyWs = false; // we've hit indentation -> keep it
            break;
          }
          look++;
        }

        if (look < content.length && content[look] == '#') {
          while (look < content.length && content[look] != '\n') {
            look++;
          }
          pos = look;
          if (pos < content.length && content[pos] == '\n') pos++;
          continue;
        }

        if (onlyWs) {
          // The whole physical line was blank; skip it.
          pos = look;
          if (pos < content.length && content[pos] == '\n') pos++;
          continue;
        }

        // We are at indentation whitespace in front of a real line of code -
        // do **not** skip it.
        break;
      }

      // -- 4  Any other character means we're at real code - stop skipping. --
      break;
    }
  }

  /// Read a logical line, which may span multiple physical lines
  LogicalLine _readLogicalLine(int lineNumber) {
    final startPos = pos;
    final chars = <String>[];

    // Stack for tracking open brackets/parentheses/braces.
    final openParens = <String>[];

    // Triple quote state.
    bool inTripleQuote = false;
    String? tripleQuoteChar;
    String? quoteChar;
    var escaped = false;

    while (pos < content.length) {
      final char = content[pos];

      // Handle end of line.
      if (char == '\n') {
        if (openParens.isEmpty && !inTripleQuote && quoteChar == null) {
          // End of logical line.
          pos++;
          break;
        }

        escaped = false;
      }
      // Check for line continuation. Drop the backslash and the following
      // newline so the two physical lines are spliced together.
      else if (char == '\\' &&
          quoteChar == null &&
          pos + 1 < content.length &&
          content[pos + 1] == '\n') {
        pos += 2;
        continue;
      }
      // Handle escaped characters inside regular quoted strings.
      else if (quoteChar != null && escaped) {
        escaped = false;
      } else if (quoteChar != null && char == r'\') {
        escaped = true;
      } else if (quoteChar != null) {
        if (char == quoteChar) {
          quoteChar = null;
        }
      }
      // A `#` outside any string begins a comment that runs to the end of the
      // physical line. This holds even inside an open bracket pair (Python
      // permits comments inside collection/call literals), so skip the comment
      // text rather than tokenising it; otherwise stray quotes or brackets in a
      // comment corrupt the quote/bracket state and abort the whole file.
      else if (!inTripleQuote && quoteChar == null && char == '#') {
        while (pos < content.length && content[pos] != '\n') {
          pos++;
        }
        continue;
      }
      // Handle quotes.
      else if (char == '"' || char == "'" || char == '`') {
        // Check for triple quotes.
        if (pos + 2 < content.length &&
            content[pos + 1] == char &&
            content[pos + 2] == char) {
          if (inTripleQuote && char == tripleQuoteChar) {
            // End of triple quote.
            inTripleQuote = false;
            tripleQuoteChar = null;
            chars.add(char);
            chars.add(char);
            chars.add(char);
            pos += 3;
            continue;
          } else if (!inTripleQuote) {
            // Start of triple quote.
            inTripleQuote = true;
            tripleQuoteChar = char;
            chars.add(char);
            chars.add(char);
            chars.add(char);
            pos += 3;
            continue;
          }
        }

        if (!inTripleQuote) {
          quoteChar = char;
        }
      }
      // Handle opening parentheses/brackets/braces.
      else if (!inTripleQuote &&
          quoteChar == null &&
          (char == '(' || char == '[' || char == '{')) {
        openParens.add(char);
      }
      // Handle closing parentheses/brackets/braces.
      else if (!inTripleQuote &&
          quoteChar == null &&
          (char == ')' || char == ']' || char == '}')) {
        if (openParens.isEmpty) {
          throw RenPyParseError(
            'Unmatched closing bracket: $char',
            filename,
            lineNumber,
            pos - startPos,
          );
        }

        final open = openParens.removeLast();
        if ((open == '(' && char != ')') ||
            (open == '[' && char != ']') ||
            (open == '{' && char != '}')) {
          throw RenPyParseError(
            'Mismatched brackets: $open and $char',
            filename,
            lineNumber,
            pos - startPos,
          );
        }
      }

      chars.add(char);
      pos++;
    }

    if (openParens.isNotEmpty) {
      throw RenPyParseError(
        'Unclosed brackets: ${openParens.join(', ')}',
        filename,
        lineNumber,
        pos - startPos,
      );
    }

    if (inTripleQuote) {
      throw RenPyParseError(
        'Unclosed triple quote',
        filename,
        lineNumber,
        pos - startPos,
      );
    }

    return LogicalLine(
      filename: filename,
      number: lineNumber,
      text: chars.join(),
    );
  }

  /// Get the indentation level (number of spaces) at the beginning of a line.
  int _getIndent(String line) {
    int indent = 0;

    for (int i = 0; i < line.length; i++) {
      if (line[i] == ' ') {
        indent++;
      } else if (line[i] == '\t') {
        throw RenPyParseError(
          'Tab characters are not allowed in Ren\'Py scripts',
          filename,
          0,
          i,
        );
      } else {
        break;
      }
    }

    return indent;
  }
}

/// Represents a logical line in the RenPy script.
class LogicalLine {
  final String filename;
  final int number;
  final String text;

  LogicalLine({
    required this.filename,
    required this.number,
    required this.text,
  });
}

/// Helper class for tracking indentation blocks.
class _IndentBlock {
  final int indent;
  final List<GroupedLine> block;

  _IndentBlock(this.indent, this.block);
}
