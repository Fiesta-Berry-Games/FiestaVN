import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

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

    test(
      'records Reference Game 4 synthesized Confession sampler without compatibility gaps',
      () async {
        final project = loadRenPyProjectFolder(
          Directory('assets/games/4/game'),
        );

        final result = await RenPyGoldenPathHarness(
          project,
        ).runUntilComplete(maxSteps: 200);

        expect(result.complete, isTrue);
        expect(result.error, isNull);
        expect(result.problematicDiagnostics, isEmpty);
        expect(
          result.dialogue.map((line) => line.displayText),
          containsAll([
            contains('Reference Game 4 begins.'),
            'NVL context reset. Extended clause.',
            '{b}Reference Game 4 Complete{/b}.',
          ]),
        );
        expect(result.menus.single.caption, 'Which Confession feature bucket?');
        expect(result.menus.single.selectedChoice, 'Transitions and staging.');
        expect(
          result.sceneNames,
          containsAll(['black', 'archive bg', 'flashback bg', 'red', 'white']),
        );
        expect(
          result.showTextDisplayables.single,
          contains('Reference Game 4'),
        );
        expect(
          result.audioAssets,
          containsAll([
            '/music/She End.opus',
            '/SE/Z1.opus',
            '/ME/rain_2.opus',
            '/se/ZS4.opus',
          ]),
        );
        expect(
          result.transitionNames,
          containsAll([
            'openfade',
            'longfade',
            'longdissolve',
            'longerdissolve',
            'quickgradientwiperight',
            'quickgradientcirclefade',
            'gradientcirclefade',
            'doorfade',
            'flash',
            'vpunch',
          ]),
        );
        expect(result.summary.dialogueCount, greaterThanOrEqualTo(8));
        expect(result.summary.imageChangeCount, greaterThanOrEqualTo(12));
        expect(result.summary.audioChangeCount, greaterThanOrEqualTo(7));
      },
    );

    test('groups compatibility diagnostics by code and detail', () async {
      final project = RenPyGameProject.fromFiles([
        RenPyProjectFile.text('diagnostics/game/script.rpy', '''
define strange = PushMove(1.0, "left")

label start:
    scene missing background at unsupported_transform with strange
    play sound "missing.ogg"
    "Done."
'''),
        RenPyProjectFile('diagnostics/game/images/present.png', Uint8List(0)),
        RenPyProjectFile('diagnostics/game/audio/present.ogg', Uint8List(0)),
      ]);

      final result = await RenPyGoldenPathHarness(
        project,
      ).runUntilComplete(maxSteps: 20);

      expect(result.complete, isTrue);
      expect(result.error, isNull);
      expect(result.problematicDiagnosticCountsByCode, {
        RenPyDiagnosticCode.unsupportedTransition: 1,
        RenPyDiagnosticCode.unsupportedPlacement: 1,
        RenPyDiagnosticCode.unresolvedImageAsset: 1,
        RenPyDiagnosticCode.unresolvedAudioAsset: 1,
      });
      expect(
        result.problematicDiagnosticDetailsByCode[RenPyDiagnosticCode
            .unsupportedTransition],
        contains('PushMove(1.0, "left")'),
      );
      expect(
        result.problematicDiagnosticDetailsByCode[RenPyDiagnosticCode
            .unsupportedPlacement],
        contains('unsupported_transform'),
      );
      expect(
        result.problematicDiagnosticDetailsByCode[RenPyDiagnosticCode
            .unresolvedImageAsset],
        contains(_detailContaining('missing background ->')),
      );
      expect(
        result.problematicDiagnosticDetailsByCode[RenPyDiagnosticCode
            .unresolvedAudioAsset],
        contains(_detailContaining('missing.ogg ->')),
      );
    });

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
        final imageChanges = result.images;
        final metaShowIndex = imageChanges.indexWhere(
          (change) => change.show == 'meta',
        );
        final logoShowIndex = imageChanges.indexWhere(
          (change) => change.show == 'logo',
        );
        final metaHideIndex = imageChanges.indexWhere(
          (change) => change.hide == 'meta',
        );
        final logoHideIndex = imageChanges.indexWhere(
          (change) => change.hide == 'logo',
        );
        expect(metaShowIndex, isNonNegative);
        expect(logoShowIndex, isNonNegative);
        expect(metaHideIndex, greaterThan(metaShowIndex));
        expect(logoHideIndex, greaterThan(logoShowIndex));
        expect(result.summary.dialogueCount, greaterThan(100));
      },
      skip: confessionSkipReason,
    );
  });
}

Matcher _detailContaining(String text) {
  return predicate<String?>((detail) => detail?.contains(text) ?? false);
}
