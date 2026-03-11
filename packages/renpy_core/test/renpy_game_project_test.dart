import 'dart:convert';
import 'dart:typed_data';

import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('loads a The Question-shaped project folder', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('the_question/game/script.rpy', '''
label start:
    play music "illurock.opus"
    scene bg lecturehall
    "Welcome."
'''),
      RenPyProjectFile(
        'the_question/game/illurock.opus',
        Uint8List.fromList([1, 2, 3]),
      ),
      RenPyProjectFile(
        r'the_question\game\images\bg lecturehall.jpg',
        Uint8List.fromList([4, 5, 6]),
      ),
    ]);

    expect(project.name, 'the_question');
    expect(project.scriptPath, 'the_question/game/script.rpy');
    expect(project.gameRoot, 'the_question/game');
    expect(project.scriptSource, contains('play music "illurock.opus"'));
    expect(project.availableAssets, {
      'the_question/game/illurock.opus',
      'the_question/game/images/bg lecturehall.jpg',
    });
    expect(
      utf8.decode(project.readAsset('the_question/game/script.rpy')!),
      project.scriptSource,
    );
  });

  test('rejects folders without a script.rpy', () {
    expect(
      () => RenPyGameProject.fromFiles([
        RenPyProjectFile('the_question/game/illurock.opus', Uint8List(0)),
      ]),
      throwsStateError,
    );
  });
}
