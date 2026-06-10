import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A user-added external project recorded in the game library.
///
/// Bundled reference games are not stored here; they are always present and
/// supplied by the launcher. Only externally added projects are persisted.
final class LibraryProject {
  const LibraryProject({
    required this.id,
    required this.name,
    this.sourcePath,
    this.lastPlayed,
  });

  factory LibraryProject.fromJson(Map<String, dynamic> json) {
    final lastPlayedMillis = json['lastPlayedMillis'];
    return LibraryProject(
      id: json['id'] as String,
      name: json['name'] as String,
      sourcePath: json['sourcePath'] as String?,
      lastPlayed:
          lastPlayedMillis is int
              ? DateTime.fromMillisecondsSinceEpoch(lastPlayedMillis)
              : null,
    );
  }

  /// Stable identifier used to key the per-game save-slot stores.
  ///
  /// For folder-based projects this is the folder path so saves stay
  /// associated with the same project across restarts.
  final String id;

  /// Display name shown in the library list.
  final String name;

  /// The on-disk folder the project was loaded from, when available.
  ///
  /// Desktop and mobile pickers expose a folder path that can be reloaded on a
  /// later launch. Web uploads have no durable path, so this is null there and
  /// the project must be re-picked.
  final String? sourcePath;

  /// When the project was last launched, used to sort recently played first.
  final DateTime? lastPlayed;

  bool get canReload => sourcePath != null && sourcePath!.isNotEmpty;

  LibraryProject copyWith({DateTime? lastPlayed}) {
    return LibraryProject(
      id: id,
      name: name,
      sourcePath: sourcePath,
      lastPlayed: lastPlayed ?? this.lastPlayed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (sourcePath != null) 'sourcePath': sourcePath,
      if (lastPlayed != null)
        'lastPlayedMillis': lastPlayed!.millisecondsSinceEpoch,
    };
  }
}

/// Persists the list of user-added external projects via shared_preferences.
///
/// The store survives app restarts: re-instantiating it and calling [load]
/// returns the previously saved projects.
final class GameLibraryStore {
  GameLibraryStore._(this._preferences);

  static const String storageKey = 'renfly.library.projects';

  static Future<GameLibraryStore> create() async {
    return GameLibraryStore._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _preferences;

  Future<List<LibraryProject>> load() async {
    final raw = _preferences.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return [
      for (final entry in decoded)
        if (entry is Map<String, dynamic>) LibraryProject.fromJson(entry),
    ];
  }

  Future<void> _save(List<LibraryProject> projects) async {
    final encoded = jsonEncode([
      for (final project in projects) project.toJson(),
    ]);
    await _preferences.setString(storageKey, encoded);
  }

  /// Adds [project], replacing any existing entry with the same id.
  Future<List<LibraryProject>> add(LibraryProject project) async {
    final projects =
        await load()
          ..removeWhere((existing) => existing.id == project.id);
    projects.add(project);
    await _save(projects);
    return projects;
  }

  Future<List<LibraryProject>> remove(String id) async {
    final projects =
        await load()
          ..removeWhere((project) => project.id == id);
    await _save(projects);
    return projects;
  }

  /// Records that [id] was just launched, for recently-played sorting.
  Future<List<LibraryProject>> markPlayed(String id, {DateTime? when}) async {
    final timestamp = when ?? DateTime.now();
    final projects = await load();
    for (var i = 0; i < projects.length; i += 1) {
      if (projects[i].id == id) {
        projects[i] = projects[i].copyWith(lastPlayed: timestamp);
      }
    }
    await _save(projects);
    return projects;
  }
}
