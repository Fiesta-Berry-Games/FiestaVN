import 'renpy_image_placement.dart';

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// The kind of image command emitted while running a RenPy script.
enum RenPyImageAction { scene, show, hide }

/// A platform-neutral image alias definition emitted while running a script.
class RenPyImageDefinitionEvent {
  const RenPyImageDefinitionEvent({
    required this.name,
    required this.expression,
  });

  final String name;
  final String expression;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyImageDefinitionEvent &&
            name == other.name &&
            expression == other.expression;
  }

  @override
  int get hashCode => Object.hash(name, expression);

  @override
  String toString() {
    return 'RenPyImageDefinitionEvent(name: $name, expression: $expression)';
  }
}

/// A platform-neutral image command emitted while running a RenPy script.
class RenPyImageEvent {
  const RenPyImageEvent.scene(
    this.imageName, {
    this.at,
    this.placement,
    this.onLayer,
    this.zOrder,
  }) : action = RenPyImageAction.scene,
       behind = null,
       displayableText = null,
       layers = const [];

  const RenPyImageEvent.show(
    this.imageName, {
    this.at,
    this.placement,
    this.onLayer,
    this.zOrder,
    this.behind,
    this.displayableText,
    this.layers = const [],
  }) : action = RenPyImageAction.show;

  const RenPyImageEvent.hide(this.imageName, {this.onLayer})
    : action = RenPyImageAction.hide,
      at = null,
      placement = null,
      zOrder = null,
      behind = null,
      displayableText = null,
      layers = const [];

  final RenPyImageAction action;
  final String? imageName;

  /// The raw RenPy placement expression after `at`, such as `left`.
  final String? at;

  /// Parsed placement intent for common RenPy `at` expressions.
  final RenPyImagePlacement? placement;

  /// The RenPy layer targeted by `onlayer`, if specified.
  final String? onLayer;

  /// The numeric RenPy z-order for this image statement, if specified.
  final int? zOrder;

  /// The image tag this show statement should render behind, if specified.
  final String? behind;

  /// Inline displayable text from `show text "..."`.
  final String? displayableText;

  /// The ordered (bottom-to-top) layer image names of a resolved layeredimage
  /// `show`, or empty for an ordinary single-image show. Each entry is a plain
  /// image name the host resolves to an asset like any other image.
  final List<String> layers;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyImageEvent &&
            action == other.action &&
            imageName == other.imageName &&
            at == other.at &&
            placement == other.placement &&
            onLayer == other.onLayer &&
            zOrder == other.zOrder &&
            behind == other.behind &&
            displayableText == other.displayableText &&
            _listEquals(layers, other.layers);
  }

  @override
  int get hashCode => Object.hash(
    action,
    imageName,
    at,
    placement,
    onLayer,
    zOrder,
    behind,
    displayableText,
    Object.hashAll(layers),
  );

  @override
  String toString() {
    return 'RenPyImageEvent.$action('
        'imageName: $imageName, at: $at, placement: $placement, '
        'onLayer: $onLayer, zOrder: $zOrder, behind: $behind, '
        'displayableText: $displayableText, layers: $layers)';
  }
}
