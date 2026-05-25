import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Drains a runner to completion, advancing through every dialogue/input wait.
void _drain(RenPyRunner runner) {
  runner.run();
  var guard = 0;
  while (runner.state == RenPyRunnerState.waitingForInput && guard < 1000) {
    runner.continueExecution();
    guard += 1;
  }
}

void main() {
  group('renpy.call from Python', () {
    test('a \$ renpy.call("label") transfers control and returns after it', () {
      final script =
          RenPyParser().parse('''
label start:
    "Before."
    \$ renpy.call("day")
    "After."
    return

label day:
    "Inside day."
    return
''', 'call.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];
      final depthAtDay = <int>[];

      runner.onDiagnostic = diagnostics.add;
      runner.onDialogue = (character, text) {
        dialogue.add(text);
        depthAtDay.add(runner.callStackDepth);
      };

      runner.jumpToLabel('start');
      _drain(runner);

      // Control enters `day` then RETURNS to the statement after the `$`.
      expect(dialogue, ['Before.', 'Inside day.', 'After.']);
      // While inside the called label there is one call frame on the stack;
      // back in the caller it is gone again.
      expect(depthAtDay, [0, 1, 0]);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
      expect(runner.state, RenPyRunnerState.complete);
    });

    test(
      'a python: block runs pre-call stmts once and abandons post-call stmts',
      () {
        final script =
            RenPyParser().parse('''
label start:
    python:
        count = 0
        count += 1
        renpy.call("day")
        count += 100
    if count == 1:
        "count is one."
    if count == 101:
        "count is one hundred one."
    return

label day:
    "Inside day."
    return
''', 'call_block.rpy').script;
        final runner = RenPyRunner(script);
        final dialogue = <String>[];
        final diagnostics = <RenPyDiagnostic>[];

        runner.onDiagnostic = diagnostics.add;
        runner.onDialogue = (character, text) => dialogue.add(text);

        runner.jumpToLabel('start');
        _drain(runner);

        // The statement before the call ran exactly once (count == 1); the one
        // after the call did NOT run (count is not 101). Control returned to
        // the statements after the python: block.
        expect(dialogue, ['Inside day.', 'count is one.']);
        expect(runner.snapshot().variables['count'], 1);
        expect(
          diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
          isEmpty,
        );
      },
    );

    test('side effects before a call are applied exactly once', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ log = []
    python:
        log.append("a")
        log.append("b")
        renpy.call("day")
        log.append("never")
    return

label day:
    return
''', 'once.rpy').script;
      final runner = RenPyRunner(script);

      runner.jumpToLabel('start');
      _drain(runner);

      // Exactly two appends before the call, none after (no double-apply).
      expect(runner.snapshot().variables['log'], ['a', 'b']);
    });
  });

  group('renpy.jump from Python', () {
    test('jump transfers without a return frame', () {
      final script =
          RenPyParser().parse('''
label start:
    "Before."
    \$ renpy.jump("day")
    "Never after jump."
    return

label day:
    "Inside day."
    return
''', 'jump.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      // The statement after the jump never runs; there is no return frame, so
      // execution ends at `day`'s return.
      expect(dialogue, ['Before.', 'Inside day.']);
      expect(runner.callStackDepth, 0);
      expect(runner.state, RenPyRunnerState.complete);
    });
  });

  group('graceful fallback', () {
    test('a call to an unknown label skips without crashing', () {
      final script =
          RenPyParser().parse('''
label start:
    "Before."
    \$ renpy.call("nope")
    "After."
    return
''', 'unknown_call.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDiagnostic = diagnostics.add;
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      // The runner survives, emits a skip diagnostic, and continues past the
      // unresolvable call as if it no-opped.
      expect(dialogue, ['Before.', 'After.']);
      expect(runner.state, RenPyRunnerState.complete);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isNotEmpty,
      );
    });

    test('a jump to an unknown label skips without crashing', () {
      final script =
          RenPyParser().parse('''
label start:
    "Before."
    \$ renpy.jump("nope")
    "After."
    return
''', 'unknown_jump.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDiagnostic = diagnostics.add;
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      expect(dialogue, ['Before.', 'After.']);
      expect(runner.state, RenPyRunnerState.complete);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isNotEmpty,
      );
    });

    test('a non-string label argument falls back to a skip', () {
      final script =
          RenPyParser().parse('''
label start:
    "Before."
    \$ renpy.call(42)
    "After."
    return
''', 'bad_label.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDiagnostic = diagnostics.add;
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      expect(dialogue, ['Before.', 'After.']);
      expect(runner.state, RenPyRunnerState.complete);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isNotEmpty,
      );
    });
  });

  group('side-effect shims do not abort the enclosing block', () {
    test(
      'show_screen + persistent set add + sound.play all complete in a block',
      () {
        final audio = <RenPyAudioEvent>[];
        final script =
            RenPyParser().parse('''
default persistent.achievements = set()

label start:
    python:
        renpy.show_screen("hud")
        persistent.achievements.add("first")
        renpy.sound.play("ping.ogg")
        done = True
    if done:
        "Block completed."
    return
''', 'shims.rpy').script;
        final runner = RenPyRunner(script);
        final dialogue = <String>[];
        final diagnostics = <RenPyDiagnostic>[];

        runner.onDiagnostic = diagnostics.add;
        runner.onAudio = audio.add;
        runner.onDialogue = (character, text) => dialogue.add(text);

        runner.jumpToLabel('start');
        _drain(runner);

        // Every later side effect ran: `done = True` was reached, so the
        // unsupported-ish show_screen call did not strand the rest of the block.
        expect(dialogue, ['Block completed.']);
        // The persistent set was mutated.
        final achievements =
            runner.snapshot().persistent['achievements'] as Set;
        expect(achievements, contains('first'));
        // sound.play routed to the audio hook.
        expect(audio, isNotEmpty);
        // The screen was shown (best-effort, non-blocking).
        expect(runner.shownScreens.map((s) => s.name), contains('hud'));
        expect(
          diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
          isEmpty,
        );
      },
    );

    test('hide_screen from Python does not abort the block', () {
      final script =
          RenPyParser().parse('''
label start:
    \$ renpy.show_screen("hud")
    python:
        renpy.hide_screen("hud")
        done = True
    if done:
        "Done."
    return
''', 'hide.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];

      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      expect(dialogue, ['Done.']);
      expect(runner.shownScreens.map((s) => s.name), isNot(contains('hud')));
    });

    test('persistent.X.add when X is unset skips gracefully without aborting '
        'siblings or auto-vivifying', () {
      final script =
          RenPyParser().parse('''
label start:
    python:
        persistent.achievements.add("first")
        done = True
    if done:
        "Done."
    return
''', 'unset_persistent.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDiagnostic = diagnostics.add;
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      // The `.add` on the unset (None) collection is skipped, but the runner
      // survives and the following `done = True` still runs (so `if done`
      // fires). The persistent store is NOT auto-vivified.
      expect(runner.state, RenPyRunnerState.complete);
      expect(dialogue, ['Done.']);
      expect(runner.snapshot().persistent.containsKey('achievements'), false);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isNotEmpty,
      );
    });
  });

  group('renpy.call/jump outside a transfer point falls back safely', () {
    // A `renpy.call`/`renpy.jump` evaluated where no transfer can be performed
    // (a screen expression, a define RHS) must NOT escape as a control-flow
    // signal and must NOT leave a pending transfer armed for the next
    // statement. Regression for the contract hole the adversarial verifier
    // found: the screen evaluators only catch RenPyPythonError.
    test('a screen if-condition calling renpy.call does not throw or phantom '
        'transfer the next statement', () {
      final script =
          RenPyParser().parse('''
screen gate():
    if renpy.call("somewhere"):
        text "shown"
    else:
        text "hidden"

label start:
    \$ marker = 0
    "Before screen."
    \$ marker = 1
    "After screen."
    return

label somewhere:
    "PHANTOM"
    return
''', 'screen_callflow.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];
      runner.onDiagnostic = diagnostics.add;
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run(); // executes `$ marker = 0`, stops at "Before screen."

      // Resolving a screen whose condition calls renpy.call must not throw the
      // control-flow signal into the host, and the if simply falls back.
      Object? resolved;
      expect(() => resolved = runner.resolveScreen('gate'), returnsNormally);
      expect(resolved, isNotNull);

      // No pending transfer leaked: continuing runs the author's real flow
      // (marker becomes 1, the "After screen." line shows) and never visits the
      // `somewhere` label - no phantom call.
      _drain(runner);
      expect(dialogue, ['Before screen.', 'After screen.']);
      expect(dialogue, isNot(contains('PHANTOM')));
      expect(runner.snapshot().variables['marker'], 1);
      expect(runner.state, RenPyRunnerState.complete);
      expect(runner.callStackDepth, 0);
    });

    test('a define RHS calling renpy.call degrades gracefully at load', () {
      // `define x = renpy.call(...)` is nonsensical, but it must not crash the
      // load - it degrades to the definition fallback rather than escaping.
      RenPyRunner? runner;
      expect(() {
        final script =
            RenPyParser().parse('''
define bogus = renpy.call("nowhere")

label start:
    "ok"
    return

label nowhere:
    "PHANTOM"
    return
''', 'define_callflow.rpy').script;
        runner = RenPyRunner(script);
      }, returnsNormally);

      final r = runner!;
      final dialogue = <String>[];
      r.onDialogue = (character, text) => dialogue.add(text);
      r.jumpToLabel('start');
      _drain(r);

      // The bogus define did not arm a phantom transfer.
      expect(dialogue, ['ok']);
      expect(dialogue, isNot(contains('PHANTOM')));
      expect(r.state, RenPyRunnerState.complete);
    });
  });
}
