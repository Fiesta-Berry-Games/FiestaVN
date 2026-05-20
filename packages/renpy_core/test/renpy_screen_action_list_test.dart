import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyRunner _runner(String source) {
  final result = RenPyParser().parse(source, 'screen_action_list.rpy');
  return RenPyRunner(result.script);
}

RenPyPythonScope _literalScope() =>
    RenPyMapScope(store: <String, Object?>{}, persistent: <String, Object?>{});

void main() {
  group('list-of-actions [A, B] parsing', () {
    test('a top-level list literal parses to a multiple action', () {
      final action = RenPyScreenAction.parseWith(
        '[Hide("foo"), Return()]',
        _literalScope(),
      );
      expect(action.kind, RenPyScreenActionKind.multiple);
      expect(action.actions, hasLength(2));
      expect(action.actions[0].kind, RenPyScreenActionKind.hideScreen);
      expect(action.actions[0].screenName, 'foo');
      expect(action.actions[1].kind, RenPyScreenActionKind.returnValue);
      expect(action.raw, '[Hide("foo"), Return()]');
    });

    test('empty/whitespace elements are skipped', () {
      final action = RenPyScreenAction.parseWith(
        '[ Return(), ,  ]',
        _literalScope(),
      );
      expect(action.kind, RenPyScreenActionKind.multiple);
      expect(action.actions, hasLength(1));
      expect(action.actions.single.kind, RenPyScreenActionKind.returnValue);
    });

    test('an empty list is a no-op sequence, not a null action', () {
      final action = RenPyScreenAction.parseWith('[]', _literalScope());
      expect(action.kind, RenPyScreenActionKind.multiple);
      expect(action.actions, isEmpty);
    });

    test('nested commas inside an element are respected', () {
      final action = RenPyScreenAction.parseWith(
        '[SetVariable("x", 1), Return(True)]',
        _literalScope(),
      );
      expect(action.actions, hasLength(2));
      expect(action.actions[0].kind, RenPyScreenActionKind.setVariable);
      expect(action.actions[0].target, 'x');
      expect(action.actions[1].kind, RenPyScreenActionKind.returnValue);
    });
  });

  group('executeScreenAction(multiple)', () {
    test(
      '[Hide(...), Return()] hides then resolves a blocking call screen',
      () {
        final runner = _runner('''
screen titlecard():
    text "loading"

label start:
    call screen titlecard
    "after call"
''');
        String? lastLine;
        runner.onDialogue = (_, text) => lastLine = text;
        runner.run();

        // Blocked on the call screen, just like a timed title card would be.
        expect(runner.pendingCallScreen, isNotNull);
        expect(runner.pendingCallScreen!.name, 'titlecard');
        expect(runner.state, RenPyRunnerState.waitingForInput);

        // Fire the timer action: [Hide("titlecard"), Return()].
        runner.executeScreenAction(
          RenPyScreenAction.parseWith(
            '[Hide("titlecard"), Return()]',
            _literalScope(),
          ),
        );

        // The call screen resolved (no longer wedged) and execution resumed,
        // reaching the line after the call.
        expect(runner.pendingCallScreen, isNull);
        expect(lastLine, 'after call');
      },
    );

    test('order matters: Return value lands in _return', () {
      final runner = _runner('''
screen titlecard():
    text "loading"

label start:
    call screen titlecard
    \$ answered = _return
    if answered:
        "yes"
    else:
        "no"
''');
      String? lastLine;
      runner.onDialogue = (_, text) => lastLine = text;
      runner.run();
      expect(runner.pendingCallScreen, isNotNull);

      runner.executeScreenAction(
        RenPyScreenAction.parseWith(
          '[Hide("titlecard"), Return(True)]',
          _literalScope(),
        ),
      );

      expect(runner.pendingCallScreen, isNull);
      expect(lastLine, 'yes');
    });
  });
}
