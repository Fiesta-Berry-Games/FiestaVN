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
    final outlineColor = _parseColor(run.outlineColor);
    return TextSpan(
      text: run.text,
      style: TextStyle(
        color: _parseColor(run.color),
        fontSize: run.size,
        fontFamily: run.font,
        fontWeight: run.bold ? FontWeight.bold : null,
        fontStyle: run.italic ? FontStyle.italic : null,
        shadows: outlineColor == null ? null : _outlineShadows(outlineColor),
      ),
    );
  }

  static List<Shadow> _outlineShadows(Color color) {
    return [
      for (final offset in const [
        Offset(-1, -1),
        Offset(0, -1),
        Offset(1, -1),
        Offset(-1, 0),
        Offset(1, 0),
        Offset(-1, 1),
        Offset(0, 1),
        Offset(1, 1),
      ])
        Shadow(offset: offset, color: color),
    ];
  }

  static Color? _parseColor(String? expression) {
    if (expression == null) return null;

    final value = expression.trim();
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (!RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex) &&
        !RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
      return null;
    }

    final expanded =
        hex.length == 3
            ? hex.split('').map((char) => '$char$char').join()
            : hex;
    final argb = expanded.length == 6 ? 'FF$expanded' : expanded;
    return Color(int.parse(argb, radix: 16));
  }
}
