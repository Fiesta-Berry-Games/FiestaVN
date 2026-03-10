/// A platform-neutral audio command emitted while running a RenPy script.
class RenPyAudioEvent {
  const RenPyAudioEvent.play({required this.channel, required this.asset})
    : action = RenPyAudioAction.play,
      fadeout = null;

  const RenPyAudioEvent.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadeout;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyAudioEvent &&
            action == other.action &&
            channel == other.channel &&
            asset == other.asset &&
            fadeout == other.fadeout;
  }

  @override
  int get hashCode => Object.hash(action, channel, asset, fadeout);

  @override
  String toString() {
    return 'RenPyAudioEvent.$action(channel: $channel, asset: $asset, '
        'fadeout: $fadeout)';
  }
}

enum RenPyAudioAction { play, stop }
