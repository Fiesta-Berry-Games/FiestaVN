import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner reports skipped compatibility constructs', () {
    final script =
        RenPyParser().parse('''
define strange = PushMove(1.0, "left")

label start:
    scene bg library at Transform(xzoom=1.2) with strange
    \$ persistent.confession_finished = True
    "Done."
''', 'diagnostics.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(
      diagnostics.map((diagnostic) => diagnostic.code),
      containsAll([
        RenPyDiagnosticCode.unsupportedPlacement,
        RenPyDiagnosticCode.unsupportedTransition,
        RenPyDiagnosticCode.skippedPython,
      ]),
    );
    expect(
      diagnostics.map((diagnostic) => diagnostic.detail),
      contains('persistent.confession_finished = True'),
    );
  });
}
