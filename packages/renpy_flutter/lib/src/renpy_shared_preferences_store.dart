import 'dart:async';
import 'dart:convert';

import 'package:renpy_core/renpy_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'renpy_preference_store.dart';

/// Stores Ren'Py-style player preferences in Flutter's platform preferences.
final class RenPySharedPreferencesPreferenceStore
    implements RenPyPreferenceStore {
  RenPySharedPreferencesPreferenceStore(
    this._preferences, {
    this.key = defaultKey,
  });

  static const defaultKey = 'renpy.preferences';

  final SharedPreferences _preferences;
  final String key;

  static Future<RenPySharedPreferencesPreferenceStore> create({
    String key = defaultKey,
  }) async {
    return RenPySharedPreferencesPreferenceStore(
      await SharedPreferences.getInstance(),
      key: key,
    );
  }

  @override
  Map<String, Object?> load() {
    final encoded = _preferences.getString(key);
    if (encoded == null || encoded.isEmpty) return const {};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const {};

      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      return const {};
    }
  }

  @override
  void save(Map<String, Object?> values) {
    unawaited(_preferences.setString(key, jsonEncode(values)));
  }
}

/// Stores Ren'Py persistent values in Flutter's platform preferences.
final class RenPySharedPreferencesPersistentStore
    implements RenPyPersistentStore {
  RenPySharedPreferencesPersistentStore(
    this._preferences, {
    this.key = defaultKey,
  });

  static const defaultKey = 'renpy.persistent';

  final SharedPreferences _preferences;
  final String key;

  static Future<RenPySharedPreferencesPersistentStore> create({
    String key = defaultKey,
  }) async {
    return RenPySharedPreferencesPersistentStore(
      await SharedPreferences.getInstance(),
      key: key,
    );
  }

  @override
  Map<String, dynamic> load() {
    final encoded = _preferences.getString(key);
    if (encoded == null || encoded.isEmpty) return const {};

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return const {};

      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      return const {};
    }
  }

  @override
  void save(Map<String, dynamic> values) {
    unawaited(_preferences.setString(key, jsonEncode(values)));
  }
}

/// Stores serialized runner snapshots in Flutter's platform preferences.
final class RenPySharedPreferencesSnapshotStore
    implements RenPyRunnerSnapshotStore {
  RenPySharedPreferencesSnapshotStore(
    this._preferences, {
    this.key = defaultKey,
  });

  static const defaultKey = 'renpy.snapshot';

  final SharedPreferences _preferences;
  final String key;

  static Future<RenPySharedPreferencesSnapshotStore> create({
    String key = defaultKey,
  }) async {
    return RenPySharedPreferencesSnapshotStore(
      await SharedPreferences.getInstance(),
      key: key,
    );
  }

  @override
  Future<RenPyRunnerSnapshot?> load() async {
    final encoded = _preferences.getString(key);
    if (encoded == null || encoded.isEmpty) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return RenPyRunnerSnapshot.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(RenPyRunnerSnapshot snapshot) async {
    await _preferences.setString(key, jsonEncode(snapshot.toJson()));
  }

  @override
  Future<void> clear() async {
    await _preferences.remove(key);
  }
}

/// Stores named snapshot slots and their metadata in platform preferences.
///
/// The metadata index lives under [indexKey] so a browser can list slots
/// without decoding every snapshot, while each slot's full entry is stored
/// under a key derived from [slotKeyPrefix].
final class RenPySharedPreferencesSnapshotSlotStore
    implements RenPyRunnerSnapshotSlotStore {
  RenPySharedPreferencesSnapshotSlotStore(
    this._preferences, {
    this.keyPrefix = defaultKeyPrefix,
  });

  static const defaultKeyPrefix = 'renpy.slot';

  final SharedPreferences _preferences;
  final String keyPrefix;

  String get indexKey => '$keyPrefix.index';
  String get slotKeyPrefix => '$keyPrefix.entry';

  String _slotKey(String slot) => '$slotKeyPrefix.$slot';

  static Future<RenPySharedPreferencesSnapshotSlotStore> create({
    String keyPrefix = defaultKeyPrefix,
  }) async {
    return RenPySharedPreferencesSnapshotSlotStore(
      await SharedPreferences.getInstance(),
      keyPrefix: keyPrefix,
    );
  }

  @override
  Future<RenPyRunnerSlotEntry?> load(String slot) async {
    final encoded = _preferences.getString(_slotKey(slot));
    if (encoded == null || encoded.isEmpty) return null;

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return RenPyRunnerSlotEntry.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String slot, RenPyRunnerSlotEntry entry) async {
    await _preferences.setString(_slotKey(slot), jsonEncode(entry.toJson()));
    final index =
        _loadIndex()
          ..removeWhere((metadata) => metadata.slot == slot)
          ..add(entry.metadata);
    await _saveIndex(index);
  }

  @override
  Future<void> delete(String slot) async {
    await _preferences.remove(_slotKey(slot));
    final index =
        _loadIndex()..removeWhere((metadata) => metadata.slot == slot);
    await _saveIndex(index);
  }

  @override
  Future<List<RenPyRunnerSlotMetadata>> list() async {
    return _loadIndex();
  }

  List<RenPyRunnerSlotMetadata> _loadIndex() {
    final encoded = _preferences.getString(indexKey);
    if (encoded == null || encoded.isEmpty) return [];

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => RenPyRunnerSlotMetadata.fromJson(
              Map<String, Object?>.from(item),
            ),
          )
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _saveIndex(List<RenPyRunnerSlotMetadata> index) async {
    await _preferences.setString(
      indexKey,
      jsonEncode(index.map((metadata) => metadata.toJson()).toList()),
    );
  }
}
