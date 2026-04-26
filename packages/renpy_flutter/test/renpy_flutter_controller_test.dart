import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'controller collects diagnostics for unsupported compatibility signals',
    () async {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      controller.load(
        '''
define strange = PushMove(1.0, "left")

label start:
    scene missing background at Transform(xzoom=1.2) with strange
    play sound "missing.ogg"
    \$ persistent.confession_finished = True
    "Done."
        ''',
        gameRoot: 'assets/game',
        availableAssets: const {'assets/game/images/other.png'},
      );

      await _continueUntil(controller, (status) => status is RenPyDialogue);

      expect(
        controller.diagnostics.map((diagnostic) => diagnostic.code),
        containsAll([
          RenPyDiagnosticCode.unsupportedTransition,
          RenPyDiagnosticCode.unresolvedImageAsset,
          RenPyDiagnosticCode.unresolvedAudioAsset,
        ]),
      );
      expect(
        controller.diagnostics.map((diagnostic) => diagnostic.code),
        isNot(contains(RenPyDiagnosticCode.unsupportedPlacement)),
      );
      expect(
        controller.diagnostics.where(
          (diagnostic) => diagnostic.code == RenPyDiagnosticCode.skippedPython,
        ),
        isEmpty,
      );
      expect(controller.persistent, {'confession_finished': true});
    },
  );

  test(
    'controller restores persistent values from shared preferences',
    () async {
      const key = 'renpy.test.controller.persistent';
      SharedPreferences.setMockInitialValues({});

      final firstStore = await RenPySharedPreferencesPersistentStore.create(
        key: key,
      );
      final firstController = RenPyFlutterController(
        persistentStore: firstStore,
      );
      addTearDown(firstController.dispose);

      firstController.load('''
label start:
    \$ persistent.confession_finished = True
    "Stored."
''');

      await _continueUntil(
        firstController,
        (status) => status is RenPyDialogue,
      );
      expect(firstController.persistent, {'confession_finished': true});

      final secondStore = await RenPySharedPreferencesPersistentStore.create(
        key: key,
      );
      final secondController = RenPyFlutterController(
        persistentStore: secondStore,
      );
      final dialogue = <String>[];
      addTearDown(secondController.dispose);

      secondController.addListener(() {
        final status = secondController.value;
        if (status is RenPyDialogue) dialogue.add(status.text);
      });
      secondController.load('''
label start:
    if persistent.confession_finished:
        "Restored."
    else:
        "Missing."
''');

      await _continueUntil(
        secondController,
        (status) => status is RenPyDialogue,
      );

      expect(secondController.persistent, {'confession_finished': true});
      expect(dialogue, ['Restored.']);
    },
  );

  test('controller saves and loads dialogue snapshots', () async {
    const key = 'renpy.test.controller.snapshot.dialogue';
    SharedPreferences.setMockInitialValues({});

    final firstStore = await RenPySharedPreferencesSnapshotStore.create(
      key: key,
    );
    final firstController = RenPyFlutterController(snapshotStore: firstStore);
    addTearDown(firstController.dispose);

    firstController.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _continueUntil(
      firstController,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    firstController.continueGame();
    await _continueUntil(
      firstController,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );

    expect(await firstController.saveGame(), isTrue);

    final secondStore = await RenPySharedPreferencesSnapshotStore.create(
      key: key,
    );
    final secondController = RenPyFlutterController(snapshotStore: secondStore);
    addTearDown(secondController.dispose);

    secondController.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _continueUntil(
      secondController,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );

    expect(await secondController.loadSavedGame(), isTrue);
    expect((secondController.value as RenPyDialogue).text, 'Second.');

    secondController.continueGame();
    await _continueUntil(
      secondController,
      (status) => status is RenPyDialogue && status.text == 'Third.',
    );
  });

  test('controller saves and loads menu snapshots', () async {
    const key = 'renpy.test.controller.snapshot.menu';
    SharedPreferences.setMockInitialValues({});

    final firstStore = await RenPySharedPreferencesSnapshotStore.create(
      key: key,
    );
    final firstController = RenPyFlutterController(snapshotStore: firstStore);
    addTearDown(firstController.dispose);

    firstController.load('''
label start:
    menu:
        "Left":
            "Left ending."
        "Right":
            "Right ending."
''');

    await _continueUntil(firstController, (status) => status is RenPyMenu);
    expect(await firstController.saveGame(), isTrue);

    final secondStore = await RenPySharedPreferencesSnapshotStore.create(
      key: key,
    );
    final secondController = RenPyFlutterController(snapshotStore: secondStore);
    addTearDown(secondController.dispose);
    final dialogue = <String>[];
    secondController.addListener(() {
      final status = secondController.value;
      if (status is RenPyDialogue) dialogue.add(status.text);
    });

    secondController.load('''
label start:
    menu:
        "Left":
            "Left ending."
        "Right":
            "Right ending."
''');

    expect(await secondController.loadSavedGame(), isTrue);
    final menu = secondController.value as RenPyMenu;
    expect(menu.choices, ['Left', 'Right']);

    menu.onChoice(1);
    await _continueUntil(
      secondController,
      (status) => status is RenPyDialogue && status.text == 'Right ending.',
    );
    expect(dialogue, ['Right ending.']);
  });

  test('controller saves and loads presentation snapshots', () async {
    final store = RenPyMemoryRunnerSnapshotStore();
    final firstController = RenPyFlutterController(snapshotStore: store);
    addTearDown(firstController.dispose);

    firstController.load(
      '''
label start:
    scene bg lecturehall
    play music "first.ogg"
    show sylvie green normal at left
    "First."
    scene bg uni
    play music "second.ogg"
    show sylvie green smile
    "Second."
    "Third."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg lecturehall.png',
        'assets/game/images/bg uni.png',
        'assets/game/images/sylvie green normal.png',
        'assets/game/images/sylvie green smile.png',
      },
    );

    await _continueUntil(
      firstController,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    firstController.continueGame();
    await _continueUntil(
      firstController,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );

    expect(await firstController.saveGame(), isTrue);

    final secondController = RenPyFlutterController(snapshotStore: store);
    addTearDown(secondController.dispose);
    final restoredEvents = <RenPyGameStatus>[];
    secondController.addListener(() {
      restoredEvents.add(secondController.value);
    });

    secondController.load(
      '''
label start:
    scene bg lecturehall
    play music "first.ogg"
    show sylvie green normal at left
    "First."
    scene bg uni
    play music "second.ogg"
    show sylvie green smile
    "Second."
    "Third."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg lecturehall.png',
        'assets/game/images/bg uni.png',
        'assets/game/images/sylvie green normal.png',
        'assets/game/images/sylvie green smile.png',
      },
    );

    await _continueUntil(
      secondController,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    restoredEvents.clear();

    expect(await secondController.loadSavedGame(), isTrue);

    expect((secondController.value as RenPyDialogue).text, 'Second.');
    final visualRestore = restoredEvents.whereType<RenPyVisualRestore>().single;
    expect(visualRestore.visual.scene?.imageName, 'bg uni');
    expect(
      visualRestore.visual.scene?.assetPath,
      'assets/game/images/bg uni.png',
    );
    expect(visualRestore.visual.sprites.map((sprite) => sprite.imageName), [
      'sylvie green smile',
    ]);
    expect(restoredEvents.whereType<RenPyImageChange>(), isEmpty);
    expect(
      restoredEvents.whereType<RenPyAudioChange>().map((event) => event.asset),
      contains('second.ogg'),
    );
  });

  test('controller rolls back to the previous dialogue boundary', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "First."
    "Second."
    "Third."
''');

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    expect(controller.canRollback, isFalse);

    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );

    expect(controller.canRollback, isTrue);
    expect(controller.rollback(), isTrue);
    expect((controller.value as RenPyDialogue).text, 'First.');

    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
  });

  test('controller rolls back from a menu branch to the menu', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    menu:
        "Left":
            "Left ending."
        "Right":
            "Right ending."
''');

    await _continueUntil(controller, (status) => status is RenPyMenu);
    final firstMenu = controller.value as RenPyMenu;
    expect(firstMenu.choices, ['Left', 'Right']);
    expect(controller.canRollback, isFalse);

    firstMenu.onChoice(1);
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Right ending.',
    );

    expect(controller.canRollback, isTrue);
    expect(controller.rollback(), isTrue);

    final restoredMenu = controller.value as RenPyMenu;
    expect(restoredMenu.choices, ['Left', 'Right']);

    restoredMenu.onChoice(0);
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Left ending.',
    );
  });

  test('controller rollback restores presentation snapshots', () async {
    final controller = RenPyFlutterController();
    final restoredEvents = <RenPyGameStatus>[];
    addTearDown(controller.dispose);
    controller.addListener(() {
      restoredEvents.add(controller.value);
    });

    controller.load(
      '''
label start:
    scene bg lecturehall
    play music "first.ogg"
    show sylvie green normal at left
    "First."
    scene bg uni
    play music "second.ogg"
    show sylvie green smile
    "Second."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg lecturehall.png',
        'assets/game/images/bg uni.png',
        'assets/game/images/sylvie green normal.png',
        'assets/game/images/sylvie green smile.png',
      },
    );

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
    restoredEvents.clear();

    expect(controller.rollback(), isTrue);
    expect((controller.value as RenPyDialogue).text, 'First.');
    final visualRestore = restoredEvents.whereType<RenPyVisualRestore>().single;
    expect(visualRestore.visual.scene?.imageName, 'bg lecturehall');
    expect(
      visualRestore.visual.scene?.assetPath,
      'assets/game/images/bg lecturehall.png',
    );
    expect(visualRestore.visual.sprites.map((sprite) => sprite.imageName), [
      'sylvie green normal',
    ]);
    expect(restoredEvents.whereType<RenPyImageChange>(), isEmpty);
    expect(
      restoredEvents.whereType<RenPyAudioChange>().map((event) => event.asset),
      contains('first.ogg'),
    );
  });

  test('controller tracks same-tag sprites independently per layer', () async {
    final store = RenPyMemoryRunnerSnapshotStore();
    final controller = RenPyFlutterController(snapshotStore: store);
    final restoredEvents = <RenPyGameStatus>[];
    addTearDown(controller.dispose);
    controller.addListener(() {
      restoredEvents.add(controller.value);
    });

    controller.load(
      '''
label start:
    show logo onlayer master
    show logo onlayer abovemid
    "Both."
    hide logo onlayer master
    "Above only."
    hide logo onlayer abovemid
    "None."
''',
      gameRoot: 'assets/game',
      availableAssets: const {'assets/game/images/logo.png'},
    );

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Both.',
    );
    expect(await controller.saveGame(), isTrue);

    final bothSprites = (await store.load())!.presentation!.visual!.sprites;
    expect(bothSprites.map((sprite) => sprite.imageName), ['logo', 'logo']);
    expect(bothSprites.map((sprite) => sprite.layer), [null, 'abovemid']);

    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Above only.',
    );
    expect(await controller.saveGame(), isTrue);

    final remainingSprites =
        (await store.load())!.presentation!.visual!.sprites;
    expect(remainingSprites.map((sprite) => sprite.imageName), ['logo']);
    expect(remainingSprites.single.layer, 'abovemid');

    expect(controller.rollback(), isTrue);
    expect((controller.value as RenPyDialogue).text, 'Both.');
    final visualRestore = restoredEvents.whereType<RenPyVisualRestore>().single;
    expect(visualRestore.visual.sprites.map((sprite) => sprite.imageName), [
      'logo',
      'logo',
    ]);
    expect(visualRestore.visual.sprites.map((sprite) => sprite.layer), [
      null,
      'abovemid',
    ]);

    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'None.',
    );
    expect(await controller.saveGame(), isTrue);
    expect((await store.load())!.presentation!.visual!.sprites, isEmpty);
  });

  test('controller records non-master scenes as layered sprites', () async {
    final store = RenPyMemoryRunnerSnapshotStore();
    final controller = RenPyFlutterController(snapshotStore: store);
    addTearDown(controller.dispose);

    controller.load(
      '''
label start:
    scene bg room
    show logo onlayer master
    scene overlay onlayer abovemid
    "Layered."
    scene bg other
    "Master changed."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg room.png',
        'assets/game/images/bg other.png',
        'assets/game/images/logo.png',
        'assets/game/images/overlay.png',
      },
    );

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Layered.',
    );
    expect(await controller.saveGame(), isTrue);

    final layered = (await store.load())!.presentation!.visual!;
    expect(layered.scene?.imageName, 'bg room');
    expect(layered.scene?.layer, isNull);
    expect(layered.sprites.map((sprite) => sprite.imageName), [
      'logo',
      'overlay',
    ]);
    expect(layered.sprites.map((sprite) => sprite.layer), [null, 'abovemid']);

    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Master changed.',
    );
    expect(await controller.saveGame(), isTrue);

    final afterMasterScene = (await store.load())!.presentation!.visual!;
    expect(afterMasterScene.scene?.imageName, 'bg other');
    expect(afterMasterScene.sprites.map((sprite) => sprite.imageName), [
      'overlay',
    ]);
    expect(afterMasterScene.sprites.single.layer, 'abovemid');
  });

  test('controller preserves behind order within visual snapshots', () async {
    final store = RenPyMemoryRunnerSnapshotStore();
    final controller = RenPyFlutterController(snapshotStore: store);
    final restoredEvents = <RenPyGameStatus>[];
    addTearDown(controller.dispose);
    controller.addListener(() {
      restoredEvents.add(controller.value);
    });

    controller.load(
      '''
label start:
    show eileen happy onlayer abovemid
    show sylvie green normal
    show logo onlayer abovemid behind eileen
    "Layered."
    "Next."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/eileen happy.png',
        'assets/game/images/sylvie green normal.png',
        'assets/game/images/logo.png',
      },
    );

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Layered.',
    );
    expect(await controller.saveGame(), isTrue);

    final sprites = (await store.load())!.presentation!.visual!.sprites;
    expect(
      sprites
          .where((sprite) => sprite.layer == 'abovemid')
          .map((sprite) => sprite.imageName),
      ['logo', 'eileen happy'],
    );

    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Next.',
    );

    expect(controller.rollback(), isTrue);
    final visualRestore = restoredEvents.whereType<RenPyVisualRestore>().single;
    expect(
      visualRestore.visual.sprites
          .where((sprite) => sprite.layer == 'abovemid')
          .map((sprite) => sprite.imageName),
      ['logo', 'eileen happy'],
    );
  });

  test('controller preserves zorder within visual snapshots', () async {
    final store = RenPyMemoryRunnerSnapshotStore();
    final controller = RenPyFlutterController(snapshotStore: store);
    final restoredEvents = <RenPyGameStatus>[];
    addTearDown(controller.dispose);
    controller.addListener(() {
      restoredEvents.add(controller.value);
    });

    controller.load(
      '''
label start:
    show logo zorder 10 onlayer abovemid
    show sylvie green normal zorder -5
    "Layered."
    "Next."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/logo.png',
        'assets/game/images/sylvie green normal.png',
      },
    );

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Layered.',
    );
    expect(await controller.saveGame(), isTrue);

    final sprites = (await store.load())!.presentation!.visual!.sprites;
    expect(
      sprites.map((sprite) => (sprite.imageName, sprite.layer, sprite.zOrder)),
      [('logo', 'abovemid', 10), ('sylvie green normal', null, -5)],
    );

    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Next.',
    );

    expect(controller.rollback(), isTrue);
    final visualRestore = restoredEvents.whereType<RenPyVisualRestore>().single;
    expect(
      visualRestore.visual.sprites.map(
        (sprite) => (sprite.imageName, sprite.layer, sprite.zOrder),
      ),
      [('logo', 'abovemid', 10), ('sylvie green normal', null, -5)],
    );
  });

  test(
    'controller preserves layered scene zorder within visual snapshots',
    () async {
      final store = RenPyMemoryRunnerSnapshotStore();
      final controller = RenPyFlutterController(snapshotStore: store);
      final restoredEvents = <RenPyGameStatus>[];
      addTearDown(controller.dispose);
      controller.addListener(() {
        restoredEvents.add(controller.value);
      });

      controller.load(
        '''
label start:
    scene overlay onlayer abovemid zorder 10
    show logo onlayer abovemid zorder 20
    "Layered."
    "Next."
''',
        gameRoot: 'assets/game',
        availableAssets: const {
          'assets/game/images/overlay.png',
          'assets/game/images/logo.png',
        },
      );

      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Layered.',
      );
      expect(await controller.saveGame(), isTrue);

      final sprites = (await store.load())!.presentation!.visual!.sprites;
      expect(
        sprites.map(
          (sprite) => (sprite.imageName, sprite.layer, sprite.zOrder),
        ),
        [('overlay', 'abovemid', 10), ('logo', 'abovemid', 20)],
      );

      restoredEvents.clear();
      controller.continueGame();
      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Next.',
      );

      expect(controller.rollback(), isTrue);
      final visualRestore =
          restoredEvents.whereType<RenPyVisualRestore>().single;
      expect(
        visualRestore.visual.sprites.map(
          (sprite) => (sprite.imageName, sprite.layer, sprite.zOrder),
        ),
        [('overlay', 'abovemid', 10), ('logo', 'abovemid', 20)],
      );
    },
  );

  test('controller rollback does not replay one-shot sound effects', () async {
    final controller = RenPyFlutterController();
    final restoredEvents = <RenPyGameStatus>[];
    addTearDown(controller.dispose);
    controller.addListener(() {
      restoredEvents.add(controller.value);
    });

    controller.load(
      '''
label start:
    scene bg hallway
    play sound "glass.ogg"
    "First."
    "Second."
    "Third."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg hallway.png',
        'assets/game/glass.ogg',
      },
    );

    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.',
    );
    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Second.',
    );
    restoredEvents.clear();
    controller.continueGame();
    await _continueUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'Third.',
    );
    restoredEvents.clear();

    expect(controller.rollback(), isTrue);
    expect((controller.value as RenPyDialogue).text, 'Second.');
    expect(restoredEvents.whereType<RenPyAudioChange>(), isEmpty);
  });

  test(
    'controller rollback replays one-shot sound effects for their boundary',
    () async {
      final controller = RenPyFlutterController();
      final restoredEvents = <RenPyGameStatus>[];
      addTearDown(controller.dispose);
      controller.addListener(() {
        restoredEvents.add(controller.value);
      });

      controller.load(
        '''
label start:
    "Before."
    play sound "glass.ogg"
    "Break.{w} After."
''',
        gameRoot: 'assets/game',
        availableAssets: const {'assets/game/glass.ogg'},
      );

      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Break.{w}',
      );
      restoredEvents.clear();
      controller.continueGame();
      await _continueUntil(
        controller,
        (status) =>
            status is RenPyDialogue && status.text == 'Break.{w} After.',
      );
      restoredEvents.clear();

      expect(controller.rollback(), isTrue);
      expect((controller.value as RenPyDialogue).text, 'Break.{w}');
      expect(
        restoredEvents.whereType<RenPyAudioChange>().map(
          (event) => event.asset,
        ),
        contains('glass.ogg'),
      );

      restoredEvents.clear();
      controller.continueGame();
      await _continueUntil(
        controller,
        (status) =>
            status is RenPyDialogue && status.text == 'Break.{w} After.',
      );
      restoredEvents.clear();

      expect(controller.rollback(), isTrue);
      expect(
        restoredEvents.whereType<RenPyAudioChange>().map(
          (event) => event.asset,
        ),
        contains('glass.ogg'),
      );
    },
  );

  test('controller treats available audio assets case-insensitively', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load(
      '''
label start:
    play sound "/SE/Z1.wav"
    "Done."
''',
      gameRoot: 'assets/game',
      availableAssets: const {'assets/game/se/Z1.wav'},
    );

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(
      controller.diagnostics
          .where(
            (diagnostic) =>
                diagnostic.code == RenPyDiagnosticCode.unresolvedAudioAsset,
          )
          .toList(),
      isEmpty,
    );
  });

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
    scene bg lecturehall at center onlayer master
    show sylvie green normal at Position(xpos = 0.8) onlayer abovemid behind eileen
    hide sylvie onlayer abovemid
    "Welcome."
''',
      gameRoot: 'assets/game',
      availableAssets: const {
        'assets/game/images/bg lecturehall.png',
        'assets/game/images/sylvie green normal.png',
      },
    );

    await _continueUntil(controller, (status) => status is RenPyDialogue);
    expect(images, hasLength(3));

    expect(images[0].scene, 'bg lecturehall');
    expect(images[0].sceneAt, 'center');
    expect(
      images[0].scenePlacement,
      const RenPyImagePlacement.position(
        xpos: 0.5,
        xanchor: 0.5,
        ypos: 1,
        yanchor: 1,
      ),
    );
    expect(images[0].sceneOnLayer, 'master');
    expect(images[0].sceneAsset, 'assets/game/images/bg lecturehall.png');
    expect(images[1].show, 'sylvie green normal');
    expect(images[1].showAt, 'Position(xpos = 0.8)');
    expect(
      images[1].showPlacement,
      const RenPyImagePlacement.position(xpos: 0.8),
    );
    expect(images[1].showOnLayer, 'abovemid');
    expect(images[1].showBehind, 'eileen');
    expect(images[1].showAsset, 'assets/game/images/sylvie green normal.png');
    expect(images[2].hide, 'sylvie');
    expect(images[2].hideOnLayer, 'abovemid');
  });

  test(
    'controller carries simple named transform placement metadata',
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
transform small_left:
    xpos 0.25
    xanchor 0.5
    zoom 0.5

label start:
    show logo at small_left
    "Placed."
''',
        gameRoot: 'assets/game',
        availableAssets: const {'assets/game/images/logo.png'},
      );

      await _continueUntil(controller, (status) => status is RenPyDialogue);

      expect(images.single.show, 'logo');
      expect(images.single.showAt, 'small_left');
      expect(
        images.single.showPlacement,
        const RenPyImagePlacement.position(xpos: 0.25, xanchor: 0.5, zoom: 0.5),
      );
      expect(
        controller.diagnostics.where(
          (diagnostic) =>
              diagnostic.code == RenPyDiagnosticCode.unsupportedPlacement,
        ),
        isEmpty,
      );
    },
  );

  test(
    'controller carries show text displayables without image assets',
    () async {
      final controller = RenPyFlutterController();
      final images = <RenPyImageChange>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyImageChange) images.add(status);
      });

      controller.load('''
label start:
    show text "{color=#FFF}Confession{/color}" at truecenter
    "Welcome."
''');

      await _continueUntil(controller, (status) => status is RenPyDialogue);

      expect(images.single.show, 'text');
      expect(images.single.showText, '{color=#FFF}Confession{/color}');
      expect(images.single.showAsset, isNull);
      expect(
        images.single.showPlacement,
        const RenPyImagePlacement.position(
          xpos: 0.5,
          xanchor: 0.5,
          ypos: 0.5,
          yanchor: 0.5,
        ),
      );
    },
  );

  test('controller resolves image aliases defined during execution', () async {
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
    image flashback bg = im.Grayscale("/bg/flashback.jpg")
    scene flashback bg
    "Welcome."
''',
      gameRoot: 'assets/game',
      availableAssets: const {'assets/game/images/bg/flashback.jpg'},
    );

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(images.single.scene, 'flashback bg');
    expect(images.single.sceneAsset, 'assets/game/images/bg/flashback.jpg');
    expect(
      images.single.sceneImage,
      const RenPyResolvedImage(
        assetPath: 'assets/game/images/bg/flashback.jpg',
        operations: [RenPyImageOperation.grayscale()],
      ),
    );
  });

  test('controller carries Solid displayable scenes as colors', () async {
    final controller = RenPyFlutterController();
    final images = <RenPyImageChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyImageChange) images.add(status);
    });

    controller.load('''
label start:
    image red = Solid((255, 0, 0, 255))
    scene red
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(images.single.scene, 'red');
    expect(images.single.sceneAsset, isNull);
    expect(
      images.single.sceneImage,
      const RenPyResolvedImage.solid(RenPyColorValue(255, 0, 0, 255)),
    );
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

  test(
    'controller advances through nw-tagged dialogue without input',
    () async {
      final controller = RenPyFlutterController();
      final dialogue = <RenPyDialogue>[];
      addTearDown(controller.dispose);

      controller.addListener(() {
        final status = controller.value;
        if (status is RenPyDialogue) dialogue.add(status);
      });

      controller.load('''
label start:
    "Flash.{nw}"
    "Next."
''');

      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Next.',
      );

      expect(dialogue.map((event) => event.text), ['Flash.{nw}', 'Next.']);
    },
  );

  test('controller completes after terminal nw-tagged dialogue', () async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load('''
label start:
    "Flash.{nw}"
''');

    await _continueUntil(controller, (status) => status is RenPyComplete);
  });

  test('controller auto-resumes timed inline wait tags', () async {
    final controller = RenPyFlutterController();
    final dialogue = <RenPyDialogue>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyDialogue) dialogue.add(status);
    });

    controller.load('''
label start:
    "First.{w=0.01} Second."
''');

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text.contains('Second.'),
    );

    expect(dialogue.map((event) => event.text), [
      'First.{w=0.01}',
      'First.{w=0.01} Second.',
    ]);
    expect(dialogue.map((event) => event.displayText), [
      'First.',
      'First. Second.',
    ]);
  });

  test('controller waits for input at untimed inline wait tags', () async {
    final controller = RenPyFlutterController();
    final dialogue = <RenPyDialogue>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyDialogue) dialogue.add(status);
    });

    controller.load('''
label start:
    "First.{w} Second."
''');

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text == 'First.{w}',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(dialogue.map((event) => event.text), ['First.{w}']);

    controller.continueGame();

    await _waitUntil(
      controller,
      (status) => status is RenPyDialogue && status.text.contains('Second.'),
    );
    expect(dialogue.map((event) => event.text), [
      'First.{w}',
      'First.{w} Second.',
    ]);
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
    play music "illurock.opus" fadeout 1.0 fadein 2.0 volume 0.5 noloop if_changed
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(audio, hasLength(1));
    expect(audio.single.channel, 'music');
    expect(audio.single.asset, 'illurock.opus');
    expect(audio.single.fadein, '2.0');
    expect(audio.single.fadeout, '1.0');
    expect(audio.single.volume, '0.5');
    expect(audio.single.ifChanged, true);
    expect(audio.single.loop, false);
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
    expect(
      transitions.first.intent,
      const RenPyTransitionIntent.fade(outTime: 0.5, holdTime: 0, inTime: 0.5),
    );
  });

  test('controller emits RenPy pause changes', () async {
    final controller = RenPyFlutterController();
    final pauses = <RenPyPause>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyPause) pauses.add(status);
    });

    controller.load('''
label start:
    \$ renpy.pause(1.25)
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyPause);

    expect(pauses.single.duration, 1.25);

    controller.continueGame();
    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect((controller.value as RenPyDialogue).text, 'Welcome.');
  });

  test('controller carries parsed custom transition intent', () async {
    final controller = RenPyFlutterController();
    final transitions = <RenPyTransitionChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyTransitionChange) transitions.add(status);
    });

    controller.load('''
define openfade = Fade(1.5, 2.0, 2.0, color="#fff")
define quickgradientwiperight = ImageDissolve("right.png", 1.5, ramplen = 16)

label start:
    scene black with openfade
    scene bg hallway with quickgradientwiperight
    "Welcome."
''');

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    expect(transitions.map((change) => change.name), [
      'openfade',
      'quickgradientwiperight',
    ]);
    expect(
      transitions.first.intent,
      const RenPyTransitionIntent.fade(
        outTime: 1.5,
        holdTime: 2.0,
        inTime: 2.0,
        color: '#fff',
      ),
    );
    expect(
      transitions.last.intent,
      const RenPyTransitionIntent.imageDissolve(
        maskAsset: 'right.png',
        duration: 1.5,
        ramplen: 16,
      ),
    );
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
