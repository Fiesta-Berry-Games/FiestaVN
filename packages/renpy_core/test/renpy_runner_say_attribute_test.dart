import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyRunner _runner(String source) {
  final script = RenPyParser().parse(source, 'say_attribute.rpy').script;
  return RenPyRunner(script);
}

void main() {
  group('@-say temporary attribute sprite swap', () {
    test('swaps to the temp attribute for the line, then reverts', () {
      final runner = _runner('''
define a = Character("Annika", image="annika")

label start:
    show annika happy
    a @ laugh "Ha!"
    a "Back to normal."
''');
      final shows = <String?>[];
      runner.onImageEvent = (event) {
        if (event.action == RenPyImageAction.show) {
          shows.add(event.imageName);
        }
      };
      runner.jumpToLabel('start');
      runner.run();

      // The initial show plus the temporary-attribute swap have fired.
      expect(shows, contains('annika happy'));
      expect(shows, contains('annika laugh'));
      // The swap shows after the base sprite.
      expect(
        shows.indexOf('annika laugh'),
        greaterThan(shows.indexOf('annika happy')),
      );

      shows.clear();
      // Dismiss the `@` line: the sprite reverts to its prior attributes.
      runner.continueExecution();
      expect(shows, contains('annika happy'));
    });

    test('falls back to the speaker id as the tag when no image= is set', () {
      final runner = _runner('''
label start:
    show eileen vhappy
    eileen @ cry "..."
''');
      final shows = <String?>[];
      runner.onImageEvent = (event) {
        if (event.action == RenPyImageAction.show) {
          shows.add(event.imageName);
        }
      };
      runner.jumpToLabel('start');
      runner.run();

      expect(shows, contains('eileen cry'));
    });

    test('reverts on the interior-wait + trailing-{nw} path (no leak)', () {
      final runner = _runner('''
define a = Character("Annika", image="annika")

label start:
    show annika happy
    a @ laugh "Ha!{w} more{nw}"
    a "Back to normal."
''');
      final shows = <String?>[];
      runner.onImageEvent = (event) {
        if (event.action == RenPyImageAction.show) {
          shows.add(event.imageName);
        }
      };
      runner.jumpToLabel('start');
      runner.run();

      // The temp attribute is applied for the line.
      expect(shows, contains('annika laugh'));

      shows.clear();
      // Advance through the interior {w} wait; the line then resolves through
      // the trailing {nw} path, which must revert the temp sprite before
      // advancing to the next line so it does not leak.
      runner.continueExecution();
      expect(shows, contains('annika happy'));
    });

    test('no shown sprite means no swap and no throw', () {
      final runner = _runner('''
define a = Character("Annika", image="annika")

label start:
    a @ laugh "Ha!"
''');
      final shows = <String?>[];
      runner.onImageEvent = (event) {
        if (event.action == RenPyImageAction.show) {
          shows.add(event.imageName);
        }
      };
      runner.jumpToLabel('start');
      runner.run();

      // Nothing shown beforehand, so no swap event fired.
      expect(shows, isEmpty);
      expect(runner.state, isNot(RenPyRunnerState.error));
    });
  });
}
