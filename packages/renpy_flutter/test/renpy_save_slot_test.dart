import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('shared preferences slot store', () {
    test('round-trips a slot entry with its metadata', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await RenPySharedPreferencesSnapshotSlotStore.create(
        keyPrefix: 'renpy.test.slot.roundtrip',
      );

      final entry = _entry('1', label: 'start', preview: 'Sylvie: Hi.');
      await store.save('1', entry);

      final restored = await store.load('1');
      expect(restored?.metadata.slot, '1');
      expect(restored?.metadata.label, 'start');
      expect(restored?.metadata.preview, 'Sylvie: Hi.');
      expect(restored?.snapshot.toJson(), entry.snapshot.toJson());
    });

    test('lists metadata and isolates entries between slots', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await RenPySharedPreferencesSnapshotSlotStore.create(
        keyPrefix: 'renpy.test.slot.isolation',
      );

      await store.save('1', _entry('1', preview: 'First.'));
      await store.save('quick', _entry('quick', preview: 'Quick.'));

      final listing = await store.list();
      expect(listing.map((metadata) => metadata.slot).toSet(), {'1', 'quick'});
      expect((await store.load('1'))?.metadata.preview, 'First.');
      expect((await store.load('quick'))?.metadata.preview, 'Quick.');
      expect(await store.load('2'), isNull);
    });

    test('deletes a slot without touching the others', () async {
      SharedPreferences.setMockInitialValues({});
      final store = await RenPySharedPreferencesSnapshotSlotStore.create(
        keyPrefix: 'renpy.test.slot.delete',
      );

      await store.save('1', _entry('1'));
      await store.save('2', _entry('2'));
      await store.delete('1');

      expect(await store.load('1'), isNull);
      expect(await store.load('2'), isNotNull);
      expect((await store.list()).map((metadata) => metadata.slot), ['2']);
    });

    test('persists slots across store re-instantiation', () async {
      SharedPreferences.setMockInitialValues({});
      const prefix = 'renpy.test.slot.persist';

      final firstStore = await RenPySharedPreferencesSnapshotSlotStore.create(
        keyPrefix: prefix,
      );
      await firstStore.save('3', _entry('3', preview: 'Persisted.'));

      final secondStore = await RenPySharedPreferencesSnapshotSlotStore.create(
        keyPrefix: prefix,
      );
      final restored = await secondStore.load('3');
      expect(restored?.metadata.preview, 'Persisted.');
      expect((await secondStore.list()).single.slot, '3');
    });
  });

  group('controller slot api', () {
    test('saves, lists, loads, and deletes a slot', () async {
      final store = RenPyMemoryRunnerSnapshotSlotStore();
      final firstController = RenPyFlutterController(slotStore: store);
      addTearDown(firstController.dispose);

      firstController.load('''
label start:
    "First."
    "Second."
    "Third."
''');

      await _continueUntil(
        firstController,
        (status) => status is RenPyDialogue && status.text == 'First.',
      );
      firstController.continueGame();
      await _continueUntil(
        firstController,
        (status) => status is RenPyDialogue && status.text == 'Second.',
      );

      expect(firstController.hasSlotStore, isTrue);
      expect(await firstController.saveToSlot('1'), isTrue);

      final slots = await firstController.listSaveSlots();
      expect(slots.single.slot, '1');
      expect(slots.single.label, 'start');
      expect(slots.single.preview, 'Second.');

      final secondController = RenPyFlutterController(slotStore: store);
      addTearDown(secondController.dispose);
      secondController.load('''
label start:
    "First."
    "Second."
    "Third."
''');
      await _continueUntil(
        secondController,
        (status) => status is RenPyDialogue && status.text == 'First.',
      );

      expect(await secondController.loadFromSlot('1'), isTrue);
      expect((secondController.value as RenPyDialogue).text, 'Second.');

      expect(await secondController.deleteSlot('1'), isTrue);
      expect(await secondController.listSaveSlots(), isEmpty);
      expect(await secondController.loadFromSlot('1'), isFalse);
    });

    test('keeps slots isolated from one another', () async {
      final store = RenPyMemoryRunnerSnapshotSlotStore();
      final controller = RenPyFlutterController(slotStore: store);
      addTearDown(controller.dispose);

      controller.load('''
label start:
    "First."
    "Second."
''');

      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'First.',
      );
      expect(await controller.saveToSlot('1'), isTrue);

      controller.continueGame();
      await _continueUntil(
        controller,
        (status) => status is RenPyDialogue && status.text == 'Second.',
      );
      expect(await controller.saveToSlot('2'), isTrue);

      expect((await store.load('1'))?.metadata.preview, 'First.');
      expect((await store.load('2'))?.metadata.preview, 'Second.');
    });

    test('reports no slot store when none was provided', () async {
      final controller = RenPyFlutterController();
      addTearDown(controller.dispose);

      controller.load('''
label start:
    "First."
''');
      await _continueUntil(controller, (status) => status is RenPyDialogue);

      expect(controller.hasSlotStore, isFalse);
      expect(await controller.saveToSlot('1'), isFalse);
      expect(await controller.loadFromSlot('1'), isFalse);
      expect(await controller.deleteSlot('1'), isFalse);
      expect(await controller.listSaveSlots(), isEmpty);
    });

    test('still supports the prior single-slot snapshot store', () async {
      final snapshotStore = RenPyMemoryRunnerSnapshotStore();
      final firstController = RenPyFlutterController(
        snapshotStore: snapshotStore,
      );
      addTearDown(firstController.dispose);

      firstController.load('''
label start:
    "First."
    "Second."
''');

      await _continueUntil(
        firstController,
        (status) => status is RenPyDialogue && status.text == 'First.',
      );
      firstController.continueGame();
      await _continueUntil(
        firstController,
        (status) => status is RenPyDialogue && status.text == 'Second.',
      );

      expect(firstController.hasSlotStore, isFalse);
      expect(await firstController.saveGame(), isTrue);

      final secondController = RenPyFlutterController(
        snapshotStore: snapshotStore,
      );
      addTearDown(secondController.dispose);
      secondController.load('''
label start:
    "First."
    "Second."
''');
      await _continueUntil(
        secondController,
        (status) => status is RenPyDialogue && status.text == 'First.',
      );

      expect(await secondController.loadSavedGame(), isTrue);
      expect((secondController.value as RenPyDialogue).text, 'Second.');
    });
  });
}

RenPyRunnerSlotEntry _entry(String slot, {String? label, String? preview}) {
  return RenPyRunnerSlotEntry(
    metadata: RenPyRunnerSlotMetadata(
      slot: slot,
      savedAt: DateTime.utc(2026, 5, 28, 12, 30),
      label: label,
      preview: preview,
    ),
    snapshot: RenPyRunnerSnapshot(
      state: 'waitingForInput',
      currentLabel: label,
      currentBlockPath: const [
        RenPyRunnerBlockPathSegment(
          statementIndex: 0,
          branch: RenPyRunnerBlockPathBranch.block,
        ),
      ],
      position: 1,
      stack: const [],
      variables: const {},
      persistent: const {},
      characters: const {},
      lastDialogue:
          preview == null ? null : RenPyRunnerSnapshotDialogue(text: preview),
    ),
  );
}

Future<void> _continueUntil(
  RenPyFlutterController controller,
  bool Function(RenPyGameStatus status) predicate,
) async {
  for (var i = 0; i < 50; i++) {
    if (predicate(controller.value)) return;
    if (controller.value is RenPyDialogue) {
      controller.continueGame();
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  fail('Controller did not reach expected state. Last: ${controller.value}');
}
