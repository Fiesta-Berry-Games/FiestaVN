/// A platform-neutral audio command emitted while running a RenPy script.
class RenPyAudioEvent {
  const RenPyAudioEvent.play({required this.channel, required this.asset})
    : action = RenPyAudioAction.play;

  final RenPyAudioAction action;
  final String channel;
  final String asset;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyAudioEvent &&
            action == other.action &&
            channel == other.channel &&
            asset == other.asset;
  }

  @override
  int get hashCode => Object.hash(action, channel, asset);

  @override
  String toString() {
    return 'RenPyAudioEvent.$action(channel: $channel, asset: $asset)';
  }
}

enum RenPyAudioAction { play }
