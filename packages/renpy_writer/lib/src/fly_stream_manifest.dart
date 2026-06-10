import 'dart:convert';

import 'fly_archive.dart';

/// The `fly_manifest.json` manifest of a streamable RenFly game directory.
///
/// A streamable directory is the unzipped form of a `.fly.zip` archive: a
/// plain `game/` tree (`game/script.fly`, `game/images/...`, and so on)
/// served over HTTP, with this manifest at its root so a player can discover
/// every file without relying on directory listings.
///
/// Only `.fly` scripts may stream: `.rpy` games must be migrated to `.fly`
/// first (e.g. with `dart run renpy_writer:fly_stream`). This is a product
/// decision and is enforced by every constructor of this class.
///
/// Wire shape (pretty-printed JSON; `name` is omitted when null):
///
/// ```json
/// {
///   "version": 1,
///   "name": "My Game",
///   "script": "game/script.fly",
///   "files": ["game/images/bg.png", "game/script.fly"]
/// }
/// ```
final class FlyStreamManifest {
  /// Creates a manifest and validates it exhaustively.
  ///
  /// Throws [FlyArchiveException] when [script] does not end in `.fly`
  /// (`.rpy` games must be migrated first), when [script] is not listed in
  /// [files], when any path is unsafe per [FlyArchive.safePath] or uses
  /// backslashes, or when [files] contains duplicates.
  FlyStreamManifest({
    this.name,
    required this.script,
    required List<String> files,
  }) : files = List.unmodifiable(files) {
    final seen = <String>{};
    for (final path in this.files) {
      if (path.contains('\\')) {
        throw FlyArchiveException(
          'manifest path "$path" must use forward slashes',
        );
      }
      FlyArchive.safePath(path);
      if (!seen.add(path)) {
        throw FlyArchiveException('duplicate manifest path "$path"');
      }
    }
    FlyArchive.safePath(script);
    if (!script.endsWith('.fly')) {
      throw FlyArchiveException(
        'script "$script" is not a .fly document: only .fly scripts can be '
        'streamed; .rpy games must be migrated to .fly before streaming '
        '(e.g. with `dart run renpy_writer:fly_stream`)',
      );
    }
    if (!seen.contains(script)) {
      throw FlyArchiveException(
        'script "$script" is not listed in the manifest "files" list',
      );
    }
  }

  /// The manifest's file name at the root of a streamable directory.
  static const String fileName = 'fly_manifest.json';

  /// The current manifest `"version"`.
  static const int formatVersion = 1;

  /// Optional human-readable display name of the game.
  final String? name;

  /// Archive-relative path of the `.fly` script, e.g. `game/script.fly`.
  final String script;

  /// All archive-relative file paths of the game tree, including [script],
  /// with forward slashes. Does not include the manifest itself.
  final List<String> files;

  /// Encodes this manifest to pretty-printed `fly_manifest.json` text.
  String encode() {
    return const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'version': formatVersion,
      if (name case final name?) 'name': name,
      'script': script,
      'files': files,
    });
  }

  /// Decodes and validates a `fly_manifest.json` document from [json].
  ///
  /// Throws [FlyArchiveException] when the text is not a JSON object, the
  /// `"version"` is present but not [formatVersion] (a missing version is
  /// accepted), `"script"` or `"files"` is missing or of the wrong type, the
  /// script is a `.rpy` script (which must be migrated to `.fly` before
  /// streaming), the script is not listed in `"files"`, or any path is
  /// unsafe (same zip-slip rules as [FlyArchive.safePath]).
  static FlyStreamManifest decode(String json) {
    final Object? document;
    try {
      document = jsonDecode(json);
    } on FormatException catch (e) {
      throw FlyArchiveException('$fileName is not valid JSON: ${e.message}');
    }
    if (document is! Map<String, Object?>) {
      throw FlyArchiveException('$fileName must be a JSON object');
    }

    final version = document['version'];
    if (version != null && version != formatVersion) {
      throw FlyArchiveException(
        'unsupported $fileName "version" $version '
        '(expected $formatVersion)',
      );
    }

    final script = document['script'];
    if (script == null) {
      throw FlyArchiveException('$fileName is missing the "script" key');
    }
    if (script is! String || script.isEmpty) {
      throw FlyArchiveException(
        '$fileName "script" must be a non-empty string path',
      );
    }

    final name = document['name'];
    if (name != null && name is! String) {
      throw FlyArchiveException('$fileName "name" must be a string');
    }

    final filesValue = document['files'];
    if (filesValue is! List<Object?>) {
      throw FlyArchiveException('$fileName "files" must be a list of paths');
    }
    final files = <String>[];
    for (final entry in filesValue) {
      if (entry is! String) {
        throw FlyArchiveException(
          '$fileName "files" must contain only string paths, '
          'found ${jsonEncode(entry)}',
        );
      }
      files.add(entry);
    }

    return FlyStreamManifest(
      name: name as String?,
      script: script,
      files: files,
    );
  }

  /// Builds a manifest for the game tree described by [paths], selecting the
  /// script with the same single-script rule as [FlyArchive.selectScript]
  /// (`.fly` beats `.rpy`; among multiple candidates of the winning kind,
  /// `game/script.<ext>` is preferred). The stored [files] list is sorted.
  ///
  /// Throws [FlyArchiveException] when no script exists, the choice is
  /// ambiguous, the selected script is `.rpy` (which must be migrated to
  /// `.fly` before streaming), or any path is unsafe.
  static FlyStreamManifest fromFiles(Iterable<String> paths, {String? name}) {
    final normalized = [for (final path in paths) FlyArchive.safePath(path)];
    final selection = FlyArchive.selectScript(normalized);
    return FlyStreamManifest(
      name: name,
      script: selection.path,
      files: normalized..sort(),
    );
  }
}
