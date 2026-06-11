import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:renpy_parser/renpy_parser.dart';

import 'fly_archive.dart';
import 'fly_migrator.dart';
import 'fly_stream_manifest.dart';

/// The outcome of [buildStreamableDirectory]: where the tree was written,
/// its manifest, and the fidelity report of an `.rpy` migration if one
/// happened.
final class FlyStreamResult {
  const FlyStreamResult({
    required this.outputDir,
    required this.manifest,
    required this.totalBytes,
    this.migratedFrom,
    this.migrationReport,
  });

  /// The output directory the streamable tree was written into.
  final String outputDir;

  /// The manifest that was written to [FlyStreamManifest.fileName] at the
  /// root of [outputDir].
  final FlyStreamManifest manifest;

  /// Total size in bytes of the game files listed in [manifest] (the
  /// manifest file itself is not counted).
  final int totalBytes;

  /// The original `.rpy` script path when the input script was migrated to
  /// `.fly`, e.g. `game/script.rpy`; null when the input was already `.fly`.
  final String? migratedFrom;

  /// The fidelity report of the `.rpy` -> `.fly` migration; null when no
  /// migration was needed.
  final FlyMigrationReport? migrationReport;

  /// Archive-relative path of the streamable `.fly` script.
  String get scriptPath => manifest.script;

  /// The number of game files written (excluding the manifest).
  int get fileCount => manifest.files.length;
}

/// Unpacks or copies a game from [input] into [outputDir] as a streamable
/// directory: the `game/` tree plus a [FlyStreamManifest.fileName] manifest
/// at the root. This is the testable core of `bin/fly_stream.dart`.
///
/// [input] is either a `.fly.zip` / `.zip` file or a game directory. A
/// directory that contains a `game/` subtree is copied as-is (paths taken
/// relative to it); otherwise the directory itself is treated as the game
/// directory and its contents are placed under `game/`. A stale
/// [FlyStreamManifest.fileName] at the input root is ignored and
/// regenerated.
///
/// When the selected script is `.rpy` it is migrated: parsed, converted with
/// [runRpyToFlyGate] to `<same path minus .rpy>.fly`, and the `.rpy` file is
/// not copied. The gate's fidelity report is returned in
/// [FlyStreamResult.migrationReport].
///
/// The manifest [name] defaults to the input's base name (with a trailing
/// `.fly.zip` / `.zip` stripped) and its `sizes` map records each written
/// file's byte length so players can budget downloads. A non-empty
/// [outputDir] is refused unless [force] is true, in which case its previous
/// contents are deleted.
///
/// Throws [FlyArchiveException] when the input does not exist or is invalid,
/// the single-script rule is violated, an `.rpy` script does not parse, or
/// the output directory is non-empty without [force].
Future<FlyStreamResult> buildStreamableDirectory({
  required String input,
  required String outputDir,
  String? name,
  bool force = false,
}) async {
  final entries = _collectInputEntries(input);

  // Select the script and migrate it to .fly when needed.
  final selection = FlyArchive.selectScript([for (final e in entries) e.path]);
  String? migratedFrom;
  FlyMigrationReport? migrationReport;
  if (selection.path.endsWith('.rpy')) {
    final script = entries.firstWhere((e) => e.path == selection.path);
    final String source;
    try {
      source = utf8.decode(script.bytes);
    } on FormatException catch (e) {
      throw FlyArchiveException(
        'script ${selection.path} is not valid UTF-8: ${e.message}',
      );
    }
    final FlyMigrationResult gate;
    try {
      gate = runRpyToFlyGate(source, filename: selection.path);
    } on RenPyParseError catch (e) {
      throw FlyArchiveException(
        'script ${selection.path} does not parse as .rpy and cannot be '
        'migrated to .fly: $e',
      );
    }
    migratedFrom = selection.path;
    migrationReport = gate.report;
    final flyPath =
        '${selection.path.substring(0, selection.path.length - '.rpy'.length)}'
        '.fly';
    entries
      ..removeWhere((e) => e.path == selection.path)
      ..add(FlyArchiveFile(flyPath, utf8.encode(gate.output)));
  }

  final manifest = FlyStreamManifest.fromFiles(
    [for (final e in entries) e.path],
    name: name ?? _defaultName(input),
    sizes: {for (final e in entries) e.path: e.bytes.length},
  );

  // Write the output tree.
  final outDir = Directory(outputDir);
  if (outDir.existsSync() && outDir.listSync(followLinks: false).isNotEmpty) {
    if (!force) {
      throw FlyArchiveException(
        'output directory "$outputDir" is not empty (use --force to '
        'overwrite it)',
      );
    }
    outDir.deleteSync(recursive: true);
  }
  outDir.createSync(recursive: true);
  var totalBytes = 0;
  for (final entry in entries) {
    totalBytes += entry.bytes.length;
    File('${outDir.path}/${entry.path}')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(entry.bytes);
  }
  File('${outDir.path}/${FlyStreamManifest.fileName}')
      .writeAsStringSync('${manifest.encode()}\n');

  return FlyStreamResult(
    outputDir: outDir.path,
    manifest: manifest,
    totalBytes: totalBytes,
    migratedFrom: migratedFrom,
    migrationReport: migrationReport,
  );
}

/// Reads [input] (zip file or game directory) into archive-style entries
/// with safe, forward-slash, archive-relative paths.
List<FlyArchiveFile> _collectInputEntries(String input) {
  if (FileSystemEntity.isFileSync(input)) {
    final Uint8List bytes;
    try {
      bytes = File(input).readAsBytesSync();
    } on FileSystemException catch (e) {
      throw FlyArchiveException('cannot read input "$input": ${e.message}');
    }
    // FlyArchive.decode validates zip-ness, path safety, and the
    // single-script rule.
    return List.of(FlyArchive.decode(bytes).files);
  }

  final dir = Directory(input);
  if (!dir.existsSync()) {
    throw FlyArchiveException(
      'input "$input" does not exist (expected a .fly.zip file or a game '
      'directory)',
    );
  }
  final root = dir.path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final hasGameSubtree = Directory('$root/game').existsSync();

  final entries = <FlyArchiveFile>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    var relative = entity.path.replaceAll('\\', '/');
    if (relative.startsWith('$root/')) {
      relative = relative.substring(root.length + 1);
    }
    // A stale manifest at the input root is regenerated, not copied.
    if (relative == FlyStreamManifest.fileName) continue;
    final path = hasGameSubtree ? relative : 'game/$relative';
    entries.add(FlyArchiveFile(
      FlyArchive.safePath(path),
      entity.readAsBytesSync(),
    ));
  }
  return entries;
}

/// The manifest display name derived from [input]: its base name with a
/// trailing `.fly.zip` or `.zip` stripped.
String _defaultName(String input) {
  final normalized =
      input.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  var base = normalized.substring(normalized.lastIndexOf('/') + 1);
  for (final suffix in ['.fly.zip', '.zip']) {
    if (base.toLowerCase().endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
      break;
    }
  }
  return base;
}
