/// A parsed RenPy dialogue string with inline style metadata.
class RenPyStyledText {
  factory RenPyStyledText(List<RenPyTextRun> runs) {
    return RenPyStyledText._(List.unmodifiable(runs));
  }

  const RenPyStyledText._(this.runs);

  /// Parses RenPy inline text tags into platform-neutral text runs.
  ///
  /// Style tags currently recognized by FiestaVN are `{b}`, `{/b}`, `{i}`,
  /// `{/i}`, `{color=...}`, and `{/color}`. Other RenPy tags are treated as
  /// control tags and omitted from the visible text.
  factory RenPyStyledText.parse(String text) {
    final runs = <RenPyTextRun>[];
    var bold = false;
    var italic = false;
    String? color;
    var index = 0;

    for (final match in _tagPattern.allMatches(text)) {
      if (match.start > index) {
        _appendRun(
          runs,
          text.substring(index, match.start),
          bold: bold,
          italic: italic,
          color: color,
        );
      }

      final tag = match.group(0)!;
      switch (tag) {
        case '{b}':
          bold = true;
          break;
        case '{/b}':
          bold = false;
          break;
        case '{i}':
          italic = true;
          break;
        case '{/i}':
          italic = false;
          break;
        case '{/color}':
          color = null;
          break;
        default:
          color = _parseColorTag(tag) ?? color;
      }

      index = match.end;
    }

    if (index < text.length) {
      _appendRun(
        runs,
        text.substring(index),
        bold: bold,
        italic: italic,
        color: color,
      );
    }

    return RenPyStyledText(runs);
  }

  static final RegExp _tagPattern = RegExp(r'\{[^}]+\}');

  /// Visible text with all RenPy inline tags removed.
  String get plainText => runs.map((run) => run.text).join();

  /// Visible text segments and their active inline styles.
  final List<RenPyTextRun> runs;

  static void _appendRun(
    List<RenPyTextRun> runs,
    String text, {
    required bool bold,
    required bool italic,
    required String? color,
  }) {
    if (text.isEmpty) {
      return;
    }

    final run = RenPyTextRun(text, bold: bold, italic: italic, color: color);
    if (runs.isNotEmpty && runs.last._hasSameStyle(run)) {
      runs[runs.length - 1] = runs.last._merge(run);
    } else {
      runs.add(run);
    }
  }
}

String? _parseColorTag(String tag) {
  final match = RegExp(r'^\{color=([^}]+)\}$').firstMatch(tag);
  return match?.group(1);
}

/// A visible segment of RenPy dialogue text with active inline styles.
class RenPyTextRun {
  const RenPyTextRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.color,
  });

  final String text;
  final bool bold;
  final bool italic;
  final String? color;

  bool _hasSameStyle(RenPyTextRun other) {
    return bold == other.bold && italic == other.italic && color == other.color;
  }

  RenPyTextRun _merge(RenPyTextRun other) {
    assert(_hasSameStyle(other));
    return RenPyTextRun(
      '$text${other.text}',
      bold: bold,
      italic: italic,
      color: color,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyTextRun &&
            text == other.text &&
            bold == other.bold &&
            italic == other.italic &&
            color == other.color;
  }

  @override
  int get hashCode => Object.hash(text, bold, italic, color);

  @override
  String toString() {
    final styles = [
      if (bold) 'bold: true',
      if (italic) 'italic: true',
      if (color != null) 'color: $color',
    ].join(', ');
    return styles.isEmpty
        ? "RenPyTextRun('$text')"
        : "RenPyTextRun('$text', $styles)";
  }
}
