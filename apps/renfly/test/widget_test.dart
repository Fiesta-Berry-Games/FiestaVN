import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renfly/main.dart';
import 'package:renfly/project_picker.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final confessionFixture = Directory('assets/games/Confession-1.03-pc/game');
  final confessionFixtureMissing = !confessionFixture.existsSync();

  testWidgets('launcher lists The Question', (tester) async {
    await _pumpFreshApp(tester);

    expect(find.text('Choose a demo game'), findsOneWidget);
    expect(find.text('Reference Game 3'), findsOneWidget);
    expect(find.text('The Question'), findsOneWidget);
  });

  testWidgets('launcher can auto-play Reference Game 3 to completion', (
    tester,
  ) async {
    final driver = _ReferenceGame3AutoPlayer();
    final playback = _RecordingAudioPlayback();
    addTearDown(playback.dispose);

    await _pumpFreshApp(
      tester,
      audioPlayback: playback,
      onGameControllerCreated: driver.attach,
    );

    final referenceGame3 = find.byKey(
      const ValueKey('demo_game_Reference Game 3'),
    );
    expect(referenceGame3, findsOneWidget);

    await tester.tap(referenceGame3);
    await _pumpUntil(
      tester,
      () => driver.dialogue.isNotEmpty,
      description: 'Reference Game 3 first dialogue',
    );
    await _pumpUntil(
      tester,
      () => driver.menus.isNotEmpty,
      description: 'Reference Game 3 first menu',
    );
    await _pumpUntil(
      tester,
      () => driver.complete,
      description: 'Reference Game 3 completion',
      attempts: 400,
    );

    expect(driver.error, isNull);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Reference Game 3'),
      ),
      findsOneWidget,
    );
    expect(
      playback.calls.first,
      const _AudioCall(
        channel: 'music',
        asset: 'sun-flower-slow-drag.mid',
        assetSourcePath: 'games/3/game/sun-flower-slow-drag.mid',
      ),
    );
    expect(
      driver.dialogue.first,
      "Hi, and welcome to the Ren'Py 4 demo program.",
    );
    expect(driver.menus.first, [
      "What are some features of Ren'Py games?",
      'How do I write my own games with it?',
      'Why are we in Washington, DC?',
    ]);
    expect(
      driver.selectedChoices,
      containsAll([
        "What are some features of Ren'Py games?",
        'How do I write my own games with it?',
        'Why are we in Washington, DC?',
        'Where can I find out more?',
        "I think I've heard enough.",
      ]),
    );
    expect(
      driver.dialogue,
      contains("We can't wait to see what you do with this. Good luck!"),
    );
    expect(
      playback.calls,
      contains(
        const _AudioCall(
          channel: 'sound',
          asset: '18005551212.wav',
          assetSourcePath: 'games/3/game/18005551212.wav',
        ),
      ),
    );
  });

  testWidgets('launcher opens The Question and renders the first beat', (
    tester,
  ) async {
    await _pumpFreshApp(tester);

    await tester.tap(find.byKey(const ValueKey('demo_game_The Question')));
    await _pumpUntilFirstLine(tester);

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('The Question'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsWidgets);

    final textTop =
        tester
            .getTopLeft(
              find.text(
                "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
              ),
            )
            .dy;
    expect(textTop, greaterThan(350));
  });

  testWidgets('launcher opens an external RenPy project folder', (
    tester,
  ) async {
    await _pumpFreshApp(
      tester,
      projectPicker: _FakeProjectPicker(
        RenPyGameProject.fromFiles([
          RenPyProjectFile.text('the_question/game/script.rpy', '''
label start:
    "Opened from folder."
'''),
        ]),
      ),
    );

    await tester.tap(find.text('Open Folder'));
    await _pumpUntilText(tester, 'Opened from folder.');

    expect(find.text('the_question'), findsOneWidget);
    expect(find.text('Opened from folder.'), findsOneWidget);
  });

  testWidgets('launcher opens The Question from a raw project folder', (
    tester,
  ) async {
    await _pumpFreshApp(
      tester,
      projectPicker: _FakeProjectPicker(
        _loadProjectFolder(Directory('assets/games/the_question')),
      ),
    );

    await tester.tap(find.text('Open Folder'));
    await _pumpUntilFirstLine(tester);

    expect(find.text('the_question'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets(
    'launcher opens Confession folder and auto-plays into chapter one',
    (tester) async {
      final driver = _ConfessionAutoPlayer();
      final playback = _RecordingAudioPlayback();
      addTearDown(driver.dispose);
      addTearDown(playback.dispose);

      await _pumpFreshApp(
        tester,
        audioPlayback: playback,
        projectPicker: _FakeProjectPicker(
          _loadProjectFolder(confessionFixture),
        ),
        onGameControllerCreated: driver.attach,
      );

      await tester.tap(find.text('Open Folder'));
      await _pumpUntil(
        tester,
        () => driver.firstDialogueSeen,
        description: 'Confession first dialogue',
      );
      await _pumpUntil(
        tester,
        () => driver.titleCardSeen,
        description: 'Confession title card',
        attempts: 700,
      );
      await _pumpUntil(
        tester,
        () => driver.chapterOneDialogueSeen,
        description: 'Confession chapter one dialogue',
        attempts: 200,
      );

      expect(driver.error, isNull);
      expect(find.text('Confession-1.03-pc'), findsOneWidget);
      expect(driver.dialogue.first.displayText, startsWith('Please note.'));
      expect(
        driver.dialogue.map((line) => line.displayText),
        contains(contains('If you are reading this, deliver unto me')),
      );
      expect(driver.scenes, contains('red'));
      expect(driver.showTextDisplayables, [
        contains('Confession of the Golden Witch'),
      ]);
      expect(driver.problematicDiagnostics, isEmpty);
      expect(
        playback.calls,
        contains(
          const _AudioCall(
            channel: 'music',
            asset: '/music/She End.ogg',
            assetSourcePath: 'games/Confession-1.03-pc/game/music/She End.ogg',
          ),
        ),
      );
    },
    skip: confessionFixtureMissing,
  );

  testWidgets(
    'launcher can scan Confession to completion for diagnostics',
    (tester) async {
      final driver = _ConfessionAutoPlayer(stopAtChapterOne: false);
      final playback = _RecordingAudioPlayback();
      addTearDown(driver.dispose);
      addTearDown(playback.dispose);

      await _pumpFreshApp(
        tester,
        audioPlayback: playback,
        projectPicker: _FakeProjectPicker(
          _loadProjectFolder(confessionFixture),
        ),
        onGameControllerCreated: driver.attach,
      );

      await tester.tap(find.text('Open Folder'));
      await _pumpUntil(
        tester,
        () => driver.complete,
        description: 'Confession completion',
        attempts: 1200,
      );

      expect(driver.error, isNull);
      expect(
        driver.dialogue.map((line) => line.displayText),
        contains('Afterword:'),
      );
      expect(driver.problematicDiagnosticSummaries, isEmpty);
    },
    skip: confessionFixtureMissing,
  );
}

Future<void> _pumpFreshApp(
  WidgetTester tester, {
  RenPyAudioPlayback audioPlayback = const RenPyNoOpAudioPlayback(),
  RenPyProjectPicker? projectPicker,
  ValueChanged<RenPyFlutterController>? onGameControllerCreated,
}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(
    FiestaVNApp(
      key: UniqueKey(),
      audioPlayback: audioPlayback,
      projectPicker: projectPicker,
      onGameControllerCreated: onGameControllerCreated,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpUntilFirstLine(WidgetTester tester) async {
  final firstLine = find.text(
    "It's only when I hear the sounds of shuffling feet and supplies being put away that I realize that the lecture's over.",
  );

  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (firstLine.evaluate().isNotEmpty) return;
  }

  fail('The Question did not render its first dialogue line.');
}

Future<void> _pumpUntilText(WidgetTester tester, String text) async {
  final finder = find.text(text);

  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (finder.evaluate().isNotEmpty) return;
  }

  fail('Timed out waiting for "$text".');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  String description = 'condition',
  int attempts = 80,
}) async {
  for (var i = 0; i < attempts; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (done()) return;
  }

  fail('Timed out waiting for $description.');
}

final class _FakeProjectPicker implements RenPyProjectPicker {
  const _FakeProjectPicker(this.project);

  final RenPyGameProject project;

  @override
  Future<RenPyGameProject?> pickProject() async => project;
}

RenPyGameProject _loadProjectFolder(Directory directory) {
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => RenPyProjectFile(file.path, file.readAsBytesSync()));
  return RenPyGameProject.fromFiles(files);
}

class _RecordingAudioPlayback implements RenPyAudioPlayback {
  final List<_AudioCall> calls = [];

  @override
  Future<void> play({
    required String channel,
    required String asset,
    required String assetSourcePath,
    String? fadein,
    String? mixer,
    String? fadeout,
    String? volume,
    bool? loop,
  }) async {
    calls.add(
      _AudioCall(
        channel: channel,
        asset: asset,
        assetSourcePath: assetSourcePath,
      ),
    );
  }

  @override
  Future<void> stop({required String channel, String? fadeout}) async {}

  @override
  Future<void> setMixer({
    required String channel,
    required double volume,
    required bool muted,
  }) async {}

  @override
  Future<void> setMuted({required String channel, required bool muted}) async {}

  @override
  Future<void> dispose() async {}
}

class _AudioCall {
  const _AudioCall({
    required this.channel,
    required this.asset,
    required this.assetSourcePath,
  });

  final String channel;
  final String asset;
  final String assetSourcePath;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _AudioCall &&
            channel == other.channel &&
            asset == other.asset &&
            assetSourcePath == other.assetSourcePath;
  }

  @override
  int get hashCode => Object.hash(channel, asset, assetSourcePath);

  @override
  String toString() {
    return '_AudioCall(channel: $channel, asset: $asset, '
        'assetSourcePath: $assetSourcePath)';
  }
}

class _ReferenceGame3AutoPlayer {
  final dialogue = <String>[];
  final menus = <List<String>>[];
  final selectedChoices = <String>[];
  final _remainingMainTopics = <String>{
    "What are some features of Ren'Py games?",
    'How do I write my own games with it?',
    'Why are we in Washington, DC?',
    'Where can I find out more?',
  };

  RenPyFlutterController? _controller;
  bool complete = false;
  String? error;

  void attach(RenPyFlutterController controller) {
    _controller?.removeListener(_onStatusChanged);
    _controller = controller..addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    final controller = _controller;
    if (controller == null) return;

    switch (controller.value) {
      case RenPyDialogue(:final text):
        dialogue.add(text);
        Future<void>.delayed(Duration.zero, controller.continueGame);
      case RenPyPause():
        Future<void>.delayed(Duration.zero, controller.continueGame);
      case RenPyMenu(:final choices, :final onChoice):
        menus.add(choices);
        final choice = _choiceFor(choices);
        selectedChoices.add(choice);
        _remainingMainTopics.remove(choice);
        Future<void>.delayed(
          Duration.zero,
          () => onChoice(choices.indexOf(choice)),
        );
      case RenPyComplete():
        complete = true;
      case RenPyError(:final message):
        error = message;
      case _:
        break;
    }
  }

  String _choiceFor(List<String> choices) {
    for (final topic in _remainingMainTopics) {
      if (choices.contains(topic)) return topic;
    }
    if (choices.contains("I think I've heard enough.")) {
      return "I think I've heard enough.";
    }
    return choices.first;
  }
}

class _ConfessionAutoPlayer {
  _ConfessionAutoPlayer({this.stopAtChapterOne = true});

  final bool stopAtChapterOne;
  final dialogue = <RenPyDialogue>[];
  final scenes = <String>[];
  final showTextDisplayables = <String>[];

  RenPyFlutterController? _controller;
  String? error;
  bool complete = false;

  bool get firstDialogueSeen => dialogue.isNotEmpty;

  bool get titleCardSeen => showTextDisplayables.any(
    (text) => text.contains('Confession of the Golden Witch'),
  );

  bool get chapterOneDialogueSeen => dialogue.any(
    (line) =>
        line.displayText.contains('bottled letter never reaches') &&
        line.displayText.contains('punishment I deserve'),
  );

  List<RenPyDiagnostic> get problematicDiagnostics {
    return [
      for (final diagnostic in _controller?.diagnostics ?? const [])
        if (_problematicDiagnosticCodes.contains(diagnostic.code)) diagnostic,
    ];
  }

  List<String> get problematicDiagnosticSummaries {
    return [
      for (final diagnostic in problematicDiagnostics)
        '${diagnostic.code}: ${diagnostic.detail}',
    ];
  }

  void attach(RenPyFlutterController controller) {
    _controller?.removeListener(_onStatusChanged);
    _controller = controller..addListener(_onStatusChanged);
  }

  void dispose() {
    _controller?.removeListener(_onStatusChanged);
    _controller = null;
  }

  void _onStatusChanged() {
    final controller = _controller;
    if (controller == null) return;

    switch (controller.value) {
      case final RenPyDialogue line:
        dialogue.add(line);
        if (!_shouldStop) {
          Future<void>.delayed(Duration.zero, controller.continueGame);
        }
      case RenPyPause():
        if (!_shouldStop) {
          Future<void>.delayed(Duration.zero, controller.continueGame);
        }
      case RenPyImageChange(:final scene, :final showText):
        if (scene != null) scenes.add(scene);
        if (showText != null) showTextDisplayables.add(showText);
      case RenPyComplete():
        complete = true;
      case RenPyError(:final message):
        error = message;
      case _:
        break;
    }
  }

  bool get _shouldStop => stopAtChapterOne && chapterOneDialogueSeen;
}

const _problematicDiagnosticCodes = {
  RenPyDiagnosticCode.skippedPython,
  RenPyDiagnosticCode.unsupportedPlacement,
  RenPyDiagnosticCode.unsupportedTransition,
  RenPyDiagnosticCode.unresolvedImageAsset,
  RenPyDiagnosticCode.unresolvedAudioAsset,
  RenPyDiagnosticCode.unknownStatement,
};
