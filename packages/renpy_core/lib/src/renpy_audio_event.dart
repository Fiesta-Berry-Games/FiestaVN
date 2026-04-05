/// A platform-neutral audio command emitted while running a RenPy script.
class RenPyAudioEvent {
  const RenPyAudioEvent.play({
    required this.channel,
    required this.asset,
    this.fadein,
    this.fadeout,
    this.volume,
    this.ifChanged,
    this.mixer,
    this.loop,
  }) : action = RenPyAudioAction.play;

  const RenPyAudioEvent.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null,
      fadein = null,
      volume = null,
      ifChanged = null,
      mixer = null,
      loop = null;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadein;
  final String? fadeout;
  final String? volume;
  final bool? ifChanged;
  final String? mixer;
  final bool? loop;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyAudioEvent &&
            action == other.action &&
            channel == other.channel &&
            asset == other.asset &&
            fadein == other.fadein &&
            fadeout == other.fadeout &&
            volume == other.volume &&
            ifChanged == other.ifChanged &&
            mixer == other.mixer &&
            loop == other.loop;
  }

  @override
  int get hashCode => Object.hash(
    action,
    channel,
    asset,
    fadein,
    fadeout,
    volume,
    ifChanged,
    mixer,
    loop,
  );

  @override
  String toString() {
    return 'RenPyAudioEvent.$action(channel: $channel, asset: $asset, '
        'fadein: $fadein, fadeout: $fadeout, volume: $volume, '
        'ifChanged: $ifChanged, mixer: $mixer, loop: $loop)';
  }
}

enum RenPyAudioAction { play, stop }
