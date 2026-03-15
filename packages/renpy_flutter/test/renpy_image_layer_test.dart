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

  testWidgets('image layer uses transition intent duration', (tester) async {
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
    controller.value = const RenPyTransitionChange(
      'openfade',
      intent: RenPyTransitionIntent.fade(
        outTime: 1.5,
        holdTime: 2.0,
        inTime: 2.0,
        color: '#fff',
      ),
    );
    await tester.pump();

    final transition = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(transition.duration, const Duration(milliseconds: 5500));
  });

  testWidgets('image layer approximates right-mask image dissolves as wipes', (
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
      scene: 'bg hallway',
      sceneAsset: 'assets/game/images/bg hallway.jpg',
    );
    await tester.pump();
    controller.value = const RenPyTransitionChange(
      'quickgradientwiperight',
      intent: RenPyTransitionIntent.imageDissolve(
        maskAsset: 'right.png',
        duration: 1.5,
        ramplen: 16,
      ),
    );
    await tester.pump();

    final transition = tester.widget<TweenAnimationBuilder<double>>(
      find.byType(TweenAnimationBuilder<double>),
    );
    expect(transition.duration, const Duration(milliseconds: 1500));
    expect(find.byType(ClipPath), findsOneWidget);
  });

  testWidgets('image layer defaults sprites to bottom center', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAsset: 'assets/game/images/sylvie green normal.png',
    );
    await tester.pump();

    expect(_spriteAlignment(tester, 'sylvie'), Alignment.bottomCenter);
  });

  testWidgets('image layer honors explicit sprite placement', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAt: 'left',
      showAsset: 'assets/game/images/sylvie green normal.png',
    );
    await tester.pump();

    controller.value = RenPyImageChange(
      show: 'eileen happy',
      showAt: 'right',
      showAsset: 'assets/game/images/eileen happy.png',
    );
    await tester.pump();

    expect(_spriteAlignment(tester, 'sylvie'), Alignment.bottomLeft);
    expect(_spriteAlignment(tester, 'eileen'), Alignment.bottomRight);
  });

  testWidgets('image layer honors fractional Position placement', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'eri defa2',
      showAt: 'Position(xpos = 0.2)',
      showPlacement: const RenPyImagePlacement.position(xpos: 0.2),
      showAsset: 'assets/game/images/eri defa2.png',
    );
    await tester.pump();

    expect(_spriteAlignment(tester, 'eri'), const Alignment(-0.6, 1));
  });

  testWidgets('image layer preserves placement across sprite swaps', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAt: 'left',
      showAsset: 'assets/game/images/sylvie green normal.png',
    );
    await tester.pump();

    controller.value = RenPyImageChange(
      show: 'sylvie green smile',
      showAsset: 'assets/game/images/sylvie green smile.png',
    );
    await tester.pump();

    expect(_spriteAlignment(tester, 'sylvie'), Alignment.bottomLeft);
    expect(_assetNames(tester), ['assets/game/images/sylvie green smile.png']);
  });

  testWidgets('image layer applies displayable operations', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'flashback bg',
      sceneImage: const RenPyResolvedImage(
        assetPath: 'assets/game/images/bg/flashback.jpg',
        operations: [RenPyImageOperation.grayscale()],
      ),
    );
    await tester.pump();

    expect(find.byType(ColorFiltered), findsOneWidget);

    controller.value = RenPyImageChange(
      show: 'sha flipped',
      showImage: const RenPyResolvedImage(
        assetPath: 'assets/game/images/sha.png',
        operations: [RenPyImageOperation.flipHorizontal()],
      ),
    );
    await tester.pump();

    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any((transform) => transform.transform.storage[0] == -1),
      isTrue,
    );
  });
}

List<String> _assetNames(WidgetTester tester) {
  return tester.widgetList<Image>(find.byType(Image)).map((image) {
    final provider = image.image as AssetImage;
    return provider.assetName;
  }).toList();
}

Alignment _spriteAlignment(WidgetTester tester, String tag) {
  return tester
          .widget<Align>(
            find.descendant(
              of: find.byKey(ValueKey(tag)),
              matching: find.byType(Align),
            ),
          )
          .alignment
      as Alignment;
}
