/// Stores Ren'Py `persistent.*` namespace values across runner instances.
abstract interface class RenPyPersistentStore {
  /// Returns the current persistent namespace values.
  Map<String, dynamic> load();

  /// Replaces the stored persistent namespace values.
  void save(Map<String, dynamic> values);
}

/// In-memory persistent store useful for tests, tools, and embedded runners.
final class RenPyMemoryPersistentStore implements RenPyPersistentStore {
  RenPyMemoryPersistentStore([Map<String, dynamic>? initialValues])
    : _values = Map<String, dynamic>.of(initialValues ?? const {});

  final Map<String, dynamic> _values;

  /// Current stored values as a defensive read-only snapshot.
  Map<String, dynamic> get values => Map.unmodifiable(_values);

  @override
  Map<String, dynamic> load() => Map<String, dynamic>.of(_values);

  @override
  void save(Map<String, dynamic> values) {
    _values
      ..clear()
      ..addAll(Map<String, dynamic>.of(values));
  }
}
