/// A platform-neutral visual transition emitted while running a RenPy script.
class RenPyTransitionEvent {
  const RenPyTransitionEvent(this.name);

  final String name;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyTransitionEvent && name == other.name;
  }

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'RenPyTransitionEvent($name)';
}
