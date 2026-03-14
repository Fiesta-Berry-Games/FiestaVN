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
    required this.assetPath,
    this.operations = const [],
  });

  final String assetPath;
  final List<RenPyImageOperation> operations;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyResolvedImage &&
            assetPath == other.assetPath &&
            _listEquals(operations, other.operations);
  }

  @override
  int get hashCode => Object.hash(assetPath, Object.hashAll(operations));

  @override
  String toString() {
    return 'RenPyResolvedImage(assetPath: $assetPath, '
        'operations: $operations)';
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i += 1) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
