import 'renpy_transition_intent.dart';

/// A platform-neutral visual transition emitted while running a RenPy script.
class RenPyTransitionEvent {
  const RenPyTransitionEvent(this.name, {this.intent});

  final String name;
  final RenPyTransitionIntent? intent;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyTransitionEvent &&
            name == other.name &&
            intent == other.intent;
  }

  @override
  int get hashCode => Object.hash(name, intent);

  @override
  String toString() => 'RenPyTransitionEvent($name, intent: $intent)';
}
