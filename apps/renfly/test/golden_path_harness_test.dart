import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/renpy_golden_path_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('real RenPy project golden path harness', () {
    test(
      'records The Question bad-ending route without compatibility gaps',
      () async {
        final project = loadRenPyProjectFolder(
          Directory('assets/games/the_question/game'),
        );

        final result = await RenPyGoldenPathHarness(
          project,
          chooseMenu:
              (menu, trace) => menu.choices.indexOf('To ask her later.'),
        ).runUntilComplete(maxSteps: 100);

        expect(result.complete, isTrue);
        expect(result.error, isNull);
        expect(result.problematicDiagnostics, isEmpty);
        expect(
          result.dialogue.map((line) => line.text),
          contains('{b}Bad Ending{/b}.'),
        );
        expect(result.menus, hasLength(1));
        expect(
          result.menus.single.caption,
          'As soon as she catches my eye, I decide...',
        );
        expect(result.menus.single.selectedChoice, 'To ask her later.');
        expect(result.audioAssets, contains('illurock.opus'));
        expect(
          result.sceneNames,
          containsAll(['bg lecturehall', 'bg uni', 'black']),
        );
        expect(result.transitionNames, containsAll(['fade', 'dissolve']));
        expect(result.summary.dialogueCount, greaterThanOrEqualTo(12));
        expect(result.summary.menuCount, 1);
      },
    );

    final confessionFixture = Directory('assets/games/Confession-1.03-pc/game');
    final confessionSkipReason =
        confessionFixture.existsSync()
            ? null
            : 'Local Confession of the Golden Witch fixture is not present.';

    test(
      'records Confession chapter-one route without compatibility gaps',
      () async {
        final project = loadRenPyProjectFolder(confessionFixture);

        final result = await RenPyGoldenPathHarness(project).runUntil(
          (trace, status) =>
              trace.showTextDisplayables.any(
                (text) => text.contains('Confession of the Golden Witch'),
              ) &&
              trace.dialogue.any(
                (line) =>
                    line.displayText.contains('bottled letter never reaches') &&
                    line.displayText.contains('punishment I deserve'),
              ),
          maxSteps: 700,
        );

        expect(result.complete, isFalse);
        expect(result.error, isNull);
        expect(result.problematicDiagnostics, isEmpty);
        expect(result.dialogue.first.displayText, startsWith('Please note.'));
        expect(
          result.dialogue.map((line) => line.displayText),
          contains(
            contains(
              'If you are reading this, deliver unto me the punishment I deserve',
            ),
          ),
        );
        expect(
          result.showTextDisplayables.single,
          contains('Confession of the Golden Witch'),
        );
        expect(result.sceneNames, containsAll(['black', 'fea_l4', 'red']));
        expect(result.audioAssets, contains('/music/She End.ogg'));
        expect(
          result.transitionNames,
          containsAll(['openfade', 'quickgradientwiperight']),
        );
        expect(result.summary.dialogueCount, greaterThan(20));
        expect(result.summary.imageChangeCount, greaterThan(10));
      },
      skip: confessionSkipReason,
    );

    test(
      'records Confession completion diagnostics separately from route assertions',
      () async {
        final project = loadRenPyProjectFolder(confessionFixture);

        final result = await RenPyGoldenPathHarness(
          project,
        ).runUntilComplete(maxSteps: 1200);

        expect(result.complete, isTrue);
        expect(result.error, isNull);
        expect(result.problematicDiagnosticSummaries, isEmpty);
        expect(
          result.dialogue.map((line) => line.displayText),
          contains('Afterword:'),
        );
        expect(result.summary.dialogueCount, greaterThan(100));
      },
      skip: confessionSkipReason,
    );
  });
}
