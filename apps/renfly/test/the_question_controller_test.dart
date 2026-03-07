import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller resolves The Question image assets and reaches first menu',
    () async {
      final source = await rootBundle.loadString(
        'assets/games/the_question/game/script.rpy',
      );
      final controller = RenPyFlutterController();
      final images = <RenPyImageChange>[];
      final audio = <RenPyAudioChange>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyImageChange) images.add(status);
        if (status is RenPyAudioChange) audio.add(status);
      });

      controller.load(
        source,
        filename: 'assets/games/the_question/game/script.rpy',
        gameRoot: 'assets/games/the_question/game',
        availableAssets: const {
          'assets/games/the_question/game/images/bg lecturehall.jpg',
          'assets/games/the_question/game/images/bg uni.jpg',
          'assets/games/the_question/game/images/sylvie green normal.png',
        },
      );

      await _continueUntil(controller, (status) => status is RenPyMenu);

      final menu = controller.value as RenPyMenu;
      expect(menu.caption, 'As soon as she catches my eye, I decide...');
      expect(menu.choices, ['To ask her right away.', 'To ask her later.']);

      expect(
        images.map((image) => image.sceneAsset).whereType<String>(),
        containsAll([
          'assets/games/the_question/game/images/bg lecturehall.jpg',
          'assets/games/the_question/game/images/bg uni.jpg',
        ]),
      );
      expect(
        images.map((image) => image.showAsset).whereType<String>(),
        contains(
          'assets/games/the_question/game/images/sylvie green normal.png',
        ),
      );
      expect(audio.map((change) => change.channel), contains('music'));
      expect(audio.map((change) => change.asset), contains('illurock.opus'));
    },
  );

  test('controller can complete The Question bad-ending branch', () async {
    final source = await rootBundle.loadString(
      'assets/games/the_question/game/script.rpy',
    );
    final controller = RenPyFlutterController();
    final dialogue = <String>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyDialogue) {
        dialogue.add(status.text);
      } else if (status is RenPyMenu) {
        status.onChoice(1);
      }
    });

    controller.load(
      source,
      filename: 'assets/games/the_question/game/script.rpy',
      gameRoot: 'assets/games/the_question/game',
      availableAssets: const {
        'assets/games/the_question/game/images/bg lecturehall.jpg',
        'assets/games/the_question/game/images/bg uni.jpg',
      },
    );

    await _continueUntil(controller, (status) => status is RenPyComplete);

    expect(dialogue, contains('{b}Bad Ending{/b}.'));
  });
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
