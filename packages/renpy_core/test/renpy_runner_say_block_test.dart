import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Tests for the faithful `renpy.say(...)` as the LAST top-level statement of a
/// multi-statement `python:` block - the dominant LearnToCodeRPG pattern
/// (`scripts__labels__day_activity_choices.rpy`):
///
/// ```
/// python:
///     day_activity = STUDY
///     text = renpy.random.choice(["Let's hit the books!", ...])
///     renpy.say(player, text)
/// ```
///
/// Before the fix the whole block ran through the executor (which does not model
/// `say`), so the trailing say was silently skipped while its siblings ran - the
/// dialogue was never shown. After the fix the leading statements run first
/// (computing `text`) and the trailing say is routed through the real say
/// handler.
void main() {
  group('renpy.say as last statement of a python: block', () {
    test('multi-statement block ending in say emits the dialogue', () {
      final script =
          RenPyParser().parse('''
define player = Character("Player")

label start:
    python:
        text = "hello world"
        renpy.say(player, text)
    "after"
''', 'say_block.rpy').script;
      final runner = RenPyRunner(script);
      final events = <RenPyDialogueEvent>[];
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDialogueEvent = events.add;
      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      // LOAD-BEARING: the say fired with the computed text and the player's
      // display name (pre-fix: no dialogue event + a skippedPython diagnostic).
      expect(events, hasLength(1));
      expect(events.first.text, 'hello world');
      expect(events.first.displayName, 'Player');
      expect(runner.state, RenPyRunnerState.waitingForInput);

      // No skip diagnostic for the say statement.
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );

      // Advancing past the say continues to the "after" line - no double-advance
      // (which would skip "after"), no missing advance.
      runner.continueExecution();
      runner.run();
      expect(dialogue, ['hello world', 'after']);
    });

    test('leading statements run first so the said value is computed', () {
      // `text` is built by a concat of two earlier-computed names, proving the
      // leading segments executed and persisted before the trailing say read it.
      final script =
          RenPyParser().parse('''
define player = Character("Player")

label start:
    python:
        greeting = "hi"
        name = "world"
        text = greeting + " " + name
        renpy.say(player, text)
    "after"
''', 'say_block_computed.rpy').script;
      final runner = RenPyRunner(script);
      final events = <RenPyDialogueEvent>[];

      runner.onDialogueEvent = events.add;

      runner.jumpToLabel('start');
      runner.run();

      expect(events, hasLength(1));
      expect(events.first.text, 'hi world');
    });

    test('block ending in a NON-say statement still runs normally', () {
      // A trailing mutation must run through the normal block path (no say),
      // leaving no dialogue and no skip diagnostic.
      final script =
          RenPyParser().parse('''
label start:
    python:
        log = []
        text = "x"
        log.append(1)
    "after"
''', 'say_block_nonsay.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      runner.run();

      // The block computed normally and execution reached the dialogue line
      // (no double-advance, no skip).
      expect(dialogue, ['after']);
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
    });

    test('renpy.call in a leading segment still transfers control', () {
      // A call armed before the trailing say must abandon the rest of the block
      // (RenPy does not run the say after a call/jump) and transfer to the
      // target label, returning afterwards.
      final script =
          RenPyParser().parse('''
define player = Character("Player")

label start:
    python:
        text = "should not be said"
        renpy.call("target")
        renpy.say(player, text)
    "back in start"

label target:
    "in target"
    return
''', 'say_block_call.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final events = <RenPyDialogueEvent>[];

      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDialogueEvent = events.add;

      runner.jumpToLabel('start');
      runner.run();

      // Control transferred to target first (the trailing say was abandoned).
      expect(dialogue.first, 'in target');
      // The abandoned say never emitted.
      expect(events.where((e) => e.text == 'should not be said'), isEmpty);

      // Drive through target -> return -> "back in start".
      var guard = 0;
      while (runner.state == RenPyRunnerState.waitingForInput && guard < 10) {
        runner.continueExecution();
        runner.run();
        guard++;
      }
      expect(dialogue, contains('back in start'));
    });

    test('interact=False say-tail advances without waiting for input', () {
      // An interact=False say-tail is routed through the same handler, which
      // advances (calls _executeNext) instead of parking on waitingForInput.
      final script =
          RenPyParser().parse('''
define player = Character("Player")

label start:
    python:
        text = "no wait"
        renpy.say(player, text, interact=False)
    "after"
''', 'say_block_interact_false.rpy').script;
      final runner = RenPyRunner(script);
      final events = <RenPyDialogueEvent>[];
      final dialogue = <String>[];

      runner.onDialogueEvent = events.add;
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      runner.run();

      // The say emitted and execution continued without parking on the say.
      expect(events.where((e) => e.text == 'no wait'), hasLength(1));
      // It flows straight into the next line, which DOES wait.
      expect(dialogue, ['no wait', 'after']);
      expect(runner.state, RenPyRunnerState.waitingForInput);
    });

    test('say-tail marks waitingForInput before the dialogue callback', () {
      // Trampoline contract: a waiting statement must set waitingForInput
      // BEFORE its host callback fires, so a host that auto-advances by calling
      // continueExecution() synchronously from inside onDialogue advances
      // instead of stranding. Pre-fix the interactive say-tail set the state
      // AFTER emitting, so the state observed inside the callback was `running`.
      final script =
          RenPyParser().parse('''
define player = Character("Player")

label start:
    python:
        text = "hello"
        renpy.say(player, text)
    "after"
''', 'say_block_state_order.rpy').script;
      final runner = RenPyRunner(script);
      final statesAtCallback = <RenPyRunnerState>[];
      final dialogue = <String>[];

      runner.onDialogue = (character, text) {
        dialogue.add(text);
        statesAtCallback.add(runner.state);
      };

      runner.jumpToLabel('start');
      runner.run();

      // The first callback (the say-tail) observes the runner already waiting.
      expect(dialogue.first, 'hello');
      expect(statesAtCallback.first, RenPyRunnerState.waitingForInput);
    });
  });
}
