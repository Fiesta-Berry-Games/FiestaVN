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

  test('combines all RenPy scripts under the game root', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('split/game/script.rpy', '''
label start:
    "From script."
    jump chapter_two
'''),
      RenPyProjectFile.text('split/game/chapter_two.rpy', '''
define e = Character("Extra", color="#fff")

label chapter_two:
    e "From chapter two."
'''),
      RenPyProjectFile.text('split/game/sub/side_story.rpy', '''
label side_story:
    "Side story."
'''),
      RenPyProjectFile.text('split/other/script.rpy', '''
label start:
    "Wrong root."
'''),
    ]);

    expect(project.scriptPath, 'split/game/script.rpy');
    expect(project.scriptSource, contains('label start:'));
    expect(project.scriptSource, contains('label chapter_two:'));
    expect(project.scriptSource, contains('label side_story:'));
    expect(project.scriptSource, isNot(contains('Wrong root.')));

    final script =
        RenPyParser().parse(project.scriptSource, project.scriptPath).script;
    final runner = RenPyRunner(script);
    final dialogue = <RenPyDialogueEvent>[];
    runner.onDialogueEvent = dialogue.add;

    runner.jumpToLabel('start');
    runner.run();
    runner.continueExecution();

    expect(dialogue.map((event) => event.text), [
      'From script.',
      'From chapter two.',
    ]);

    expect(dialogue.last.displayName, 'Extra');
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
          'fonts/Packed.ttf': [4, 5, 6],
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
    expect(
      project.fontAssets['fonts/Packed.ttf'],
      'confession/game/fonts/Packed.ttf',
    );
    expect(
      project.fontAssets['Packed.ttf'],
      'confession/game/fonts/Packed.ttf',
    );
  });

  test('reads loose and archived assets case-insensitively', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Packed."
'''),
      RenPyProjectFile(
        'confession/game/se/Z1.wav',
        Uint8List.fromList([1, 2, 3]),
      ),
      RenPyProjectFile(
        'confession/game/archive.rpa',
        _rpaArchive({
          'ME/rain_2.WAV': [4, 5, 6],
          'music/Rose.ogg': [7, 8, 9],
        }),
      ),
    ]);

    expect(project.readAsset('confession/game/SE/Z1.wav'), [1, 2, 3]);
    expect(project.readAsset('confession/game/ME/rain_2.wav'), [4, 5, 6]);
    expect(project.readAsset('confession/game/music/rose.ogg'), [7, 8, 9]);
  });

  test('discovers configured screen size from project scripts', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('wide/game/options.rpy', '''
define config.name = "Wide Game"
define config.screen_width = 1280
define config.screen_height = 720
'''),
      RenPyProjectFile.text('wide/game/script.rpy', '''
label start:
    "Wide."
'''),
    ]);

    expect(project.screenSize, const RenPyScreenSize(width: 1280, height: 720));
  });

  test('discovers configured screen size from gui init calls', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/options.rpy', '''
init python:
    gui.init(1280, 960)
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Classic."
'''),
    ]);

    expect(project.screenSize, const RenPyScreenSize(width: 1280, height: 960));
  });

  test('discovers project font assets with RenPy font tag aliases', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    show text "{font=UglyQua.ttf}Title{/font}"
'''),
      RenPyProjectFile(
        'confession/game/UglyQua.ttf',
        Uint8List.fromList([1, 2, 3]),
      ),
      RenPyProjectFile(
        'confession/game/fonts/Title.otf',
        Uint8List.fromList([4, 5, 6]),
      ),
    ]);

    expect(project.fontAssets['UglyQua.ttf'], 'confession/game/UglyQua.ttf');
    expect(
      project.fontAssets['fonts/Title.otf'],
      'confession/game/fonts/Title.otf',
    );
    expect(project.fontAssets['Title.otf'], 'confession/game/fonts/Title.otf');
  });

  test('discovers RenPy GUI dialogue text metadata from project scripts', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/options.rpy', '''
define gui.text_font = "sazanami-gothic.ttf"
define gui.text_size = 48
define gui.text_color = '#ffffff'
define gui.dialogue_text_outlines = [ (0, "#000000", 3, 3) ]
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
define gui.text_size = 12
    "Styled."
'''),
    ]);

    expect(project.gui.dialogueTextFont, 'sazanami-gothic.ttf');
    expect(project.gui.dialogueTextSize, 48);
    expect(project.gui.dialogueTextColor, '#ffffff');
    expect(project.gui.dialogueTextOutlineColor, '#000000');
  });

  test('discovers RenPy GUI dialogue window geometry metadata', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/options.rpy', '''
define gui.textbox_height = 278
define gui.textbox_yalign = 1.0
define gui.dialogue_xpos = 120
define gui.dialogue_ypos = 74
define gui.dialogue_width = 1040
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Geometry."
'''),
    ]);

    expect(project.gui.textboxHeight, 278);
    expect(project.gui.textboxYAlign, 1.0);
    expect(project.gui.dialogueXPos, 120);
    expect(project.gui.dialogueYPos, 74);
    expect(project.gui.dialogueWidth, 1040);
  });

  test('discovers RenPy GUI textbox image metadata', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/options.rpy', '''
define gui.textbox = "gui/textbox.png"
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Textbox image."
'''),
    ]);

    expect(project.gui.textboxAsset, 'gui/textbox.png');
  });

  test('discovers RenPy window style textbox image metadata', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/screens.rpy', '''
style window:
    background Frame("gui/textbox.png", 12, 12)
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Textbox image from style."
'''),
    ]);

    expect(project.gui.textboxAsset, 'gui/textbox.png');
  });

  test('preserves RenPy window Frame textbox borders', () {
    final project = RenPyGameProject.fromFiles([
      RenPyProjectFile.text('confession/game/screens.rpy', '''
style window:
    background Frame("gui/textbox.png", 12, 8, 14, 10)
'''),
      RenPyProjectFile.text('confession/game/script.rpy', '''
label start:
    "Framed textbox image."
'''),
    ]);

    final background = project.gui.textboxBackground;
    expect(background, isA<RenPyGuiFrameBackground>());

    final frame = background as RenPyGuiFrameBackground;
    expect(frame.asset, 'gui/textbox.png');
    expect(frame.left, 12);
    expect(frame.top, 8);
    expect(frame.right, 14);
    expect(frame.bottom, 10);
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
