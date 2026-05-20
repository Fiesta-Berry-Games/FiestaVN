import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyRunner _runner(String source) {
  final script = RenPyParser().parse(source, 'pause_statement.rpy').script;
  return RenPyRunner(script);
}

void main() {
  group('pause statement', () {
    test('timed `pause 2.0` fires onPause and waits, no unknownStatement', () {
      final runner = _runner('''
label start:
    pause 2.0
    "After pause."
''');
      final pauses = <RenPyPauseEvent>[];
      final dialogue = <RenPyDialogueEvent>[];
      final diagnostics = <RenPyDiagnostic>[];
      runner.onPause = pauses.add;
      runner.onDialogueEvent = dialogue.add;
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      expect(runner.state, RenPyRunnerState.waitingForInput);
      expect(pauses, [const RenPyPauseEvent(duration: 2.0)]);
      expect(dialogue, isEmpty);
      expect(
        diagnostics.where(
          (d) => d.code == RenPyDiagnosticCode.unknownStatement,
        ),
        isEmpty,
      );

      runner.continueExecution();
      expect(dialogue.single.text, 'After pause.');
    });

    test(
      'bare `pause` fires onPause and waits for input, no unknownStatement',
      () {
        final runner = _runner('''
label start:
    pause
    "After pause."
''');
        final pauses = <RenPyPauseEvent>[];
        final dialogue = <RenPyDialogueEvent>[];
        final diagnostics = <RenPyDiagnostic>[];
        runner.onPause = pauses.add;
        runner.onDialogueEvent = dialogue.add;
        runner.onDiagnostic = diagnostics.add;

        runner.jumpToLabel('start');
        runner.run();

        expect(runner.state, RenPyRunnerState.waitingForInput);
        expect(pauses, [const RenPyPauseEvent()]);
        expect(
          diagnostics.where(
            (d) => d.code == RenPyDiagnosticCode.unknownStatement,
          ),
          isEmpty,
        );

        runner.continueExecution();
        expect(dialogue.single.text, 'After pause.');
      },
    );
  });
}
