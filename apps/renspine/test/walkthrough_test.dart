// Controller-level walkthroughs of the Fiesta Skit showcase script.
//
// Loads the bundled script into an in-memory RenPyFlutterController (with
// availableAssets covering every referenced image and audio asset), drives
// continueGame and menu choices through full paths, and asserts each run
// reaches `return` without a RenPyError and without unresolved-asset
// diagnostics.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_core/renpy_core.dart' show RenPyImageResolver, RenPyParser;
import 'package:renpy_flutter/renpy_flutter.dart';

const _scriptPath = 'assets/games/1/game/script.rpy';
const _gameRoot = 'assets/games/1/game';

void main() {
  final source = File(_scriptPath).readAsStringSync();

  // Every asset the script can reference: the resolved `.spine` image paths
  // (game-root-joined, exactly as the controller's image resolver builds
  // them) plus the music track.
  final imageAliases =
      RenPyImageResolver.aliasesFor(RenPyParser().parse(source, _scriptPath).script);
  final availableAssets = <String>{
    '$_gameRoot/audio/illurock.opus',
    for (final alias in imageAliases.values) '$_gameRoot/$alias',
  };

  Future<_WalkthroughLog> walkthrough(List<int> menuChoices) async {
    final controller = RenPyFlutterController();
    final log = _WalkthroughLog();
    controller.addListener(() {
      final status = controller.value;
      if (status is RenPyError) log.errors.add(status.message);
      if (status is RenPyDialogue) log.dialogue.add(status);
      if (status is RenPyAudioChange) log.audio.add(status);
      if (status is RenPyImageChange && status.show != null) {
        log.shows.add(status);
      }
    });

    controller.load(
      source,
      filename: _scriptPath,
      gameRoot: _gameRoot,
      availableAssets: availableAssets,
    );

    var nextChoice = 0;
    var completed = false;
    for (var step = 0; step < 500 && !completed; step++) {
      final status = controller.value;
      if (status is RenPyComplete) {
        completed = true;
        break;
      }
      if (status is RenPyError) break;
      if (status is RenPyMenu) {
        log.menus.add(status.choices);
        expect(
          nextChoice,
          lessThan(menuChoices.length),
          reason: 'script presented more menus than the walkthrough planned',
        );
        status.onChoice(menuChoices[nextChoice++]);
      } else if (status is RenPyDialogue || status is RenPyPause) {
        controller.continueGame();
      }
      // Let the runner's microtask ticker drain to the next wait point.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }

    log.completed = completed;
    log.choicesTaken = nextChoice;
    log.diagnostics = controller.diagnostics;
    controller.dispose();
    return log;
  }

  test('dramatic + one-woman-band path runs to return without errors',
      () async {
    final log = await walkthrough([0, 0]);

    expect(log.errors, isEmpty);
    expect(log.completed, isTrue, reason: 'walkthrough never reached return');
    expect(log.choicesTaken, 2);
    expect(log.menus, hasLength(2));
    expect(log.menus.first, hasLength(2));
    expect(log.diagnostics, isEmpty);

    // Both leads speak, with their defined Character() colors.
    final erikari =
        log.dialogue.firstWhere((line) => line.character == 'Erikari');
    expect(erikari.color, '#ff5c8a');
    final harri = log.dialogue.firstWhere((line) => line.character == 'Harri');
    expect(harri.color, '#56c8f5');

    // Both characters appear, on opposite sides, with emote switches.
    expect(_shownAt(log, 'erikari'), contains('left'));
    expect(_shownAt(log, 'harri'), contains('right'));
    expect(_shownImages(log, 'erikari'), contains('erikari dramatic'));
    expect(_shownImages(log, 'harri'), contains('harri seeno'));
    // The dramatic path never summons Misaki.
    expect(_shownImages(log, 'misaki'), isEmpty);

    // Music starts (looping channel) and is stopped with a fadeout.
    expect(
      log.audio.any(
        (event) =>
            event.action == RenPyAudioAction.play &&
            event.channel == 'music' &&
            event.asset == 'audio/illurock.opus',
      ),
      isTrue,
    );
    expect(
      log.audio.any(
        (event) =>
            event.action == RenPyAudioAction.stop &&
            event.channel == 'music' &&
            event.fadeout != null,
      ),
      isTrue,
    );
  });

  test('cozy + DJ Misaki path runs to return and brings the cameo on stage',
      () async {
    final log = await walkthrough([1, 1]);

    expect(log.errors, isEmpty);
    expect(log.completed, isTrue, reason: 'walkthrough never reached return');
    expect(log.choicesTaken, 2);
    expect(log.diagnostics, isEmpty);

    // The cozy branch plays its own emotes...
    expect(_shownImages(log, 'erikari'), contains('erikari love'));
    expect(_shownImages(log, 'harri'), contains('harri fawning'));
    // ...and the second branch puts Misaki center stage, speaking in her
    // own color.
    expect(_shownAt(log, 'misaki'), contains('center'));
    expect(_shownImages(log, 'misaki'), contains('misaki excited'));
    final misaki =
        log.dialogue.firstWhere((line) => line.character == 'Misaki');
    expect(misaki.color, '#ffd166');
  });
}

/// The distinct cleaned image names shown for [tag] (e.g. `erikari laugh`).
Set<String> _shownImages(_WalkthroughLog log, String tag) {
  return log.shows
      .map((event) => event.show!.split('#').first.trim())
      .where((name) => name.split(RegExp(r'\s+')).first == tag)
      .toSet();
}

/// The distinct `at` positions [tag] was shown at.
Set<String> _shownAt(_WalkthroughLog log, String tag) {
  return log.shows
      .where(
        (event) =>
            event.show!.split(RegExp(r'\s+')).first == tag &&
            event.showAt != null,
      )
      .map((event) => event.showAt!.trim())
      .toSet();
}

class _WalkthroughLog {
  final errors = <String>[];
  final dialogue = <RenPyDialogue>[];
  final audio = <RenPyAudioChange>[];
  final shows = <RenPyImageChange>[];
  final menus = <List<String>>[];
  var completed = false;
  var choicesTaken = 0;
  List<RenPyDiagnostic> diagnostics = const [];
}
