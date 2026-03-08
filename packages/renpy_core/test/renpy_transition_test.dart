import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner emits structured transition events', () {
    final script =
        RenPyParser().parse('''
label start:
    scene bg lecturehall
    with fade
    show sylvie green normal
    with dissolve
''', 'transition.rpy').script;
    final runner = RenPyRunner(script);
    final transitions = <RenPyTransitionEvent>[];

    runner.onTransition = transitions.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(transitions, [
      const RenPyTransitionEvent('fade'),
      const RenPyTransitionEvent('dissolve'),
    ]);
  });
}
