import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

RenPyRunner _runner(String source) {
  final result = RenPyParser().parse(source, 'param_action.rpy');
  return RenPyRunner(result.script);
}

/// Resolves a screen the way a renderer would for a pending blocking call
/// screen: with the recorded invocation arguments.
RenPyResolvedScreen _resolvePending(RenPyRunner runner) {
  final pending = runner.pendingCallScreen!;
  return runner.resolveScreen(
    pending.name,
    positional: pending.positional,
    keywords: pending.keywords,
  )!;
}

RenPyResolvedDisplayable _button(RenPyResolvedScreen screen, String label) =>
    screen.children.firstWhere(
      (c) => c.kind == 'textbutton' && c.text == label,
    );

void main() {
  group('screen parameter-bound actions', () {
    test('a Return() passed as a screen parameter resolves to that action, '
        'not a nullAction', () {
      final runner = _runner('''
screen save_reminder(message, yes_action, no_action):
    text "[message]"
    textbutton "Yes" action yes_action
    textbutton "No" action no_action

label start:
    call screen save_reminder("Save?", yes_action=Return("ok"), no_action=Return("no"))
    \$ answered = _return
    if answered == "ok":
        "did save"
    else:
        "did not"
''');
      String? lastLine;
      runner.onDialogue = (_, text) => lastLine = text;
      runner.run();

      expect(runner.pendingCallScreen, isNotNull);
      final resolved = _resolvePending(runner);

      final yes = _button(resolved, 'Yes');
      final no = _button(resolved, 'No');

      // Before the fix these were nullAction carrying the raw "yes_action".
      expect(yes.action, isNotNull);
      expect(yes.action!.kind, RenPyScreenActionKind.returnValue);
      expect(yes.action!.value, 'ok');
      expect(no.action!.kind, RenPyScreenActionKind.returnValue);
      expect(no.action!.value, 'no');

      // Executing the resolved button drives the call screen's Return.
      runner.executeScreenAction(yes.action!);
      expect(runner.pendingCallScreen, isNull);
      expect(lastLine, 'did save');
    });

    test('a list-of-actions passed as a screen parameter resolves to a '
        'multiple action', () {
      final runner = _runner('''
screen confirm(yes_action):
    textbutton "Yes" action yes_action

label start:
    call screen confirm(yes_action=[Return("done")])
    \$ answered = _return
    "after"
''');
      runner.run();

      final resolved = _resolvePending(runner);
      final yes = _button(resolved, 'Yes');
      expect(yes.action, isNotNull);
      expect(yes.action!.kind, RenPyScreenActionKind.multiple);
      expect(yes.action!.actions, hasLength(1));
      expect(
        yes.action!.actions.single.kind,
        RenPyScreenActionKind.returnValue,
      );
      expect(yes.action!.actions.single.value, 'done');
    });

    test('a Jump() passed as a screen parameter resolves to a jump action', () {
      final runner = _runner('''
screen menu_prompt(go_action):
    textbutton "Go" action go_action

label start:
    call screen menu_prompt(go_action=Jump("target_label"))
    "after"

label target_label:
    "arrived"
''');
      String? lastLine;
      runner.onDialogue = (_, text) => lastLine = text;
      runner.run();

      final resolved = _resolvePending(runner);
      final go = _button(resolved, 'Go');
      expect(go.action, isNotNull);
      expect(go.action!.kind, RenPyScreenActionKind.jump);
      expect(go.action!.label, 'target_label');

      // Executing the jump dismisses the modal and runs the target label.
      runner.executeScreenAction(go.action!);
      expect(lastLine, 'arrived');
    });

    test('a genuinely-unknown bare name still resolves to a nullAction', () {
      final runner = _runner('''
screen broken():
    textbutton "X" action does_not_exist

label start:
    call screen broken
    "after"
''');
      runner.run();

      final resolved = _resolvePending(runner);
      final x = _button(resolved, 'X');
      expect(x.action, isNotNull);
      expect(x.action!.kind, RenPyScreenActionKind.nullAction);
      expect(x.action!.raw, 'does_not_exist');
    });

    test('a cyclic name-to-name binding degrades to nullAction without '
        'recursing to a stack overflow', () {
      // `a` is bound to the (passthrough) string "b" and `b` to "a"; resolving
      // `action a` must not chase a -> b -> a forever. A bare-identifier
      // binding is never a real action expression, so it short-circuits to
      // nullAction rather than re-parsing.
      final runner = _runner('''
screen cyclic(a, b):
    textbutton "Go" action a

label start:
    call screen cyclic(a=b, b=a)
    "after"
''');
      runner.run();

      final resolved = _resolvePending(runner);
      final go = _button(resolved, 'Go');
      expect(go.action, isNotNull);
      expect(go.action!.kind, RenPyScreenActionKind.nullAction);
    });
  });
}
