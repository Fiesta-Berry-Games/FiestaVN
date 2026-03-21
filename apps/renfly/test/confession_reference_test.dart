import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_core/renpy_core.dart'
    show
        RenPyColorValue,
        RenPyGenericStatement,
        RenPyNvlStatement,
        RenPyParser,
        RenPyStyledText;
import 'package:renpy_flutter/renpy_flutter.dart';

void main() {
  final fixture = Directory('assets/games/Confession-1.03-pc/game');
  final skipReason =
      fixture.existsSync()
          ? null
          : 'Local Confession of the Golden Witch fixture is not present.';

  test('loads Confession scripts from RPA archives', () {
    final project = _loadProjectFolder(fixture);

    expect(project.name, 'Confession-1.03-pc');
    expect(project.scriptPath, endsWith('/game/script.rpy'));
    expect(project.scriptSource, contains('label start:'));
    expect(project.scriptSource, contains('jump prologue'));
    expect(
      project.availableAssets,
      contains(endsWith('/game/images/bg/closedring.jpg')),
    );

    final script =
        RenPyParser().parse(project.scriptSource, project.scriptPath).script;
    expect(script.findStatements<RenPyNvlStatement>((_) => true), isNotEmpty);
    expect(
      script.findStatements<RenPyGenericStatement>(
        (statement) => statement.text == 'nvl clear',
      ),
      isEmpty,
    );
  }, skip: skipReason);

  test('Confession reaches the first dialogue beat', () async {
    final project = _loadProjectFolder(fixture);
    final controller = RenPyFlutterController();
    addTearDown(controller.dispose);

    controller.load(
      project.scriptSource,
      filename: project.scriptPath,
      gameRoot: project.gameRoot,
      availableAssets: project.availableAssets,
    );

    await _continueUntil(controller, (status) => status is RenPyDialogue);

    final dialogue = controller.value as RenPyDialogue;
    expect(dialogue.text, startsWith('Please note.'));
  }, skip: skipReason);

  test('Confession resolves first archived image and music assets', () async {
    final project = _loadProjectFolder(fixture);
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
      project.scriptSource,
      filename: project.scriptPath,
      gameRoot: project.gameRoot,
      availableAssets: project.availableAssets,
    );

    await _continueUntil(
      controller,
      (status) =>
          images.any((image) => image.scene == 'fea_l4') &&
          audio.any((change) => change.asset == '/music/She End.ogg'),
    );

    final firstBackground = images.firstWhere(
      (image) => image.scene == 'fea_l4',
    );
    expect(firstBackground.sceneAsset, endsWith('/game/images/bg/fea_l4.jpg'));
    expect(project.readAsset(firstBackground.sceneAsset!), isNotNull);

    final erika = images.firstWhere((image) => image.show == 'eri defa2');
    final ange = images.firstWhere((image) => image.show == 'enj fumana2');
    expect(erika.showPlacement, const RenPyImagePlacement.position(xpos: 0.2));
    expect(ange.showPlacement, const RenPyImagePlacement.position(xpos: 0.8));

    final firstMusic = audio.firstWhere(
      (change) => change.asset == '/music/She End.ogg',
    );
    expect(
      project.readAsset('${project.gameRoot}${firstMusic.asset}'),
      isNotNull,
    );
  }, skip: skipReason);

  test('Confession resolves wrapper aliases and case-varied audio', () async {
    final project = _loadProjectFolder(fixture);
    final controller = RenPyFlutterController();
    final images = <RenPyImageChange>[];
    final audio = <RenPyAudioChange>[];
    final dialogue = <RenPyDialogue>[];
    final transitions = <RenPyTransitionChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyImageChange) images.add(status);
      if (status is RenPyAudioChange) audio.add(status);
      if (status is RenPyDialogue) dialogue.add(status);
      if (status is RenPyTransitionChange) transitions.add(status);
    });

    controller.load(
      project.scriptSource,
      filename: project.scriptPath,
      gameRoot: project.gameRoot,
      availableAssets: project.availableAssets,
    );

    await _continueUntil(
      controller,
      (status) =>
          images.any((image) => image.scene == 'fea_l8bw') &&
          images.any((image) => image.scene == 'white') &&
          audio.any((change) => change.asset == '/SE/Z1.wav') &&
          audio.any((change) => change.asset == '/ME/rain_2.wav'),
      maxSteps: 200,
    );

    final grayscaleBackground = images.firstWhere(
      (image) => image.scene == 'fea_l8bw',
    );
    expect(
      grayscaleBackground.sceneAsset,
      endsWith('/game/images/bg/fea_l8.jpg'),
    );
    expect(grayscaleBackground.sceneImage?.operations, const [
      RenPyImageOperation.grayscale(),
    ]);
    expect(project.readAsset(grayscaleBackground.sceneAsset!), isNotNull);

    final grayscaleErika = images.firstWhere(
      (image) => image.show == 'eri defa2bw',
    );
    expect(
      grayscaleErika.showPlacement,
      const RenPyImagePlacement.position(xpos: 0.25),
    );
    expect(grayscaleErika.showBehind, 'enj');

    final whiteScene = images.firstWhere((image) => image.scene == 'white');
    expect(whiteScene.sceneAsset, isNull);
    expect(
      whiteScene.sceneImage?.solidColor,
      const RenPyColorValue(255, 255, 255, 255),
    );

    expect(project.readAsset('${project.gameRoot}/SE/Z1.wav'), isNotNull);
    expect(project.readAsset('${project.gameRoot}/ME/rain_2.wav'), isNotNull);
    expect(
      transitions
          .firstWhere((transition) => transition.name == 'openfade')
          .intent,
      const RenPyTransitionIntent.fade(
        outTime: 1.5,
        holdTime: 2.0,
        inTime: 2.0,
        color: '#fff',
      ),
    );
    expect(
      transitions
          .firstWhere(
            (transition) => transition.name == 'quickgradientwiperight',
          )
          .intent,
      const RenPyTransitionIntent.imageDissolve(
        maskAsset: 'right.png',
        duration: 1.5,
        ramplen: 16,
      ),
    );
    final circleFade =
        transitions
            .firstWhere(
              (transition) => transition.name == 'quickgradientcirclefade',
            )
            .intent;
    expect(
      circleFade,
      const RenPyTransitionIntent.imageDissolve(
        maskAsset: 'circle.png',
        duration: 0.5,
        ramplen: 16,
        reverse: true,
      ),
    );
    expect(circleFade?.fidelity, RenPyTransitionFidelity.approximated);
    final punch =
        transitions
            .firstWhere((transition) => transition.name == 'vpunch')
            .intent;
    expect(
      punch,
      const RenPyTransitionIntent.punch(mode: 'vertical', duration: 0.275),
    );
    expect(punch?.fidelity, RenPyTransitionFidelity.approximated);
    expect(dialogue.map((line) => line.character), isNot(contains('extend')));
    expect(
      dialogue.map((line) => line.text),
      contains(
        contains(
          'library. Her eyes were drawn to a large shelf, laden with bottles.',
        ),
      ),
    );
  }, skip: skipReason);

  test('Confession emits the title card show text displayable', () async {
    final project = _loadProjectFolder(fixture);
    final controller = RenPyFlutterController();
    final images = <RenPyImageChange>[];
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyImageChange) images.add(status);
    });

    controller.load(
      project.scriptSource,
      filename: project.scriptPath,
      gameRoot: project.gameRoot,
      availableAssets: project.availableAssets,
    );

    await _continueUntil(
      controller,
      (status) => images.any(
        (image) =>
            image.show == 'text' &&
            (image.showText?.contains('Confession of the Golden Witch') ??
                false),
      ),
      maxSteps: 500,
    );

    final title = images.firstWhere(
      (image) =>
          image.show == 'text' &&
          (image.showText?.contains('Confession of the Golden Witch') ?? false),
    );
    final redScene = images.firstWhere((image) => image.scene == 'red');
    expect(redScene.sceneAsset, isNull);
    expect(
      redScene.sceneImage?.solidColor,
      const RenPyColorValue(255, 0, 0, 255),
    );
    expect(
      RenPyStyledText.parse(title.showText!).plainText,
      'Confession of the Golden Witch',
    );
    expect(
      title.showPlacement,
      const RenPyImagePlacement.position(
        xpos: 0.5,
        xanchor: 0.5,
        ypos: 0.5,
        yanchor: 0.5,
      ),
    );
    expect(title.showAsset, isNull);
  }, skip: skipReason);

  testWidgets(
    'Confession project player renders an archived background',
    (tester) async {
      final project = _loadProjectFolder(fixture);

      await tester.pumpWidget(
        MaterialApp(
          home: RenPyProjectPlayer(
            project: project,
            audioPlayback: const RenPyNoOpAudioPlayback(),
          ),
        ),
      );

      await _pumpUntilText(tester, 'Please note.');
      expect(find.textContaining('{i}'), findsNothing);
      expect(find.textContaining('{/i}'), findsNothing);
      expect(find.textContaining('{w}'), findsNothing);
      _expectItalicSpan(tester, 'Confession of the Golden Witch');

      await tester.tap(find.textContaining('Please note.'));
      await _pumpUntilImages(tester);

      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.map((image) => image.image), contains(isA<MemoryImage>()));
    },
    skip: skipReason != null,
  );

  testWidgets(
    'Confession project player renders the red title card',
    (tester) async {
      final project = _loadProjectFolder(fixture);

      await tester.pumpWidget(
        MaterialApp(
          home: RenPyProjectPlayer(
            project: project,
            audioPlayback: const RenPyNoOpAudioPlayback(),
          ),
        ),
      );

      await _pumpUntilTitleCard(tester);

      expect(_stageColors(tester), contains(const Color(0xFFFF0000)));
      expect(
        find.textContaining('Confession of the Golden Witch'),
        findsWidgets,
      );
    },
    skip: skipReason != null,
  );
}

RenPyGameProject _loadProjectFolder(Directory directory) {
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => RenPyProjectFile(file.path, file.readAsBytesSync()));
  return RenPyGameProject.fromFiles(files);
}

Future<void> _continueUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate, {
  int maxSteps = 100,
}) async {
  for (var i = 0; i < maxSteps; i += 1) {
    if (predicate(controller.value)) return;
    if (controller.value is RenPyDialogue || controller.value is RenPyPause) {
      controller.continueGame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  for (var i = 0; i < 50; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.textContaining(text).evaluate().isNotEmpty) return;
    if (find.byType(RenPyPauseView).evaluate().isNotEmpty) {
      await tester.tap(find.byType(RenPyPauseView));
    }
  }

  fail('Timed out waiting for text containing "$text".');
}

Future<void> _pumpUntilImages(WidgetTester tester) async {
  for (var i = 0; i < 50; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(Image).evaluate().isNotEmpty) return;
  }

  fail('Timed out waiting for archived images.');
}

Future<void> _pumpUntilTitleCard(WidgetTester tester) async {
  for (var i = 0; i < 700; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    final titleVisible =
        find.textContaining('Confession of the Golden Witch').evaluate().length;
    if (titleVisible >= 1 &&
        _stageColors(tester).contains(const Color(0xFFFF0000))) {
      return;
    }

    await tester.tapAt(tester.getCenter(find.byType(RenPyProjectPlayer)));
  }

  fail('Timed out waiting for the red title card.');
}

void _expectItalicSpan(WidgetTester tester, String text) {
  final renderedText = tester.widget<Text>(
    find.descendant(of: find.byType(RenPyText), matching: find.byType(Text)),
  );
  final rootSpan = renderedText.textSpan! as TextSpan;
  final spans = rootSpan.children!.cast<TextSpan>();
  expect(
    spans.singleWhere((span) => span.text == text).style?.fontStyle,
    FontStyle.italic,
  );
}

List<Color> _stageColors(WidgetTester tester) {
  final stage = find.byKey(const ValueKey('renpy-stage-color'));
  if (stage.evaluate().isEmpty) return const [];
  return tester.widgetList<ColoredBox>(stage).map((box) => box.color).toList();
}
