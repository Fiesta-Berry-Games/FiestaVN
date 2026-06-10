import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Reference Games 1-3 render bundled image assets', (
    tester,
  ) async {
    await _expectReferenceGameImagesLoad(
      tester,
      scriptAsset: 'assets/games/1/game/script.rpy',
      text: "I'm standing in front of the White House.",
    );

    await _expectReferenceGameImagesLoad(
      tester,
      scriptAsset: 'assets/games/2/game/script.rpy',
      text: "I'd better stay quiet.",
    );

    await _expectReferenceGameImagesLoad(
      tester,
      scriptAsset: 'assets/games/3/game/script.rpy',
      text: "Hi, and welcome to the Ren'Py 4 demo program.",
    );
  });

  testWidgets('Reference Games 1-3 bundle every fixture image', (_) async {
    for (final asset in _referenceGameImageAssets) {
      await expectLater(
        rootBundle.load(asset),
        completes,
        reason: 'Missing bundled reference image $asset.',
      );
    }
  });

  testWidgets('Reference Games 1-3 bundle every fixture audio asset', (
    _,
  ) async {
    for (final asset in _referenceGameAudioAssets) {
      await expectLater(
        rootBundle.load(asset),
        completes,
        reason: 'Missing bundled reference audio $asset.',
      );
    }
  });

  test('bundled demo scripts load from the Flutter asset bundle', () async {
    for (final game in _bundledDemoGames) {
      await expectLater(
        File(game.scriptAsset).readAsString(),
        completes,
        reason: 'Missing bundled script ${game.scriptAsset}.',
      );
    }
  });

  test('The Question script keeps the bundled upstream structure', () async {
    final source =
        await File('assets/games/the_question/game/script.rpy').readAsString();

    expect(source, contains('# Declare characters used by this game.'));
    expect(source, contains('define s = Character('));
    expect(source, contains('label start:'));
    expect(source, contains('play music "illurock.opus"'));
    expect(source, contains('menu:'));
    expect(source, contains('"To ask her right away.":'));
    expect(source, contains('"To ask her later.":'));
    expect(source, contains('"{b}Bad Ending{/b}."'));
    expect(source, contains('"{b}Good Ending{/b}."'));
    expect(source, isNot(contains('FiestaVN')));
    expect(source, isNot(contains('RenFly')));
  });

  test('bundled demo games reach first playable scene with assets', () async {
    for (final game in _bundledDemoGames) {
      await _expectBundledDemoHealthy(game);
    }
  });
}

const _referenceGameImageAssets = [
  'assets/games/1/game/images/whitehouse.jpg',
  'assets/games/1/game/images/eileen_happy.png',
  'assets/games/1/game/images/eileen_upset.png',
  'assets/games/2/game/images/S2.png',
  'assets/games/2/game/images/S3.png',
  'assets/games/2/game/images/S4.png',
  'assets/games/2/game/images/S5.png',
  'assets/games/2/game/images/S6.png',
  'assets/games/2/game/images/S7.png',
  'assets/games/2/game/images/LR5.png',
  'assets/games/3/game/images/mainmenu.jpg',
  'assets/games/3/game/images/gamemenu.jpg',
  'assets/games/3/game/images/frame.png',
  'assets/games/3/game/images/button.png',
  'assets/games/3/game/images/button_checked.png',
  'assets/games/3/game/images/carillon.jpg',
  'assets/games/3/game/images/whitehouse.jpg',
  'assets/games/3/game/images/washington.jpg',
  'assets/games/3/game/images/9a_happy.png',
  'assets/games/3/game/images/9a_vhappy.png',
  'assets/games/3/game/images/9a_concerned.png',
  'assets/games/3/game/images/ground.png',
  'assets/games/3/game/images/selected.png',
];

const _referenceGameAudioAssets = [
  'assets/games/3/game/sun-flower-slow-drag.mid',
  'assets/games/4/game/SE/Z1.opus',
  'assets/games/4/game/music/She End.opus',
  'assets/games/4/game/ME/rain_2.opus',
  'assets/games/4/game/se/ZS4.opus',
  'assets/games/the_question/game/illurock.opus',
];

const _bundledDemoGames = [
  _BundledDemoGame(
    scriptAsset: 'assets/games/1/game/script.rpy',
    firstBeatText: "I'm standing in front of the White House.",
    expectedImageCount: 2,
  ),
  _BundledDemoGame(
    scriptAsset: 'assets/games/2/game/script.rpy',
    firstBeatText: "I'd better stay quiet.",
    expectedImageCount: 1,
  ),
  _BundledDemoGame(
    scriptAsset: 'assets/games/3/game/script.rpy',
    firstBeatText: "Hi, and welcome to the Ren'Py 4 demo program.",
    expectedImageCount: 2,
    expectedAudioCount: 1,
  ),
  _BundledDemoGame(
    scriptAsset: 'assets/games/4/game/script.rpy',
    firstBeatText: 'Reference Game 4 begins.',
    expectedImageCount: 3,
    expectedAudioCount: 2,
  ),
  _BundledDemoGame(
    scriptAsset: 'assets/games/the_question/game/script.rpy',
    firstBeatText:
        "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
    expectedImageCount: 1,
    expectedAudioCount: 1,
  ),
];

final class _BundledDemoGame {
  const _BundledDemoGame({
    required this.scriptAsset,
    required this.firstBeatText,
    required this.expectedImageCount,
    this.expectedAudioCount = 0,
  });

  final String scriptAsset;
  final String firstBeatText;
  final int expectedImageCount;
  final int expectedAudioCount;
}

Future<void> _expectBundledDemoHealthy(_BundledDemoGame game) async {
  final source = await File(game.scriptAsset).readAsString();
  final gameRoot = _gameRootForScript(game.scriptAsset);
  final availableAssets = _assetFilesUnder(gameRoot);
  final images = <RenPyImageChange>[];
  final audio = <RenPyAudioChange>[];
  final controller = RenPyFlutterController();

  controller.addListener(() {
    final status = controller.value;
    if (status is RenPyImageChange) images.add(status);
    if (status is RenPyAudioChange && status.action == RenPyAudioAction.play) {
      audio.add(status);
    }
  });

  try {
    controller.load(
      source,
      filename: game.scriptAsset,
      gameRoot: gameRoot,
      availableAssets: availableAssets,
    );
    await _continueControllerUntil(
      controller,
      (status) =>
          status is RenPyDialogue &&
          status.displayText.contains(game.firstBeatText),
    );

    final imageAssets = [
      for (final image in images) ...[
        if (image.sceneAsset != null) image.sceneAsset!,
        if (image.showAsset != null) image.showAsset!,
      ],
    ];
    expect(
      imageAssets,
      hasLength(greaterThanOrEqualTo(game.expectedImageCount)),
      reason: '${game.scriptAsset} resolved too few image assets.',
    );
    for (final asset in imageAssets) {
      await expectLater(
        File(asset).exists(),
        completion(isTrue),
        reason: '${game.scriptAsset} resolved missing image $asset.',
      );
    }

    final audioAssets = [
      for (final change in audio)
        if (change.asset != null)
          'assets/${RenPyAudioAssetResolver.assetSourcePath(gameRoot: gameRoot, asset: change.asset!)}',
    ];
    expect(
      audioAssets,
      hasLength(greaterThanOrEqualTo(game.expectedAudioCount)),
      reason: '${game.scriptAsset} emitted too few audio commands.',
    );
    for (final asset in audioAssets) {
      await expectLater(
        File(asset).exists(),
        completion(isTrue),
        reason: '${game.scriptAsset} resolved missing audio $asset.',
      );
    }
  } finally {
    controller.dispose();
  }
}

Future<void> _expectReferenceGameImagesLoad(
  WidgetTester tester, {
  required String scriptAsset,
  required String text,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RenPyAssetPlayer(
        scriptAsset: scriptAsset,
        audioPlayback: const RenPyNoOpAudioPlayback(),
      ),
    ),
  );

  await tester.pump();
  await _pumpUntil(tester, find.textContaining(text));

  final assetImages =
      tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .whereType<AssetImage>()
          .toList();

  expect(assetImages, isNotEmpty, reason: '$scriptAsset rendered no images.');
  for (final image in assetImages) {
    await expectLater(
      rootBundle.load(image.assetName),
      completes,
      reason: '$scriptAsset resolved missing image ${image.assetName}.',
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int attempts = 120,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;

    final firstMenuChoice = find.byKey(const ValueKey('menu_choice_0'));
    if (firstMenuChoice.evaluate().isNotEmpty) {
      await tester.tap(firstMenuChoice);
    }

    final player = find.byType(RenPyPlayer);
    if (player.evaluate().isNotEmpty) {
      await tester.tapAt(tester.getCenter(player));
    }
  }

  fail('Timed out waiting for $finder.');
}

Set<String> _assetFilesUnder(String root) {
  final directory = Directory(root);
  if (!directory.existsSync()) return const {};
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceAll(r'\', '/'))
      .toSet();
}

String _gameRootForScript(String scriptAsset) {
  final scriptIndex = scriptAsset.lastIndexOf('/script.rpy');
  if (scriptIndex < 0) {
    throw ArgumentError.value(
      scriptAsset,
      'scriptAsset',
      'Must end in script.rpy',
    );
  }
  return scriptAsset.substring(0, scriptIndex);
}

Future<void> _continueControllerUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate, {
  int attempts = 250,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    final status = controller.value;
    if (predicate(status)) return;

    switch (status) {
      case RenPyDialogue() || RenPyPause():
        controller.continueGame();
      case RenPyMenu(:final onChoice):
        onChoice(0);
      case RenPyError(:final message):
        fail('RenPy controller errored before expected status: $message');
      case _:
        break;
    }
  }

  throw TimeoutException(
    'Timed out waiting for controller status. Last status: ${controller.value}',
  );
}
