/// A platform-neutral dialogue line emitted while running a RenPy script.
class RenPyDialogueEvent {
  const RenPyDialogueEvent({
    this.characterId,
    this.displayName,
    required this.text,
    this.color,
  });

  /// The RenPy character variable, such as `s` in `s "Hello"`.
  final String? characterId;

  /// The resolved display name shown to the player.
  final String? displayName;

  final String text;

  /// The raw RenPy color expression for the character, usually `#rrggbb`.
  final String? color;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyDialogueEvent &&
            characterId == other.characterId &&
            displayName == other.displayName &&
            text == other.text &&
            color == other.color;
  }

  @override
  int get hashCode => Object.hash(characterId, displayName, text, color);

  @override
  String toString() {
    return 'RenPyDialogueEvent(characterId: $characterId, '
        'displayName: $displayName, text: $text, color: $color)';
  }
}
