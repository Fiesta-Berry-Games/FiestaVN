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
      final transitions = <RenPyTransitionChange>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyImageChange) images.add(status);
        if (status is RenPyAudioChange) audio.add(status);
        if (status is RenPyTransitionChange) transitions.add(status);
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
      expect(transitions.map((transition) => transition.name), [
        'fade',
        'fade',
        'dissolve',
      ]);
    },
  );

  test('controller carries The Question character colors', () async {
    final source = await rootBundle.loadString(
      'assets/games/the_question/game/script.rpy',
    );
    final controller = RenPyFlutterController();
    final dialogue = <RenPyDialogue>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyDialogue) dialogue.add(status);
      if (status is RenPyMenu) status.onChoice(0);
    });

    controller.load(
      source,
      filename: 'assets/games/the_question/game/script.rpy',
      gameRoot: 'assets/games/the_question/game',
      availableAssets: const {
        'assets/games/the_question/game/images/bg lecturehall.jpg',
        'assets/games/the_question/game/images/bg uni.jpg',
        'assets/games/the_question/game/images/bg meadow.jpg',
        'assets/games/the_question/game/images/sylvie green normal.png',
        'assets/games/the_question/game/images/sylvie green smile.png',
      },
    );

    await _continueUntil(
      controller,
      (status) =>
          dialogue.any((line) => line.characterId == 's') &&
          dialogue.any((line) => line.characterId == 'm'),
    );

    expect(
      dialogue,
      contains(
        isA<RenPyDialogue>()
            .having((line) => line.characterId, 'characterId', 's')
            .having((line) => line.character, 'character', 'Sylvie')
            .having((line) => line.color, 'color', '#c8ffc8'),
      ),
    );
    expect(
      dialogue,
      contains(
        isA<RenPyDialogue>()
            .having((line) => line.characterId, 'characterId', 'm')
            .having((line) => line.character, 'character', 'Me')
            .having((line) => line.color, 'color', '#c8c8ff'),
      ),
    );
  });

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
