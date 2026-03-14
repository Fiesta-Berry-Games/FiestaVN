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
      const RenPyImageEvent.scene('bg lecturehall', at: 'center'),
      const RenPyImageEvent.show('sylvie green normal', at: 'left'),
      const RenPyImageEvent.hide('sylvie'),
    ]);
    expect(legacy, [
      'bg lecturehall|-|-',
      '-|sylvie green normal|-',
      '-|-|sylvie',
    ]);
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
