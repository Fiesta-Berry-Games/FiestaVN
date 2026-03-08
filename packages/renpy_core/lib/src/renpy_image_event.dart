/// The kind of image command emitted while running a RenPy script.
enum RenPyImageAction { scene, show, hide }

/// A platform-neutral image command emitted while running a RenPy script.
class RenPyImageEvent {
  const RenPyImageEvent.scene(this.imageName, {this.at})
    : action = RenPyImageAction.scene;

  const RenPyImageEvent.show(this.imageName, {this.at})
    : action = RenPyImageAction.show;

  const RenPyImageEvent.hide(this.imageName)
    : action = RenPyImageAction.hide,
      at = null;

  final RenPyImageAction action;
  final String? imageName;

  /// The raw RenPy placement expression after `at`, such as `left`.
  final String? at;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyImageEvent &&
            action == other.action &&
            imageName == other.imageName &&
            at == other.at;
  }

  @override
  int get hashCode => Object.hash(action, imageName, at);

  @override
  String toString() {
    return 'RenPyImageEvent.$action(imageName: $imageName, at: $at)';
  }
}
