import 'package:flutter/material.dart';

const _keywordColor = Color(0xFFFF8A65); // warm orange
const _stringColor = Color(0xFF81C784); // green
const _commentColor = Color(0xFF616161); // dim grey
const _labelColor = Color(0xFFBA68C8); // purple
const _numberColor = Color(0xFF4FC3F7); // cyan

final _tokenPattern = RegExp(
  r'(#[^\n]*)'           // comment
  r'|("(?:[^"\\]|\\.)*"' // double-quoted string
  r"|'(?:[^'\\]|\\.)*')" // single-quoted string
  r'|(\blabel\s+\w+)'    // label definition
  r'|(\b(?:define|default|init|python|screen|style|transform|image|'
  r'show|hide|scene|with|play|stop|queue|pause|menu|jump|call|return|'
  r'if|elif|else|while|for|pass|True|False|None)\b)'
  r'|(\b\d+(?:\.\d+)?\b)', // numbers
);

class SyntaxHighlightController extends TextEditingController {
  SyntaxHighlightController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final source = text;
    if (source.isEmpty) {
      return TextSpan(text: '', style: style);
    }

    final spans = <TextSpan>[];
    var cursor = 0;

    for (final match in _tokenPattern.allMatches(source)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: source.substring(cursor, match.start)));
      }
      final Color color;
      if (match.group(1) != null) {
        color = _commentColor;
      } else if (match.group(2) != null) {
        color = _stringColor;
      } else if (match.group(3) != null) {
        color = _labelColor;
      } else if (match.group(4) != null) {
        color = _keywordColor;
      } else {
        color = _numberColor;
      }
      spans.add(TextSpan(text: match.group(0), style: TextStyle(color: color)));
      cursor = match.end;
    }

    if (cursor < source.length) {
      spans.add(TextSpan(text: source.substring(cursor)));
    }

    return TextSpan(style: style, children: spans);
  }
}
