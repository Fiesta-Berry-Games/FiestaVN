import 'dart:math' as math;

import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_python.dart';

/// The animatable transform state produced by an [RenPyAtlProgram] at a given
/// time. Every field is nullable; a null value means the ATL program never
/// touches that property and the renderer should fall back to its own default.
///
/// Positions follow RenPy's convention: `xpos`/`ypos` are fractions of the
/// stage (0..1) unless [xposIsPixel]/[yposIsPixel] is set, in which case they
/// are pixels in RenPy's virtual resolution. `xalign`/`yalign` set both the
/// position and the anchor to the same fraction. `xoffset`/`yoffset` are pixel
/// nudges applied after positioning.
class RenPyAtlState {
  const RenPyAtlState({
    this.xpos,
    this.ypos,
    this.xanchor,
    this.yanchor,
    this.xalign,
    this.yalign,
    this.xposIsPixel = false,
    this.yposIsPixel = false,
    this.zoom,
    this.xzoom,
    this.yzoom,
    this.rotate,
    this.alpha,
    this.xoffset,
    this.yoffset,
    this.cropLeft,
    this.cropTop,
    this.cropWidth,
    this.cropHeight,
  });

  final double? xpos;
  final double? ypos;
  final double? xanchor;
  final double? yanchor;
  final double? xalign;
  final double? yalign;
  final bool xposIsPixel;
  final bool yposIsPixel;
  final double? zoom;
  final double? xzoom;
  final double? yzoom;

  /// Rotation in degrees, matching RenPy's `rotate`.
  final double? rotate;
  final double? alpha;
  final double? xoffset;
  final double? yoffset;

  /// `crop (l, t, w, h)` rectangle, as fractions of the source unless larger
  /// than 1, in which case they are pixels. Null when no crop is applied.
  final double? cropLeft;
  final double? cropTop;
  final double? cropWidth;
  final double? cropHeight;

  bool get hasCrop =>
      cropLeft != null &&
      cropTop != null &&
      cropWidth != null &&
      cropHeight != null;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyAtlState &&
            xpos == other.xpos &&
            ypos == other.ypos &&
            xanchor == other.xanchor &&
            yanchor == other.yanchor &&
            xalign == other.xalign &&
            yalign == other.yalign &&
            xposIsPixel == other.xposIsPixel &&
            yposIsPixel == other.yposIsPixel &&
            zoom == other.zoom &&
            xzoom == other.xzoom &&
            yzoom == other.yzoom &&
            rotate == other.rotate &&
            alpha == other.alpha &&
            xoffset == other.xoffset &&
            yoffset == other.yoffset &&
            cropLeft == other.cropLeft &&
            cropTop == other.cropTop &&
            cropWidth == other.cropWidth &&
            cropHeight == other.cropHeight;
  }

  @override
  int get hashCode => Object.hash(
    xpos,
    ypos,
    xanchor,
    yanchor,
    xalign,
    yalign,
    xposIsPixel,
    yposIsPixel,
    zoom,
    xzoom,
    Object.hash(
      yzoom,
      rotate,
      alpha,
      xoffset,
      yoffset,
      cropLeft,
      cropTop,
      cropWidth,
      cropHeight,
    ),
  );

  @override
  String toString() {
    return 'RenPyAtlState(xpos: $xpos, ypos: $ypos, xalign: $xalign, '
        'yalign: $yalign, zoom: $zoom, xzoom: $xzoom, yzoom: $yzoom, '
        'rotate: $rotate, alpha: $alpha, xoffset: $xoffset, '
        'yoffset: $yoffset)';
  }
}

/// The set of property names this runtime knows how to interpolate.
const _animatableProperties = <String>{
  'xpos',
  'ypos',
  'pos',
  'xanchor',
  'yanchor',
  'anchor',
  'xalign',
  'yalign',
  'align',
  'zoom',
  'xzoom',
  'yzoom',
  'rotate',
  'alpha',
  'xoffset',
  'yoffset',
  'offset',
  'crop',
  'xcenter',
  'ycenter',
};

/// Maps a RenPy warper name to its eased progress. [t] is the linear progress
/// in `0..1`; the return value is the warped progress used to interpolate.
///
/// `linear` is the identity. `ease` is a smooth in-out cosine, `easein` and
/// `easeout` are the corresponding one-sided cosine curves, matching RenPy's
/// built-in warpers closely enough for playback. Unknown warpers fall back to
/// linear.
double warp(String? warper, double t) {
  final clamped = t.clamp(0.0, 1.0).toDouble();
  switch (warper) {
    case null:
    case 'linear':
      return clamped;
    case 'ease':
      return 0.5 - 0.5 * math.cos(math.pi * clamped);
    case 'easein':
    case 'easein_quad':
      // Slow start, accelerating to the target.
      return 1.0 - math.cos(clamped * math.pi / 2);
    case 'easeout':
    case 'easeout_quad':
      // Fast start, decelerating into the target.
      return math.sin(clamped * math.pi / 2);
    default:
      return clamped;
  }
}

/// A compiled ATL transform program.
///
/// Construct it from the parser's [RenPyAtlNode] list plus a [scope] used to
/// evaluate property target expressions (numbers, `0.5`, `1.0 - x`, ...). The
/// program flattens the ATL nodes into a per-property keyframe timeline so that
/// [transformAt] can answer the interpolated [RenPyAtlState] for any time.
///
/// Supported nodes: bare property assignments, warper interpolations
/// (`linear`/`ease`/`easein`/`easeout`), `pause`, `repeat`, `block:`, and
/// `parallel:` (children run on independent clocks and their property tracks
/// are merged). `choice` picks its first branch. `on`/`contains`/`raw` nodes
/// are ignored. Anything that cannot be evaluated degrades to leaving that
/// property untouched rather than throwing.
class RenPyAtlProgram {
  RenPyAtlProgram._(this._tracks, this._duration);

  /// Compiles [nodes] into a program. [scope] resolves property expressions;
  /// pass null to only handle plain numeric literals.
  factory RenPyAtlProgram.compile(
    List<RenPyAtlNode> nodes, {
    RenPyPythonScope? scope,
  }) {
    final builder = _TimelineBuilder(scope);
    builder.runProgram(nodes);
    final total = builder.infinite ? double.infinity : builder.cursor;
    return RenPyAtlProgram._(builder.tracks, total);
  }

  /// True when [nodes] contains nothing this runtime can animate, so callers
  /// can cheaply skip building an animation and keep a static placement.
  static bool isAnimatable(List<RenPyAtlNode> nodes) {
    for (final node in nodes) {
      switch (node.nodeKind) {
        case RenPyAtlNodeKind.interpolation:
        case RenPyAtlNodeKind.pause:
        case RenPyAtlNodeKind.repeat:
          return true;
        case RenPyAtlNodeKind.block:
        case RenPyAtlNodeKind.parallel:
        case RenPyAtlNodeKind.choice:
        case RenPyAtlNodeKind.on:
          if (isAnimatable(node.children)) return true;
        case RenPyAtlNodeKind.property:
        case RenPyAtlNodeKind.contains:
        case RenPyAtlNodeKind.raw:
          break;
      }
    }
    return false;
  }

  final Map<String, _Track> _tracks;
  final double _duration;

  /// The finite duration of the program in seconds, or null when it loops
  /// forever (an unbounded `repeat`).
  double? get duration => _duration.isFinite ? _duration : null;

  /// Whether the program has finished animating at time [t]. An infinitely
  /// repeating program is never complete.
  bool isComplete(double t) {
    final d = duration;
    if (d == null) return false;
    return t >= d;
  }

  /// The interpolated transform state at time [t] seconds since the program
  /// started.
  RenPyAtlState transformAt(double t) {
    final time = t < 0 ? 0.0 : t;
    double? value(String name) => _tracks[name]?.valueAt(time);

    final align = _tracks['align'];
    final pos = _tracks['pos'];
    final anchor = _tracks['anchor'];
    final offset = _tracks['offset'];

    final xalign = value('xalign') ?? align?.valueAt(time);
    final yalign = value('yalign') ?? align?.valueAt(time);
    final xpos = value('xpos') ?? value('xcenter') ?? pos?.valueAt(time);
    final ypos = value('ypos') ?? value('ycenter') ?? pos?.valueAt(time);
    final xanchor = value('xanchor') ?? anchor?.valueAt(time);
    final yanchor = value('yanchor') ?? anchor?.valueAt(time);
    final xoffset = value('xoffset') ?? offset?.valueAt(time);
    final yoffset = value('yoffset') ?? offset?.valueAt(time);

    final xposPixel = _tracks['xpos']?.isPixel ?? pos?.isPixel ?? false;
    final yposPixel = _tracks['ypos']?.isPixel ?? pos?.isPixel ?? false;

    final crop = _tracks['crop'];

    return RenPyAtlState(
      xpos: xpos,
      ypos: ypos,
      xanchor: xanchor,
      yanchor: yanchor,
      xalign: xalign,
      yalign: yalign,
      xposIsPixel: xposPixel,
      yposIsPixel: yposPixel,
      zoom: value('zoom'),
      xzoom: value('xzoom'),
      yzoom: value('yzoom'),
      rotate: value('rotate'),
      alpha: value('alpha'),
      xoffset: xoffset,
      yoffset: yoffset,
      cropLeft: crop?.crop?[0],
      cropTop: crop?.crop?[1],
      cropWidth: crop?.crop?[2],
      cropHeight: crop?.crop?[3],
    );
  }
}

/// One animatable property's keyframe timeline.
class _Track {
  final List<_Keyframe> keyframes = [];
  bool isPixel = false;
  List<double>? crop;

  bool get isEmpty => keyframes.isEmpty;

  void setStart(double time, double? value) {
    // A bare assignment becomes an instant keyframe (snap) at [time].
    keyframes.add(_Keyframe(time: time, value: value, warper: null));
  }

  void interpolate(double endTime, double? value, String? warper) {
    keyframes.add(_Keyframe(time: endTime, value: value, warper: warper));
  }

  /// Pins a holding keyframe at [time] carrying the current last value, so a
  /// gap (a `pause`) since the last keyframe holds rather than stretching the
  /// next interpolation's start back to the previous keyframe.
  void holdUntil(double time) {
    if (keyframes.isEmpty) return;
    final last = keyframes.last;
    if (time > last.time) {
      keyframes.add(_Keyframe(time: time, value: last.value, warper: null));
    }
  }

  double? valueAt(double time) {
    if (keyframes.isEmpty) return null;
    if (time <= keyframes.first.time) return keyframes.first.value;

    // The active segment is the last keyframe whose time is <= [time]. Picking
    // the last (not the first) keeps a same-time snap - e.g. a repeat wrapping
    // back to its start - taking precedence over the prior segment's end.
    var segment = 0;
    for (var i = 0; i < keyframes.length; i += 1) {
      if (keyframes[i].time <= time) {
        segment = i;
      } else {
        break;
      }
    }

    if (segment >= keyframes.length - 1) return keyframes.last.value;

    final prev = keyframes[segment];
    final next = keyframes[segment + 1];
    final span = next.time - prev.time;
    if (span <= 0 || next.warper == null) {
      return time >= next.time ? next.value : prev.value;
    }
    final from = prev.value;
    final to = next.value;
    if (from == null || to == null) return to ?? from;
    final progress = warp(next.warper, (time - prev.time) / span);
    return from + (to - from) * progress;
  }
}

class _Keyframe {
  const _Keyframe({required this.time, required this.value, this.warper});

  final double time;
  final double? value;

  /// The warper interpolating into this keyframe from the previous one; null
  /// for an instant snap.
  final String? warper;
}

/// Walks the ATL node list, accumulating per-property keyframe tracks and a
/// running clock [cursor].
class _TimelineBuilder {
  _TimelineBuilder(this._scope);

  static const _evaluator = RenPyPythonEvaluator();

  final RenPyPythonScope? _scope;
  final Map<String, _Track> tracks = {};
  double cursor = 0;

  /// Set when an unbounded `repeat` is expanded: the program loops forever, so
  /// [RenPyAtlProgram.duration] is reported as infinite even though the built
  /// keyframe timeline is finite (a few sampled cycles).
  bool infinite = false;

  _Track _track(String name) => tracks.putIfAbsent(name, _Track.new);

  /// Entry point: runs the whole node list, honoring a top-level trailing
  /// `repeat`.
  void runProgram(List<RenPyAtlNode> nodes) {
    _runBlockChildren(nodes);
  }

  void run(List<RenPyAtlNode> nodes) {
    var i = 0;
    while (i < nodes.length) {
      // Consecutive `parallel:` siblings start together from the same clock and
      // the group ends at the latest branch, matching RenPy.
      if (nodes[i].nodeKind == RenPyAtlNodeKind.parallel) {
        final start = cursor;
        var maxEnd = start;
        while (i < nodes.length &&
            nodes[i].nodeKind == RenPyAtlNodeKind.parallel) {
          cursor = start;
          run(nodes[i].children);
          if (cursor > maxEnd) maxEnd = cursor;
          i += 1;
        }
        cursor = maxEnd;
        continue;
      }
      _runNode(nodes[i]);
      i += 1;
    }
  }

  void _runNode(RenPyAtlNode node) {
    switch (node.nodeKind) {
      case RenPyAtlNodeKind.property:
        for (final entry in node.properties.entries) {
          _assignInstant(entry.key, entry.value);
        }
      case RenPyAtlNodeKind.interpolation:
        _runInterpolation(node);
      case RenPyAtlNodeKind.pause:
        final d = _evalDuration(node.duration) ?? 0;
        cursor += d;
      case RenPyAtlNodeKind.repeat:
        // Repeat is handled by the enclosing block builder; a top-level repeat
        // with no surrounding block loops the whole program. It is expanded in
        // [_runBlockChildren]; encountered standalone it has no body to repeat.
        break;
      case RenPyAtlNodeKind.block:
      case RenPyAtlNodeKind.parallel:
        _runBlockChildren(node.children);
      case RenPyAtlNodeKind.choice:
        if (node.children.isNotEmpty) {
          _runBlockChildren(node.children);
        }
      case RenPyAtlNodeKind.on:
      case RenPyAtlNodeKind.contains:
      case RenPyAtlNodeKind.raw:
        break;
    }
  }

  /// Runs a child list, honoring a trailing `repeat` by replaying the children
  /// from the block's start time. Caps the expansion so an unbounded repeat
  /// produces a finite, looping timeline of a few cycles while reporting an
  /// infinite duration so [RenPyAtlProgram.isComplete] never finishes.
  void _runBlockChildren(List<RenPyAtlNode> children) {
    final repeatIndex = children.lastIndexWhere(
      (c) => c.nodeKind == RenPyAtlNodeKind.repeat,
    );

    if (repeatIndex < 0) {
      run(children);
      return;
    }

    final body = children.sublist(0, repeatIndex);
    final repeatNode = children[repeatIndex];
    final count = _evalDuration(repeatNode.repeatCount);

    if (count == null) {
      // Unbounded repeat: build a few cycles for sampling and mark infinite so
      // the program never reports completion.
      const cycles = 4;
      for (var i = 0; i < cycles; i += 1) {
        run(body);
      }
      infinite = true;
      return;
    }

    final repeats = count.round().clamp(0, 1000);
    for (var i = 0; i < repeats; i += 1) {
      run(body);
    }
  }

  void _runInterpolation(RenPyAtlNode node) {
    final d = _evalDuration(node.duration) ?? 0;
    final endTime = cursor + d;
    for (final entry in node.properties.entries) {
      _interpolateProperty(entry.key, entry.value, endTime, node.warper);
    }
    cursor = endTime;
  }

  void _assignInstant(String name, String expression) {
    for (final assignment in _expand(name, expression)) {
      final track = _track(assignment.property);
      if (assignment.crop != null) {
        track.crop = assignment.crop;
        track.setStart(cursor, 0);
        continue;
      }
      track.isPixel = track.isPixel || assignment.isPixel;
      // Seed the previous segment value if the track is empty so a later
      // interpolation has a defined start.
      track.setStart(cursor, assignment.value);
    }
  }

  void _interpolateProperty(
    String name,
    String expression,
    double endTime,
    String? warper,
  ) {
    for (final assignment in _expand(name, expression)) {
      final track = _track(assignment.property);
      if (assignment.crop != null) {
        track.crop = assignment.crop;
        track.interpolate(endTime, 0, warper);
        continue;
      }
      track.isPixel = track.isPixel || assignment.isPixel;
      if (track.isEmpty) {
        // No prior start: RenPy interpolates from the property's current value,
        // which for an untouched property is its default (0 for most, 1 for
        // zoom/alpha). Seed that so the tween animates rather than snapping.
        track.setStart(cursor, _defaultFor(assignment.property));
      } else {
        // A gap since the last keyframe (e.g. a `pause`) holds the value; pin a
        // holding keyframe at the cursor so the tween starts from here, not the
        // previous keyframe's time.
        track.holdUntil(cursor);
      }
      track.interpolate(endTime, assignment.value, warper);
    }
  }

  /// Expands a property name into one or more concrete track assignments. `pos`
  /// / `align` / `anchor` / `offset` accept either a scalar (rare) or a tuple
  /// `(x, y)`; `crop` accepts a 4-tuple.
  List<_Assignment> _expand(String name, String expression) {
    if (!_animatableProperties.contains(name)) return const [];

    if (name == 'crop') {
      final values = _evalTuple(expression);
      if (values == null || values.length < 4) return const [];
      return [
        _Assignment(property: 'crop', value: 0, crop: values.sublist(0, 4)),
      ];
    }

    if (name == 'pos' ||
        name == 'align' ||
        name == 'anchor' ||
        name == 'offset') {
      final values = _evalTuple(expression);
      if (values == null) return const [];
      if (values.length == 1) {
        return [_Assignment(property: name, value: values[0])];
      }
      final isPixel =
          name == 'offset' ||
          (name == 'pos' && (_looksPixel(values[0]) || _looksPixel(values[1])));
      return [
        _Assignment(
          property: 'x${_axisName(name)}',
          value: values[0],
          isPixel: name == 'offset' ? false : isPixel,
        ),
        _Assignment(
          property: 'y${_axisName(name)}',
          value: values[1],
          isPixel: name == 'offset' ? false : isPixel,
        ),
      ];
    }

    final value = _evalNumber(expression);
    if (value == null) return const [];
    final isPixel =
        (name == 'xpos' || name == 'ypos') && _isIntegerLiteral(expression);
    final property = switch (name) {
      'xcenter' => 'xpos',
      'ycenter' => 'ypos',
      _ => name,
    };
    return [_Assignment(property: property, value: value, isPixel: isPixel)];
  }

  String _axisName(String name) => switch (name) {
    'pos' => 'pos',
    'align' => 'align',
    'anchor' => 'anchor',
    'offset' => 'offset',
    _ => name,
  };

  bool _looksPixel(double value) => value > 1 || value < 0;

  /// RenPy's default starting value for an untouched property, used to seed an
  /// interpolation that has no explicit prior assignment.
  double _defaultFor(String property) => switch (property) {
    'zoom' || 'xzoom' || 'yzoom' || 'alpha' => 1,
    _ => 0,
  };

  double? _evalDuration(String? expression) => _evalNumber(expression);

  double? _evalNumber(String? expression) {
    final clean = expression?.trim();
    if (clean == null || clean.isEmpty) return null;
    final direct = double.tryParse(clean.startsWith('.') ? '0$clean' : clean);
    if (direct != null) return direct;

    final scope = _scope;
    if (scope == null) return null;
    try {
      final result = _evaluator.evaluate(clean, scope);
      if (result is num) return result.toDouble();
      if (result is bool) return result ? 1 : 0;
    } catch (_) {
      // Fall through: unevaluable expressions leave the property untouched.
    }
    return null;
  }

  List<double>? _evalTuple(String expression) {
    final trimmed = expression.trim();
    final inner =
        trimmed.startsWith('(') && trimmed.endsWith(')')
            ? trimmed.substring(1, trimmed.length - 1)
            : trimmed;
    final parts = _splitTopLevel(inner);
    final values = <double>[];
    for (final part in parts) {
      final v = _evalNumber(part);
      if (v == null) return null;
      values.add(v);
    }
    return values.isEmpty ? null : values;
  }

  bool _isIntegerLiteral(String value) =>
      RegExp(r'^[-+]?\d+$').hasMatch(value.trim());

  List<String> _splitTopLevel(String source) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
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
      if (char == '(' || char == '[' || char == '{') depth += 1;
      if (char == ')' || char == ']' || char == '}') depth -= 1;
      if (char == ',' && depth == 0) {
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
}

class _Assignment {
  const _Assignment({
    required this.property,
    required this.value,
    this.isPixel = false,
    this.crop,
  });

  final String property;
  final double value;
  final bool isPixel;
  final List<double>? crop;
}
