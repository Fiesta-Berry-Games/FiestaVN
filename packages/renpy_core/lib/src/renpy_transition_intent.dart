/// A platform-neutral class of RenPy visual transition.
enum RenPyTransitionType {
  none,
  fade,
  dissolve,
  imageDissolve,
  cropMove,
  punch,
  unsupported,
}

/// Whether FiestaVN can render a transition exactly or only approximately.
enum RenPyTransitionFidelity { exact, approximated, unsupported }

/// Platform-neutral transition metadata parsed from RenPy transition values.
class RenPyTransitionIntent {
  const RenPyTransitionIntent.none()
    : type = RenPyTransitionType.none,
      fidelity = RenPyTransitionFidelity.exact,
      duration = 0,
      outTime = null,
      holdTime = null,
      inTime = null,
      color = null,
      maskAsset = null,
      ramplen = null,
      reverse = false,
      mode = null,
      expression = null;

  const RenPyTransitionIntent.fade({
    required double this.outTime,
    required double this.holdTime,
    required double this.inTime,
    this.color,
  }) : type = RenPyTransitionType.fade,
       fidelity = RenPyTransitionFidelity.exact,
       duration = null,
       maskAsset = null,
       ramplen = null,
       reverse = false,
       mode = null,
       expression = null;

  const RenPyTransitionIntent.dissolve({required double this.duration})
    : type = RenPyTransitionType.dissolve,
      fidelity = RenPyTransitionFidelity.exact,
      outTime = null,
      holdTime = null,
      inTime = null,
      color = null,
      maskAsset = null,
      ramplen = null,
      reverse = false,
      mode = null,
      expression = null;

  const RenPyTransitionIntent.imageDissolve({
    required String this.maskAsset,
    required double this.duration,
    this.ramplen,
    this.reverse = false,
  }) : type = RenPyTransitionType.imageDissolve,
       fidelity = RenPyTransitionFidelity.approximated,
       outTime = null,
       holdTime = null,
       inTime = null,
       color = null,
       mode = null,
       expression = null;

  const RenPyTransitionIntent.cropMove({
    required String this.mode,
    required double this.duration,
  }) : type = RenPyTransitionType.cropMove,
       fidelity = RenPyTransitionFidelity.approximated,
       outTime = null,
       holdTime = null,
       inTime = null,
       color = null,
       maskAsset = null,
       ramplen = null,
       reverse = false,
       expression = null;

  const RenPyTransitionIntent.punch({
    required String this.mode,
    required double this.duration,
  }) : type = RenPyTransitionType.punch,
       fidelity = RenPyTransitionFidelity.approximated,
       outTime = null,
       holdTime = null,
       inTime = null,
       color = null,
       maskAsset = null,
       ramplen = null,
       reverse = false,
       expression = null;

  const RenPyTransitionIntent.unsupported({required String this.expression})
    : type = RenPyTransitionType.unsupported,
      fidelity = RenPyTransitionFidelity.unsupported,
      duration = null,
      outTime = null,
      holdTime = null,
      inTime = null,
      color = null,
      maskAsset = null,
      ramplen = null,
      reverse = false,
      mode = null;

  final RenPyTransitionType type;
  final RenPyTransitionFidelity fidelity;
  final double? duration;
  final double? outTime;
  final double? holdTime;
  final double? inTime;
  final String? color;
  final String? maskAsset;
  final int? ramplen;
  final bool reverse;
  final String? mode;
  final String? expression;

  double get totalDuration {
    return switch (type) {
      RenPyTransitionType.none => 0,
      RenPyTransitionType.fade =>
        (outTime ?? 0) + (holdTime ?? 0) + (inTime ?? 0),
      _ => duration ?? 0,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyTransitionIntent &&
            type == other.type &&
            fidelity == other.fidelity &&
            duration == other.duration &&
            outTime == other.outTime &&
            holdTime == other.holdTime &&
            inTime == other.inTime &&
            color == other.color &&
            maskAsset == other.maskAsset &&
            ramplen == other.ramplen &&
            reverse == other.reverse &&
            mode == other.mode &&
            expression == other.expression;
  }

  @override
  int get hashCode {
    return Object.hash(
      type,
      fidelity,
      duration,
      outTime,
      holdTime,
      inTime,
      color,
      maskAsset,
      ramplen,
      reverse,
      mode,
      expression,
    );
  }

  @override
  String toString() {
    return switch (type) {
      RenPyTransitionType.none => 'RenPyTransitionIntent.none()',
      RenPyTransitionType.fade =>
        'RenPyTransitionIntent.fade(outTime: $outTime, '
            'holdTime: $holdTime, inTime: $inTime, color: $color)',
      RenPyTransitionType.dissolve =>
        'RenPyTransitionIntent.dissolve(duration: $duration)',
      RenPyTransitionType.imageDissolve =>
        'RenPyTransitionIntent.imageDissolve(maskAsset: $maskAsset, '
            'duration: $duration, ramplen: $ramplen, reverse: $reverse)',
      RenPyTransitionType.cropMove =>
        'RenPyTransitionIntent.cropMove(mode: $mode, duration: $duration)',
      RenPyTransitionType.punch =>
        'RenPyTransitionIntent.punch(mode: $mode, duration: $duration)',
      RenPyTransitionType.unsupported =>
        'RenPyTransitionIntent.unsupported(expression: $expression)',
    };
  }
}
