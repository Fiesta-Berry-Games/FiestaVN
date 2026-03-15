/// Platform-neutral placement metadata for a RenPy image command.
class RenPyImagePlacement {
  const RenPyImagePlacement.position({
    this.xpos,
    this.ypos,
    this.xanchor,
    this.yanchor,
    this.xalign,
    this.yalign,
  }) : expression = null;

  const RenPyImagePlacement.unsupported(this.expression)
    : xpos = null,
      ypos = null,
      xanchor = null,
      yanchor = null,
      xalign = null,
      yalign = null;

  final double? xpos;
  final double? ypos;
  final double? xanchor;
  final double? yanchor;
  final double? xalign;
  final double? yalign;
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
      return RenPyImagePlacement.position(
        xpos: _positionValue(args['xpos']),
        ypos: _positionValue(args['ypos']),
        xanchor: _anchorValue(args['xanchor']),
        yanchor: _anchorValue(args['yanchor']),
        xalign: _positionValue(args['xalign']),
        yalign: _positionValue(args['yalign']),
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
        'yanchor: $yanchor, xalign: $xalign, yalign: $yalign)';
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

double? _positionValue(String? value) {
  if (value == null) return null;
  final clean = value.trim();
  return double.tryParse(clean.startsWith('.') ? '0$clean' : clean);
}

double? _anchorValue(String? value) {
  final clean = value?.trim();
  if (clean == null) return null;
  return switch (clean.replaceAll('"', "'")) {
    "'left'" || "'top'" => 0,
    "'center'" || "'truecenter'" => 0.5,
    "'right'" || "'bottom'" => 1,
    _ => _positionValue(clean),
  };
}
