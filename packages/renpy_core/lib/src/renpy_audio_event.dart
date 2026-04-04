/// A platform-neutral audio command emitted while running a RenPy script.
class RenPyAudioEvent {
  const RenPyAudioEvent.play({
    required this.channel,
    required this.asset,
    this.mixer,
    this.loop,
  }) : action = RenPyAudioAction.play,
       fadeout = null;

  const RenPyAudioEvent.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null,
      mixer = null,
      loop = null;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadeout;
  final String? mixer;
  final bool? loop;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyAudioEvent &&
            action == other.action &&
            channel == other.channel &&
            asset == other.asset &&
            fadeout == other.fadeout &&
            mixer == other.mixer &&
            loop == other.loop;
  }

  @override
  int get hashCode => Object.hash(action, channel, asset, fadeout, mixer, loop);

  @override
  String toString() {
    return 'RenPyAudioEvent.$action(channel: $channel, asset: $asset, '
        'fadeout: $fadeout, mixer: $mixer, loop: $loop)';
  }
}

enum RenPyAudioAction { play, stop }
