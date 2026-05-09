import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  test('skip fast-forwards dialogue until completion', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _waitUntil(controller, (status) => status is RenPyDialogue);
    controller.skipEnabled = true;

    await _waitUntil(controller, (status) => status is RenPyComplete);
  });

  test('skip stops at a menu and does not auto-select', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
    menu:
        "Left":
            "Left ending."
        "Right":
            "Right ending."
''');

    await _waitUntil(controller, (status) => status is RenPyDialogue);
    controller.skipEnabled = true;

    await _waitUntil(controller, (status) => status is RenPyMenu);
    // Skip is cancelled at the menu and the choices are still pending.
    expect(controller.skipEnabled, isFalse);
    final menu = controller.value as RenPyMenu;
    expect(menu.choices, ['Left', 'Right']);

    // Give the timer a chance to (incorrectly) fire; it must not advance.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.value, isA<RenPyMenu>());
  });

  test('skip is cancellable by clearing the flag', () async {
    final controller = RenPyFlutterController();
    final dialogue = <String>[];
    addTearDown(controller.dispose);
    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyDialogue) dialogue.add(status.text);
    });

    controller.load('''
label start:
    "First."
    "Second."
    "Third."
    "Fourth."
''');

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    controller.skipEnabled = true;
    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
    controller.skipEnabled = false;

    await Future<void>.delayed(const Duration(milliseconds: 80));
    // Once skip is cleared the player is parked on a line, not at the end.
    expect(controller.value, isA<RenPyDialogue>());
    expect(controller.value, isNot(isA<RenPyComplete>()));
  });

  test('auto-forward advances after the reveal is reported', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    // Speed up the delay multiplier for the test.
    controller.autoDelay = 0;

    controller.load('''
label start:
    "First."
    "Second."
''');

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    controller.autoForwardEnabled = true;

    // Auto waits for the view to report the reveal complete.
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect((controller.value as RenPyDialogue).text, 'First.');

    controller.notifyTextRevealed();
    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
  });

  test('auto-forward stops at a menu', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    controller.autoDelay = 0;

    controller.load('''
label start:
    "First."
    menu:
        "Left":
            "Left ending."
        "Right":
            "Right ending."
''');

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    controller.autoForwardEnabled = true;
    controller.notifyTextRevealed();

    await _waitUntil(controller, (status) => status is RenPyMenu);
    expect(controller.autoForwardEnabled, isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.value, isA<RenPyMenu>());
  });

  test('auto-forward stops when cancelled', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    controller.autoDelay = 1;

    controller.load('''
label start:
    "First."
    "Second."
''');

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    controller.autoForwardEnabled = true;
    controller.notifyTextRevealed();
    controller.autoForwardEnabled = false;

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((controller.value as RenPyDialogue).text, 'First.');
  });

  test('skip and auto are mutually exclusive', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
''');

    await _waitUntil(controller, (status) => status is RenPyDialogue);

    controller.autoForwardEnabled = true;
    controller.skipEnabled = true;
    expect(controller.autoForwardEnabled, isFalse);

    controller.autoForwardEnabled = true;
    expect(controller.skipEnabled, isFalse);
  });
}

Future<void> _waitUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 200; i++) {
    if (predicate(controller.value)) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}
