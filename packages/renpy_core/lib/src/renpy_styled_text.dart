/// A parsed RenPy dialogue string with inline style metadata.
class RenPyStyledText {
  factory RenPyStyledText(List<RenPyTextRun> runs) {
    return RenPyStyledText._(List.unmodifiable(runs));
  }

  const RenPyStyledText._(this.runs);

  /// Parses RenPy inline text tags into platform-neutral text runs.
  ///
  /// Style tags currently recognized by FiestaVN are `{b}`, `{/b}`, `{i}`,
  /// and `{/i}`. Other RenPy tags are treated as control tags and omitted
  /// from the visible text.
  factory RenPyStyledText.parse(String text) {
    final runs = <RenPyTextRun>[];
    var bold = false;
    var italic = false;
    var index = 0;

    for (final match in _tagPattern.allMatches(text)) {
      if (match.start > index) {
        _appendRun(
          runs,
          text.substring(index, match.start),
          bold: bold,
          italic: italic,
        );
      }

      switch (match.group(0)) {
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
      }

      index = match.end;
    }

    if (index < text.length) {
      _appendRun(runs, text.substring(index), bold: bold, italic: italic);
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
  }) {
    if (text.isEmpty) {
      return;
    }

    final run = RenPyTextRun(text, bold: bold, italic: italic);
    if (runs.isNotEmpty && runs.last._hasSameStyle(run)) {
      runs[runs.length - 1] = runs.last._merge(run);
    } else {
      runs.add(run);
    }
  }
}

/// A visible segment of RenPy dialogue text with active inline styles.
class RenPyTextRun {
  const RenPyTextRun(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  bool _hasSameStyle(RenPyTextRun other) {
    return bold == other.bold && italic == other.italic;
  }

  RenPyTextRun _merge(RenPyTextRun other) {
    assert(_hasSameStyle(other));
    return RenPyTextRun('$text${other.text}', bold: bold, italic: italic);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyTextRun &&
            text == other.text &&
            bold == other.bold &&
            italic == other.italic;
  }

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() {
    final styles = [
      if (bold) 'bold: true',
      if (italic) 'italic: true',
    ].join(', ');
    return styles.isEmpty
        ? "RenPyTextRun('$text')"
        : "RenPyTextRun('$text', $styles)";
  }
}
