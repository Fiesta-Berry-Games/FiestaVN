import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyRunner _runner(String source) {
  final result = RenPyParser().parse(source, 'runner_screen.rpy');
  return RenPyRunner(result.script);
}

/// A scope for parsing action argument expressions in tests. Action arguments
/// in these tests are literals, so an empty scope is sufficient.
RenPyPythonScope _literalScope() =>
    RenPyMapScope(store: <String, Object?>{}, persistent: <String, Object?>{});

/// Reads back a store value through a probe screen that surfaces it as text,
/// since the runner does not expose its private store map directly.
Object? _storeValue(RenPyRunner runner, String screen, String key) {
  final resolved = runner.resolveScreen(screen);
  final node = resolved!.children.firstWhere((c) => c.properties['id'] == key);
  return node.positional.first;
}

void main() {
  group('show screen / hide screen', () {
    test('show screen adds to the shown set and fires the hook', () {
      final runner = _runner('''
screen hud(level):
    text "[level]"

label start:
    show screen hud(3)
    "after"
''');
      final layers = <List<RenPyShownScreen>>[];
      runner.onScreenLayerChanged = (shown) => layers.add(shown);
      runner.run();

      expect(runner.shownScreens, hasLength(1));
      final shown = runner.shownScreens.single;
      expect(shown.name, 'hud');
      expect(shown.positional, [3]);
      expect(layers, isNotEmpty);
      expect(layers.last.single.name, 'hud');
    });

    test('hide screen removes the screen and fires the hook', () {
      final runner = _runner('''
screen hud():
    text "x"

label start:
    show screen hud
    hide screen hud
    "done"
''');
      var fires = 0;
      runner.onScreenLayerChanged = (_) => fires += 1;
      runner.run();

      expect(runner.shownScreens, isEmpty);
      expect(fires, 2);
    });

    test('a screen resolves against current state through the runner', () {
      final runner = _runner('''
default score = 7

screen scoreboard():
    text "score"
    textbutton "add" action SetVariable("score", 99)

label start:
    show screen scoreboard
    "wait"
''');
      runner.run();
      final resolved = runner.resolveScreen('scoreboard');
      expect(resolved, isNotNull);
      final button = resolved!.children.firstWhere(
        (c) => c.kind == 'textbutton',
      );
      expect(button.action!.kind, RenPyScreenActionKind.setVariable);
    });
  });

  group('executeScreenAction', () {
    test('SetVariable mutates the store', () {
      final runner = _runner('''
default score = 1

screen probe():
    text score id "score"

label start:
    "wait"
''');
      runner.run();
      expect(_storeValue(runner, 'probe', 'score'), 1);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith(
          'SetVariable("score", 50)',
          _literalScope(),
        ),
      );
      expect(_storeValue(runner, 'probe', 'score'), 50);
    });

    test('ToggleVariable flips a store flag', () {
      final runner = _runner('''
default flag = False

screen probe():
    text flag id "flag"

label start:
    "wait"
''');
      runner.run();
      expect(_storeValue(runner, 'probe', 'flag'), false);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith('ToggleVariable("flag")', _literalScope()),
      );
      expect(_storeValue(runner, 'probe', 'flag'), true);
    });

    test('ToggleField flips a field on a store object', () {
      final runner = _runner('''
default opts = {"muted": False}

screen probe():
    text opts["muted"] id "muted"

label start:
    "wait"
''');
      runner.run();
      expect(_storeValue(runner, 'probe', 'muted'), false);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith(
          'ToggleField(opts, "muted")',
          _literalScope(),
        ),
      );
      expect(_storeValue(runner, 'probe', 'muted'), true);
    });

    test('Jump routes into runner control flow', () {
      final runner = _runner('''
screen s():
    text "x"

label start:
    show screen s
    "first"

label elsewhere:
    "landed"
''');
      String? lastLine;
      runner.onDialogue = (_, text) => lastLine = text;
      runner.run();
      expect(lastLine, 'first');

      runner.executeScreenAction(
        RenPyScreenAction.parseWith('Jump("elsewhere")', _literalScope()),
      );
      runner.run();
      expect(runner.currentLabel, 'elsewhere');
      expect(lastLine, 'landed');
    });

    test('Return resolves a blocking call screen', () {
      final runner = _runner('''
screen confirm():
    textbutton "ok" action Return(True)

label start:
    call screen confirm
    "after call"
''');
      String? lastLine;
      runner.onDialogue = (_, text) => lastLine = text;
      runner.run();

      // Blocked on the call screen, waiting for a Return.
      expect(runner.pendingCallScreen, isNotNull);
      expect(runner.pendingCallScreen!.name, 'confirm');
      expect(runner.pendingCallScreen!.isCall, isTrue);
      expect(runner.state, RenPyRunnerState.waitingForInput);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith('Return(True)', _literalScope()),
      );
      expect(runner.pendingCallScreen, isNull);
      expect(lastLine, 'after call');
    });

    test('call screen captures args and the Return value reaches the '
        'script', () {
      final runner = _runner('''
screen confirm(message):
    text "[message]"
    textbutton "yes" action Return(True)

label start:
    call screen confirm("Quit?")
    \$ answered = _return
    if answered:
        "quit"
    else:
        "stay"
''');
      String? lastLine;
      runner.onDialogue = (_, text) => lastLine = text;
      runner.run();

      // The screen name and its evaluated argument are recoverable.
      expect(runner.pendingCallScreen, isNotNull);
      expect(runner.pendingCallScreen!.name, 'confirm');
      expect(runner.pendingCallScreen!.positional, ['Quit?']);

      // The screen resolves live against the bound argument.
      final resolved = runner.resolveScreen(
        runner.pendingCallScreen!.name,
        positional: runner.pendingCallScreen!.positional,
        keywords: runner.pendingCallScreen!.keywords,
      );
      expect(resolved, isNotNull);
      expect(
        resolved!.children.firstWhere((c) => c.kind == 'text').interpolatedText,
        'Quit?',
      );

      runner.executeScreenAction(
        RenPyScreenAction.parseWith('Return(True)', _literalScope()),
      );
      expect(runner.pendingCallScreen, isNull);
      expect(lastLine, 'quit');
    });

    test('a pending call screen is not on the shown screen set', () {
      final runner = _runner('''
screen confirm():
    textbutton "ok" action Return(True)

label start:
    call screen confirm
    "after call"
''');
      runner.run();

      expect(runner.pendingCallScreen, isNotNull);
      expect(runner.shownScreens, isEmpty);
    });
  });
}
