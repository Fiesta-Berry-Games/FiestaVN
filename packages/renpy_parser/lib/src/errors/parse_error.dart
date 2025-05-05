/// Exception thrown when there's an error parsing RenPy scripts.
class RenPyParseError implements Exception {
  final String message;
  final String filename;
  final int linenumber;
  final int offset;
  final String? text;

  RenPyParseError(
    this.message,
    this.filename,
    this.linenumber,
    this.offset, [
    this.text,
  ]);

  @override
  String toString() {
    String result = 'File "$filename", line $linenumber: $message';

    if (text != null) {
      // Show the line of code.
      result += '\n    ${text!.trim()}';

      // Show a caret at the position of the error.
      if (offset >= 0) {
        final caretPosition = offset;
        final caretSpaces = ' ' * caretPosition;
        result += '\n    $caretSpaces^';
      }
    }

    return result;
  }
}
