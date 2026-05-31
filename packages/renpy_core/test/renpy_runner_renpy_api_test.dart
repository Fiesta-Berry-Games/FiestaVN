import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('renpy.random.* is deterministic and renpy.variant returns false', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ a = renpy.random.randint(1, 6)
    \$ b = renpy.random.randint(1, 6)
    \$ pick = renpy.random.choice(["x", "y", "z"])
    if renpy.variant("touch"):
        "Touch variant."
    else:
        "Default variant."
''', 'renpy_api.rpy').script;

    int runOnce() {
      final runner = RenPyRunner(script);
      final dialogue = <String>[];
      final diagnostics = <RenPyDiagnostic>[];
      runner.onDialogue = (character, text) => dialogue.add(text);
      runner.onDiagnostic = diagnostics.add;
      runner.jumpToLabel('start');
      runner.run();
      expect(dialogue, ['Default variant.']);
      // The randint/choice/variant calls must execute, not be skipped.
      expect(
        diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
        isEmpty,
      );
      return runner.snapshot().variables['a'] as int;
    }

    final first = runOnce();
    final second = runOnce();
    expect(first, inInclusiveRange(1, 6));
    // Two fresh runners share the fixed seed, so the sequence is reproducible.
    expect(first, second);
  });

  test('renpy.notify routes to the onNotify hook without aborting', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.notify("Saved.")
    "Done."
''', 'renpy_api.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final notifications = <String>[];
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onNotify = notifications.add;
    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(notifications, ['Saved.']);
    expect(dialogue, ['Done.']);
    expect(diagnostics, isEmpty);
  });

  test('renpy no-op calls execute and do not skip the statement', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.restart_interaction()
    \$ renpy.block_rollback()
    \$ renpy.checkpoint()
    \$ screen_ref = renpy.get_screen("nope")
    if screen_ref is None:
        "No screen."
''', 'renpy_api.rpy').script;
    final runner = RenPyRunner(script);
    final dialogue = <String>[];
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDialogue = (character, text) => dialogue.add(text);
    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(dialogue, ['No screen.']);
    expect(
      diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
      isEmpty,
    );
  });

  test('renpy.sound.play inside an expression emits a play event', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.sound.play("click.ogg")
    "Played."
''', 'renpy_api.rpy').script;
    final runner = RenPyRunner(script);
    final audio = <RenPyAudioEvent>[];
    final diagnostics = <RenPyDiagnostic>[];

    runner.onAudio = audio.add;
    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(audio, hasLength(1));
    expect(audio.single.channel, 'sound');
    expect(audio.single.asset, 'click.ogg');
    expect(
      diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
      isEmpty,
    );
  });

  test('renpy.show_screen routes to the screen layer without a skip', () {
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.show_screen("inventory")
''', 'renpy_api.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    // show_screen is now a best-effort, non-blocking shim: it shows the screen
    // and does NOT emit a skip diagnostic.
    expect(
      diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
      isEmpty,
    );
    expect(runner.shownScreens.map((s) => s.name), contains('inventory'));
  });

  test('renpy.call_screen from Python degrades to a benign no-op', () {
    // call_screen is interactive/blocking and cannot block from an expression
    // context. It degrades to a best-effort no-op returning null
    // instead of throwing, so a method body that calls it (e.g. Calendar.next()
    // doing a date mutation then renpy.call_screen('the next day...')) completes
    // its modelable work instead of aborting the whole `$ obj.method()`
    // statement. A bare top-level call therefore emits no skip diagnostic.
    final script =
        RenPyParser().parse('''
label start:
    \$ renpy.call_screen("inventory")
''', 'renpy_api.rpy').script;
    final runner = RenPyRunner(script);
    final diagnostics = <RenPyDiagnostic>[];

    runner.onDiagnostic = diagnostics.add;

    runner.jumpToLabel('start');
    runner.run();

    expect(
      diagnostics.where((d) => d.code == RenPyDiagnosticCode.skippedPython),
      isEmpty,
    );
  });
}
