import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  test('normalizes absolute desktop picker paths', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('/tmp/the_question/game/script.rpy', '''
label start:
    "Desktop."
'''),
    ]);

    expect(project.name, 'the_question');
    expect(project.scriptPath, 'tmp/the_question/game/script.rpy');
    expect(project.gameRoot, 'tmp/the_question/game');
  });

  test('loads scripts from RPA archives when loose script.rpy is absent', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile(
        'confession/game/scripts.rpa',
        _rpaArchive({
          'script.rpy': utf8.encode('''
label start:
    "Packed."
'''),
          'options.rpy': utf8.encode('define config.name = "Packed Game"'),
          'images/bg.png': [1, 2, 3],
        }),
      ),
    ]);

    expect(project.name, 'confession');
    expect(project.scriptPath, 'confession/game/script.rpy');
    expect(project.gameRoot, 'confession/game');
    expect(project.scriptSource, contains('label start:'));
    expect(project.scriptSource, contains('"Packed."'));
    expect(project.readAsset('confession/game/options.rpy'), isNotNull);
    expect(project.availableAssets, contains('confession/game/images/bg.png'));
    expect(project.readAsset('confession/game/images/bg.png'), [1, 2, 3]);
  });
}

Uint8List _rpaArchive(Map<String, List<int>> files) {
  const key = 0x42424242;
  const headerLength = 34;
  final payload = BytesBuilder();
  final entries = <String, ({int offset, int length})>{};

  for (final entry in files.entries) {
    entries[entry.key] = (
      offset: headerLength + payload.length,
      length: entry.value.length,
    );
    payload.add(entry.value);
  }

  final indexOffset = headerLength + payload.length;
  final index = ZLibEncoder().encode(_pickleRpaIndex(entries, key));
  final header =
      'RPA-3.0 ${indexOffset.toRadixString(16).padLeft(16, '0')} '
      '${key.toRadixString(16).padLeft(8, '0')}\n';

  return Uint8List.fromList([
    ...ascii.encode(header),
    ...payload.toBytes(),
    ...index,
  ]);
}

List<int> _pickleRpaIndex(
  Map<String, ({int offset, int length})> entries,
  int key,
) {
  final bytes = BytesBuilder()..add([0x80, 0x02, 0x7d, 0x71, 0x01, 0x28]);
  var memo = 2;

  for (final entry in entries.entries) {
    final name = utf8.encode(entry.key);
    bytes
      ..add([0x58])
      ..add(_uint32(name.length))
      ..add(name)
      ..add([0x5d, 0x71, memo++, 0x4a])
      ..add(_int32(entry.value.offset ^ key))
      ..add([0x4a])
      ..add(_int32(entry.value.length ^ key))
      ..add([0x55, 0x00, 0x87, 0x71, memo++, 0x61]);
  }

  bytes.add([0x75, 0x2e]);
  return bytes.toBytes();
}

List<int> _uint32(int value) {
  return [
    value & 0xff,
    (value >> 8) & 0xff,
    (value >> 16) & 0xff,
    (value >> 24) & 0xff,
  ];
}

List<int> _int32(int value) => _uint32(value);
