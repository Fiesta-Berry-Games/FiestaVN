import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:renpy_parser/renpy_parser.dart';

import 'fly_codec.dart';
import 'renpy_emitter.dart';

/// Thrown when a `.fly.zip` archive or a streamable game directory (see
/// `FlyStreamManifest`) is structurally invalid: not a zip, unsafe entry
/// paths, no script, an ambiguous script, or a script that is not valid
/// UTF-8 / does not parse.
class FlyArchiveException implements Exception {
  FlyArchiveException(this.message);

  /// Human-readable description of what is wrong.
  final String message;

  @override
  String toString() => 'FlyArchiveException: $message';
}

/// One entry of a `.fly.zip` archive.
class FlyArchiveFile {
  const FlyArchiveFile(this.path, this.bytes);

  /// Archive-relative path with forward slashes, e.g. `game/images/bg.png`.
  final String path;

  /// The entry's raw content.
  final Uint8List bytes;
}

/// A decoded `.fly.zip` archive: a standard ZIP of a full RenFly game
/// directory for one-file distribution (see `doc/fly_archive.md`).
///
/// The layout mirrors a classic Ren'Py project (`game/script.fly` or
/// `game/script.rpy`, plus `game/images/...`, `game/audio/...`, and so on).
/// Exactly one script file must exist in the `game/` tree; when both `.fly`
/// and `.rpy` scripts are present the `.fly` one wins and the `.rpy` ones are
/// recorded in [notes].
class FlyArchive {
  FlyArchive._({
    required this.scriptPath,
    required this.scriptSource,
    required this.scriptIsFly,
    required this.files,
    required this.notes,
  });

  /// Archive path of the chosen script, e.g. `game/script.fly`.
  final String scriptPath;

  /// The script's decoded UTF-8 text. When [scriptIsFly] is true this is the
  /// stored .fly JSON text, *not* converted; use [scriptAsRpy] to convert.
  final String scriptSource;

  /// Whether the stored script is a `.fly` document (as opposed to `.rpy`).
  final bool scriptIsFly;

  /// All file entries of the archive, including the script itself.
  final List<FlyArchiveFile> files;

  /// Human-readable remarks gathered while decoding, e.g.
  /// `ignored game/script.rpy because game/script.fly is present`.
  final List<String> notes;

  /// Decodes and validates a `.fly.zip` from [zipBytes].
  ///
  /// Throws [FlyArchiveException] when the bytes are not a valid zip, an
  /// entry path is unsafe (absolute or containing `..` segments), the
  /// single-script rule is violated, or the script is not valid UTF-8.
  static FlyArchive decode(Uint8List zipBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } on Object catch (e) {
      throw FlyArchiveException('not a valid zip archive: $e');
    }

    final files = <FlyArchiveFile>[];
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final path = safePath(entry.name);
      files.add(FlyArchiveFile(path, entry.readBytes() ?? Uint8List(0)));
    }

    final selection = selectScript([for (final f in files) f.path]);
    final script = files.firstWhere((f) => f.path == selection.path);
    final String scriptSource;
    try {
      scriptSource = utf8.decode(script.bytes);
    } on FormatException catch (e) {
      throw FlyArchiveException(
        'script ${selection.path} is not valid UTF-8: ${e.message}',
      );
    }

    return FlyArchive._(
      scriptPath: selection.path,
      scriptSource: scriptSource,
      scriptIsFly: selection.path.endsWith('.fly'),
      files: files,
      notes: selection.notes,
    );
  }

  /// The script as `.rpy` text regardless of stored form.
  ///
  /// For a `.rpy` script this is [scriptSource] verbatim; for a `.fly`
  /// script the JSON is decoded with [FlyCodec] and emitted with
  /// [RenPyEmitter]. Throws [FlyFormatException] when a stored `.fly`
  /// document is invalid.
  String scriptAsRpy() {
    if (!scriptIsFly) return scriptSource;
    final script =
        const FlyCodec().decodeFromString(scriptSource, filename: scriptPath);
    return const RenPyEmitter().emitScript(script);
  }

  /// Builds a `.fly.zip` from [files].
  ///
  /// Validates entry-path safety, uniqueness, and the single-script rule.
  /// Throws [FlyArchiveException] on violation.
  static Uint8List encode(List<FlyArchiveFile> files) {
    final archive = Archive();
    final paths = <String>{};
    for (final file in files) {
      final path = safePath(file.path);
      if (!paths.add(path)) {
        throw FlyArchiveException('duplicate entry path "$path"');
      }
      archive.add(ArchiveFile.bytes(path, file.bytes));
    }
    selectScript(paths);
    return ZipEncoder().encodeBytes(archive);
  }

  /// Convenience: builds a `.fly.zip` from a `.rpy` script plus [assets].
  ///
  /// [scriptSource] is `.rpy` text. When [storeAsFly] is true (the default)
  /// it is parsed and stored as `game/script.fly` via [FlyCodec]; otherwise
  /// it is stored verbatim as `game/script.rpy`. Asset paths are taken
  /// relative to `game/` (e.g. `images/bg.png`); paths that already start
  /// with `game/` are kept as-is.
  ///
  /// Throws [FlyArchiveException] when [storeAsFly] is true and
  /// [scriptSource] does not parse as a Ren'Py script.
  static Uint8List fromScript({
    required String scriptSource,
    bool storeAsFly = true,
    List<FlyArchiveFile> assets = const [],
  }) {
    final FlyArchiveFile script;
    if (storeAsFly) {
      final RenPyScript parsed;
      try {
        parsed = RenPyParser().parse(scriptSource, 'script.rpy').script;
      } on RenPyParseError catch (e) {
        throw FlyArchiveException('script does not parse as .rpy: $e');
      }
      final flyText = const FlyCodec().encodeToString(parsed);
      script = FlyArchiveFile('game/script.fly', utf8.encode(flyText));
    } else {
      script = FlyArchiveFile('game/script.rpy', utf8.encode(scriptSource));
    }
    return encode([
      script,
      for (final asset in assets)
        asset.path.startsWith('game/')
            ? asset
            : FlyArchiveFile('game/${asset.path}', asset.bytes),
    ]);
  }

  /// Normalizes [path] to forward slashes and rejects unsafe entries
  /// (zip-slip protection): absolute paths, drive-letter paths, and paths
  /// containing `..` segments.
  ///
  /// These are the entry-path rules shared by `.fly.zip` archives and
  /// streamable game directories (`FlyStreamManifest`). Throws
  /// [FlyArchiveException] on violation; returns the normalized path.
  static String safePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    if (normalized.isEmpty) {
      throw FlyArchiveException('empty entry path');
    }
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      throw FlyArchiveException('absolute entry path "$path" is not allowed');
    }
    if (normalized.split('/').contains('..')) {
      throw FlyArchiveException(
        'entry path "$path" contains a ".." segment, which is not allowed',
      );
    }
    return normalized;
  }

  /// Applies the single-script rule to [paths]: exactly one `game/**.fly`
  /// or `game/**.rpy` script must be loadable. `.fly` beats `.rpy`; among
  /// multiple candidates of the winning kind, `game/script.<ext>` is
  /// preferred. Throws [FlyArchiveException] when no script exists or the
  /// choice is ambiguous.
  ///
  /// This is the selection rule shared by `.fly.zip` archives and streamable
  /// game directories (`FlyStreamManifest`).
  static FlyScriptSelection selectScript(Iterable<String> paths) {
    final fly = <String>[];
    final rpy = <String>[];
    for (final path in paths) {
      if (!path.startsWith('game/')) continue;
      if (path.endsWith('.fly')) fly.add(path);
      if (path.endsWith('.rpy')) rpy.add(path);
    }

    final List<String> candidates;
    final String extension;
    if (fly.isNotEmpty) {
      candidates = fly;
      extension = 'fly';
    } else if (rpy.isNotEmpty) {
      candidates = rpy;
      extension = 'rpy';
    } else {
      throw FlyArchiveException(
        'no script found: expected exactly one game/**.fly or game/**.rpy '
        'entry',
      );
    }

    final String chosen;
    if (candidates.length == 1) {
      chosen = candidates.single;
    } else {
      final preferred = 'game/script.$extension';
      if (!candidates.contains(preferred)) {
        throw FlyArchiveException(
          'multiple .$extension scripts found '
          '(${(candidates..sort()).join(', ')}) and none is "$preferred"',
        );
      }
      chosen = preferred;
    }

    final notes = <String>[
      for (final path in candidates)
        if (path != chosen) 'ignored $path because $chosen is preferred',
      if (extension == 'fly')
        for (final path in rpy..sort())
          'ignored $path because $chosen is present',
    ];
    return FlyScriptSelection(chosen, notes);
  }
}

/// The outcome of the single-script rule ([FlyArchive.selectScript]): the
/// chosen script [path] and any [notes] about ignored candidates.
class FlyScriptSelection {
  FlyScriptSelection(this.path, this.notes);

  /// The chosen script path, e.g. `game/script.fly`.
  final String path;

  /// Human-readable remarks about ignored script candidates.
  final List<String> notes;
}
