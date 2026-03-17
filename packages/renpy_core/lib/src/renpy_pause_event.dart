/// A platform-neutral pause emitted while running a RenPy script.
class RenPyPauseEvent {
  const RenPyPauseEvent({this.duration});

  /// Optional RenPy pause duration in seconds.
  final double? duration;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyPauseEvent && duration == other.duration;
  }

  @override
  int get hashCode => duration.hashCode;

  @override
  String toString() => 'RenPyPauseEvent(duration: $duration)';
}
