import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

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
  }) : _assets = Map.unmodifiable(assets),
       availableAssets = Set.unmodifiable(
         assets.keys.where((asset) => asset != scriptPath),
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
    );
  }

  final String name;
  final String scriptPath;
  final String gameRoot;
  final String scriptSource;
  final Set<String> availableAssets;
  final Map<String, Uint8List> _assets;

  Map<String, Uint8List> get assetBytes => _assets;

  Uint8List? readAsset(String assetPath) => _assets[_normalizePath(assetPath)];

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
}

String _normalizePath(String value) {
  final withoutQuery = value.replaceAll(r'\', '/').split('?').first.trim();
  final normalized = path.posix.normalize(withoutQuery);
  return normalized.replaceFirst(RegExp(r'^(\./|/)+'), '');
}
