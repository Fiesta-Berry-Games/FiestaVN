import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner emits image events with placement metadata', () {
    final script =
        RenPyParser().parse('''
label start:
    scene bg lecturehall at center
    show sylvie green normal at left
    hide sylvie
''', 'image.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];
    final legacy = <String>[];

    runner.onImageEvent = events.add;
    runner.onImage = (scene, show, hide) {
      legacy.add('${scene ?? '-'}|${show ?? '-'}|${hide ?? '-'}');
    };

    runner.jumpToLabel('start');
    runner.run();

    expect(runner.state, RenPyRunnerState.complete);
    expect(events, [
      const RenPyImageEvent.scene(
        'bg lecturehall',
        at: 'center',
        placement: RenPyImagePlacement.position(
          xpos: 0.5,
          xanchor: 0.5,
          ypos: 1,
          yanchor: 1,
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
      const RenPyImageEvent.hide('sylvie'),
    ]);
    expect(legacy, [
      'bg lecturehall|-|-',
      '-|sylvie green normal|-',
      '-|-|sylvie',
    ]);
  });

  test('runner emits structured image placement intent', () {
    final script =
        RenPyParser().parse('''
label start:
    show eri defa2 at Position(xpos = 0.2)
    show enj fumana2 at Position(xpos = 0.8, yalign = 1.0)
    show beatrice at truecenter
    show eri defa2bw at Position(xpos = 0.25) behind enj
''', 'image.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(events[0].placement, const RenPyImagePlacement.position(xpos: 0.2));
    expect(
      events[1].placement,
      const RenPyImagePlacement.position(xpos: 0.8, yalign: 1.0),
    );
    expect(
      events[2].placement,
      const RenPyImagePlacement.position(
        xpos: 0.5,
        xanchor: 0.5,
        ypos: 0.5,
        yanchor: 0.5,
      ),
    );
    expect(events[3].placement, const RenPyImagePlacement.position(xpos: 0.25));
    expect(events[3].at, 'Position(xpos = 0.25)');
    expect(events[3].behind, 'enj');
  });

  test('runner emits show text displayables as structured image events', () {
    final script =
        RenPyParser().parse('''
label start:
    show text "{color=#FFF}Confession{/color}" at truecenter with dissolve
''', 'image.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(events.single.imageName, 'text');
    expect(events.single.displayableText, '{color=#FFF}Confession{/color}');
    expect(
      events.single.placement,
      const RenPyImagePlacement.position(
        xpos: 0.5,
        xanchor: 0.5,
        ypos: 0.5,
        yanchor: 0.5,
      ),
    );
  });

  test('runner emits runtime image definition events', () {
    final script =
        RenPyParser().parse('''
label start:
    image flashback bg = im.Grayscale("/bg/flashback.jpg")
    scene flashback bg
''', 'image.rpy').script;
    final runner = RenPyRunner(script);
    final definitions = <RenPyImageDefinitionEvent>[];
    final images = <RenPyImageEvent>[];

    runner.onImageDefinition = definitions.add;
    runner.onImageEvent = images.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(definitions, [
      const RenPyImageDefinitionEvent(
        name: 'flashback bg',
        expression: 'im.Grayscale("/bg/flashback.jpg")',
      ),
    ]);
    expect(images, [const RenPyImageEvent.scene('flashback bg')]);
  });
}
