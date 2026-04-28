import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('runner restores execution state from a dialogue boundary', () {
    final script =
        RenPyParser().parse('''
define e = Character("Eileen", color="#c8ffc8")

label start:
    \$ route = "good"
    \$ persistent.confession_finished = True
    e "Before save."

    if route == "good":
        e "Route restored."
    else:
        e "Route lost."

    if persistent.confession_finished:
        "Persistent restored."
    else:
        "Persistent lost."
''', 'snapshot.rpy').script;
    final firstRunner = RenPyRunner(script);
    final firstDialogue = <RenPyDialogueEvent>[];

    firstRunner.onDialogueEvent = firstDialogue.add;
    firstRunner.jumpToLabel('start');
    firstRunner.run();

    expect(firstDialogue.single.displayName, 'Eileen');
    expect(firstDialogue.single.color, '#c8ffc8');
    expect(firstDialogue.single.text, 'Before save.');
    expect(firstRunner.state, RenPyRunnerState.waitingForInput);

    final snapshot = RenPyRunnerSnapshot.fromJson(
      firstRunner.snapshot().toJson(),
    );
    final restoredRunner = RenPyRunner(script);
    final restoredDialogue = <RenPyDialogueEvent>[];

    restoredRunner.onDialogueEvent = restoredDialogue.add;
    restoredRunner.restoreSnapshot(snapshot);
    restoredRunner.continueExecution();

    expect(restoredDialogue.single.displayName, 'Eileen');
    expect(restoredDialogue.single.color, '#c8ffc8');
    expect(restoredDialogue.single.text, 'Route restored.');
    expect(restoredRunner.persistent, {'confession_finished': true});

    final branchSnapshot = RenPyRunnerSnapshot.fromJson(
      restoredRunner.snapshot().toJson(),
    );
    final branchRunner = RenPyRunner(script);
    final branchDialogue = <RenPyDialogueEvent>[];

    branchRunner.onDialogueEvent = branchDialogue.add;
    branchRunner.restoreSnapshot(branchSnapshot);
    branchRunner.continueExecution();

    expect(branchDialogue.single.text, 'Persistent restored.');
  });

  test(
    'runner restores menu state and executes choices on the restored runner',
    () {
      final script =
          RenPyParser().parse('''
label start:
    menu:
        "Take the left path":
            "Left restored."
        "Take the right path":
            "Right restored."

    "After menu."
''', 'snapshot_menu.rpy').script;
      final firstRunner = RenPyRunner(script);
      late List<String> firstChoices;

      firstRunner.onMenu = (choices, onChoice, caption) {
        firstChoices = choices;
      };
      firstRunner.jumpToLabel('start');
      firstRunner.run();

      expect(firstChoices, ['Take the left path', 'Take the right path']);
      expect(firstRunner.state, RenPyRunnerState.waitingForInput);

      final restoredRunner = RenPyRunner(script);
      final restoredDialogue = <String>[];
      late List<String> restoredChoices;
      late void Function(int) choose;

      restoredRunner.onMenu = (choices, onChoice, caption) {
        restoredChoices = choices;
        choose = onChoice;
      };
      restoredRunner.onDialogue =
          (character, text) => restoredDialogue.add(text);
      restoredRunner.restoreSnapshot(firstRunner.snapshot());
      restoredRunner.continueExecution();

      expect(restoredChoices, ['Take the left path', 'Take the right path']);

      choose(1);

      expect(restoredDialogue, ['Right restored.']);

      final choiceSnapshot = RenPyRunnerSnapshot.fromJson(
        restoredRunner.snapshot().toJson(),
      );
      final choiceRunner = RenPyRunner(script);
      final choiceDialogue = <String>[];

      choiceRunner.onDialogue = (character, text) => choiceDialogue.add(text);
      choiceRunner.restoreSnapshot(choiceSnapshot);
      choiceRunner.continueExecution();

      expect(choiceDialogue, ['After menu.']);
    },
  );

  test('runner snapshot serializes presentation state', () {
    const snapshot = RenPyRunnerSnapshot(
      state: 'waitingForInput',
      currentLabel: 'start',
      currentBlockPath: [],
      position: 0,
      stack: [],
      variables: {},
      persistent: {},
      characters: {},
      presentation: RenPyPresentationSnapshot(
        visual: RenPyVisualSnapshot(
          scene: RenPyVisualElementSnapshot(
            imageName: 'bg lecturehall',
            assetPath: 'assets/game/images/bg lecturehall.png',
          ),
          sprites: [
            RenPyVisualElementSnapshot(
              tag: 'sylvie',
              imageName: 'sylvie green smile',
              assetPath: 'assets/game/images/sylvie green smile.png',
              placement: RenPyImagePlacement.position(
                xpos: 400,
                xanchor: 0.5,
                xposIsPixel: true,
                zoom: 1.25,
                xzoom: 0.8,
                yzoom: 1.5,
                alpha: 0.5,
              ),
            ),
          ],
        ),
        audio: RenPyAudioSnapshot(
          channels: {
            'music': RenPyAudioChannelSnapshot(
              asset: 'theme.ogg',
              mixer: 'sfx',
              loop: false,
            ),
          },
          transient: [
            RenPyTransientAudioSnapshot(
              channel: 'sound',
              asset: 'glass.ogg',
              fadein: '0.1',
              fadeout: '0.2',
              mixer: 'sfx',
              volume: '0.5',
              ifChanged: true,
              loop: false,
            ),
          ],
        ),
      ),
    );

    final restored = RenPyRunnerSnapshot.fromJson(snapshot.toJson());

    expect(restored.toJson(), snapshot.toJson());
  });

  test('visual element snapshot serializes layer identity', () {
    const snapshot = RenPyVisualElementSnapshot(
      tag: 'logo',
      layer: 'abovemid',
      imageName: 'logo',
      assetPath: 'assets/game/images/logo.png',
      zOrder: 10,
    );

    final restored = RenPyVisualElementSnapshot.fromJson(snapshot.toJson());

    expect(restored.layer, 'abovemid');
    expect(restored.zOrder, 10);
    expect(restored.toJson(), snapshot.toJson());
  });
}
