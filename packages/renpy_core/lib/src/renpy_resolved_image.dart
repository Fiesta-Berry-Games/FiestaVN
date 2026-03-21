/// A display operation requested by a RenPy image expression.
enum RenPyImageOperationType { grayscale, sepia, matrixColor, flipHorizontal }

/// Platform-neutral display operation metadata.
class RenPyImageOperation {
  const RenPyImageOperation.grayscale()
    : type = RenPyImageOperationType.grayscale,
      tintRed = null,
      tintGreen = null,
      tintBlue = null;

  const RenPyImageOperation.sepia()
    : type = RenPyImageOperationType.sepia,
      tintRed = null,
      tintGreen = null,
      tintBlue = null;

  const RenPyImageOperation.flipHorizontal()
    : type = RenPyImageOperationType.flipHorizontal,
      tintRed = null,
      tintGreen = null,
      tintBlue = null;

  const RenPyImageOperation.matrixColor({
    required double this.tintRed,
    required double this.tintGreen,
    required double this.tintBlue,
  }) : type = RenPyImageOperationType.matrixColor;

  final RenPyImageOperationType type;
  final double? tintRed;
  final double? tintGreen;
  final double? tintBlue;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyImageOperation &&
            type == other.type &&
            tintRed == other.tintRed &&
            tintGreen == other.tintGreen &&
            tintBlue == other.tintBlue;
  }

  @override
  int get hashCode => Object.hash(type, tintRed, tintGreen, tintBlue);

  @override
  String toString() {
    return switch (type) {
      RenPyImageOperationType.grayscale => 'RenPyImageOperation.grayscale()',
      RenPyImageOperationType.sepia => 'RenPyImageOperation.sepia()',
      RenPyImageOperationType.flipHorizontal =>
        'RenPyImageOperation.flipHorizontal()',
      RenPyImageOperationType.matrixColor =>
        'RenPyImageOperation.matrixColor('
            'tintRed: $tintRed, tintGreen: $tintGreen, '
            'tintBlue: $tintBlue)',
    };
  }
}

/// A resolved RenPy image source and any display operations requested for it.
class RenPyResolvedImage {
  const RenPyResolvedImage({
    required String this.assetPath,
    this.operations = const [],
  }) : solidColor = null;

  const RenPyResolvedImage.solid(this.solidColor, {this.operations = const []})
    : assetPath = null;

  final String? assetPath;
  final RenPyColorValue? solidColor;
  final List<RenPyImageOperation> operations;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyResolvedImage &&
            assetPath == other.assetPath &&
            solidColor == other.solidColor &&
            _listEquals(operations, other.operations);
  }

  @override
  int get hashCode {
    return Object.hash(assetPath, solidColor, Object.hashAll(operations));
  }

  @override
  String toString() {
    return 'RenPyResolvedImage(assetPath: $assetPath, '
        'solidColor: $solidColor, '
        'operations: $operations)';
  }
}

/// Platform-neutral RGBA color used by RenPy solid displayables.
class RenPyColorValue {
  const RenPyColorValue(this.red, this.green, this.blue, this.alpha);

  final int red;
  final int green;
  final int blue;
  final int alpha;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyColorValue &&
            red == other.red &&
            green == other.green &&
            blue == other.blue &&
            alpha == other.alpha;
  }

  @override
  int get hashCode => Object.hash(red, green, blue, alpha);

  @override
  String toString() {
    return 'RenPyColorValue(red: $red, green: $green, '
        'blue: $blue, alpha: $alpha)';
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
