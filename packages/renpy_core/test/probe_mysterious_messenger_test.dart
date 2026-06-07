import 'dart:io';

import 'package:renpy_core/renpy_core.dart';
import 'package:test/test.dart';

void main() {
  test('mysterious-messenger probe run', () {
    final gameDir =
        '/tmp/recon_wild_candidate/mysterious-messenger/game';
    final dir = Directory(gameDir);
    if (!dir.existsSync()) {
      markTestSkipped('mysterious-messenger not cloned');
      return;
    }

    final rpyFiles = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.rpy'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    // Parse all files
    final parser = RenPyParser();
    final allStatements = <RenPyStatement>[];
    final parseWarnings = <String>[];
    var parseFailed = 0;

    for (final file in rpyFiles) {
      final src = file.readAsStringSync();
      final relPath = file.path.substring(gameDir.length + 1);
      try {
        final result = parser.parse(src, relPath);
        allStatements.addAll(result.script.statements);
        parseWarnings.addAll(result.warnings);
      } catch (e) {
        parseFailed++;
        parseWarnings.add('FATAL PARSE: $relPath: $e');
      }
    }

    print('=== PARSE PHASE ===');
    print('Files: ${rpyFiles.length}');
    print('Parse failures: $parseFailed');
    print('Parse warnings: ${parseWarnings.length}');
    print('Total statements: ${allStatements.length}');

    // Count statement types
    final typeCounts = <String, int>{};
    for (final s in allStatements) {
      final t = s.runtimeType.toString();
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
    }
    final sortedTypes = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('\nStatement types:');
    for (final e in sortedTypes) {
      print('  ${e.key}: ${e.value}');
    }

    // Count generic statements (unparsed)
    final generics = allStatements
        .whereType<RenPyGenericStatement>()
        .toList();
    if (generics.isNotEmpty) {
      print('\nGeneric (unparsed) statements: ${generics.length}');
      final genericPrefixes = <String, int>{};
      for (final g in generics) {
        final text = g.text.trim();
        final prefix = text.split(RegExp(r'\s+')).first;
        genericPrefixes[prefix] = (genericPrefixes[prefix] ?? 0) + 1;
      }
      final sortedPrefixes = genericPrefixes.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      print('By leading keyword:');
      for (final e in sortedPrefixes) {
        print('  ${e.key}: ${e.value}');
      }
    }

    // Build a merged script and run
    final script = RenPyScript(allStatements);
    final runner = RenPyRunner(script);

    final diagnostics = <RenPyDiagnostic>[];
    final dialogueLines = <String>[];
    var menuCount = 0;
    var menuChoiceIndex = 0;

    runner.onDialogue = (character, text) {
      dialogueLines.add(text);
    };
    runner.onMenu = (choices, onChoice, caption) {
      menuCount++;
      final idx = menuChoiceIndex % choices.length;
      menuChoiceIndex++;
      onChoice(idx);
    };
    runner.onDiagnostic = (d) {
      diagnostics.add(d);
    };

    // Try to jump to start
    try {
      runner.jumpToLabel('start');
    } catch (e) {
      print('\nCannot jump to start: $e');
      // Try other common entry labels
      for (final label in ['main_menu', 'splashscreen', 'before_main_menu']) {
        try {
          runner.jumpToLabel(label);
          print('Jumped to $label instead');
          break;
        } catch (_) {}
      }
    }

    // Run with a step cap
    const maxSteps = 4000;
    var steps = 0;
    try {
      runner.run();
      while (runner.state == RenPyRunnerState.waitingForInput &&
          steps < maxSteps) {
        steps++;
        runner.continueExecution();
      }
    } catch (e) {
      print('\nRunner error: $e');
    }

    print('\n=== RUN PHASE ===');
    print('Steps: $steps');
    print('Dialogue lines: ${dialogueLines.length}');
    print('Menus encountered: $menuCount');
    print('Final state: ${runner.state}');
    print('Total diagnostics: ${diagnostics.length}');

    // Categorize diagnostics
    final diagCounts = <String, int>{};
    for (final d in diagnostics) {
      diagCounts[d.code.toString()] = (diagCounts[d.code.toString()] ?? 0) + 1;
    }
    final sortedDiags = diagCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    print('\nDiagnostics by code:');
    for (final e in sortedDiags) {
      print('  ${e.key}: ${e.value}');
    }

    // Show first 30 diagnostics for debugging
    print('\nFirst 30 diagnostics:');
    for (var i = 0; i < diagnostics.length && i < 30; i++) {
      final d = diagnostics[i];
      print('  [${d.code}] ${d.message} ${d.detail ?? ''}');
    }

    // Show unique skippedDefinition details
    final skippedDefs = diagnostics
        .where((d) =>
            d.code == RenPyDiagnosticCode.skippedDefinition)
        .toList();
    if (skippedDefs.isNotEmpty) {
      print('\nUnique skippedDefinition names:');
      final names = <String>{};
      for (final d in skippedDefs) {
        names.add(d.detail ?? d.message);
      }
      final sorted = names.toList()..sort();
      for (final n in sorted) {
        print('  $n');
      }
    }

    // Show unique skippedPython details
    final skippedPy = diagnostics
        .where((d) =>
            d.code == RenPyDiagnosticCode.skippedPython)
        .toList();
    if (skippedPy.isNotEmpty) {
      print('\nFirst 20 unique skippedPython:');
      final details = <String>{};
      for (final d in skippedPy) {
        details.add(d.detail ?? d.message);
      }
      final sorted = details.toList()..sort();
      for (var i = 0; i < sorted.length && i < 20; i++) {
        print('  ${sorted[i]}');
      }
    }

    // Parse warnings
    if (parseWarnings.isNotEmpty) {
      print('\nFirst 20 parse warnings:');
      for (var i = 0; i < parseWarnings.length && i < 20; i++) {
        print('  ${parseWarnings[i]}');
      }
    }

    // Make it a test that doesn't crash
    expect(parseFailed, 0);
  });
}
