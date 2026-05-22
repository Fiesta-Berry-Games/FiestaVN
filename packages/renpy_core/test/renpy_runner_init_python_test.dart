import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests for init python handling:
///  - Task 1: `init python:` bodies run at load, in priority order, before
///    `define`/`default`.
///  - Task 2: `window show` / `window hide` / `window auto` advance as no-ops.
///  - Task 3: `renpy.say(who, what, interact=...)` shim.
///  - Task 5: `_isNamespacedName` recognizes the explicit `store.` namespace.
void main() {
  ({
    List<String> dialogue,
    List<RenPyDialogueEvent> events,
    List<RenPyDiagnostic> diagnostics,
    RenPyRunner runner,
  })
  play(String source) {
    final script = RenPyParser().parse(source, 'sample.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final events = <RenPyDialogueEvent>[];
    final diagnostics = <RenPyDiagnostic>[];
    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDialogueEvent = events.add;
    runner.onDiagnostic = diagnostics.add;
    runner.jumpToLabel('start');
    runner.run();
    return (
      dialogue: dialogue,
      events: events,
      diagnostics: diagnostics,
      runner: runner,
    );
  }

  List<RenPyDiagnostic> skipped(List<RenPyDiagnostic> diagnostics) =>
      diagnostics
          .where((d) => d.code == RenPyDiagnosticCode.skippedPython)
          .toList();

  group('Task 1: init python runs at load before define/default', () {
    test('default reads a variable an init python block defined', () {
      // Pre-fix: the `init python:` body was never executed, so `base_hp` and
      // `bonus` were undefined and `default total_hp = base_hp + bonus`
      // fell back to the literal string. Now the block runs first.
      final result = play('''
init python:
    base_hp = 10
    bonus = 5

default total_hp = base_hp + bonus

label start:
    if total_hp == 15:
        "Fifteen."
    else:
        "Other."
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(result.dialogue, ['Fifteen.']);
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['total_hp'], 15);
      expect(result.runner.snapshot().variables['base_hp'], 10);
    });

    test('init blocks run in priority then source order', () {
      // The lower-priority (0) block runs first and seeds `order`; the higher
      // priority (10) block appends afterward. `default` is applied LAST and so
      // observes the fully-built value.
      final result = play('''
init 10 python:
    order = order + "B"

init python:
    order = "A"

default seen = order

label start:
    "done"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), isEmpty);
      expect(result.runner.snapshot().variables['order'], 'AB');
      expect(result.runner.snapshot().variables['seen'], 'AB');
    });

    test(
      'a broken init python body emits a skip diagnostic and load completes',
      () {
        // Graceful fallback: an unsupported/erroring init-python body must not
        // abort construction; it emits skippedPython and the rest of load
        // (the `default`, the script) proceeds normally.
        final result = play('''
init python:
    undefined_function_qqq(1, 2, 3)

default ok = 1

label start:
    if ok == 1:
        "Loaded anyway."
''');

        expect(result.runner.state, isNot(RenPyRunnerState.error));
        expect(result.dialogue, ['Loaded anyway.']);
        expect(skipped(result.diagnostics), hasLength(1));
        expect(result.runner.snapshot().variables['ok'], 1);
      },
    );

    test('a failed init block does not abort a later init block', () {
      // One block fails; a subsequent (higher-priority) init block must still
      // run, proving load does not abort on the first failure.
      final result = play('''
init python:
    undefined_function_qqq()

init 5 python:
    survived = 42

default value = survived

label start:
    "done"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(skipped(result.diagnostics), hasLength(1));
      expect(result.runner.snapshot().variables['survived'], 42);
      expect(result.runner.snapshot().variables['value'], 42);
    });

    test(
      'a top-level register_channel coexists with other code in the same block',
      () {
        // The parser hands the whole `init python:` body as one statement, so a
        // `register_channel` mixed with ordinary code must be peeled off
        // line-by-line: the channel registers AND the surrounding code still
        // executes. (Pre-fix the whole block was offered to the matcher as one
        // string, failed to match, and the entire block - registration and
        // `base_hp` alike - was skipped.)
        final script =
            RenPyParser().parse('''
init python:
    renpy.music.register_channel("ambience", "sfx", loop=True)
    base_hp = 99

label start:
    play ambience "rain.ogg"
    "done"
''', 'audio.rpy').script;
        final runner = RenPyRunner(script);
        final audio = <RenPyAudioEvent>[];
        final diagnostics = <RenPyDiagnostic>[];
        runner.onAudio = audio.add;
        runner.onDiagnostic = diagnostics.add;
        runner.jumpToLabel('start');
        runner.run();

        // The surrounding assignment ran (the regression this guards).
        expect(runner.snapshot().variables['base_hp'], 99);
        // No skip diagnostic: the registration line was peeled, not skipped.
        expect(skipped(diagnostics), isEmpty);
        // The channel registered with its loop default, so a plain `play`
        // (no modifier) loops.
        expect(audio, hasLength(1));
        expect(audio.first.channel, 'ambience');
        expect(audio.first.loop, isTrue);
      },
    );
  });

  group('Task 2: window statements advance as no-ops', () {
    test(
      'window show/hide/auto advance with no unknownStatement diagnostic',
      () {
        // Pre-fix: RenPyWindowStatement hit the unknownStatement fallback.
        final result = play('''
label start:
    window show
    "One."
    window hide
    "Two."
    window auto
    "Three."
''');

        // Drive past each say's input wait.
        final runner = result.runner;
        while (runner.state == RenPyRunnerState.waitingForInput) {
          runner.continueExecution();
        }

        expect(result.dialogue, ['One.', 'Two.', 'Three.']);
        expect(
          result.diagnostics.where(
            (d) => d.code == RenPyDiagnosticCode.unknownStatement,
          ),
          isEmpty,
        );
      },
    );

    test('window show with a transition advances without diagnostic', () {
      final result = play('''
label start:
    window show dissolve
    "Shown."
''');
      expect(result.dialogue, ['Shown.']);
      expect(
        result.diagnostics.where(
          (d) => d.code == RenPyDiagnosticCode.unknownStatement,
        ),
        isEmpty,
      );
    });
  });

  group('Task 3: renpy.say shim', () {
    test('renpy.say(None, what, interact=False) emits a narrator line', () {
      // Pre-fix: `renpy.say` was unsupported and the statement was skipped.
      final result = play('''
default q = "What is 2 plus 2?"

label start:
    \$ renpy.say(None, q, interact=False)
    "After."
''');

      expect(skipped(result.diagnostics), isEmpty);
      expect(result.dialogue, ['What is 2 plus 2?', 'After.']);
      expect(result.events.first.displayName, isNull);
      expect(result.events.first.text, 'What is 2 plus 2?');
    });

    test('renpy.say with a named Character resolves the speaker', () {
      final result = play('''
define e = Character("Eileen", color="#ff0000")

label start:
    \$ renpy.say(e, "Hello there", interact=False)
    "Done."
''');

      expect(skipped(result.diagnostics), isEmpty);
      final said = result.events.first;
      expect(said.characterId, 'e');
      expect(said.displayName, 'Eileen');
      expect(said.color, '#ff0000');
      expect(said.text, 'Hello there');
    });

    test(
      'renpy.say without interact=False blocks for input like a say line',
      () {
        final result = play('''
label start:
    \$ renpy.say(None, "Wait here.")
    "Next."
''');

        // The interactive say leaves the runner waiting; only the first line
        // has been emitted.
        expect(result.runner.state, RenPyRunnerState.waitingForInput);
        expect(result.dialogue, ['Wait here.']);
        result.runner.continueExecution();
        expect(result.dialogue, ['Wait here.', 'Next.']);
      },
    );
  });

  group('Task 5: store. namespace routes to the bare store slot', () {
    test(
      'default store.x and define store.y are visible bare and qualified',
      () {
        final result = play('''
default store.x = 5
define store.y = 7

label start:
    if x == 5 and store.x == 5 and y == 7 and store.y == 7:
        "all match"
    else:
        "mismatch"
''');

        expect(result.dialogue, ['all match']);
        expect(result.runner.snapshot().variables['x'], 5);
        expect(result.runner.snapshot().variables['y'], 7);
      },
    );

    test('a runtime \$ store.x = ... is visible bare and qualified', () {
      // The read path aliases `store.x` to the bare `x` slot; the write path
      // must do the same or a runtime assignment lands in a dead `store.x` key
      // that no read consults. Both branch reads must observe the new value.
      final result = play('''
default x = 0

label start:
    \$ store.x = 10
    if store.x == 10 and x == 10:
        "both see it"
    else:
        "lost"
''');

      expect(result.dialogue, ['both see it']);
      expect(result.runner.snapshot().variables['x'], 10);
    });
  });
}
