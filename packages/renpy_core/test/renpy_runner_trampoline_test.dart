import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void _drain(RenPyRunner runner) {
  runner.run();
  var guard = 0;
  while (runner.state == RenPyRunnerState.waitingForInput && guard < 100000) {
    runner.continueExecution();
    guard += 1;
  }
}

void main() {
  group('execution trampoline (no native-stack recursion)', () {
    test('a long linear run of non-waiting statements does not overflow', () {
      // ~20000 consecutive `$` statements. Under the old recursive drive each
      // one added a native-stack frame, overflowing the Dart stack long before
      // the end. The trampoline drives them iteratively.
      final lines = List<String>.generate(20000, (_) => '    \$ x += 1');
      final script =
          RenPyParser().parse('''
label start:
    \$ x = 0
${lines.join('\n')}
    "Done."
    return
''', 'long_linear.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      expect(runner.state, RenPyRunnerState.complete);
      expect(runner.snapshot().variables['x'], 20000);
      expect(dialogue, ['Done.']);
    });

    test('a deep nested renpy.call chain unwinds without overflowing', () {
      // 4000 labels each calling the next via `renpy.call`. Each call pushes a
      // frame on the runner's own stack (not the native stack), so the
      // trampoline keeps it iterative; the old recursion would overflow.
      final labels = StringBuffer();
      const depth = 4000;
      for (var i = 0; i < depth; i++) {
        labels.writeln('label l$i:');
        labels.writeln('    \$ hits += 1');
        if (i < depth - 1) labels.writeln('    \$ renpy.call("l${i + 1}")');
        labels.writeln('    return');
      }
      final script =
          RenPyParser().parse('''
label start:
    \$ hits = 0
    \$ renpy.call("l0")
    "All returned."
    return

$labels
''', 'deep_calls.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      runner.onDialogue = (character, text) => dialogue.add(text);

      runner.jumpToLabel('start');
      _drain(runner);

      expect(runner.state, RenPyRunnerState.complete);
      expect(runner.snapshot().variables['hits'], depth);
      expect(dialogue, ['All returned.']);
      expect(runner.callStackDepth, 0);
    });

    test('a non-terminating script-level while degrades to a diagnostic '
        'instead of crashing (the LearnToCodeRPG study_session shape)', () {
      // Mirrors quiz_session.rpy: a `while` whose condition never goes false
      // because its body cannot update the gating value. Previously the
      // per-iteration recursion overflowed the native stack (a fatal error);
      // now it trips the iteration guard, emits a diagnostic, and execution
      // continues past the loop.
      final script =
          RenPyParser().parse('''
label start:
    \$ spins = 0
    while True:
        \$ spins += 1
    "Recovered."
    return
''', 'runaway.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];
      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;

      runner.jumpToLabel('start');
      _drain(runner);

      // Not a crash/error state: the runner recovered and ran past the loop.
      expect(runner.state, RenPyRunnerState.complete);
      expect(dialogue, ['Recovered.']);
      expect(
        diagnostics.any((d) => d.message.contains('exceeded')),
        isTrue,
        reason: 'the runaway loop should report an iteration-cap diagnostic',
      );
    });

    test('a host that continues synchronously from onDialogue/onPause '
        'advances instead of stranding', () {
      // An auto-advance/skip-style host that calls continueExecution() directly
      // inside the dialogue/pause callbacks. The waiting state is now set BEFORE
      // the callback, so the synchronous continue advances; setting it after
      // (the old order) would clobber the continue and strand after line one.
      final script =
          RenPyParser().parse('''
label start:
    "One."
    pause 1.0
    "Two."
    "Three."
    return
''', 'sync_continue.rpy').script;
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      runner.onDialogue = (character, text) {
        dialogue.add(text);
        runner.continueExecution(); // synchronous auto-advance
      };
      runner.onPause = (event) => runner.continueExecution();

      runner.jumpToLabel('start');
      runner.run();

      expect(dialogue, ['One.', 'Two.', 'Three.']);
      expect(runner.state, RenPyRunnerState.complete);
    });
  });
}
