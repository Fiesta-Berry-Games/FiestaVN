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
      const RenPyTransitionEvent(
        'fade',
        intent: RenPyTransitionIntent.fade(
          outTime: 0.5,
          holdTime: 0,
          inTime: 0.5,
        ),
      ),
      const RenPyTransitionEvent(
        'dissolve',
        intent: RenPyTransitionIntent.dissolve(duration: 0.5),
      ),
    ]);
  });

  test('runner emits inline image transitions after image events', () {
    final script =
        RenPyParser().parse('''
label start:
    scene bg lecturehall with fade
    show sylvie green normal at left with dissolve
''', 'transition.rpy').script;
    final runner = RenPyRunner(script);
    final events = <Object>[];

    runner.onImageEvent = events.add;
    runner.onTransition = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(events, [
      const RenPyImageEvent.scene('bg lecturehall'),
      const RenPyTransitionEvent(
        'fade',
        intent: RenPyTransitionIntent.fade(
          outTime: 0.5,
          holdTime: 0,
          inTime: 0.5,
        ),
      ),
      const RenPyImageEvent.show(
        'sylvie green normal',
        at: 'left',
        placement: RenPyImagePlacement.position(
          xpos: 0,
          xanchor: 0,
          ypos: 1,
          yanchor: 1,
        ),
      ),
      const RenPyTransitionEvent(
        'dissolve',
        intent: RenPyTransitionIntent.dissolve(duration: 0.5),
      ),
    ]);
  });

  test('runner emits transition intent from RenPy definitions', () {
    final script =
        RenPyParser().parse('''
define openfade = Fade(1.5, 2.0, 2.0, color="#fff")
define longerdissolve = Dissolve(2.5)
define quickgradientwiperight = ImageDissolve("right.png", 1.5, ramplen = 16)

label start:
    scene black with openfade
    scene bg library with longerdissolve
    scene bg hallway with quickgradientwiperight
''', 'transition.rpy').script;
    final runner = RenPyRunner(script);
    final transitions = <RenPyTransitionEvent>[];

    runner.onTransition = transitions.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(transitions, hasLength(3));
    expect(
      transitions[0].intent,
      const RenPyTransitionIntent.fade(
        outTime: 1.5,
        holdTime: 2.0,
        inTime: 2.0,
        color: '#fff',
      ),
    );
    expect(
      transitions[1].intent,
      const RenPyTransitionIntent.dissolve(duration: 2.5),
    );
    expect(
      transitions[2].intent,
      const RenPyTransitionIntent.imageDissolve(
        maskAsset: 'right.png',
        duration: 1.5,
        ramplen: 16,
      ),
    );
  });

  test('runner resolves block-style transition clauses without colon', () {
    final script =
        RenPyParser().parse('''
define longerdissolve = Dissolve(2.5)

label start:
    show logo with longerdissolve:
        pause 1.0
    with longerdissolve:
        pause 0.5
''', 'transition_block.rpy').script;
    final runner = RenPyRunner(script);
    final transitions = <RenPyTransitionEvent>[];

    runner.onTransition = transitions.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(transitions, [
      const RenPyTransitionEvent(
        'longerdissolve',
        intent: RenPyTransitionIntent.dissolve(duration: 2.5),
      ),
      const RenPyTransitionEvent(
        'longerdissolve',
        intent: RenPyTransitionIntent.dissolve(duration: 2.5),
      ),
    ]);
  });

  test('runner emits approximated punch transition intent', () {
    final script =
        RenPyParser().parse('''
label start:
    with vpunch
    with hpunch
''', 'transition.rpy').script;
    final runner = RenPyRunner(script);
    final transitions = <RenPyTransitionEvent>[];

    runner.onTransition = transitions.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(transitions, [
      const RenPyTransitionEvent(
        'vpunch',
        intent: RenPyTransitionIntent.punch(mode: 'vertical', duration: 0.275),
      ),
      const RenPyTransitionEvent(
        'hpunch',
        intent: RenPyTransitionIntent.punch(
          mode: 'horizontal',
          duration: 0.275,
        ),
      ),
    ]);
  });
}
