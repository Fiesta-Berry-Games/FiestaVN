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

  /// A `define`/`default` right-hand side could not be evaluated and fell back
  /// to its literal source (e.g. an unmodeled displayable like `Borders(...)`).
  /// This is a load-time config/styling gap, distinct from a runtime gameplay
  /// [skippedPython] skip, so hosts can surface it without treating it as a
  /// flow-breaking compatibility gap.
  skippedDefinition,
  unsupportedPlacement,
  unsupportedTransition,
  unresolvedImageAsset,
  unresolvedAudioAsset,
  unknownStatement,
  skippedScreen,
}

typedef RenPyDiagnosticCallback = void Function(RenPyDiagnostic diagnostic);
