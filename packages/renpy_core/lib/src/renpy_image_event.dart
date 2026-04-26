import 'renpy_image_placement.dart';

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
       displayableText = null;

  const RenPyImageEvent.show(
    this.imageName, {
    this.at,
    this.placement,
    this.onLayer,
    this.zOrder,
    this.behind,
    this.displayableText,
  }) : action = RenPyImageAction.show;

  const RenPyImageEvent.hide(this.imageName, {this.onLayer})
    : action = RenPyImageAction.hide,
      at = null,
      placement = null,
      zOrder = null,
      behind = null,
      displayableText = null;

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
            displayableText == other.displayableText;
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
  );

  @override
  String toString() {
    return 'RenPyImageEvent.$action('
        'imageName: $imageName, at: $at, placement: $placement, '
        'onLayer: $onLayer, zOrder: $zOrder, behind: $behind, '
        'displayableText: $displayableText)';
  }
}
