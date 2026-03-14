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
class RenPyLabelStatement extends RenPyBlockStatement {
  final String name;

  RenPyLabelStatement(
    this.name,
    List<RenPyStatement> block,
    String filename,
    int linenumber,
  ) : super(block, filename, linenumber);

  @override
  String toString() => 'Label: $name';
}

/// Represents a say statement (character "text" or "text").
class RenPySayStatement extends RenPyStatement {
  final String? character; // null for narrator
  final String? text;

  RenPySayStatement(this.character, this.text, String filename, int linenumber)
    : super(filename, linenumber);

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

  RenPyMenuStatement(
    this.items,
    String filename,
    int linenumber, {
    this.caption,
  }) : super(filename, linenumber);

  @override
  String toString() =>
      'Menu${caption != null ? ' "$caption"' : ''} with ${items.length} choices';
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

  RenPyJumpStatement(this.target, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Jump to: $target';
}

/// Represents a call statement (call label).
class RenPyCallStatement extends RenPyStatement {
  final String target;

  RenPyCallStatement(this.target, String filename, int linenumber)
    : super(filename, linenumber);

  @override
  String toString() => 'Call: $target';
}

/// Represents a show statement (show image_name).
class RenPyShowStatement extends RenPyStatement {
  final String imageName;
  final String? atExpression;
  final String? withExpression;

  RenPyShowStatement(
    this.imageName,
    this.atExpression,
    this.withExpression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Show: $imageName';
}

/// Represents a scene statement (scene [image_name]).
class RenPySceneStatement extends RenPyStatement {
  final String? imageName;
  final String? atExpression;
  final String? withExpression;

  RenPySceneStatement(
    this.imageName,
    this.atExpression,
    this.withExpression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Scene: ${imageName ?? "clear"}';
}

/// Represents a hide statement (hide image_name).
class RenPyHideStatement extends RenPyStatement {
  final String imageName;
  final String? withExpression;

  RenPyHideStatement(
    this.imageName,
    this.withExpression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

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

/// Represents an image statement (image name = expression).
class RenPyImageStatement extends RenPyStatement {
  final String name;
  final String expression;

  RenPyImageStatement(
    this.name,
    this.expression,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() => 'Image: $name = $expression';
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
