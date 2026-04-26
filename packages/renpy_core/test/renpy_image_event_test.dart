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

  test('runner preserves pixel units in Position placement intent', () {
    final script =
        RenPyParser().parse('''
label start:
    show title at Position(xpos = 400, ypos = 300, xanchor = 0.5, yanchor = 0.5)
''', 'image_pixel_position.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(
      events.single.placement,
      const RenPyImagePlacement.position(
        xpos: 400,
        ypos: 300,
        xanchor: 0.5,
        yanchor: 0.5,
        xposIsPixel: true,
        yposIsPixel: true,
      ),
    );
  });
  test('runner preserves Transform scale placement intent', () {
    final script =
        RenPyParser().parse('''
label start:
    show sylvie green normal at Transform(zoom = 1.5, xzoom = 1.2, yzoom = 0.75)
''', 'image_transform_scale.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(
      events.single.placement,
      const RenPyImagePlacement.position(zoom: 1.5, xzoom: 1.2, yzoom: 0.75),
    );
  });

  test('runner resolves simple named transform placement intent', () {
    final script =
        RenPyParser().parse('''
transform small_left:
    xpos 0.25
    xanchor 0.5
    ypos 0.5
    yanchor 0.5
    zoom 0.5

label start:
    show logo at small_left
''', 'image_named_transform.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];
    final diagnostics = <RenPyDiagnostic>[];

    runner.onImageEvent = events.add;
    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(
      events.single.placement,
      const RenPyImagePlacement.position(
        xpos: 0.25,
        xanchor: 0.5,
        ypos: 0.5,
        yanchor: 0.5,
        zoom: 0.5,
      ),
    );
    expect(diagnostics, isEmpty);
  });

  test('runner emits onlayer metadata separately from image names', () {
    final script =
        RenPyParser().parse('''
label start:
    show meta onlayer belowmid with longdissolve
    hide logo onlayer abovemid with dissolve
''', 'image_onlayer.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(events, [
      const RenPyImageEvent.show('meta', onLayer: 'belowmid'),
      const RenPyImageEvent.hide('logo', onLayer: 'abovemid'),
    ]);
  });

  test('runner emits show zorder metadata', () {
    final script =
        RenPyParser().parse('''
label start:
    show logo zorder 10 onlayer abovemid
    show title zorder -5
''', 'image_zorder.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(events, [
      const RenPyImageEvent.show('logo', onLayer: 'abovemid', zOrder: 10),
      const RenPyImageEvent.show('title', zOrder: -5),
    ]);
  });

  test('runner emits scene zorder metadata', () {
    final script =
        RenPyParser().parse('''
label start:
    scene overlay onlayer abovemid zorder 10
''', 'scene_zorder.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];

    runner.onImageEvent = events.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(events, [
      const RenPyImageEvent.scene('overlay', onLayer: 'abovemid', zOrder: 10),
    ]);
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

  test('runner uses explicit show text tags for hideable displayables', () {
    final script =
        RenPyParser().parse('''
label start:
    show text "Chapter One" as title at truecenter
    hide title with dissolve
''', 'image.rpy').script;
    final runner = RenPyRunner(script);
    final events = <RenPyImageEvent>[];
    final transitions = <RenPyTransitionEvent>[];

    runner.onImageEvent = events.add;
    runner.onTransition = transitions.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(events, [
      const RenPyImageEvent.show(
        'title',
        at: 'truecenter',
        placement: RenPyImagePlacement.position(
          xpos: 0.5,
          xanchor: 0.5,
          ypos: 0.5,
          yanchor: 0.5,
        ),
        displayableText: 'Chapter One',
      ),
      const RenPyImageEvent.hide('title'),
    ]);
    expect(transitions.single.name, 'dissolve');
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
