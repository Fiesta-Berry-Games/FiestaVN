/// Builds a streamable RenFly game directory from a `.fly.zip` archive or a
/// game directory: unpacks/copies the `game/` tree, migrates `.rpy` scripts
/// to `.fly` (with a fidelity report), and writes `fly_manifest.json`.
///
/// Usage: `dart run renpy_writer:fly_stream <input> <output-dir>`.
library;

import 'dart:io';

import 'package:renpy_writer/renpy_writer.dart';

const String _usage = '''
Usage: dart run renpy_writer:fly_stream <input> <output-dir> [options]

Builds a streamable game directory: the unpacked game/ tree plus a
${FlyStreamManifest.fileName} manifest at its root, ready to serve over HTTP.
Only .fly scripts may stream; a .rpy script is migrated to .fly and a
migration fidelity report is printed.

<input>       a .fly.zip / .zip archive, or a game directory (one containing
              a game/ subtree, or the game directory itself)
<output-dir>  directory to write the streamable tree into

Options:
  --name <name>  display name stored in the manifest
                 (default: the input's base name)
  --force        overwrite a non-empty output directory
  -h, --help     show this help
''';

Future<void> main(List<String> args) async {
  String? name;
  var force = false;
  final positional = <String>[];

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      stdout.write(_usage);
      return;
    } else if (arg == '--force') {
      force = true;
    } else if (arg == '--name') {
      if (i + 1 >= args.length) {
        _usageError('--name requires a value');
        return;
      }
      name = args[++i];
    } else if (arg.startsWith('--name=')) {
      name = arg.substring('--name='.length);
    } else if (arg.startsWith('-')) {
      _usageError('unknown option "$arg"');
      return;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length != 2) {
    _usageError('expected exactly <input> and <output-dir>');
    return;
  }

  final FlyStreamResult result;
  try {
    result = await buildStreamableDirectory(
      input: positional[0],
      outputDir: positional[1],
      name: name,
      force: force,
    );
  } on FlyArchiveException catch (e) {
    stderr.writeln('Error: ${e.message}');
    exitCode = 1;
    return;
  }

  if (result.migrationReport case final report?) {
    stdout
      ..writeln('Migrated ${result.migratedFrom} -> ${result.scriptPath}')
      ..writeln('Migration fidelity: $report');
    for (final issue in report.issues) {
      stdout.writeln('  $issue');
    }
  }
  stdout
    ..writeln(
      'Wrote ${result.fileCount} game file(s), ${result.totalBytes} bytes, '
      'to ${result.outputDir}',
    )
    ..writeln('Script:   ${result.scriptPath}')
    ..writeln(
      'Manifest: ${result.outputDir}/${FlyStreamManifest.fileName}',
    );
}

void _usageError(String message) {
  stderr
    ..writeln('Error: $message')
    ..writeln()
    ..write(_usage);
  exitCode = 64; // EX_USAGE
}
