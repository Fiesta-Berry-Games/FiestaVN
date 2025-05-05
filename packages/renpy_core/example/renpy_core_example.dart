import 'dart:io';

import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_core/renpy_core.dart';

/// CLI example demonstrating how to execute a RenPy script with [RenPyRunner].
///
/// It parses the supplied `.rpy` file, hooks up simple callbacks for dialogue,
/// images and menus, and drives the runner forward whenever the player presses
/// Enter.
///
/// ```bash
/// # From packages/renpy_core.
/// dart run example/renpy_core_example.dart ../../renpy_parser/test/scripts/001.rpy
/// ```
Future<void> main(List<String> args) async {
  // Validate input.
  if (args.isEmpty) {
    stderr.writeln(
      'Usage: dart run example/renpy_core_example.dart <file.rpy>',
    );
    exit(64); // EX_USAGE
  }

  final scriptFile = File(args.first);
  if (!await scriptFile.exists()) {
    stderr.writeln('File not found: ${scriptFile.path}');
    exit(66); // EX_NOINPUT.
  }

  // Parse the script.
  final source = await scriptFile.readAsString();
  final parser = RenPyParser();
  final parseResult = parser.parse(source, scriptFile.path);

  if (parseResult.warnings.isNotEmpty) {
    stdout.writeln('\u2500 Warnings \u2500');
    parseResult.warnings.forEach(stdout.writeln);
    stdout.writeln();
  }

  // Set up the runner & callbacks.
  final runner = RenPyRunner(parseResult.script);

  runner.onDialogue = (character, text) {
    if (character != null && character.isNotEmpty) {
      stdout.writeln('$character: $text');
    } else {
      stdout.writeln(text);
    }
  };

  runner.onImage = (scene, show, hide) {
    if (scene != null) stdout.writeln('[Scene] $scene');
    if (show != null) stdout.writeln('[Show ] $show');
    if (hide != null) stdout.writeln('[Hide ] $hide');
  };

  runner.onMenu = (choices, onChoice) {
    stdout.writeln('\n— Menu —');
    for (var i = 0; i < choices.length; i++) {
      stdout.writeln('  ${i + 1}. ${choices[i]}');
    }
    stdout.write('Select choice (default 1): ');
    final input = stdin.readLineSync();
    final index = int.tryParse(input ?? '') ?? 1;
    final safeIndex = index.clamp(1, choices.length) - 1;
    onChoice(safeIndex);
  };

  // Jump to the canonical entry point if it exists.
  if (parseResult.script.findLabel('start') != null) {
    runner.jumpToLabel('start');
  }

  // Run!  Advance on every <Enter> press.
  runner.run();

  while (runner.state != RenPyRunnerState.complete &&
      runner.state != RenPyRunnerState.error) {
    if (runner.state == RenPyRunnerState.waitingForInput) {
      stdout.write('[Press Enter]');
      stdin.readLineSync();
      runner.continueExecution();
    }
  }

  // Finished.
  if (runner.state == RenPyRunnerState.complete) {
    stdout.writeln('\n— End of script —');
  } else if (runner.state == RenPyRunnerState.error) {
    stderr.writeln('Error: ${runner.errorMessage}');
    exit(1);
  }
}
