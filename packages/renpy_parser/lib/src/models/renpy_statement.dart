import 'renpy_screen.dart';

/// Base class for all RenPy statements.
abstract class RenPyStatement {
  final String filename;
  final int linenumber;

  RenPyStatement(this.filename, this.linenumber);
}

/// A statement that contains a block of other statements.
abstract class RenPyBlockStatement extends RenPyStatement {
  final List<RenPyStatement> block;

  RenPyBlockStatement(this.block, String filename, int linenumber)
    : super(filename, linenumber);
}

/// Represents a label statement (label name:).
/// A single formal parameter of a parameterized `label name(params):`. [name]
/// is the bare parameter name (a leading `*`/`**` is preserved for varargs);
/// [defaultExpression] is the raw source of its default, or null if none.
class RenPyParameter {
  final String name;
  final String? defaultExpression;

  const RenPyParameter(this.name, [this.defaultExpression]);

  @override
  String toString() =>
      defaultExpression == null ? name : '$name=$defaultExpression';
}

class RenPyLabelStatement extends RenPyBlockStatement {
  final String name;

  /// Formal parameters declared by a `label name(a, b=expr):` header. Empty for
  /// a plain `label name:`.
  final List<RenPyParameter> parameters;

  RenPyLabelStatement(
    this.name,
    List<RenPyStatement> block,
    String filename,
    int linenumber, {
    this.parameters = const [],
  }) : super(block, filename, linenumber);

  @override
  String toString() => 'Label: $name';
}

/// Represents a say statement (character "text" or "text").
class RenPySayStatement extends RenPyStatement {
  final String? character; // null for narrator
  final String? text;
  final List<String>
  attributes; // permanent sprite attributes, e.g. e happy "Hi"

  /// Temporary sprite attributes introduced by the `@` form, shown only for
  /// this line, e.g. `e happy @ sad "..."` -> temporaryAttributes `['sad']`.
  /// A bare `@` with no following tokens (`e @ "..."`) leaves this empty.
  final List<String> temporaryAttributes;

  RenPySayStatement(
    this.character,
    this.text,
    String filename,
    int linenumber, {
    this.attributes = const [],
    this.temporaryAttributes = const [],
  }) : super(filename, linenumber);

  @override
  String toString() {
    if (character != null) {
      return '$character: "$text"';
    } else {
      return 'Narrator: "$text"';
    }
  }
}

/// Represents a menu statement with choices.
class RenPyMenuStatement extends RenPyStatement {
  final List<MenuChoice> items;
  final String? caption;
  final String? setVariable;

  /// The optional menu name from `menu <name>:`. RenPy registers a named menu
  /// as a label so `jump`/`call` can re-enter it (the "guess again" retry
  /// pattern). Null for an anonymous `menu:`.
  final String? name;

  RenPyMenuStatement(
    this.items,
    String filename,
    int linenumber, {
    this.caption,
    this.setVariable,
    this.name,
  }) : super(filename, linenumber);

  @override
  String toString() =>
      'Menu${name != null ? ' $name' : ''}'
      '${caption != null ? ' "$caption"' : ''} with ${items.length} choices';
}

/// Represents a menu choice.
class MenuChoice {
  final String text;
  final String condition;
  final List<RenPyStatement> block;

  MenuChoice({
    required this.text,
    required this.condition,
    required this.block,
  });

  @override
  String toString() => 'Choice: "$text"';
}

/// Represents a jump statement (jump label).
class RenPyJumpStatement extends RenPyStatement {
  final String target;
  final bool isExpression; // true for `jump expression <expr>`

  RenPyJumpStatement(
    this.target,
    String filename,
    int linenumber, {
    this.isExpression = false,
  }) : super(filename, linenumber);

  @override
  String toString() => 'Jump to: $target';
}

/// Represents a call statement (call label).
class RenPyCallStatement extends RenPyStatement {
  final String target;
  final bool isExpression; // true for `call expression <expr>`

  /// True for `call screen <name>(<args>)`, a blocking interactive screen call.
  /// When set, [target] is the literal `screen` token (preserved for
  /// back-compat) and [screenName]/[screenArgs] carry the resolved screen.
  final bool isScreen;

  /// The screen name for a `call screen` statement, or null otherwise.
  final String? screenName;

  /// The raw argument string inside the parentheses of a `call screen`
  /// invocation (e.g. `"Quit?"`), or null when no parentheses were given.
  final String? screenArgs;

  RenPyCallStatement(
    this.target,
    String filename,
    int linenumber, {
    this.isExpression = false,
    this.isScreen = false,
    this.screenName,
    this.screenArgs,
  }) : super(filename, linenumber);

  @override
  String toString() {
    if (isScreen) return 'Call screen: $screenName';
    return 'Call: $target';
  }
}

/// Represents a show statement (show image_name).
class RenPyShowStatement extends RenPyStatement {
  final String imageName;
  final String? atExpression;
  final String? behindExpression;
  final String? onLayerExpression;
  final String? zOrderExpression;
  final String? withExpression;
  final String? displayableText;

  RenPyShowStatement(
    this.imageName,
    this.atExpression,
    this.withExpression,
    String filename,
    int linenumber, {
    this.behindExpression,
    this.onLayerExpression,
    this.zOrderExpression,
    this.displayableText,
  }) : super(filename, linenumber);

  @override
  String toString() => 'Show: $imageName';
}

/// Represents a scene statement (scene [image_name]).
class RenPySceneStatement extends RenPyStatement {
  final String? imageName;
  final String? atExpression;
  final String? onLayerExpression;
  final String? zOrderExpression;
  final String? withExpression;

  RenPySceneStatement(
    this.imageName,
    this.atExpression,
    this.withExpression,
    String filename,
    int linenumber, {
    this.onLayerExpression,
    this.zOrderExpression,
  }) : super(filename, linenumber);

  @override
  String toString() => 'Scene: ${imageName ?? "clear"}';
}

/// Represents a hide statement (hide image_name).
class RenPyHideStatement extends RenPyStatement {
  final String imageName;
  final String? onLayerExpression;
  final String? withExpression;

  RenPyHideStatement(
    this.imageName,
    this.withExpression,
    String filename,
    int linenumber, {
    this.onLayerExpression,
  }) : super(filename, linenumber);

  @override
  String toString() => 'Hide: $imageName';
}

/// Represents a with statement (with transition).
class RenPyWithStatement extends RenPyStatement {
  final String transition;

  RenPyWithStatement(this.transition, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'With: $transition';
}

/// Represents a python statement ($ code or python: block).
class RenPyPythonStatement extends RenPyStatement {
  final String code;
  final bool isInit;

  RenPyPythonStatement(this.code, this.isInit, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Python${isInit ? " (init)" : ""}: $code';
}

/// Represents a define statement (define name = expression).
class RenPyDefineStatement extends RenPyStatement {
  final String name;
  final String expression;

  RenPyDefineStatement(
    this.name,
    this.expression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Define: $name = $expression';
}

/// Represents a default statement (default name = expression).
class RenPyDefaultStatement extends RenPyStatement {
  final String name;
  final String expression;

  RenPyDefaultStatement(
    this.name,
    this.expression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Default: $name = $expression';
}

/// Represents an if statement (if condition: block).
class RenPyIfStatement extends RenPyBlockStatement {
  final List<IfEntry> entries;

  RenPyIfStatement(this.entries, String filename, int linenumber)
    : super(entries.isNotEmpty ? entries[0].block : [], filename, linenumber);

  @override
  String toString() => 'If: ${entries.map((e) => e.condition).join(" elif ")}';
}

/// Represents an if-elif-else entry.
class IfEntry {
  final String condition;
  final List<RenPyStatement> block;

  IfEntry(this.condition, this.block);
}

/// Represents a top-level `while <condition>:` loop whose [block] holds ordinary
/// script statements (dialogue, menu, jump, `$`, ...). Distinct from the
/// `while` inside a `python:` block, which the Python interpreter runs.
class RenPyWhileStatement extends RenPyBlockStatement {
  final String condition;

  RenPyWhileStatement(
    this.condition,
    List<RenPyStatement> block,
    String filename,
    int linenumber,
  ) : super(block, filename, linenumber);

  @override
  String toString() => 'While: $condition';
}

/// Represents a top-level `for <variable> in <iterable>:` loop whose [block]
/// holds ordinary script statements. Distinct from the `for` inside a
/// `python:` block, which the Python interpreter runs.
class RenPyForStatement extends RenPyBlockStatement {
  /// The loop target text, e.g. `q` or `i, value`.
  final String variable;

  /// The iterable expression text, e.g. `questions` or `[1, 2, 3]`.
  final String iterable;

  RenPyForStatement(
    this.variable,
    this.iterable,
    List<RenPyStatement> block,
    String filename,
    int linenumber,
  ) : super(block, filename, linenumber);

  @override
  String toString() => 'For: $variable in $iterable';
}

enum RenPyLoopControlAction { breakLoop, continueLoop }

/// Represents a top-level `break` or `continue` loop-control statement.
class RenPyLoopControlStatement extends RenPyStatement {
  final RenPyLoopControlAction action;

  RenPyLoopControlStatement(this.action, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() =>
      action == RenPyLoopControlAction.breakLoop ? 'Break' : 'Continue';
}

/// Represents a pass statement (pass).
class RenPyPassStatement extends RenPyStatement {
  RenPyPassStatement(String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Pass';
}

/// Represents a return statement (return [expression]).
class RenPyReturnStatement extends RenPyStatement {
  final String? expression;

  RenPyReturnStatement(this.expression, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Return${expression != null ? ": $expression" : ""}';
}

enum RenPyNvlAction { clear }

/// Represents an NVL-mode control statement, such as `nvl clear`.
class RenPyNvlStatement extends RenPyStatement {
  final RenPyNvlAction action;

  RenPyNvlStatement(this.action, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'NVL: $action';
}

/// Represents a generic statement that we couldn't parse more specifically.
class RenPyGenericStatement extends RenPyStatement {
  final String text;

  RenPyGenericStatement(this.text, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Generic: $text';
}

/// Represents an image statement.
///
/// Two forms are supported: `image name = expression` (where [expression] is
/// the right-hand side) and `image name:` with an ATL body (where [expression]
/// is empty and [body] holds the indented ATL lines).
class RenPyImageStatement extends RenPyStatement {
  final String name;
  final String expression;
  final List<String> body;

  RenPyImageStatement(
    this.name,
    this.expression,
    String filename,
    int linenumber, {
    this.body = const [],
  }) : super(filename, linenumber);

  @override
  String toString() =>
      expression.isNotEmpty ? 'Image: $name = $expression' : 'Image: $name';
}

/// Represents a bare `window` control statement (`window show`, `window hide`,
/// or `window auto`), optionally with a trailing transition expression.
class RenPyWindowStatement extends RenPyStatement {
  final RenPyWindowAction action;
  final String? transition;

  RenPyWindowStatement(
    this.action,
    String filename,
    int linenumber, {
    this.transition,
  }) : super(filename, linenumber);

  @override
  String toString() => 'Window: ${action.name}';
}

enum RenPyWindowAction { show, hide, auto }

/// Represents a `pause [duration]` statement. [duration] is the raw argument
/// text (e.g. `0.25`, `.25`, `delay`) or null for a bare `pause`.
class RenPyPauseStatement extends RenPyStatement {
  final String? duration;

  RenPyPauseStatement(this.duration, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Pause${duration != null ? ': $duration' : ''}';
}

/// Represents an audio playback statement (e.g.  'play sound "foo.ogg"').
class RenPyPlayStatement extends RenPyStatement {
  /// The audio channel ('sound', 'music', 'voice', ...).  We only store it,
  /// the runner can decide later what to do with it.
  final String channel;

  /// The expression that follows the channel - usually a quoted file-name or
  /// something like [my_sound].
  final String expression;

  RenPyPlayStatement(
    this.channel,
    this.expression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Play $channel: $expression';
}

/// Represents an audio queue statement (e.g. `queue music "next.ogg"`).
///
/// Mirrors [RenPyPlayStatement] but the audio is appended to the channel's
/// playlist to start when the current track ends rather than replacing it.
class RenPyQueueStatement extends RenPyStatement {
  /// The audio channel ('sound', 'music', 'voice', ...).
  final String channel;

  /// The expression that follows the channel - usually a quoted file-name.
  final String expression;

  RenPyQueueStatement(
    this.channel,
    this.expression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Queue $channel: $expression';
}

/// Represents a `voice "file.ogg"` statement.
///
/// Voice is RenPy's dedicated one-shot dialogue-audio channel: a new voice line
/// (or the next dialogue) automatically interrupts the previous one.
class RenPyVoiceStatement extends RenPyStatement {
  /// The expression that follows `voice` - usually a quoted file-name. A bare
  /// `voice sustain` keeps the currently playing voice across the next line.
  final String expression;

  RenPyVoiceStatement(this.expression, String filename, int linenumber)
    : super(filename, linenumber);

  /// Whether this is `voice sustain` (keep the prior voice playing).
  bool get isSustain => expression.trim() == 'sustain';

  @override
  String toString() => 'Voice: $expression';
}

/// Represents an audio stop statement (e.g. `stop music fadeout 1.0`).
class RenPyStopStatement extends RenPyStatement {
  final String channel;
  final String? fadeout;

  RenPyStopStatement(
    this.channel,
    this.fadeout,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() {
    return fadeout == null ? 'Stop $channel' : 'Stop $channel fadeout $fadeout';
  }
}

/// Represents an `init offset = N` statement.
class RenPyInitOffsetStatement extends RenPyStatement {
  final int offset;

  RenPyInitOffsetStatement(this.offset, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() {
    return 'Init offset: $offset';
  }
}

/// Represents a Ren'Py screen-language declaration.
///
/// [signature] keeps the raw `name(params)` text for back-compat. [children]
/// holds the parsed screen body as a tree of [RenPyScreenNode]s.
class RenPyScreenStatement extends RenPyStatement {
  final String signature;

  /// The parsed top-level nodes of the screen body. Defaults to empty so
  /// existing consumers that only read [signature] are unaffected.
  final List<RenPyScreenNode> children;

  RenPyScreenStatement(
    this.signature,
    String filename,
    int linenumber, {
    this.children = const [],
  }) : super(filename, linenumber);

  @override
  String toString() {
    return 'Screen: $signature';
  }
}

/// Represents a Ren'Py style declaration.
///
/// [declaration] keeps the raw `name [is parent]` text for back-compat. [style]
/// holds the parsed name/parent/properties.
class RenPyStyleStatement extends RenPyStatement {
  final String declaration;

  /// The parsed style structure, or null when the declaration could not be
  /// structured. Defaults to null so existing consumers are unaffected.
  final RenPyStyle? style;

  RenPyStyleStatement(
    this.declaration,
    String filename,
    int linenumber, {
    this.style,
  }) : super(filename, linenumber);

  @override
  String toString() {
    return 'Style: $declaration';
  }
}

/// Represents a Ren'Py ATL transform declaration.
///
/// [body] keeps the raw indented ATL lines for back-compat. [atl] holds the
/// parsed ATL node sequence.
class RenPyTransformStatement extends RenPyStatement {
  final String signature;
  final List<String> body;

  /// The parsed ATL node sequence. Defaults to empty so existing consumers
  /// that only read [body] are unaffected.
  final List<RenPyAtlNode> atl;

  RenPyTransformStatement(
    this.signature,
    String filename,
    int linenumber, {
    this.body = const [],
    this.atl = const [],
  }) : super(filename, linenumber);

  @override
  String toString() {
    return 'Transform: $signature';
  }
}
