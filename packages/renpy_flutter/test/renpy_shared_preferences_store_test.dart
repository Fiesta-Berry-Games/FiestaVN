import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('shared preferences store restores saved persistent values', () async {
    const key = 'renpy.test.persistent';
    SharedPreferences.setMockInitialValues({
      key: jsonEncode({'finished': true}),
    });

    final store = await RenPySharedPreferencesPersistentStore.create(key: key);

    expect(store.load(), {'finished': true});
  });

  test('shared preferences store ignores malformed persistent data', () async {
    const key = 'renpy.test.persistent.malformed';
    SharedPreferences.setMockInitialValues({key: 'not json'});

    final store = await RenPySharedPreferencesPersistentStore.create(key: key);

    expect(store.load(), isEmpty);
  });

  test(
    'shared preferences store saves persistent values for later sessions',
    () async {
      const key = 'renpy.test.persistent.save';
      SharedPreferences.setMockInitialValues({});

      final store = await RenPySharedPreferencesPersistentStore.create(
        key: key,
      );
      store.save({'finished': true, 'route': 'good'});

      final restored = await RenPySharedPreferencesPersistentStore.create(
        key: key,
      );

      expect(restored.load(), {'finished': true, 'route': 'good'});
    },
  );

  test(
    'snapshot store round-trips snapshots through shared preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = await RenPySharedPreferencesSnapshotStore.create(
        key: 'renpy.test.snapshot',
      );
      const snapshot = RenPyRunnerSnapshot(
        state: 'waitingForInput',
        currentLabel: 'start',
        currentBlockPath: [
          RenPyRunnerBlockPathSegment(
            statementIndex: 0,
            branch: RenPyRunnerBlockPathBranch.block,
          ),
        ],
        position: 1,
        stack: [],
        variables: {'route': 'good'},
        persistent: {'finished': true},
        characters: {},
        lastDialogue: RenPyRunnerSnapshotDialogue(text: 'Saved.'),
      );

      await store.save(snapshot);

      final restored = await store.load();

      expect(restored?.toJson(), snapshot.toJson());
    },
  );
}
