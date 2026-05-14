import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_transition_intent.dart';

/// Resolves RenPy transition names to platform-neutral transition intent.
class RenPyTransitionResolver {
  RenPyTransitionResolver({
    Map<String, RenPyTransitionIntent> transitions = const {},
  }) : transitions = Map.unmodifiable({..._builtInTransitions, ...transitions});

  factory RenPyTransitionResolver.fromScript(RenPyScript script) {
    return RenPyTransitionResolver(transitions: definitionsFor(script));
  }

  static Map<String, RenPyTransitionIntent> definitionsFor(RenPyScript script) {
    final definitions = <String, RenPyTransitionIntent>{};

    void addDefinition(RenPyDefineStatement define) {
      final intent = parseExpression(define.expression);
      if (intent == null) return;
      definitions[define.name] = intent;
    }

    void scan(List<RenPyStatement> statements) {
      for (final statement in statements) {
        if (statement is RenPyDefineStatement) {
          addDefinition(statement);
        } else if (statement is RenPyInitStatement) {
          scan(statement.block);
        }
      }
    }

    scan(script.statements);
    return definitions;
  }

  static RenPyTransitionIntent? parseExpression(String expression) {
    final value = expression.trim();
    if (_noneNames.contains(value)) return const RenPyTransitionIntent.none();

    final fade = RegExp(
      r'''^Fade\s*\(\s*([^,]+)\s*,\s*([^,]+)\s*,\s*([^,\)]+)(?:,\s*color\s*=\s*["']([^"']+)["'])?''',
    ).firstMatch(value);
    if (fade != null) {
      final outTime = _parseDouble(fade.group(1));
      final holdTime = _parseDouble(fade.group(2));
      final inTime = _parseDouble(fade.group(3));
      if (outTime == null || holdTime == null || inTime == null) {
        return RenPyTransitionIntent.unsupported(expression: value);
      }
      return RenPyTransitionIntent.fade(
        outTime: outTime,
        holdTime: holdTime,
        inTime: inTime,
        color: fade.group(4),
      );
    }

    final dissolve = RegExp(r'^Dissolve\s*\(\s*([^,\)]+)').firstMatch(value);
    if (dissolve != null) {
      final duration = _parseDouble(dissolve.group(1));
      if (duration == null) {
        return RenPyTransitionIntent.unsupported(expression: value);
      }
      return RenPyTransitionIntent.dissolve(duration: duration);
    }

    final imageDissolve = RegExp(
      r'''^ImageDissolve\s*\(\s*(?:im\.Tile\s*\(\s*)?["']([^"']+)["']\)?\s*,\s*([^,\)]+)''',
    ).firstMatch(value);
    if (imageDissolve != null) {
      final duration = _parseDouble(imageDissolve.group(2));
      if (duration == null) {
        return RenPyTransitionIntent.unsupported(expression: value);
      }
      return RenPyTransitionIntent.imageDissolve(
        maskAsset: imageDissolve.group(1)!,
        duration: duration,
        ramplen:
            _parseNamedInteger(value, 'ramplen') ?? _parseThirdInteger(value),
        reverse: _parseNamedBool(value, 'reverse') ?? false,
      );
    }

    final cropMove = RegExp(
      r'''^CropMove\s*\(\s*([^,]+)\s*,\s*["']([^"']+)["']''',
    ).firstMatch(value);
    if (cropMove != null) {
      final duration = _parseDouble(cropMove.group(1));
      if (duration == null) {
        return RenPyTransitionIntent.unsupported(expression: value);
      }
      return RenPyTransitionIntent.cropMove(
        duration: duration,
        mode: cropMove.group(2)!,
      );
    }

    // `Pixellate(time, steps)` - approximate as a same-duration dissolve.
    final pixellate = RegExp(r'^Pixellate\s*\(\s*([^,\)]+)').firstMatch(value);
    if (pixellate != null) {
      final duration = _parseDouble(pixellate.group(1));
      if (duration == null) {
        return RenPyTransitionIntent.unsupported(expression: value);
      }
      return RenPyTransitionIntent.dissolve(duration: duration);
    }

    // `MoveTransition(time, ...)` / `MoveIn*` / `MoveOut*` family - approximate
    // as a same-duration dissolve so the change is still visibly animated.
    final moveTransition = RegExp(
      r'^(?:MoveTransition|MoveIn\w*|MoveOut\w*|OldMoveTransition)\s*\(\s*([^,\)]+)',
    ).firstMatch(value);
    if (moveTransition != null) {
      final duration = _parseDouble(moveTransition.group(1));
      if (duration == null) {
        return RenPyTransitionIntent.unsupported(expression: value);
      }
      return RenPyTransitionIntent.dissolve(duration: duration);
    }

    if (_looksLikeTransitionExpression(value)) {
      return RenPyTransitionIntent.unsupported(expression: value);
    }
    return null;
  }

  final Map<String, RenPyTransitionIntent> transitions;

  RenPyTransitionResolver withDefinition(String name, String expression) {
    final intent = parseExpression(expression);
    if (intent == null) return this;
    return RenPyTransitionResolver(transitions: {...transitions, name: intent});
  }

  RenPyTransitionIntent? resolve(String? transitionName) {
    final clean = transitionName?.trim();
    if (clean == null || clean.isEmpty) return null;
    return transitions[clean] ?? parseExpression(clean);
  }
}

const _noneNames = {'None', 'none', 'null'};

const _builtInTransitions = {
  'None': RenPyTransitionIntent.none(),
  'none': RenPyTransitionIntent.none(),
  'fade': RenPyTransitionIntent.fade(outTime: 0.5, holdTime: 0, inTime: 0.5),
  'dissolve': RenPyTransitionIntent.dissolve(duration: 0.5),
  'wiperight': RenPyTransitionIntent.cropMove(duration: 1.0, mode: 'wiperight'),
  'wipeleft': RenPyTransitionIntent.cropMove(duration: 1.0, mode: 'wipeleft'),
  'wipeup': RenPyTransitionIntent.cropMove(duration: 1.0, mode: 'wipeup'),
  'wipedown': RenPyTransitionIntent.cropMove(duration: 1.0, mode: 'wipedown'),
  'vpunch': RenPyTransitionIntent.punch(mode: 'vertical', duration: 0.275),
  'hpunch': RenPyTransitionIntent.punch(mode: 'horizontal', duration: 0.275),
  'pixellate': RenPyTransitionIntent.dissolve(duration: 0.5),
  'slideright': RenPyTransitionIntent.cropMove(
    duration: 0.5,
    mode: 'slideright',
  ),
  'slideleft': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'slideleft'),
  'slideup': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'slideup'),
  'slidedown': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'slidedown'),
  'moveinright': RenPyTransitionIntent.cropMove(
    duration: 0.5,
    mode: 'slideright',
  ),
  'moveinleft': RenPyTransitionIntent.cropMove(
    duration: 0.5,
    mode: 'slideleft',
  ),
  'moveintop': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'slideup'),
  'moveinbottom': RenPyTransitionIntent.cropMove(
    duration: 0.5,
    mode: 'slidedown',
  ),
  'pushright': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'pushright'),
  'pushleft': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'pushleft'),
  'pushup': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'pushup'),
  'pushdown': RenPyTransitionIntent.cropMove(duration: 0.5, mode: 'pushdown'),
  'zoomin': RenPyTransitionIntent.dissolve(duration: 0.5),
  'zoomout': RenPyTransitionIntent.dissolve(duration: 0.5),
  'zoominout': RenPyTransitionIntent.dissolve(duration: 0.5),
};

double? _parseDouble(String? value) {
  final clean = value?.trim();
  if (clean == null || clean.isEmpty) return null;
  return double.tryParse(clean.startsWith('.') ? '0$clean' : clean);
}

int? _parseNamedInteger(String expression, String name) {
  final match = RegExp('$name\\s*=\\s*(\\d+)').firstMatch(expression);
  return int.tryParse(match?.group(1) ?? '');
}

int? _parseThirdInteger(String expression) {
  final args = _topLevelArguments(expression);
  if (args.length < 3) return null;
  return int.tryParse(args[2].trim());
}

bool? _parseNamedBool(String expression, String name) {
  final match = RegExp(
    '$name\\s*=\\s*(True|False|true|false)',
  ).firstMatch(expression);
  final value = match?.group(1);
  return switch (value) {
    'True' || 'true' => true,
    'False' || 'false' => false,
    _ => null,
  };
}

List<String> _topLevelArguments(String expression) {
  final start = expression.indexOf('(');
  final end = expression.lastIndexOf(')');
  if (start == -1 || end <= start) return const [];
  final source = expression.substring(start + 1, end);
  final args = <String>[];
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
    if (char == '(') depth += 1;
    if (char == ')') depth -= 1;
    if (char == ',' && depth == 0) {
      args.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }

  final tail = buffer.toString().trim();
  if (tail.isNotEmpty) args.add(tail);
  return args;
}

bool _looksLikeTransitionExpression(String value) {
  return RegExp(
    r'^(?:Fade|Dissolve|ImageDissolve|CropMove|PushMove|Pixellate|'
    r'OldMoveTransition|MoveTransition|MultipleTransition|ComposeTransition|'
    r'AlphaDissolve|Move)\s*\(',
  ).hasMatch(value);
}
