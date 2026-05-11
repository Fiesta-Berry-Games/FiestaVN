import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('define config./gui. seeds the namespaces for later reads', () {
    final script =
        RenPyParser().parse('''
define config.has_voice = True
define gui.text_size = 22

label start:
    \$ y = gui.text_size + 1
    if config.has_voice:
        "Voice on."
    else:
        "Voice off."
    if y == 23:
        "Computed from gui."
''', 'namespace.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    _finish(runner);

    expect(dialogue, ['Voice on.', 'Computed from gui.']);
  });

  test('default persistent. only seeds when absent and survives reset', () {
    final script =
        RenPyParser().parse('''
default persistent.seen = False
default config.fast = True

label start:
    if persistent.seen:
        "Seen before."
    else:
        "First time."
    \$ persistent.seen = True
''', 'namespace.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    _finish(runner);

    expect(dialogue, ['First time.']);
    expect(runner.persistent['seen'], isTrue);

    // A reset rebuilds config/gui from defines but preserves persistent, so the
    // `default persistent.seen = False` must not clobber the surviving `True`.
    dialogue.clear();
    runner.reset();
    runner.jumpToLabel('start');
    runner.run();
    _finish(runner);

    expect(dialogue, ['Seen before.']);
  });

  test('bare define/default names keep their store behavior', () {
    final script =
        RenPyParser().parse('''
default count = 0
define greeting = "hi"

label start:
    \$ count = count + 5
    if count == 5 and greeting == "hi":
        "Both bare names resolved."
''', 'namespace.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    _finish(runner);

    expect(dialogue, ['Both bare names resolved.']);
  });

  test('config./gui. assignments inside python blocks round-trip', () {
    final script =
        RenPyParser().parse('''
define gui.base = 10

label start:
    python:
        gui.derived = gui.base * 2
        config.flag = gui.derived > 15
    if config.flag:
        "Flag set."
    if gui.derived == 20:
        "Derived twenty."
''', 'namespace.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];

    runner.onDialogue = (character, text) => dialogue.add(text);

    runner.jumpToLabel('start');
    runner.run();
    _finish(runner);

    expect(dialogue, ['Flag set.', 'Derived twenty.']);
  });
}

void _finish(RenPyRunner runner) {
  var guard = 0;
  while (runner.state == RenPyRunnerState.waitingForInput && guard++ < 200) {
    runner.continueExecution();
  }
}
