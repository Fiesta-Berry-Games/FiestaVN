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

  test('controller carries image placement metadata', () async {
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
    scene bg lecturehall at center
    show sylvie green normal at right
    "Welcome."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg lecturehall.png',
        'assets/game/images/sylvie green normal.png',
      },
    );

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(images.first.scene, 'bg lecturehall');
    expect(images.first.sceneAt, 'center');
    expect(images.first.sceneAsset, 'assets/game/images/bg lecturehall.png');
    expect(images.last.show, 'sylvie green normal');
    expect(images.last.showAt, 'right');
    expect(images.last.showAsset, 'assets/game/images/sylvie green normal.png');
  });

  test('controller carries character metadata into dialogue states', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
define s = Character(_("Sylvie"), color="#c8ffc8")

label start:
    s "Hi there!"
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    final dialogue = controller.value as RenPyDialogue;
    expect(dialogue.characterId, 's');
    expect(dialogue.character, 'Sylvie');
    expect(dialogue.text, 'Hi there!');
    expect(dialogue.color, '#c8ffc8');
  });

  test('controller emits audio changes from play statements', () async {
    final controller = RenPyFlutterController();
    final audio = <RenPyAudioChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyAudioChange) audio.add(status);
    });

    controller.load('''
label start:
    play music "illurock.opus"
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(audio, hasLength(1));
    expect(audio.single.channel, 'music');
    expect(audio.single.asset, 'illurock.opus');
  });

  test('controller emits repeated identical audio commands', () async {
    final controller = RenPyFlutterController();
    final audio = <RenPyAudioChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyAudioChange) audio.add(status);
    });

    controller.load('''
label start:
    play sound "click.opus"
    play sound "click.opus"
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(audio, hasLength(2));
    expect(audio.map((change) => change.asset), ['click.opus', 'click.opus']);
  });

  test('controller emits audio stop changes', () async {
    final controller = RenPyFlutterController();
    final audio = <RenPyAudioChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyAudioChange) audio.add(status);
    });

    controller.load('''
label start:
    play music "illurock.opus"
    stop music fadeout 1.5
    stop sound
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(audio, hasLength(3));
    expect(audio[0].action, RenPyAudioAction.play);
    expect(audio[0].channel, 'music');
    expect(audio[0].asset, 'illurock.opus');
    expect(audio[1].action, RenPyAudioAction.stop);
    expect(audio[1].channel, 'music');
    expect(audio[1].fadeout, '1.5');
    expect(audio[2].action, RenPyAudioAction.stop);
    expect(audio[2].channel, 'sound');
    expect(audio[2].fadeout, isNull);
  });

  test('controller emits transition changes from with statements', () async {
    final controller = RenPyFlutterController();
    final transitions = <RenPyTransitionChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyTransitionChange) transitions.add(status);
    });

    controller.load('''
label start:
    scene bg lecturehall
    with fade
    show sylvie green normal
    with dissolve
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(transitions.map((change) => change.name), ['fade', 'dissolve']);
  });

  test(
    'controller emits inline image transitions after image changes',
    () async {
      final controller = RenPyFlutterController();
      final events = <Object>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyImageChange || status is RenPyTransitionChange) {
          events.add(status);
        }
      });

      controller.load('''
label start:
    scene bg lecturehall with fade
    show sylvie green normal at left with dissolve
    "Welcome."
''');

      await _continueUntil(controller, (status) => status is RenPyDialogue);

      expect(events, [
        isA<RenPyImageChange>().having(
          (event) => event.scene,
          'scene',
          'bg lecturehall',
        ),
        isA<RenPyTransitionChange>().having(
          (event) => event.name,
          'name',
          'fade',
        ),
        isA<RenPyImageChange>()
            .having((event) => event.show, 'show', 'sylvie green normal')
            .having((event) => event.showAt, 'showAt', 'left'),
        isA<RenPyTransitionChange>().having(
          (event) => event.name,
          'name',
          'dissolve',
        ),
      ]);
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
