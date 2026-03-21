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

  testWidgets('image layer renders RenPy solid color scenes', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(scene: 'white');
    await tester.pump();

    expect(_stageColor(tester), Colors.white);

    controller.value = RenPyImageChange(scene: 'red');
    await tester.pump();

    expect(_stageColor(tester), const Color(0xFFFF0000));
  });

  testWidgets('image layer renders resolved Solid displayable scenes', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'custom solid',
      sceneImage: const RenPyResolvedImage.solid(
        RenPyColorValue(64, 128, 192, 255),
      ),
    );
    await tester.pump();

    expect(_stageColor(tester), const Color(0xFF4080C0));
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

  testWidgets('image layer approximates punch transitions as shakes', (
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
    controller.value = const RenPyTransitionChange(
      'vpunch',
      intent: RenPyTransitionIntent.punch(mode: 'vertical', duration: 0.275),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));

    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    expect(
      transforms.any((transform) => transform.transform.storage[13] != 0),
      isTrue,
    );
    expect(_assetNames(tester), [
      'assets/game/images/bg lecturehall.jpg',
      'assets/game/images/sylvie green normal.png',
    ]);
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

  testWidgets('image layer inserts shown sprites behind target tags', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'enj defa1',
      showAsset: 'assets/game/images/enj.png',
    );
    await tester.pump();

    controller.value = RenPyImageChange(
      show: 'eri defa2bw',
      showBehind: 'enj',
      showAsset: 'assets/game/images/eri.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/eri.png',
      'assets/game/images/enj.png',
    ]);
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

  testWidgets('image layer renders show text displayables at placement', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'text',
      showText: '{color=#FFF}Confession{/color}',
      showPlacement: const RenPyImagePlacement.position(
        xpos: 0.5,
        xanchor: 0.5,
        ypos: 0.5,
        yanchor: 0.5,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byType(RenPyText), findsOneWidget);
    expect(
      tester.widget<RenPyText>(find.byType(RenPyText)).text,
      contains('Confession'),
    );
    expect(_spriteAlignment(tester, 'text'), Alignment.center);

    final renderedText = tester.widget<Text>(
      find.descendant(of: find.byType(RenPyText), matching: find.byType(Text)),
    );
    final rootSpan = renderedText.textSpan! as TextSpan;
    final confession = rootSpan.children!.cast<TextSpan>().singleWhere(
      (span) => span.text == 'Confession',
    );
    expect(confession.style?.color, Colors.white);
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

Color _stageColor(WidgetTester tester) {
  return tester
      .widget<ColoredBox>(find.byKey(const ValueKey('renpy-stage-color')))
      .color;
}
