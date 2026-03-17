import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner emits untimed renpy.pause and waits for continuation', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.pause()
    "After pause."
''', 'pause.rpy').script;
    final runner = RenPyRunner(script);
    final pauses = <RenPyPauseEvent>[];
    final dialogue = <RenPyDialogueEvent>[];

    runner.onPause = pauses.add;
    runner.onDialogueEvent = dialogue.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.waitingForInput);
    expect(pauses, [const RenPyPauseEvent()]);
    expect(dialogue, isEmpty);

    runner.continueExecution();

    expect(dialogue.single.text, 'After pause.');
  });

  test('runner emits timed renpy.pause duration', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.pause(1.25)
    "After pause."
''', 'pause.rpy').script;
    final runner = RenPyRunner(script);
    final pauses = <RenPyPauseEvent>[];

    runner.onPause = pauses.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.waitingForInput);
    expect(pauses, [const RenPyPauseEvent(duration: 1.25)]);
  });
}
