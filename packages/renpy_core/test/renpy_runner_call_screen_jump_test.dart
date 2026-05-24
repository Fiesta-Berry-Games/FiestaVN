import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyRunner _runner(String source) {
  final result = RenPyParser().parse(source, 'call_screen_jump.rpy');
  return RenPyRunner(result.script);
}

RenPyPythonScope _literalScope() =>
    RenPyMapScope(store: <String, Object?>{}, persistent: <String, Object?>{});

void main() {
  group('executeScreenAction Jump/Call dismiss a blocking call screen', () {
    test('Jump dismisses the call screen and runs the target', () {
      final runner = _runner('''
screen confirm():
    textbutton "leave" action Jump("elsewhere")

label start:
    call screen confirm
    "after call"

label elsewhere:
    "jumped away"
''');
      final lines = <String>[];
      runner.onDialogue = (_, text) => lines.add(text);
      runner.run();

      // Blocked on the call screen, waiting for an action.
      expect(runner.pendingCallScreen, isNotNull);
      expect(runner.state, RenPyRunnerState.waitingForInput);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith('Jump("elsewhere")', _literalScope()),
      );

      // Pre-fix: the call screen stayed pending and the jump target never ran.
      expect(runner.pendingCallScreen, isNull);
      expect(runner.shownScreens.any((s) => s.tag == 'confirm'), isFalse);
      expect(lines, contains('jumped away'));
      expect(lines, isNot(contains('after call')));
      expect(runner.state, isNot(RenPyRunnerState.error));
    });

    test('Call dismisses the call screen and runs the target', () {
      final runner = _runner('''
screen confirm():
    textbutton "go" action Call("sub")

label start:
    call screen confirm
    "after call"

label sub:
    "inside sub"
    return
''');
      final lines = <String>[];
      runner.onDialogue = (_, text) => lines.add(text);
      runner.run();

      expect(runner.pendingCallScreen, isNotNull);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith('Call("sub")', _literalScope()),
      );

      expect(runner.pendingCallScreen, isNull);
      expect(runner.shownScreens.any((s) => s.tag == 'confirm'), isFalse);
      expect(lines, contains('inside sub'));
      expect(runner.state, isNot(RenPyRunnerState.error));
    });
  });
}
