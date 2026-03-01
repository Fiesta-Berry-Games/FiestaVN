import 'package:flutter/widgets.dart';

/// Renders RenPy inline text tags using Flutter text spans.
class RenPyText extends StatelessWidget {
  const RenPyText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.textScaler,
  });

  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      RenPyTextSpanParser.parse(text, style: style),
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      textScaler: textScaler,
    );
  }
}

/// Converts a RenPy dialogue string into Flutter [TextSpan]s.
class RenPyTextSpanParser {
  const RenPyTextSpanParser._();

  static TextSpan parse(String text, {TextStyle? style}) {
    return TextSpan(style: style, children: _parseChildren(text));
  }

  static List<TextSpan> _parseChildren(String text) {
    final spans = <TextSpan>[];
    var bold = false;
    var italic = false;
    var index = 0;

    for (final match in RegExp(r'\{[^}]+\}').allMatches(text)) {
      if (match.start > index) {
        spans.add(_span(text.substring(index, match.start), bold, italic));
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
      spans.add(_span(text.substring(index), bold, italic));
    }

    return spans.isEmpty ? [TextSpan(text: text)] : spans;
  }

  static TextSpan _span(String value, bool bold, bool italic) {
    return TextSpan(
      text: value,
      style: TextStyle(
        fontWeight: bold ? FontWeight.bold : null,
        fontStyle: italic ? FontStyle.italic : null,
      ),
    );
  }
}
