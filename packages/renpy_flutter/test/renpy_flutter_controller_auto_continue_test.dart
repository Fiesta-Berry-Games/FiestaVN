import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  test(
    'auto-continue dialogue before a menu does not auto-dismiss the menu',
    () async {
      final controller = RenPyFlutterController();
      final menus = <RenPyMenu>[];
      final dialogue = <String>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyMenu) menus.add(status);
        if (status is RenPyDialogue) dialogue.add(status.text);
      });

      // The dialogue auto-continues after a comparatively long delay so its
      // timer is still scheduled while the player advances into the menu.
      controller.load('''
label start:
    "Choose.{w=0.2}"
    menu:
        "Left":
            "Left ending."
        "Right":
            "Right ending."
''');

      await _waitUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Choose.{w=0.2}',
      );

      // Advance through the auto-continue line and into the menu before the
      // auto-continue timer would have fired.
      await _continueUntil(controller, (status) => status is RenPyMenu);

      final menu = controller.value as RenPyMenu;

      // Wait well past the auto-continue duration. A stray timer that was not
      // cancelled by the menu callback would fire here and replace or dismiss
      // the menu.
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(controller.value, same(menu));
      expect(menus, hasLength(1));
      expect(dialogue, contains('Choose.{w=0.2}'));

      // The menu remains interactive after the auto-continue window elapses.
      menu.onChoice(1);
      await _waitUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Right ending.',
      );
    },
  );
}

Future<void> _continueUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 50; i++) {
    if (predicate(controller.value)) return;
    if (controller.value is RenPyDialogue) {
      controller.continueGame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}

Future<void> _waitUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 50; i++) {
    if (predicate(controller.value)) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}
