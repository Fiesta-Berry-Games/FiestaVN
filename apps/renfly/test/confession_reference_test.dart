import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    addTearDown(controller.dispose);

    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyImageChange) images.add(status);
      if (status is RenPyAudioChange) audio.add(status);
      if (status is RenPyDialogue) dialogue.add(status);
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
    expect(project.readAsset(grayscaleBackground.sceneAsset!), isNotNull);

    final whiteScene = images.firstWhere((image) => image.scene == 'white');
    expect(whiteScene.sceneAsset, isNull);

    expect(project.readAsset('${project.gameRoot}/SE/Z1.wav'), isNotNull);
    expect(project.readAsset('${project.gameRoot}/ME/rain_2.wav'), isNotNull);
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
      await tester.tap(find.textContaining('Please note.'));
      await _pumpUntilImages(tester);

      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.map((image) => image.image), contains(isA<MemoryImage>()));
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
    if (controller.value is RenPyDialogue) {
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
