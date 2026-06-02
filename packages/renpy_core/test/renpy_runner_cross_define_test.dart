import 'dart:convert';

import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

/// Regression tests for the runner's define/store handling.
///
/// 1. Cross-`define` Character-name resolution: `define npc = annika` where
///    `annika` is itself a Character define must resolve (no `skippedDefinition`)
///    AND alias the character so a say with `npc` renders annika's name/color.
/// 2. `_return` pseudo-variable seeding: reading `_return` before any call
///    returns resolves to null instead of skipping.

({List<RenPyDiagnostic> diagnostics, RenPyRunner runner}) _load(String source) {
  final script = RenPyParser().parse(source, 'define_store.rpy').script;
  final diagnostics = <RenPyDiagnostic>[];
  final runner = RenPyRunner(script);
  // Wiring the callback flushes diagnostics buffered during construction
  // (define/default are applied in the constructor).
  runner.onDiagnostic = diagnostics.add;
  return (diagnostics: diagnostics, runner: runner);
}

List<RenPyDiagnostic> _skipped(List<RenPyDiagnostic> diagnostics) =>
    diagnostics
        .where((d) => d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();

void main() {
  group('cross-define Character-name resolution', () {
    test('define npc = annika does not emit skippedDefinition', () {
      // Pre-fix: `annika` was bound only in `_characters`, never as a store
      // value, so evaluating `define npc = annika` threw and emitted a
      // `skippedDefinition` with "name `annika` is not defined".
      final result = _load('''
define annika = Character("Annika", color="#ff0000")
define npc = annika

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      final skips = _skipped(result.diagnostics);
      expect(
        skips.where((d) => d.detail?.contains('npc') ?? false),
        isEmpty,
        reason: 'npc = annika should resolve, not skip',
      );
    });

    test(
      'say with aliased character npc renders annika display name/color',
      () {
        final result = _load('''
define annika = Character("Annika", color="#ff0000")
define npc = annika

label start:
    npc "Hello there."
''');

        final dialogue = <RenPyDialogueEvent>[];
        result.runner.onDialogueEvent = dialogue.add;
        result.runner.jumpToLabel('start');
        result.runner.run();

        expect(dialogue, hasLength(1));
        expect(dialogue.single.displayName, 'Annika');
        expect(dialogue.single.color, '#ff0000');
        expect(dialogue.single.text, 'Hello there.');
      },
    );

    test('runtime \$ npc = annika aliases the character for say', () {
      final result = _load('''
define annika = Character("Annika", color="#00ff00")

label start:
    \$ npc = annika
    npc "Runtime alias."
''');

      final dialogue = <RenPyDialogueEvent>[];
      result.runner.onDialogueEvent = dialogue.add;
      result.runner.jumpToLabel('start');
      result.runner.run();

      expect(dialogue, hasLength(1));
      expect(dialogue.single.displayName, 'Annika');
      expect(dialogue.single.color, '#00ff00');
      expect(dialogue.single.text, 'Runtime alias.');
      expect(_skipped(result.diagnostics), isEmpty);
    });

    test('default npc2 = annika aliases the character for say (no skip)', () {
      // Pre-fix: _applyDefault did not run the character-alias logic, so a
      // `default npc2 = annika` rendered "npc2" instead of Annika.
      final result = _load('''
define annika = Character("Annika", color="#abcdef")
default npc2 = annika

label start:
    npc2 "Default alias."
''');

      final dialogue = <RenPyDialogueEvent>[];
      result.runner.onDialogueEvent = dialogue.add;
      result.runner.jumpToLabel('start');
      result.runner.run();

      expect(dialogue, hasLength(1));
      expect(dialogue.single.displayName, 'Annika');
      expect(dialogue.single.color, '#abcdef');
      expect(dialogue.single.text, 'Default alias.');
      expect(
        _skipped(
          result.diagnostics,
        ).where((d) => d.detail?.contains('npc2') ?? false),
        isEmpty,
        reason: 'default npc2 = annika should alias, not skip',
      );
    });

    test('snapshot JSON round-trip keeps cross-define alias type-stable', () {
      // Pre-fix: RenPyRunnerSnapshot.fromJson revived `npc` from the JSON map as
      // a plain Map ({'__character_ref__': 'npc'}) rather than a _CharacterRef,
      // so a post-load `$ y = npc` saw a Map and failed to re-alias the say.
      final result = _load('''
define annika = Character("Annika", color="#013579")
define npc = annika

label start:
    "marker"
''');

      // Round-trip the snapshot through real JSON (jsonEncode must succeed).
      final json = jsonEncode(result.runner.snapshot().toJson());
      final decoded = RenPyRunnerSnapshot.fromJson(
        jsonDecode(json) as Map<String, Object?>,
      );

      // Restore into a FRESH runner built from the same script.
      final script =
          RenPyParser().parse('''
define annika = Character("Annika", color="#013579")
define npc = annika

label start:
    \$ y = npc
    y "Post-load alias."
''', 'restore.rpy').script;
      final fresh = RenPyRunner(script);
      final dialogue = <RenPyDialogueEvent>[];
      fresh.onDialogueEvent = dialogue.add;
      fresh.restoreSnapshot(decoded);

      // Type-stability assertion (load-bearing): immediately after restore the
      // store value for `npc` must NOT degrade to a plain Map. Pre-fix it came
      // back as {'__character_ref__': 'npc'} (a Map); post-fix it is revived to
      // the private _CharacterRef whose toString() is the name. We assert on the
      // restored value here - before any run()/jump that would re-apply the
      // constructor defines and mask the degradation.
      final restoredNpc = fresh.pythonScope.read('npc');
      expect(
        restoredNpc,
        isNot(isA<Map>()),
        reason: 'snapshot round-trip must not degrade _CharacterRef to a Map',
      );
      expect(restoredNpc.toString(), 'npc');

      // And it still behaves as an alias: a `$ y = npc` followed by a say
      // resolves Annika post-restore.
      fresh.jumpToLabel('start');
      fresh.run();

      expect(dialogue, hasLength(1));
      expect(dialogue.single.displayName, 'Annika');
      expect(dialogue.single.color, '#013579');
      expect(dialogue.single.text, 'Post-load alias.');
    });
  });

  group('_return pseudo-variable seeding', () {
    test('reading _return before any call resolves to null (no skip)', () {
      // Pre-fix: `selected_song = _return` threw "name `_return` is not defined"
      // and emitted a skippedDefinition. Post-fix: _return is seeded to null.
      final result = _load('''
define selected_song = _return

label start:
    "hi"
''');

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(
        _skipped(
          result.diagnostics,
        ).where((d) => d.detail?.contains('_return') ?? false),
        isEmpty,
      );
      expect(result.runner.pythonScope.read('selected_song'), isNull);
    });

    test('\$ x = _return before any call resolves to null', () {
      final result = _load('''
label start:
    \$ x = _return
    "hi"
''');

      result.runner.jumpToLabel('start');
      result.runner.run();

      expect(result.runner.state, isNot(RenPyRunnerState.error));
      expect(result.runner.pythonScope.read('x'), isNull);
      expect(
        _skipped(
          result.diagnostics,
        ).where((d) => d.detail?.contains('_return') ?? false),
        isEmpty,
      );
    });
  });
}
