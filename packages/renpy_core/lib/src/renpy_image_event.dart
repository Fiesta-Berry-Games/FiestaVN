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
  const RenPyImageEvent.scene(this.imageName, {this.at, this.placement})
    : action = RenPyImageAction.scene;

  const RenPyImageEvent.show(this.imageName, {this.at, this.placement})
    : action = RenPyImageAction.show;

  const RenPyImageEvent.hide(this.imageName)
    : action = RenPyImageAction.hide,
      at = null,
      placement = null;

  final RenPyImageAction action;
  final String? imageName;

  /// The raw RenPy placement expression after `at`, such as `left`.
  final String? at;

  /// Parsed placement intent for common RenPy `at` expressions.
  final RenPyImagePlacement? placement;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyImageEvent &&
            action == other.action &&
            imageName == other.imageName &&
            at == other.at &&
            placement == other.placement;
  }

  @override
  int get hashCode => Object.hash(action, imageName, at, placement);

  @override
  String toString() {
    return 'RenPyImageEvent.$action('
        'imageName: $imageName, at: $at, placement: $placement)';
  }
}
