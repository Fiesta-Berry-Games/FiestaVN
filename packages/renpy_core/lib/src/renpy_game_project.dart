import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import 'renpy_rpa_archive.dart';

/// The configured virtual screen size of a RenPy project.
final class RenPyScreenSize {
  const RenPyScreenSize({required this.width, required this.height});

  final int width;
  final int height;

  double get aspectRatio => width / height;

  static RenPyScreenSize? fromScriptSource(String source) {
    return _screenSizeFromSources([source]);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyScreenSize &&
            width == other.width &&
            height == other.height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() {
    return 'RenPyScreenSize(width: $width, height: $height)';
  }
}

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
    required this.screenSize,
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
    if (!byPath.containsKey(selectedScriptPath)) {
      throw StateError('RenPy project script not found: $selectedScriptPath');
    }

    final gameRoot = path.posix.dirname(selectedScriptPath);
    final normalizedGameRoot = gameRoot == '.' ? '' : gameRoot;
    return RenPyGameProject._(
      name: _projectName(selectedScriptPath),
      scriptPath: selectedScriptPath,
      gameRoot: normalizedGameRoot,
      scriptSource: _scriptSource(
        byPath,
        selectedScriptPath,
        normalizedGameRoot,
      ),
      assets: byPath,
      archives: archives,
      fontAssets: _fontAssets(byPath.keys, archives, normalizedGameRoot),
      screenSize: _screenSize(byPath, normalizedGameRoot),
    );
  }

  final String name;
  final String scriptPath;
  final String gameRoot;
  final String scriptSource;
  final Set<String> availableAssets;
  final RenPyScreenSize? screenSize;
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

  static String _scriptSource(
    Map<String, Uint8List> assets,
    String selectedScriptPath,
    String gameRoot,
  ) {
    final scripts = _scriptFiles(assets, gameRoot);
    if (scripts.length <= 1) {
      return utf8.decode(assets[selectedScriptPath]!, allowMalformed: true);
    }

    scripts.sort((a, b) {
      if (a.key == selectedScriptPath) return -1;
      if (b.key == selectedScriptPath) return 1;
      return a.key.compareTo(b.key);
    });

    return scripts
        .map((script) => utf8.decode(script.value, allowMalformed: true))
        .join('\n\n');
  }

  static List<MapEntry<String, Uint8List>> _scriptFiles(
    Map<String, Uint8List> assets,
    String gameRoot,
  ) {
    return assets.entries
        .where(
          (entry) =>
              entry.key.toLowerCase().endsWith('.rpy') &&
              (gameRoot.isEmpty || entry.key.startsWith('$gameRoot/')),
        )
        .toList();
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

  static RenPyScreenSize? _screenSize(
    Map<String, Uint8List> assets,
    String gameRoot,
  ) {
    final scriptSources = <String>[];
    final scripts =
        assets.entries
            .where(
              (entry) =>
                  entry.key.toLowerCase().endsWith('.rpy') &&
                  (gameRoot.isEmpty || entry.key.startsWith('$gameRoot/')),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    for (final script in scripts) {
      scriptSources.add(utf8.decode(script.value, allowMalformed: true));
    }

    return _screenSizeFromSources(scriptSources);
  }
}

RenPyScreenSize? _screenSizeFromSources(Iterable<String> sources) {
  int? width;
  int? height;
  final pattern = RegExp(r'config\.screen_(width|height)\s*=\s*(\d+)');
  for (final source in sources) {
    for (final match in pattern.allMatches(source)) {
      final value = int.parse(match.group(2)!);
      if (match.group(1) == 'width') width = value;
      if (match.group(1) == 'height') height = value;
    }
  }

  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return RenPyScreenSize(width: width, height: height);
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
