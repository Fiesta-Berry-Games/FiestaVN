import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  test(
    'controller emits dialogue, menu captions, and resolved image assets',
    () async {
      final controller = RenPyFlutterController();
      final images = <RenPyImageChange>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyImageChange) images.add(status);
      });

      controller.load(
        '''
label start:
    scene bg lecturehall
    "Welcome."
    menu:
        "Choose a branch."
        "Go.":
            "Done."
''',
        gameRoot: 'assets/game',
        availableAssets: const {'assets/game/images/bg lecturehall.png'},
      );

      await _continueUntil(controller, (status) => status is RenPyMenu);

      final menu = controller.value as RenPyMenu;
      expect(menu.caption, 'Choose a branch.');
      expect(menu.choices, ['Go.']);
      expect(images.single.sceneAsset, 'assets/game/images/bg lecturehall.png');
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
