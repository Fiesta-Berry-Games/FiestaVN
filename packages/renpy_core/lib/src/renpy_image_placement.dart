/// Platform-neutral placement metadata for a RenPy image command.
class RenPyImagePlacement {
  const RenPyImagePlacement.position({
    this.xpos,
    this.ypos,
    this.xanchor,
    this.yanchor,
    this.xalign,
    this.yalign,
    this.xposIsPixel = false,
    this.yposIsPixel = false,
    this.xanchorIsPixel = false,
    this.yanchorIsPixel = false,
  }) : expression = null;

  const RenPyImagePlacement.unsupported(this.expression)
    : xpos = null,
      ypos = null,
      xanchor = null,
      yanchor = null,
      xalign = null,
      yalign = null,
      xposIsPixel = false,
      yposIsPixel = false,
      xanchorIsPixel = false,
      yanchorIsPixel = false;

  final double? xpos;
  final double? ypos;
  final double? xanchor;
  final double? yanchor;
  final double? xalign;
  final double? yalign;
  final bool xposIsPixel;
  final bool yposIsPixel;
  final bool xanchorIsPixel;
  final bool yanchorIsPixel;
  final String? expression;

  bool get isSupported => expression == null;

  static RenPyImagePlacement? parse(String? expression) {
    final value = expression?.trim();
    if (value == null || value.isEmpty) return null;

    final named = _namedPlacements[value];
    if (named != null) return named;

    final position = RegExp(
      r'^Position\s*\((.*)\)(?:\s+behind\s+.+)?$',
    ).firstMatch(value);
    if (position != null) {
      final args = _parseNamedArguments(position.group(1)!);
      final xpos = _positionValue(args['xpos']);
      final ypos = _positionValue(args['ypos']);
      final xanchor = _anchorValue(args['xanchor']);
      final yanchor = _anchorValue(args['yanchor']);
      return RenPyImagePlacement.position(
        xpos: xpos?.value,
        ypos: ypos?.value,
        xanchor: xanchor?.value,
        yanchor: yanchor?.value,
        xalign: _positionValue(args['xalign'])?.value,
        yalign: _positionValue(args['yalign'])?.value,
        xposIsPixel: xpos?.isPixel ?? false,
        yposIsPixel: ypos?.isPixel ?? false,
        xanchorIsPixel: xanchor?.isPixel ?? false,
        yanchorIsPixel: yanchor?.isPixel ?? false,
      );
    }

    return RenPyImagePlacement.unsupported(value);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyImagePlacement &&
            xpos == other.xpos &&
            ypos == other.ypos &&
            xanchor == other.xanchor &&
            yanchor == other.yanchor &&
            xalign == other.xalign &&
            yalign == other.yalign &&
            xposIsPixel == other.xposIsPixel &&
            yposIsPixel == other.yposIsPixel &&
            xanchorIsPixel == other.xanchorIsPixel &&
            yanchorIsPixel == other.yanchorIsPixel &&
            expression == other.expression;
  }

  @override
  int get hashCode {
    return Object.hash(
      xpos,
      ypos,
      xanchor,
      yanchor,
      xalign,
      yalign,
      xposIsPixel,
      yposIsPixel,
      xanchorIsPixel,
      yanchorIsPixel,
      expression,
    );
  }

  @override
  String toString() {
    if (expression != null) {
      return 'RenPyImagePlacement.unsupported($expression)';
    }
    return 'RenPyImagePlacement.position('
        'xpos: $xpos, ypos: $ypos, xanchor: $xanchor, '
        'yanchor: $yanchor, xalign: $xalign, yalign: $yalign, '
        'xposIsPixel: $xposIsPixel, yposIsPixel: $yposIsPixel, '
        'xanchorIsPixel: $xanchorIsPixel, '
        'yanchorIsPixel: $yanchorIsPixel)';
  }
}

const _namedPlacements = {
  'left': RenPyImagePlacement.position(
    xpos: 0,
    xanchor: 0,
    ypos: 1,
    yanchor: 1,
  ),
  'right': RenPyImagePlacement.position(
    xpos: 1,
    xanchor: 1,
    ypos: 1,
    yanchor: 1,
  ),
  'center': RenPyImagePlacement.position(
    xpos: 0.5,
    xanchor: 0.5,
    ypos: 1,
    yanchor: 1,
  ),
  'truecenter': RenPyImagePlacement.position(
    xpos: 0.5,
    xanchor: 0.5,
    ypos: 0.5,
    yanchor: 0.5,
  ),
  'topleft': RenPyImagePlacement.position(
    xpos: 0,
    xanchor: 0,
    ypos: 0,
    yanchor: 0,
  ),
  'topright': RenPyImagePlacement.position(
    xpos: 1,
    xanchor: 1,
    ypos: 0,
    yanchor: 0,
  ),
  'top': RenPyImagePlacement.position(
    xpos: 0.5,
    xanchor: 0.5,
    ypos: 0,
    yanchor: 0,
  ),
  'offscreenleft': RenPyImagePlacement.position(
    xpos: 0,
    xanchor: 1,
    ypos: 1,
    yanchor: 1,
  ),
  'offscreenright': RenPyImagePlacement.position(
    xpos: 1,
    xanchor: 0,
    ypos: 1,
    yanchor: 1,
  ),
};

Map<String, String> _parseNamedArguments(String source) {
  final values = <String, String>{};
  for (final argument in _splitTopLevel(source)) {
    final equals = argument.indexOf('=');
    if (equals <= 0) continue;
    values[argument.substring(0, equals).trim()] =
        argument.substring(equals + 1).trim();
  }
  return values;
}

List<String> _splitTopLevel(String source) {
  final parts = <String>[];
  final buffer = StringBuffer();
  String? quote;

  for (var i = 0; i < source.length; i += 1) {
    final char = source[i];
    if (quote != null) {
      buffer.write(char);
      if (char == quote) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      buffer.write(char);
      continue;
    }
    if (char == ',') {
      parts.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) parts.add(tail);
  return parts;
}

_PlacementValue? _positionValue(String? value) {
  if (value == null) return null;
  final clean = value.trim();
  final normalized = clean.startsWith('.') ? '0$clean' : clean;
  final parsed = double.tryParse(normalized);
  if (parsed == null) return null;
  return _PlacementValue(parsed, _isIntegerLiteral(clean));
}

_PlacementValue? _anchorValue(String? value) {
  final clean = value?.trim();
  if (clean == null) return null;
  return switch (clean.replaceAll('"', "'")) {
    "'left'" || "'top'" => const _PlacementValue(0, false),
    "'center'" || "'truecenter'" => const _PlacementValue(0.5, false),
    "'right'" || "'bottom'" => const _PlacementValue(1, false),
    _ => _positionValue(clean),
  };
}

bool _isIntegerLiteral(String value) {
  return RegExp(r'^[-+]?\d+$').hasMatch(value.trim());
}

class _PlacementValue {
  const _PlacementValue(this.value, this.isPixel);

  final double value;
  final bool isPixel;
}
