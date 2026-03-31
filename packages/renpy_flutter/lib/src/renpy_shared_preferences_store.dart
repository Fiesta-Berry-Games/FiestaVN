import 'dart:async';
import 'dart:convert';

import 'package:renpy_core/renpy_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
