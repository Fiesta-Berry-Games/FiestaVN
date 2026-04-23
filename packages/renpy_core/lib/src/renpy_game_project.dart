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

/// A Ren'Py GUI background value that can be rendered behind dialogue.
sealed class RenPyGuiBackground {
  const RenPyGuiBackground({required this.asset});

  final String asset;
}

/// A plain Ren'Py GUI image background.
final class RenPyGuiImageBackground extends RenPyGuiBackground {
  const RenPyGuiImageBackground(String asset) : super(asset: asset);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyGuiImageBackground && asset == other.asset;
  }

  @override
  int get hashCode => Object.hash(RenPyGuiImageBackground, asset);

  @override
  String toString() => 'RenPyGuiImageBackground(asset: $asset)';
}

/// A Ren'Py Frame background with fixed image-border regions.
final class RenPyGuiFrameBackground extends RenPyGuiBackground {
  const RenPyGuiFrameBackground({
    required super.asset,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyGuiFrameBackground &&
            asset == other.asset &&
            left == other.left &&
            top == other.top &&
            right == other.right &&
            bottom == other.bottom;
  }

  @override
  int get hashCode =>
      Object.hash(RenPyGuiFrameBackground, asset, left, top, right, bottom);

  @override
  String toString() {
    return 'RenPyGuiFrameBackground('
        'asset: $asset, '
        'left: $left, '
        'top: $top, '
        'right: $right, '
        'bottom: $bottom)';
  }
}

/// Ren'Py GUI configuration values that affect default presentation.
final class RenPyGuiConfiguration {
  const RenPyGuiConfiguration({
    this.dialogueTextFont,
    this.dialogueTextSize,
    this.dialogueTextColor,
    this.dialogueTextOutlineColor,
    this.textboxHeight,
    this.textboxYAlign,
    this.textboxBackground,
    this.windowYMinimum,
    this.windowYAlign,
    this.windowXPadding,
    this.windowYPadding,
    this.dialogueXPos,
    this.dialogueYPos,
    this.dialogueWidth,
  });

  final String? dialogueTextFont;
  final double? dialogueTextSize;
  final String? dialogueTextColor;
  final String? dialogueTextOutlineColor;
  final double? textboxHeight;
  final double? textboxYAlign;
  final RenPyGuiBackground? textboxBackground;
  final double? windowYMinimum;
  final double? windowYAlign;
  final double? windowXPadding;
  final double? windowYPadding;
  final double? dialogueXPos;
  final double? dialogueYPos;
  final double? dialogueWidth;

  String? get textboxAsset => textboxBackground?.asset;

  static const empty = RenPyGuiConfiguration();

  static RenPyGuiConfiguration fromScriptSources(Iterable<String> sources) {
    String? dialogueTextFont;
    double? dialogueTextSize;
    String? dialogueTextColor;
    String? dialogueTextOutlineColor;
    double? textboxHeight;
    double? textboxYAlign;
    RenPyGuiBackground? textboxBackground;
    double? windowYMinimum;
    double? windowYAlign;
    double? windowXPadding;
    double? windowYPadding;
    double? dialogueXPos;
    var textboxBackgroundFromGui = false;
    double? dialogueYPos;
    double? dialogueWidth;

    for (final source in sources) {
      for (final match in _guiDefinePattern.allMatches(source)) {
        final name = match.group(1)!;
        final expression = match.group(2)!.trim();
        switch (name) {
          case 'text_font':
            dialogueTextFont = _renpyStringLiteral(expression);
          case 'text_size':
            dialogueTextSize = double.tryParse(expression);
          case 'text_color':
            dialogueTextColor = _renpyStringLiteral(expression);
          case 'dialogue_text_outlines':
            dialogueTextOutlineColor = _renpyFirstQuotedColor(expression);
          case 'textbox_height':
            textboxHeight = _renpyNumberLiteral(expression);
          case 'textbox_yalign':
            textboxYAlign = _renpyNumberLiteral(expression);
          case 'textbox':
            textboxBackground = _renpyImageBackground(expression);
            textboxBackgroundFromGui = textboxBackground != null;
          case 'dialogue_xpos':
            dialogueXPos = _renpyNumberLiteral(expression);
          case 'dialogue_ypos':
            dialogueYPos = _renpyNumberLiteral(expression);
          case 'dialogue_width':
            dialogueWidth = _renpyNumberLiteral(expression);
        }
      }
      final windowStyle = _renpyWindowStyle(source);
      if (!textboxBackgroundFromGui && textboxBackground == null) {
        textboxBackground = windowStyle.background;
      }
      windowYMinimum ??= windowStyle.yMinimum;
      windowYAlign ??= windowStyle.yAlign;
      windowXPadding ??= windowStyle.xPadding;
      windowYPadding ??= windowStyle.yPadding;
    }

    return RenPyGuiConfiguration(
      dialogueTextFont: dialogueTextFont,
      dialogueTextSize: dialogueTextSize,
      dialogueTextColor: dialogueTextColor,
      dialogueTextOutlineColor: dialogueTextOutlineColor,
      textboxHeight: textboxHeight,
      textboxYAlign: textboxYAlign,
      textboxBackground: textboxBackground,
      windowYMinimum: windowYMinimum,
      windowYAlign: windowYAlign,
      windowXPadding: windowXPadding,
      windowYPadding: windowYPadding,
      dialogueXPos: dialogueXPos,
      dialogueYPos: dialogueYPos,
      dialogueWidth: dialogueWidth,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RenPyGuiConfiguration &&
            dialogueTextFont == other.dialogueTextFont &&
            dialogueTextSize == other.dialogueTextSize &&
            dialogueTextColor == other.dialogueTextColor &&
            dialogueTextOutlineColor == other.dialogueTextOutlineColor &&
            textboxHeight == other.textboxHeight &&
            textboxYAlign == other.textboxYAlign &&
            textboxBackground == other.textboxBackground &&
            windowYMinimum == other.windowYMinimum &&
            windowYAlign == other.windowYAlign &&
            windowXPadding == other.windowXPadding &&
            windowYPadding == other.windowYPadding &&
            dialogueXPos == other.dialogueXPos &&
            dialogueYPos == other.dialogueYPos &&
            dialogueWidth == other.dialogueWidth;
  }

  @override
  int get hashCode => Object.hash(
    dialogueTextFont,
    dialogueTextSize,
    dialogueTextColor,
    dialogueTextOutlineColor,
    textboxHeight,
    textboxYAlign,
    textboxBackground,
    windowYMinimum,
    windowYAlign,
    windowXPadding,
    windowYPadding,
    dialogueXPos,
    dialogueYPos,
    dialogueWidth,
  );
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
    required this.gui,
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
      gui: _guiConfiguration(byPath, selectedScriptPath, normalizedGameRoot),
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
  final RenPyGuiConfiguration gui;
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
    final scripts = _sortedScriptFiles(assets, selectedScriptPath, gameRoot);

    return scripts
        .map((script) => utf8.decode(script.value, allowMalformed: true))
        .join('\n\n');
  }

  static List<MapEntry<String, Uint8List>> _sortedScriptFiles(
    Map<String, Uint8List> assets,
    String selectedScriptPath,
    String gameRoot,
  ) {
    final scripts = _scriptFiles(assets, gameRoot);
    if (scripts.length <= 1) return scripts;

    scripts.sort((a, b) {
      if (a.key == selectedScriptPath) return -1;
      if (b.key == selectedScriptPath) return 1;
      return a.key.compareTo(b.key);
    });
    return scripts;
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

  static RenPyGuiConfiguration _guiConfiguration(
    Map<String, Uint8List> assets,
    String selectedScriptPath,
    String gameRoot,
  ) {
    return RenPyGuiConfiguration.fromScriptSources(
      _sortedScriptFiles(
        assets,
        selectedScriptPath,
        gameRoot,
      ).map((script) => utf8.decode(script.value, allowMalformed: true)),
    );
  }
}

final class _RenPyWindowStyle {
  const _RenPyWindowStyle({
    this.background,
    this.yMinimum,
    this.yAlign,
    this.xPadding,
    this.yPadding,
  });

  final RenPyGuiBackground? background;
  final double? yMinimum;
  final double? yAlign;
  final double? xPadding;
  final double? yPadding;
}

_RenPyWindowStyle _renpyWindowStyle(String source) {
  final lines = const LineSplitter().convert(source);
  RenPyGuiBackground? background;
  double? yMinimum;
  double? yAlign;
  double? xPadding;
  double? yPadding;

  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed != 'style window:') continue;

    final blockIndent = line.length - trimmed.length;
    for (var j = i + 1; j < lines.length; j += 1) {
      final childLine = lines[j];
      final childTrimmed = childLine.trimLeft();
      if (childTrimmed.isEmpty || childTrimmed.startsWith('#')) continue;

      final childIndent = childLine.length - childTrimmed.length;
      if (childIndent <= blockIndent) break;

      final parsedBackground = _renpyBackground(childTrimmed);
      if (parsedBackground != null) {
        background ??= parsedBackground;
        continue;
      }

      final property = _renpyStyleProperty(childTrimmed);
      switch (property?.name) {
        case 'yminimum':
          yMinimum ??= _renpyNumberLiteral(property!.value);
        case 'yalign':
          yAlign ??= _renpyNumberLiteral(property!.value);
        case 'xpadding':
          xPadding ??= _renpyNumberLiteral(property!.value);
        case 'ypadding':
          yPadding ??= _renpyNumberLiteral(property!.value);
      }
    }
  }

  return _RenPyWindowStyle(
    background: background,
    yMinimum: yMinimum,
    yAlign: yAlign,
    xPadding: xPadding,
    yPadding: yPadding,
  );
}

RenPyGuiBackground? _renpyBackground(String line) {
  const keyword = 'background';
  if (line != keyword && !line.startsWith('$keyword ')) return null;

  final expression = line.substring(keyword.length).trim();
  return _renpyImageBackground(expression) ??
      _renpyDisplayableBackground(expression);
}

RenPyGuiImageBackground? _renpyImageBackground(String expression) {
  final asset = _renpyStringLiteral(expression);
  return asset == null ? null : RenPyGuiImageBackground(asset);
}

RenPyGuiBackground? _renpyDisplayableBackground(String expression) {
  final trimmed = expression.trim();
  return _renpyFrameBackground(trimmed) ?? _renpyImageDisplayable(trimmed);
}

RenPyGuiFrameBackground? _renpyFrameBackground(String expression) {
  final match = RegExp(
    r'''^Frame\(\s*(["'])(.*?)\1\s*(?:,\s*(.*?))?\s*\)$''',
  ).firstMatch(expression);
  if (match == null) return null;

  final args = _renpyArgumentList(match.group(3) ?? '');
  if (args.length < 2) return null;

  final left = _renpyNumberLiteral(args[0]);
  final top = _renpyNumberLiteral(args[1]);
  final right = args.length >= 4 ? _renpyNumberLiteral(args[2]) : left;
  final bottom = args.length >= 4 ? _renpyNumberLiteral(args[3]) : top;
  if (left == null || top == null || right == null || bottom == null) {
    return null;
  }

  return RenPyGuiFrameBackground(
    asset: match.group(2)!,
    left: left,
    top: top,
    right: right,
    bottom: bottom,
  );
}

RenPyGuiImageBackground? _renpyImageDisplayable(String expression) {
  final match = RegExp(r'''^Image\(\s*(["'])(.*?)\1''').firstMatch(expression);
  return match == null ? null : RenPyGuiImageBackground(match.group(2)!);
}

List<String> _renpyArgumentList(String expression) {
  if (expression.trim().isEmpty) return const [];
  return expression.split(',').map((argument) => argument.trim()).toList();
}

({String name, String value})? _renpyStyleProperty(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty || trimmed.startsWith('#')) return null;

  final separator = trimmed.indexOf(RegExp(r'\s+'));
  if (separator <= 0) return null;

  final name = trimmed.substring(0, separator);
  final value = trimmed.substring(separator).trim();
  if (value.isEmpty) return null;

  return (name: name, value: value);
}

RenPyScreenSize? _screenSizeFromSources(Iterable<String> sources) {
  int? width;
  int? height;
  final configPattern = RegExp(r'config\.screen_(width|height)\s*=\s*(\d+)');
  final guiInitPattern = RegExp(r'gui\.init\s*\(\s*(\d+)\s*,\s*(\d+)\s*\)');
  for (final source in sources) {
    for (final match in configPattern.allMatches(source)) {
      final value = int.parse(match.group(2)!);
      if (match.group(1) == 'width') width = value;
      if (match.group(1) == 'height') height = value;
    }

    final guiInit = guiInitPattern.firstMatch(source);
    if (guiInit != null) {
      width = int.parse(guiInit.group(1)!);
      height = int.parse(guiInit.group(2)!);
    }
  }

  if (width == null || height == null || width <= 0 || height <= 0) return null;
  return RenPyScreenSize(width: width, height: height);
}

final _guiDefinePattern = RegExp(
  r'''^\s*define\s+gui\.([a-zA-Z_]\w*)\s*=\s*(.+)$''',
  multiLine: true,
);

String? _renpyStringLiteral(String expression) {
  final trimmed = expression.trim();
  if (trimmed.length < 2) return null;
  final quote = trimmed[0];
  if (quote != '"' && quote != "'") return null;
  final end = trimmed.indexOf(quote, 1);
  if (end == -1) return null;
  return trimmed.substring(1, end);
}

String? _renpyFirstQuotedColor(String expression) {
  final match = RegExp(
    r'''["'](#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?(?:[0-9a-fA-F]{2})?)["']''',
  ).firstMatch(expression);

  return match?.group(1);
}

double? _renpyNumberLiteral(String expression) {
  return double.tryParse(expression.trim());
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
