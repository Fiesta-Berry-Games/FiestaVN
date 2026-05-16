import 'renpy_statement.dart';

/// Represents a RenPy `layeredimage name:` declaration.
///
/// A layeredimage is a composite sprite assembled from stacked [layers], each
/// contributing a displayable. The order of [layers] is the bottom-to-top draw
/// order. Attribute layers are grouped (see [RenPyLayeredImageLayer.group]);
/// `show <name> <attrs>` selects at most one attribute per group, falling back
/// to the group's `default` attribute when none is named. `always` layers and
/// satisfied `if` layers are included unconditionally.
class RenPyLayeredImageStatement extends RenPyStatement {
  final String name;
  final List<RenPyLayeredImageLayer> layers;

  RenPyLayeredImageStatement(
    this.name,
    this.layers,
    String filename,
    int linenumber,
  ) : super(filename, linenumber);

  @override
  String toString() =>
      'LayeredImage: $name (${layers.length} layer'
      '${layers.length == 1 ? '' : 's'})';
}

/// The kind of layer inside a [RenPyLayeredImageStatement].
enum RenPyLayeredImageLayerKind {
  /// An `always:` layer that is always drawn.
  always,

  /// An `attribute name [default]:` layer belonging to a [group].
  attribute,

  /// An `if <condition>:` layer drawn when its condition holds.
  condition,
}

/// A single stacked layer of a [RenPyLayeredImageStatement].
class RenPyLayeredImageLayer {
  const RenPyLayeredImageLayer({
    required this.kind,
    required this.displayable,
    this.group,
    this.attribute,
    this.isDefault = false,
    this.condition,
    this.properties = const {},
  });

  /// Builds an `always:` layer.
  factory RenPyLayeredImageLayer.always(
    String displayable, {
    Map<String, String> properties = const {},
  }) {
    return RenPyLayeredImageLayer(
      kind: RenPyLayeredImageLayerKind.always,
      displayable: displayable,
      properties: properties,
    );
  }

  /// Builds an `attribute name [default]:` layer in [group].
  factory RenPyLayeredImageLayer.attribute({
    required String group,
    required String attribute,
    required String displayable,
    bool isDefault = false,
    Map<String, String> properties = const {},
  }) {
    return RenPyLayeredImageLayer(
      kind: RenPyLayeredImageLayerKind.attribute,
      displayable: displayable,
      group: group,
      attribute: attribute,
      isDefault: isDefault,
      properties: properties,
    );
  }

  /// Builds an `if <condition>:` layer.
  factory RenPyLayeredImageLayer.condition({
    required String condition,
    required String displayable,
    Map<String, String> properties = const {},
  }) {
    return RenPyLayeredImageLayer(
      kind: RenPyLayeredImageLayerKind.condition,
      displayable: displayable,
      condition: condition,
      properties: properties,
    );
  }

  final RenPyLayeredImageLayerKind kind;

  /// The displayable expression for this layer (usually a quoted image name).
  final String displayable;

  /// The group this attribute belongs to, or null for non-attribute layers.
  final String? group;

  /// The attribute name selecting this layer, or null for non-attribute layers.
  final String? attribute;

  /// Whether this attribute is its group's default selection.
  final bool isDefault;

  /// The raw condition expression for an `if` layer, or null otherwise.
  final String? condition;

  /// Per-layer properties (`at`, `if_all`, `if_any`, `if_not`, ...) kept as raw
  /// text for best-effort handling downstream.
  final Map<String, String> properties;

  @override
  String toString() {
    return switch (kind) {
      RenPyLayeredImageLayerKind.always => 'always $displayable',
      RenPyLayeredImageLayerKind.attribute =>
        'attribute $group/$attribute${isDefault ? ' default' : ''} '
            '$displayable',
      RenPyLayeredImageLayerKind.condition => 'if $condition: $displayable',
    };
  }
}
