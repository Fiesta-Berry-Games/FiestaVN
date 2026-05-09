import 'dart:async';

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

  /// Builds spans for [text] revealing only the first [visibleCharacters]
  /// glyphs while preserving inline styling of the revealed portion.
  static TextSpan parsePartial(
    String text,
    int visibleCharacters, {
    TextStyle? style,
  }) {
    final children = <TextSpan>[];
    var remaining = visibleCharacters;
    for (final run in RenPyStyledText.parse(text).runs) {
      if (remaining <= 0) break;
      if (run.text.length <= remaining) {
        children.add(_span(run));
        remaining -= run.text.length;
      } else {
        children.add(_span(run, override: run.text.substring(0, remaining)));
        remaining = 0;
      }
    }
    return TextSpan(style: style, children: children);
  }

  /// Total number of visible characters in [text] once tags are removed.
  static int visibleLength(String text) {
    return RenPyStyledText.parse(text).plainText.length;
  }

  static TextSpan _span(RenPyTextRun run, {String? override}) {
    final outlineColor = _parseColor(run.outlineColor);
    return TextSpan(
      text: override ?? run.text,
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

/// Drives a [RenPyTextReveal], letting an ancestor force the line complete.
class RenPyTextRevealController extends ChangeNotifier {
  bool _complete = false;

  /// Whether the current line has finished revealing.
  bool get isComplete => _complete;

  void _setComplete(bool value) {
    if (_complete == value) return;
    _complete = value;
    notifyListeners();
  }

  /// Requests the bound [RenPyTextReveal] reveal the full line immediately.
  void complete() => _setComplete(true);

  void _reset() => _setComplete(false);
}

/// Renders RenPy dialogue with an optional typewriter reveal driven by a
/// characters-per-second rate. A rate of zero (or less) shows the full line at
/// once. Tapping while revealing should call [RenPyTextRevealController.complete]
/// to finish the line before advancing.
class RenPyTextReveal extends StatefulWidget {
  const RenPyTextReveal(
    this.text, {
    super.key,
    required this.cps,
    this.controller,
    this.onRevealed,
    this.style,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.textScaler,
  });

  final String text;

  /// Characters revealed per second; zero or less reveals instantly.
  final double cps;

  final RenPyTextRevealController? controller;

  /// Called once the line is fully revealed (immediately when instant).
  final VoidCallback? onRevealed;

  final TextStyle? style;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextScaler? textScaler;

  @override
  State<RenPyTextReveal> createState() => _RenPyTextRevealState();
}

class _RenPyTextRevealState extends State<RenPyTextReveal> {
  Timer? _timer;
  int _visible = 0;
  late int _total;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
    _start();
  }

  @override
  void didUpdateWidget(RenPyTextReveal oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
    if (oldWidget.text != widget.text || oldWidget.cps != widget.cps) {
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    _total = RenPyTextSpanParser.visibleLength(widget.text);
    widget.controller?._reset();

    if (widget.cps <= 0 || _total == 0) {
      _visible = _total;
      _finish();
      return;
    }

    _visible = 0;
    final interval = Duration(
      microseconds: (1000000 / widget.cps).round().clamp(1, 1000000),
    );
    _timer = Timer.periodic(interval, (_) {
      if (!mounted) return;
      setState(() => _visible += 1);
      if (_visible >= _total) _finish();
    });
  }

  void _finish() {
    _timer?.cancel();
    _timer = null;
    if (_visible != _total) {
      // Defer the rebuild when called from initState's instant path.
      _visible = _total;
    }
    widget.controller?._setComplete(true);
    widget.onRevealed?.call();
  }

  void _onControllerChanged() {
    if (widget.controller?.isComplete != true) return;
    if (_visible >= _total && _timer == null) return;
    setState(() => _visible = _total);
    _finish();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Once fully revealed, defer to [RenPyText] so callers can still inspect
    // the rendered style through the widget tree.
    if (_visible >= _total) {
      return RenPyText(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        textDirection: widget.textDirection,
        softWrap: widget.softWrap,
        overflow: widget.overflow,
        maxLines: widget.maxLines,
        textScaler: widget.textScaler,
      );
    }

    return Text.rich(
      RenPyTextSpanParser.parsePartial(
        widget.text,
        _visible,
        style: widget.style,
      ),
      textAlign: widget.textAlign,
      textDirection: widget.textDirection,
      softWrap: widget.softWrap,
      overflow: widget.overflow,
      maxLines: widget.maxLines,
      textScaler: widget.textScaler,
    );
  }
}
