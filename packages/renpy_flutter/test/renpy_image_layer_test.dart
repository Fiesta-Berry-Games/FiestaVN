import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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

  testWidgets('image layer starts same-frame fades from previous state', (
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
    controller.value = const RenPyTransitionChange(
      'fade',
      intent: RenPyTransitionIntent.fade(
        outTime: 0.5,
        holdTime: 0,
        inTime: 0.5,
      ),
    );

    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 750));
    expect(_assetNames(tester), ['assets/game/images/bg lecturehall.jpg']);
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

    expect(_spriteAnchor(tester, 'sylvie'), const Offset(400, 600));
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

    expect(_spriteAnchor(tester, 'sylvie'), const Offset(0, 600));
    expect(_spriteAnchor(tester, 'eileen'), const Offset(800, 600));
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

    expect(_spriteAnchor(tester, 'eri'), const Offset(160, 600));
  });

  testWidgets(
    'image layer resolves pixel Position placement against screen size',
    (tester) async {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 800,
            height: 600,
            child: RenPyImageLayer(
              controller: controller,
              screenSize: const RenPyScreenSize(width: 800, height: 600),
            ),
          ),
        ),
      );

      controller.value = RenPyImageChange(
        show: 'title',
        showText: 'Centered',
        showPlacement: RenPyImagePlacement.position(
          xpos: 400,
          ypos: 300,
          xanchor: 0.5,
          yanchor: 0.5,
          xposIsPixel: true,
          yposIsPixel: true,
        ),
      );
      await tester.pump();

      expect(_spriteAnchor(tester, 'title'), const Offset(400, 300));
    },
  );

  testWidgets('image layer renders image sprites at native image size', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    final spriteImage = await _createTestImage(500, 300);
    addTearDown(spriteImage.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: RenPyImageLayer(
            controller: controller,
            imageProvider:
                (_) => _FixedSizeImageProvider('sprite.png', spriteImage),
          ),
        ),
      ),
    );

    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAsset: 'assets/game/images/sylvie green normal.png',
      showPlacement: const RenPyImagePlacement.position(
        xpos: 0.5,
        ypos: 0.5,
        xanchor: 0.5,
        yanchor: 0.5,
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(Image)), const Size(500, 300));
  });

  testWidgets('image layer scales sprites from RenPy screen coordinates', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    final spriteImage = await _createTestImage(1154, 960);
    addTearDown(spriteImage.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: RenPyImageLayer(
            controller: controller,
            screenSize: const RenPyScreenSize(width: 1280, height: 960),
            imageProvider:
                (_) => _FixedSizeImageProvider('sprite.png', spriteImage),
          ),
        ),
      ),
    );

    controller.value = RenPyImageChange(
      show: 'eri defa2',
      showAsset: 'assets/game/images/eri defa2.png',
      showPlacement: const RenPyImagePlacement.position(xpos: 0.2),
    );
    await tester.pump();

    final scaleTransforms = tester.widgetList<Transform>(
      find.ancestor(of: find.byType(Image), matching: find.byType(Transform)),
    );
    final screenScale = scaleTransforms.singleWhere(
      (transform) => transform.transform.storage[0] == 0.625,
    );

    expect(screenScale.transform.storage[5], 0.625);
    expect(screenScale.alignment, Alignment.topLeft);
    expect(_spriteAnchor(tester, 'eri'), const Offset(160, 600));
  });

  testWidgets('image layer positions scaled sprites across the stage', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    final spriteImage = await _createTestImage(320, 960);
    addTearDown(spriteImage.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: RenPyImageLayer(
            controller: controller,
            screenSize: const RenPyScreenSize(width: 1280, height: 960),
            imageProvider:
                (_) => _FixedSizeImageProvider('sprite.png', spriteImage),
          ),
        ),
      ),
    );

    controller.value = RenPyImageChange(
      show: 'eri defa2',
      showAsset: 'assets/game/images/eri defa2.png',
      showPlacement: const RenPyImagePlacement.position(xpos: 0.2),
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'enj fumana2',
      showAsset: 'assets/game/images/enj fumana2.png',
      showPlacement: const RenPyImagePlacement.position(xpos: 0.8),
    );
    await tester.pump();

    final eri = _spriteImageRect(tester, 'eri');
    final enj = _spriteImageRect(tester, 'enj');
    expect(eri.center.dx, moreOrLessEquals(160));
    expect(enj.center.dx, moreOrLessEquals(640));
    expect(eri.top, moreOrLessEquals(0));
    expect(eri.bottom, moreOrLessEquals(600));
  });

  testWidgets('image layer applies Transform scale intent to image sprites', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);
    final spriteImage = await _createTestImage(200, 100);
    addTearDown(spriteImage.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 800,
          height: 600,
          child: RenPyImageLayer(
            controller: controller,
            imageProvider:
                (_) => _FixedSizeImageProvider('sprite.png', spriteImage),
          ),
        ),
      ),
    );

    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAsset: 'assets/game/images/sylvie green normal.png',
      showPlacement: const RenPyImagePlacement.position(
        xpos: 0.5,
        ypos: 0.5,
        xanchor: 0.5,
        yanchor: 0.5,
        zoom: 2,
        xzoom: 1.5,
        yzoom: 0.5,
      ),
    );
    await tester.pump();

    final scaleTransforms = tester.widgetList<Transform>(
      find.ancestor(of: find.byType(Image), matching: find.byType(Transform)),
    );
    expect(
      scaleTransforms.any(
        (transform) =>
            transform.transform.storage[0] == 3 &&
            transform.transform.storage[5] == 1,
      ),
      isTrue,
    );
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

    expect(_spriteAnchor(tester, 'sylvie'), const Offset(0, 600));
    expect(_assetNames(tester), ['assets/game/images/sylvie green smile.png']);
  });

  testWidgets('image layer keys same-tag sprites by layer', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'logo',
      showAsset: 'assets/game/images/logo-master.png',
    );
    await tester.pump();

    controller.value = RenPyImageChange(
      show: 'logo',
      showOnLayer: 'abovemid',
      showAsset: 'assets/game/images/logo-abovemid.png',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('abovemid::logo')), findsOneWidget);
    expect(_assetNames(tester), [
      'assets/game/images/logo-master.png',
      'assets/game/images/logo-abovemid.png',
    ]);

    controller.value = RenPyImageChange(hide: 'logo', hideOnLayer: 'master');
    await tester.pump();

    expect(find.byKey(const ValueKey('logo')), findsNothing);
    expect(find.byKey(const ValueKey('abovemid::logo')), findsOneWidget);
    expect(_assetNames(tester), ['assets/game/images/logo-abovemid.png']);

    controller.value = RenPyImageChange(
      show: 'logo',
      showAsset: 'assets/game/images/logo-master.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      scene: 'black',
      sceneOnLayer: 'abovemid',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('abovemid::logo')), findsNothing);
    expect(_assetNames(tester), ['assets/game/images/logo-master.png']);
  });

  testWidgets('image layer renders non-master scenes as layered sprites', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'bg room',
      sceneAsset: 'assets/game/images/bg-room.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'logo',
      showAsset: 'assets/game/images/logo.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      scene: 'overlay',
      sceneOnLayer: 'abovemid',
      sceneAsset: 'assets/game/images/overlay.png',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('logo')), findsOneWidget);
    expect(find.byKey(const ValueKey('abovemid::overlay')), findsOneWidget);
    expect(_assetNames(tester), [
      'assets/game/images/bg-room.png',
      'assets/game/images/logo.png',
      'assets/game/images/overlay.png',
    ]);

    controller.value = RenPyImageChange(
      scene: 'bg other',
      sceneAsset: 'assets/game/images/bg-other.png',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('logo')), findsNothing);
    expect(find.byKey(const ValueKey('abovemid::overlay')), findsOneWidget);
    expect(_assetNames(tester), [
      'assets/game/images/bg-other.png',
      'assets/game/images/overlay.png',
    ]);

    controller.value = RenPyImageChange(
      scene: 'overlay replacement',
      sceneOnLayer: 'abovemid',
      sceneAsset: 'assets/game/images/overlay-replacement.png',
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('abovemid::overlay')), findsOneWidget);
    expect(_assetNames(tester), [
      'assets/game/images/bg-other.png',
      'assets/game/images/overlay-replacement.png',
    ]);
  });

  testWidgets('image layer renders higher layers above master sprites', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'bg room',
      sceneAsset: 'assets/game/images/bg-room.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'overlay',
      showOnLayer: 'abovemid',
      showAsset: 'assets/game/images/overlay.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'logo',
      showAsset: 'assets/game/images/logo.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/bg-room.png',
      'assets/game/images/logo.png',
      'assets/game/images/overlay.png',
    ]);
  });

  testWidgets('image layer honors configured layer order', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyImageLayer(
          controller: controller,
          layerOrder: const ['hud', 'master'],
        ),
      ),
    );

    controller.value = RenPyImageChange(
      scene: 'bg room',
      sceneAsset: 'assets/game/images/bg-room.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'overlay',
      showOnLayer: 'hud',
      showAsset: 'assets/game/images/overlay.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'logo',
      showAsset: 'assets/game/images/logo.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'sparkle',
      showOnLayer: 'unlisted',
      showAsset: 'assets/game/images/sparkle.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/bg-room.png',
      'assets/game/images/overlay.png',
      'assets/game/images/logo.png',
      'assets/game/images/sparkle.png',
    ]);
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

  testWidgets('image layer resolves behind targets within the same layer', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'eileen happy',
      showOnLayer: 'abovemid',
      showAsset: 'assets/game/images/eileen.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'sylvie green normal',
      showAsset: 'assets/game/images/sylvie.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'logo',
      showOnLayer: 'abovemid',
      showBehind: 'eileen',
      showAsset: 'assets/game/images/logo.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/sylvie.png',
      'assets/game/images/logo.png',
      'assets/game/images/eileen.png',
    ]);
  });

  testWidgets('image layer ignores behind targets on other layers', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'eileen happy',
      showAsset: 'assets/game/images/eileen.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'logo',
      showOnLayer: 'abovemid',
      showBehind: 'eileen',
      showAsset: 'assets/game/images/logo.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/eileen.png',
      'assets/game/images/logo.png',
    ]);
  });

  testWidgets('image layer orders sprites by layer then zorder', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'front',
      showZOrder: 10,
      showAsset: 'assets/game/images/front.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'back',
      showZOrder: -5,
      showAsset: 'assets/game/images/back.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'above',
      showOnLayer: 'abovemid',
      showZOrder: -100,
      showAsset: 'assets/game/images/above.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/back.png',
      'assets/game/images/front.png',
      'assets/game/images/above.png',
    ]);
  });

  testWidgets('image layer orders layered scenes by zorder', (tester) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      scene: 'overlay',
      sceneOnLayer: 'abovemid',
      sceneZOrder: 10,
      sceneAsset: 'assets/game/images/overlay.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'logo',
      showOnLayer: 'abovemid',
      showZOrder: 20,
      showAsset: 'assets/game/images/logo.png',
    );
    await tester.pump();
    controller.value = RenPyImageChange(
      show: 'back',
      showOnLayer: 'abovemid',
      showZOrder: -5,
      showAsset: 'assets/game/images/back.png',
    );
    await tester.pump();

    expect(_assetNames(tester), [
      'assets/game/images/back.png',
      'assets/game/images/overlay.png',
      'assets/game/images/logo.png',
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

  testWidgets('image layer applies placement alpha to displayables', (
    tester,
  ) async {
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(home: RenPyImageLayer(controller: controller)),
    );

    controller.value = RenPyImageChange(
      show: 'logo',
      showAsset: 'assets/game/images/logo.png',
      showPlacement: const RenPyImagePlacement.position(alpha: 0.5),
    );
    await tester.pump();

    final opacity = tester.widget<Opacity>(
      find.descendant(
        of: find.byKey(const ValueKey('logo')),
        matching: find.byType(Opacity),
      ),
    );
    expect(opacity.opacity, 0.5);
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
        zoom: 1.5,
        yzoom: 2,
      ),
    );
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.byType(RenPyText), findsOneWidget);
    expect(
      tester.widget<RenPyText>(find.byType(RenPyText)).text,
      contains('Confession'),
    );
    expect(_spriteAnchor(tester, 'text'), const Offset(400, 300));

    final renderedText = tester.widget<Text>(
      find.descendant(of: find.byType(RenPyText), matching: find.byType(Text)),
    );
    final rootSpan = renderedText.textSpan! as TextSpan;
    final confession = rootSpan.children!.cast<TextSpan>().singleWhere(
      (span) => span.text == 'Confession',
    );
    expect(confession.style?.color, Colors.white);

    final scaleTransforms = tester.widgetList<Transform>(
      find.ancestor(
        of: find.byType(RenPyText),
        matching: find.byType(Transform),
      ),
    );
    expect(
      scaleTransforms.any(
        (transform) =>
            transform.transform.storage[0] == 1.5 &&
            transform.transform.storage[5] == 3,
      ),
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

Offset _spriteAnchor(WidgetTester tester, String tag) {
  final positioned = tester.widgetList<Positioned>(
    find.descendant(
      of: find.byKey(ValueKey(tag)),
      matching: find.byType(Positioned),
    ),
  );
  final anchor = positioned.lastWhere(
    (widget) =>
        widget.left != null && widget.top != null && widget.right == null,
  );
  return Offset(anchor.left!, anchor.top!);
}

Color _stageColor(WidgetTester tester) {
  return tester
      .widget<ColoredBox>(find.byKey(const ValueKey('renpy-stage-color')))
      .color;
}

Rect _spriteImageRect(WidgetTester tester, String tag) {
  return tester.getRect(
    find.descendant(
      of: find.byKey(ValueKey(tag)),
      matching: find.byType(Image),
    ),
  );
}

Future<ui.Image> _createTestImage(int width, int height) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = Colors.white,
  );
  return recorder.endRecording().toImage(width, height);
}

class _FixedSizeImageProvider extends ImageProvider<_FixedSizeImageProvider> {
  const _FixedSizeImageProvider(this.assetPath, this.image);

  final String assetPath;
  final ui.Image image;

  @override
  Future<_FixedSizeImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_FixedSizeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FixedSizeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      SynchronousFuture<ImageInfo>(ImageInfo(image: image)),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _FixedSizeImageProvider &&
        other.assetPath == assetPath &&
        other.image == image;
  }

  @override
  int get hashCode => Object.hash(assetPath, image);

  @override
  String toString() => '_FixedSizeImageProvider($assetPath)';
}
