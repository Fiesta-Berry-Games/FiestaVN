import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
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

  test('Reference Games 1-3 bundle every fixture image', () async {
    for (final asset in _referenceGameImageAssets) {
      await expectLater(
        rootBundle.load(asset),
        completes,
        reason: 'Missing bundled reference image $asset.',
      );
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
