import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// The runner must reach a parameterized entry label `label start():` and bind
/// a label's formal parameters at entry (to their defaults, or null when none),
/// so a body that reads a parameter doesn't NameError.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source, {String label = 'start'}) {
    final script = RenPyParser().parse(source, 'labels.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel(label);
    runner.run();
    return (dialogue: dialogue, diagnostics: diagnostics, runner: runner);
  }

  test('a parameterized start label is reachable', () {
    final result = play('label start():\n    "Hello"\n');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.dialogue, ['Hello']);
  });

  test('a label parameter default is bound at entry', () {
    final result = play('''
label start(greeting="Hi there"):
    "[greeting]"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['greeting'], 'Hi there');
  });

  test('a parameter without a default binds to null', () {
    final result = play('''
label start(x):
    "done"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    final vars = result.runner.snapshot().variables;
    expect(vars.containsKey('x'), isTrue);
    expect(vars['x'], isNull);
  });

  test('varargs bind to an empty list/dict', () {
    final result = play('''
label start(a, *args, **kwargs):
    "done"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    final vars = result.runner.snapshot().variables;
    expect(vars['args'], <dynamic>[]);
    expect(vars['kwargs'], <dynamic, dynamic>{});
  });

  test('a jumped-to parameterized label binds its defaults', () {
    final result = play('''
label start():
    jump greet

label greet(name="World"):
    "Hi [name]"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'World');
  });
}
