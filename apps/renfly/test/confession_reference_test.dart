import 'dart:io';

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
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 100; i += 1) {
    if (predicate(controller.value)) return;
    if (controller.value is RenPyDialogue) {
      controller.continueGame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}
