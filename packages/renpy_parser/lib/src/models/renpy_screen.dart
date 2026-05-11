/// Structured models for the bodies of `screen`, `style`, and
/// `transform`(ATL) declarations.
///
/// The parser previously kept only the screen *signature*, the style
/// *declaration*, and the transform *body* as raw text. These models hold the
/// parsed structure so the runtime can descend into and render the bodies.
/// Property values are kept as raw expression text; the core Python evaluator
/// resolves them at render time.
library;

/// The kind of a screen-language node.
///
/// [displayable] covers the standard GUI displayables and layout containers
/// (`vbox`, `text`, `textbutton`, ...). The remaining kinds are screen
/// control-flow and structural constructs that are not plain displayables.
enum RenPyScreenNodeKind {
  /// A displayable or layout statement, e.g. `vbox`, `text`, `textbutton`.
  displayable,

  /// An `if`/`elif`/`else` chain.
  ifChain,

  /// A `for target in iterable:` loop.
  forLoop,

  /// A `$ ...` inline Python line.
  python,

  /// A `python:` block.
  pythonBlock,

  /// An `on "event":` handler block.
  on,

  /// A `use other_screen` reference.
  use,

  /// A `transclude` placeholder.
  transclude,

  /// A `has layout` statement inside a button/container.
  has,

  /// A screen keyword-statement that configures the enclosing screen rather
  /// than adding a displayable, e.g. `style_prefix "input"`, `zorder 100`,
  /// `tag menu`, `modal True`, `predict False`, `variant "touch"`,
  /// `showif cond:`, `sensitive expr`, or a screen-local `default x = v`.
  ///
  /// [RenPyScreenNode.keyword] holds the keyword name and
  /// [RenPyScreenNode.value] holds the raw expression argument.
  keyword,
}

/// Screen keyword-statements: directives that configure the enclosing screen
/// (or, for [showif], gate a body) rather than emitting a displayable. Their
/// argument is preserved verbatim as a raw expression in
/// [RenPyScreenNode.value]; the core Python evaluator resolves it at render
/// time.
const renPyScreenKeywords = <String>{
  'tag',
  'zorder',
  'style_prefix',
  'modal',
  'predict',
  'variant',
  'showif',
  'sensitive',
  'default',
};

/// A node in a parsed screen body.
///
/// For [RenPyScreenNodeKind.displayable] the [kind] string is the displayable
/// name (`vbox`, `text`, `textbutton`, ...), [positionalArgs] holds the raw
/// positional argument expressions, [properties] maps property/keyword names to
/// their raw expression text, and [children] holds nested nodes.
class RenPyScreenNode {
  /// The displayable or statement keyword (e.g. `vbox`, `text`, `if`, `for`).
  final String kind;

  /// What category of node this is.
  final RenPyScreenNodeKind nodeKind;

  /// Raw positional argument expressions, in order.
  final List<String> positionalArgs;

  /// Property / keyword-argument expressions, keyed by property name. Includes
  /// both `name=value` keyword args and bare style/layout properties such as
  /// `xalign 0.5` or `spacing 10`.
  final Map<String, String> properties;

  /// Child nodes nested under this node.
  final List<RenPyScreenNode> children;

  /// For [RenPyScreenNodeKind.ifChain], the conditional branches.
  final List<RenPyScreenConditionalBranch> branches;

  /// For [RenPyScreenNodeKind.forLoop], the loop target (e.g. `i` or `x, y`).
  final String? forTarget;

  /// For [RenPyScreenNodeKind.forLoop], the iterable expression.
  final String? forIterable;

  /// For [RenPyScreenNodeKind.python], the inline Python source. For
  /// [RenPyScreenNodeKind.pythonBlock], the joined block source.
  final String? pythonCode;

  /// For [RenPyScreenNodeKind.on], the event expression (e.g. `"show"`).
  final String? event;

  /// For [RenPyScreenNodeKind.keyword], the keyword name (e.g. `style_prefix`,
  /// `zorder`, `tag`, `modal`, `showif`, `default`).
  final String? keyword;

  /// For [RenPyScreenNodeKind.keyword], the raw expression argument
  /// (e.g. `"input"`, `100`, `menu`, `True`, `x = v`), or null for a bare
  /// keyword with no argument.
  final String? value;

  RenPyScreenNode({
    required this.kind,
    required this.nodeKind,
    this.positionalArgs = const [],
    this.properties = const {},
    this.children = const [],
    this.branches = const [],
    this.forTarget,
    this.forIterable,
    this.pythonCode,
    this.event,
    this.keyword,
    this.value,
  });

  @override
  String toString() => 'ScreenNode($kind)';
}

/// One branch of an `if`/`elif`/`else` chain inside a screen.
class RenPyScreenConditionalBranch {
  /// The branch condition. `else` is represented as the literal `True`.
  final String condition;

  /// The nodes nested under this branch.
  final List<RenPyScreenNode> children;

  RenPyScreenConditionalBranch(this.condition, this.children);
}

/// A parsed `style name [is parent]:` declaration body.
class RenPyStyle {
  /// The style name (e.g. `say_dialogue`).
  final String name;

  /// The parent style from the `is` clause, or null.
  final String? parent;

  /// Property -> raw expression text (e.g. `xalign` -> `0.5`).
  final Map<String, String> properties;

  RenPyStyle({required this.name, this.parent, this.properties = const {}});

  @override
  String toString() =>
      'Style($name${parent != null ? ' is $parent' : ''}, ${properties.length} props)';
}

/// The kind of an ATL node.
enum RenPyAtlNodeKind {
  /// A bare property assignment, e.g. `xpos 0.5`, `alpha 1.0`.
  property,

  /// A warper interpolation, e.g. `linear 1.0 xpos 0.5`.
  interpolation,

  /// A `pause <duration>` statement.
  pause,

  /// A `repeat [count]` statement.
  repeat,

  /// A `block:` group.
  block,

  /// A `parallel:` group.
  parallel,

  /// A `choice [chance]:` group.
  choice,

  /// An `on <event>:` handler.
  on,

  /// A `contains <expression>` statement.
  contains,

  /// A statement captured but not structured.
  raw,
}

/// A node in a parsed ATL (transform) body.
class RenPyAtlNode {
  final RenPyAtlNodeKind nodeKind;

  /// For [RenPyAtlNodeKind.property] / [RenPyAtlNodeKind.interpolation], the
  /// target properties mapped to their raw expression text (e.g. `xpos` ->
  /// `0.5`). An interpolation may target several properties at once.
  final Map<String, String> properties;

  /// For [RenPyAtlNodeKind.interpolation], the warper name
  /// (`linear`/`ease`/`easein`/`easeout`/...).
  final String? warper;

  /// For [RenPyAtlNodeKind.interpolation] / [RenPyAtlNodeKind.pause] /
  /// [RenPyAtlNodeKind.choice], the raw duration/chance expression.
  final String? duration;

  /// For [RenPyAtlNodeKind.repeat], the raw repeat-count expression, or null
  /// for an unbounded `repeat`.
  final String? repeatCount;

  /// For [RenPyAtlNodeKind.on], the event name(s) (e.g. `show`, `hide`).
  final String? event;

  /// For [RenPyAtlNodeKind.contains], the contained expression.
  final String? containsExpression;

  /// Child nodes for block/parallel/choice/on groups.
  final List<RenPyAtlNode> children;

  /// For [RenPyAtlNodeKind.raw], the captured source text.
  final String? raw;

  RenPyAtlNode({
    required this.nodeKind,
    this.properties = const {},
    this.warper,
    this.duration,
    this.repeatCount,
    this.event,
    this.containsExpression,
    this.children = const [],
    this.raw,
  });

  @override
  String toString() => 'AtlNode(${nodeKind.name})';
}
