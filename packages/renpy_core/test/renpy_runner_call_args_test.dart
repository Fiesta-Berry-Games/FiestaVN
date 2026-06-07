import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests that `call label(args)` evaluates and forwards its arguments to the
/// target label's formal parameters, mirroring Ren'Py's call-with-arguments
/// semantics.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source, {String label = 'start'}) {
    final script = RenPyParser().parse(source, 'test.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel(label);
    runner.run();
    return (dialogue: dialogue, diagnostics: diagnostics, runner: runner);
  }

  test('call passes a positional string arg to a parameterized label', () {
    final result = play('''
label start:
    call greet("World")
    return

label greet(name):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'World');
  });

  test('call passes multiple positional args', () {
    final result = play('''
label start:
    call greet("Hello", "World")
    return

label greet(greeting, name):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    final vars = result.runner.snapshot().variables;
    expect(vars['greeting'], 'Hello');
    expect(vars['name'], 'World');
  });

  test('call with empty parens uses defaults', () {
    final result = play('''
label start:
    call greet()
    return

label greet(name="Default"):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'Default');
  });

  test('call passes an integer arg', () {
    final result = play('''
label start:
    call show_number(42)
    return

label show_number(n):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['n'], 42);
  });

  test('call with keyword argument', () {
    final result = play('''
label start:
    call greet(name="Alice")
    return

label greet(name):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'Alice');
  });

  test('call without parens uses defaults for parameterized label', () {
    final result = play('''
label start:
    call greet
    return

label greet(name="Stranger"):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'Stranger');
  });

  test('call arg overrides default', () {
    final result = play('''
label start:
    call greet("Override")
    return

label greet(name="Default"):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'Override');
  });

  test('call with from clause preserves args', () {
    final result = play('''
label start:
    call greet("World") from start_greet
    return

label greet(name):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    expect(result.runner.snapshot().variables['name'], 'World');
  });

  test('excess positional args collect into *args', () {
    final result = play('''
label start:
    call greet("a", "b", "c")
    return

label greet(first, *rest):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    final vars = result.runner.snapshot().variables;
    expect(vars['first'], 'a');
    expect(vars['rest'], ['b', 'c']);
  });

  test('excess keyword args collect into **kwargs', () {
    final result = play('''
label start:
    call greet(name="A", extra="B")
    return

label greet(name, **kw):
    "hi"
''');
    expect(result.runner.state, isNot(RenPyRunnerState.error));
    final vars = result.runner.snapshot().variables;
    expect(vars['name'], 'A');
    expect(vars['kw'], {'extra': 'B'});
  });
}
