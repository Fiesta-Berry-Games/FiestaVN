import 'package:flutter/widgets.dart';
import 'package:renpy_core/renpy_core.dart';

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
    return TextSpan(
      style: style,
      children: [
        for (final run in RenPyStyledText.parse(text).runs) _span(run),
      ],
    );
  }

  static TextSpan _span(RenPyTextRun run) {
    return TextSpan(
      text: run.text,
      style: TextStyle(
        fontWeight: run.bold ? FontWeight.bold : null,
        fontStyle: run.italic ? FontStyle.italic : null,
      ),
    );
  }
}
