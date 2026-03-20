import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'renpy_rpa_archive.dart';

/// A file selected from a RenPy project folder.
final class RenPyProjectFile {
  RenPyProjectFile(String path, Uint8List bytes)
    : path = _normalizePath(path),
      bytes = Uint8List.fromList(bytes);

  RenPyProjectFile.text(String path, String source)
    : this(path, Uint8List.fromList(utf8.encode(source)));

  final String path;
  final Uint8List bytes;
}

/// A loaded RenPy project folder with script source and addressable assets.
final class RenPyGameProject {
  RenPyGameProject._({
    required this.name,
    required this.scriptPath,
    required this.gameRoot,
    required this.scriptSource,
    required Map<String, Uint8List> assets,
    required Map<String, RenPyRpaArchive> archives,
    required Map<String, String> fontAssets,
  }) : _assets = Map.unmodifiable(assets),
       _assetsByLowerPath = Map.unmodifiable(
         _caseInsensitiveIndex(assets.keys),
       ),
       _archives = Map.unmodifiable(archives),
       fontAssets = Map.unmodifiable(fontAssets),
       availableAssets = Set.unmodifiable(
         {
           ...assets.keys.where((asset) => asset != scriptPath),
           for (final archive in archives.entries)
             for (final entry in archive.value.entries.keys)
               path.posix.join(path.posix.dirname(archive.key), entry),
         }.where((asset) => asset != scriptPath),
       );

  factory RenPyGameProject.fromFiles(
    Iterable<RenPyProjectFile> files, {
    String? scriptPath,
  }) {
    final byPath = <String, Uint8List>{};
    for (final file in files) {
      if (file.path.isEmpty) continue;
      byPath[file.path] = file.bytes;
    }
    final archives = _loadRpaArchives(byPath);
    _expandRpaScripts(byPath, archives);

    final normalizedScriptPath =
        scriptPath == null ? null : _normalizePath(scriptPath);
    final selectedScriptPath =
        normalizedScriptPath ?? _chooseScriptPath(byPath.keys);
    final scriptBytes = byPath[selectedScriptPath];
    if (scriptBytes == null) {
      throw StateError('RenPy project script not found: $selectedScriptPath');
    }

    final gameRoot = path.posix.dirname(selectedScriptPath);
    return RenPyGameProject._(
      name: _projectName(selectedScriptPath),
      scriptPath: selectedScriptPath,
      gameRoot: gameRoot == '.' ? '' : gameRoot,
      scriptSource: utf8.decode(scriptBytes),
      assets: byPath,
      archives: archives,
      fontAssets: _fontAssets(
        byPath.keys,
        archives,
        gameRoot == '.' ? '' : gameRoot,
      ),
    );
  }

  final String name;
  final String scriptPath;
  final String gameRoot;
  final String scriptSource;
  final Set<String> availableAssets;
  final Map<String, String> fontAssets;
  final Map<String, Uint8List> _assets;
  final Map<String, String> _assetsByLowerPath;
  final Map<String, RenPyRpaArchive> _archives;

  Map<String, Uint8List> get assetBytes => _assets;

  Uint8List? readAsset(String assetPath) {
    final normalized = _normalizePath(assetPath);
    final loose =
        _assets[normalized] ??
        _assets[_assetsByLowerPath[normalized.toLowerCase()]];
    if (loose != null) return loose;

    for (final archive in _archives.entries) {
      final root = path.posix.dirname(archive.key);
      if (!normalized.toLowerCase().startsWith('${root.toLowerCase()}/')) {
        continue;
      }
      final entryPath = normalized.substring(root.length + 1);
      final archived = archive.value.read(entryPath);
      if (archived != null) return archived;
    }

    return null;
  }

  static String _chooseScriptPath(Iterable<String> paths) {
    final scripts =
        paths.where((path) => path.endsWith('script.rpy')).toList()..sort();

    for (final script in scripts) {
      if (script.endsWith('/game/script.rpy')) return script;
    }
    if (scripts.isNotEmpty) return scripts.first;

    throw StateError('RenPy project folder does not contain script.rpy');
  }

  static String _projectName(String scriptPath) {
    final parts = path.posix.split(scriptPath);
    final gameIndex = parts.lastIndexOf('game');
    if (gameIndex > 0) return parts[gameIndex - 1];
    if (parts.length > 1) return parts[parts.length - 2];
    return 'RenPy Project';
  }

  static Map<String, RenPyRpaArchive> _loadRpaArchives(
    Map<String, Uint8List> byPath,
  ) {
    final archives = <String, RenPyRpaArchive>{};

    for (final archiveFile in byPath.entries.where(
      (entry) => entry.key.toLowerCase().endsWith('.rpa'),
    )) {
      try {
        archives[archiveFile.key] = RenPyRpaArchive(archiveFile.value);
      } on FormatException {
        continue;
      }
    }

    return archives;
  }

  static void _expandRpaScripts(
    Map<String, Uint8List> byPath,
    Map<String, RenPyRpaArchive> archives,
  ) {
    for (final archiveFile in archives.entries) {
      final archiveRoot = path.posix.dirname(archiveFile.key);
      final archive = archiveFile.value;
      for (final entryPath in archive.entries.keys) {
        if (!entryPath.toLowerCase().endsWith('.rpy')) continue;
        final bytes = archive.read(entryPath);
        if (bytes == null) continue;
        byPath.putIfAbsent(
          path.posix.join(archiveRoot, entryPath),
          () => bytes,
        );
      }
    }
  }

  static Map<String, String> _fontAssets(
    Iterable<String> loosePaths,
    Map<String, RenPyRpaArchive> archives,
    String gameRoot,
  ) {
    final fonts = <String, String>{};

    void addFont(String assetPath) {
      if (!_isFontAsset(assetPath)) return;
      fonts.putIfAbsent(path.posix.basename(assetPath), () => assetPath);
      if (gameRoot.isNotEmpty &&
          assetPath.toLowerCase().startsWith('${gameRoot.toLowerCase()}/')) {
        final relativePath = assetPath.substring(gameRoot.length + 1);
        fonts.putIfAbsent(relativePath, () => assetPath);
      }
      fonts.putIfAbsent(assetPath, () => assetPath);
    }

    for (final assetPath in loosePaths) {
      addFont(assetPath);
    }

    for (final archiveFile in archives.entries) {
      final archiveRoot = path.posix.dirname(archiveFile.key);
      for (final entryPath in archiveFile.value.entries.keys) {
        addFont(path.posix.join(archiveRoot, entryPath));
      }
    }

    return fonts;
  }
}

String _normalizePath(String value) {
  final withoutQuery = value.replaceAll(r'\', '/').split('?').first.trim();
  final normalized = path.posix.normalize(withoutQuery);
  return normalized.replaceFirst(RegExp(r'^(\./|/)+'), '');
}

bool _isFontAsset(String assetPath) {
  final lower = assetPath.toLowerCase();
  return lower.endsWith('.ttf') || lower.endsWith('.otf');
}

Map<String, String> _caseInsensitiveIndex(Iterable<String> paths) {
  final index = <String, String>{};
  for (final path in paths) {
    index.putIfAbsent(path.toLowerCase(), () => path);
  }
  return index;
}
