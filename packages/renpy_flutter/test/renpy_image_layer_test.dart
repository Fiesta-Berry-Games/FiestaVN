import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  testWidgets('image layer renders scene and show asset changes', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'bg lecturehall',
      sceneAsset: 'assets/game/images/bg lecturehall.jpg',
    );
    await tester.pump();

    expect(_assetNames(tester), ['assets/game/images/bg lecturehall.jpg']);

    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAsset: 'assets/game/images/sylvie green normal.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/bg lecturehall.jpg',
      'assets/game/images/sylvie green normal.png',
    ]);
  });

  testWidgets('image layer clears sprites and background for black scenes', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'bg lecturehall',
      sceneAsset: 'assets/game/images/bg lecturehall.jpg',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAsset: 'assets/game/images/sylvie green normal.png',
    );
    await tester.pump();

    controller.value = RenPyImageChange(scene: 'black');
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('image layer crossfades previous and current visual states', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'bg lecturehall',
      sceneAsset: 'assets/game/images/bg lecturehall.jpg',
    );
    await tester.pump();

    controller.value = RenPyImageChange(
      scene: 'bg uni',
      sceneAsset: 'assets/game/images/bg uni.jpg',
    );
    await tester.pump();
    controller.value = const RenPyTransitionChange('fade');
    await tester.pump();

    expect(
      _assetNames(tester),
      containsAll([
        'assets/game/images/bg lecturehall.jpg',
        'assets/game/images/bg uni.jpg',
      ]),
    );

    await tester.pump(const Duration(milliseconds: 400));

    expect(_assetNames(tester), ['assets/game/images/bg uni.jpg']);
  });
}

List<String> _assetNames(WidgetTester tester) {
  return tester.widgetList<Image>(find.byType(Image)).map((image) {
    final provider = image.image as AssetImage;
    return provider.assetName;
  }).toList();
}
