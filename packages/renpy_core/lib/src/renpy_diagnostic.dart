/// Machine-readable compatibility signal produced while running a RenPy script.
final class RenPyDiagnostic {
  const RenPyDiagnostic({
    required this.code,
    required this.message,
    this.detail,
  });

  final RenPyDiagnosticCode code;
  final String message;
  final String? detail;

  @override
  String toString() {
    final detail = this.detail;
    return detail == null
        ? 'RenPyDiagnostic($code, $message)'
        : 'RenPyDiagnostic($code, $message, detail: $detail)';
  }
}

enum RenPyDiagnosticCode {
  skippedPython,
  unsupportedPlacement,
  unsupportedTransition,
  unresolvedImageAsset,
  unresolvedAudioAsset,
  unknownStatement,
}

typedef RenPyDiagnosticCallback = void Function(RenPyDiagnostic diagnostic);
