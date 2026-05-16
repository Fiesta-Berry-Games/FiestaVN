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
  }) : action = RenPyAudioAction.play,
       queued = false;

  /// Appends [asset] to [channel]'s playlist, to start when the current track
  /// ends rather than replacing it (RenPy `queue <channel> "file"` /
  /// `renpy.music.queue(...)`).
  const RenPyAudioEvent.queue({
    required this.channel,
    required this.asset,
    this.fadein,
    this.fadeout,
    this.volume,
    this.mixer,
    this.loop,
  }) : action = RenPyAudioAction.play,
       ifChanged = null,
       queued = true;

  const RenPyAudioEvent.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null,
      fadein = null,
      volume = null,
      ifChanged = null,
      mixer = null,
      loop = null,
      queued = false;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadein;
  final String? fadeout;
  final String? volume;
  final bool? ifChanged;
  final String? mixer;
  final bool? loop;

  /// Whether a play event should append to the channel's playlist (queue) rather
  /// than replace the current track. Always false for stop events.
  final bool queued;

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
            loop == other.loop &&
            queued == other.queued;
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
    queued,
  );

  @override
  String toString() {
    return 'RenPyAudioEvent.${queued ? 'queue' : action.name}'
        '(channel: $channel, asset: $asset, '
        'fadein: $fadein, fadeout: $fadeout, volume: $volume, '
        'ifChanged: $ifChanged, mixer: $mixer, loop: $loop)';
  }
}

enum RenPyAudioAction { play, stop }
