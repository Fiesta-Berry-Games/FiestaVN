import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

const _eileen = '''
layeredimage eileen:
    always:
        "eileen_base"
    group outfit:
        attribute casual default:
            "eileen_casual"
        attribute formal:
            "eileen_formal"
    group face:
        attribute smile:
            "eileen_smile"
        attribute frown:
            "eileen_frown"
''';

List<List<String>> _showLayers(String body) {
  final script = RenPyParser().parse('$_eileen\n$body', 'layered.rpy').script;
  final runner = RenPyRunner(script);
  final layers = <List<String>>[];
  runner.onImageEvent = (event) {
    if (event.action == RenPyImageAction.show) layers.add(event.layers);
  };
  runner.jumpToLabel('start');
  runner.run();
  return layers;
}

void main() {
  group('layeredimage resolution', () {
    test('show eileen casual smile resolves to [base, casual, smile]', () {
      final layers = _showLayers('''
label start:
    show eileen casual smile
''');
      expect(layers, [
        ['eileen_base', 'eileen_casual', 'eileen_smile'],
      ]);
    });

    test('incremental show keeps the outfit and swaps the face', () {
      final layers = _showLayers('''
label start:
    show eileen casual smile
    show eileen frown
''');
      expect(layers, [
        ['eileen_base', 'eileen_casual', 'eileen_smile'],
        ['eileen_base', 'eileen_casual', 'eileen_frown'],
      ]);
    });

    test('default applies when a group attribute is omitted', () {
      final layers = _showLayers('''
label start:
    show eileen smile
''');
      // outfit omitted -> default `casual`; face -> smile.
      expect(layers, [
        ['eileen_base', 'eileen_casual', 'eileen_smile'],
      ]);
    });

    test('explicit non-default attribute overrides the default', () {
      final layers = _showLayers('''
label start:
    show eileen formal frown
''');
      expect(layers, [
        ['eileen_base', 'eileen_formal', 'eileen_frown'],
      ]);
    });

    test('a normal (non-layeredimage) show carries no layers', () {
      final script =
          RenPyParser().parse('''
label start:
    show sylvie green normal
''', 'plain.rpy').script;
      final runner = RenPyRunner(script);
      final events = <RenPyImageEvent>[];
      runner.onImageEvent = events.add;
      runner.jumpToLabel('start');
      runner.run();

      expect(events.single.layers, isEmpty);
    });

    test('hide then re-show resets to defaults', () {
      final layers = _showLayers('''
label start:
    show eileen formal frown
    hide eileen
    show eileen smile
''');
      expect(layers, [
        ['eileen_base', 'eileen_formal', 'eileen_frown'],
        ['eileen_base', 'eileen_casual', 'eileen_smile'],
      ]);
    });
  });
}
