import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

import 'support/renpy_golden_path_harness.dart';
import 'support/renpy_project_player_harness.dart';

void main() {
  testWidgets(
    'Reference Game 4 keeps placed sprites separated and inside the stage',
    (tester) async {
      final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));

      await tester.pumpWidget(
        MaterialApp(
          home: RenPyProjectPlayer(
            project: project,
            audioPlayback: const RenPyNoOpAudioPlayback(),
          ),
        ),
      );

      final harness = RenPyProjectPlayerHarness(tester);
      await harness.pumpUntilText('Reference Game 4 begins.');
      await harness.pumpPastTransition();

      harness.expectSpriteAnchor('eri', const Offset(160, 600));
      harness.expectSpriteAnchor('enj', const Offset(640, 600));

      final stage = harness.stageRect;
      final eri = harness.spriteImageRect('eri');
      final enj = harness.spriteImageRect('enj');

      expect(eri.top, greaterThanOrEqualTo(stage.top));
      expect(enj.top, greaterThanOrEqualTo(stage.top));
      expect(eri.bottom, lessThanOrEqualTo(stage.bottom));
      expect(enj.bottom, lessThanOrEqualTo(stage.bottom));
      expect(eri.center.dx, lessThan(stage.center.dx));
      expect(enj.center.dx, greaterThan(stage.center.dx));
      expect(eri.overlaps(enj), isFalse);
    },
  );

  testWidgets('Reference Game 4 clears sprites on scene replacement', (
    tester,
  ) async {
    final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          audioPlayback: const RenPyNoOpAudioPlayback(),
        ),
      ),
    );

    final harness = RenPyProjectPlayerHarness(tester);
    await harness.pumpUntilText('Reference Game 4 begins.');
    await harness.pumpPastTransition();
    expect(harness.spriteCount('eri'), 1);
    expect(harness.spriteCount('enj'), 1);
    expect(harness.spriteCount('sha'), 0);

    await harness.pumpUntilText(
      'Grayscale flashbacks, multiple characters, and layered placement are active.',
      attempts: 120,
    );
    await harness.pumpPastTransition();

    expect(harness.spriteCount('eri'), 1);
    expect(harness.spriteCount('enj'), 1);
    expect(harness.spriteCount('sha'), 0);
    final eri = harness.spriteImageRect('eri');
    final enj = harness.spriteImageRect('enj');
    expect(eri.center.dx, lessThan(enj.center.dx));
    expect(eri.overlaps(enj), isFalse);
  });

  testWidgets('Reference Game 4 show text displayable is centered and clears', (
    tester,
  ) async {
    final project = loadRenPyProjectFolder(Directory('assets/games/4/game'));

    await tester.pumpWidget(
      MaterialApp(
        home: RenPyProjectPlayer(
          project: project,
          audioPlayback: const RenPyNoOpAudioPlayback(),
        ),
      ),
    );

    final harness = RenPyProjectPlayerHarness(tester);
    await harness.pumpUntilSprite('title', attempts: 120);
    await harness.pumpPastTransition();

    harness.expectSpriteAnchor('title', const Offset(400, 300));
    final title = tester.getRect(find.byKey(const ValueKey('title')));
    expect((title.center.dx - harness.stageRect.center.dx).abs(), lessThan(60));

    await tester.tapAt(tester.getCenter(find.byType(RenPyProjectPlayer)));
    await harness.pumpUntilTextGone('Reference Game 4', attempts: 120);
    await harness.pumpPastTransition();
    expect(find.byKey(const ValueKey('title')), findsNothing);
  });
}
