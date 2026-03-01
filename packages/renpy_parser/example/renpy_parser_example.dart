import 'dart:io';
import 'package:renpy_parser/renpy_parser.dart';

/// Simple CLI example that parses a .rpy file and prints a short summary.
///
/// Run with:
///   dart run example/renpy_parser_example.dart <path-to-.rpy>
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run example/renpy_parser_example.dart <file.rpy>',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final file = File(args.first);
  if (!await file.exists()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final source = await file.readAsString();
  final parser = RenPyParser();
  final result = parser.parse(source, file.path);

  // Show any non-fatal warnings.
  if (result.warnings.isNotEmpty) {
    stdout.writeln('- Warnings -');
    result.warnings.forEach(stdout.writeln);
    stdout.writeln();
  }

  stdout.writeln('Parsed OK!');
  stdout.writeln('Top-level statements  : ${result.script.statements.length}');
  stdout.writeln(
    'Labels                : ${result.script.labels.keys.join(", ")}',
  );
  stdout.writeln(
    'Characters defined    : ${result.script.characters.keys.join(", ")}',
  );

  final images = result.script
      .findStatements<RenPyImageStatement>((_) => true)
      .map((i) => '${i.name}  ->  ${i.expression}')
      .join('\n');
  if (images.isNotEmpty) {
    stdout.writeln('\nImages found:\n$images');
  }
}
