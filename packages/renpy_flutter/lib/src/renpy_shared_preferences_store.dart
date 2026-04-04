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
