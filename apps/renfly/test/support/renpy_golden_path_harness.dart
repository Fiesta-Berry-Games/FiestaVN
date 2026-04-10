import 'dart:async';
import 'dart:io';

import 'package:renpy_flutter/renpy_flutter.dart';

typedef RenPyGoldenPathStopPredicate =
    bool Function(RenPyGoldenPathTrace trace, RenPyGameStatus status);

typedef RenPyGoldenPathMenuChooser =
    int Function(RenPyMenu menu, RenPyGoldenPathTrace trace);

RenPyGameProject loadRenPyProjectFolder(Directory directory) {
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => RenPyProjectFile(file.path, file.readAsBytesSync()));
  return RenPyGameProject.fromFiles(files);
}

final class RenPyGoldenPathHarness {
  RenPyGoldenPathHarness(this.project, {RenPyGoldenPathMenuChooser? chooseMenu})
    : chooseMenu = chooseMenu ?? _chooseFirstMenuEntry;

  final RenPyGameProject project;
  final RenPyGoldenPathMenuChooser chooseMenu;

  Future<RenPyGoldenPathTrace> runUntilComplete({int maxSteps = 500}) {
    return runUntil(
      (trace, status) => trace.complete || status is RenPyComplete,
      maxSteps: maxSteps,
    );
  }

  Future<RenPyGoldenPathTrace> runUntil(
    RenPyGoldenPathStopPredicate stopWhen, {
    int maxSteps = 500,
  }) async {
    final controller = RenPyFlutterController();
    final trace = RenPyGoldenPathTrace._();
    RenPyMenu? handledMenu;

    void recordStatus() {
      final status = controller.value;
      switch (status) {
        case RenPyDialogue():
          trace.dialogue.add(status);
        case RenPyMenu():
          if (identical(status, handledMenu)) return;
          handledMenu = status;
          final selectedIndex = chooseMenu(status, trace);
          if (selectedIndex < 0 || selectedIndex >= status.choices.length) {
            throw RangeError.range(
              selectedIndex,
              0,
              status.choices.length - 1,
              'selectedIndex',
              'Menu chooser selected an invalid choice.',
            );
          }
          trace.menus.add(
            RenPyGoldenPathMenuSelection(
              caption: status.caption,
              choices: status.choices,
              selectedIndex: selectedIndex,
            ),
          );
          scheduleMicrotask(() => status.onChoice(selectedIndex));
        case RenPyPause():
          trace.pauses.add(status);
        case RenPyImageChange():
          trace.images.add(status);
        case RenPyAudioChange():
          trace.audio.add(status);
        case RenPyTransitionChange():
          trace.transitions.add(status);
        case RenPyComplete():
          trace.complete = true;
        case RenPyError(:final message):
          trace.error = message;
        case RenPyIdle():
          break;
      }
    }

    controller.addListener(recordStatus);
    try {
      controller.load(
        project.scriptSource,
        filename: project.scriptPath,
        gameRoot: project.gameRoot,
        availableAssets: project.availableAssets,
      );

      for (var step = 0; step < maxSteps; step += 1) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        final status = controller.value;
        if (stopWhen(trace, status)) {
          trace.diagnostics.addAll(controller.diagnostics);
          return trace;
        }

        switch (status) {
          case RenPyDialogue() || RenPyPause():
            controller.continueGame();
          case RenPyComplete():
            trace.complete = true;
            trace.diagnostics.addAll(controller.diagnostics);
            return trace;
          case RenPyError(:final message):
            trace.error = message;
            trace.diagnostics.addAll(controller.diagnostics);
            return trace;
          case _:
            break;
        }
      }

      trace.diagnostics.addAll(controller.diagnostics);
      throw TimeoutException(
        'RenPy golden path did not reach the requested stop condition. '
        'Last status: ${controller.value}; summary: ${trace.summary}.',
      );
    } finally {
      controller.removeListener(recordStatus);
      controller.dispose();
    }
  }
}

final class RenPyGoldenPathTrace {
  RenPyGoldenPathTrace._();

  final dialogue = <RenPyDialogue>[];
  final menus = <RenPyGoldenPathMenuSelection>[];
  final pauses = <RenPyPause>[];
  final images = <RenPyImageChange>[];
  final audio = <RenPyAudioChange>[];
  final transitions = <RenPyTransitionChange>[];
  final diagnostics = <RenPyDiagnostic>[];

  bool complete = false;
  String? error;

  List<String> get sceneNames {
    return images.map((image) => image.scene).whereType<String>().toList();
  }

  List<String> get showTextDisplayables {
    return images.map((image) => image.showText).whereType<String>().toList();
  }

  List<String> get audioAssets {
    return audio.map((change) => change.asset).whereType<String>().toList();
  }

  List<String> get transitionNames {
    return transitions.map((transition) => transition.name).toList();
  }

  List<RenPyDiagnostic> get problematicDiagnostics {
    return [
      for (final diagnostic in diagnostics)
        if (_problematicDiagnosticCodes.contains(diagnostic.code)) diagnostic,
    ];
  }

  List<String> get problematicDiagnosticSummaries {
    return [
      for (final diagnostic in problematicDiagnostics)
        '${diagnostic.code}: ${diagnostic.detail}',
    ];
  }

  RenPyGoldenPathSummary get summary {
    return RenPyGoldenPathSummary(
      dialogueCount: dialogue.length,
      menuCount: menus.length,
      pauseCount: pauses.length,
      imageChangeCount: images.length,
      audioChangeCount: audio.length,
      transitionCount: transitions.length,
      diagnosticCount: diagnostics.length,
      problematicDiagnosticCount: problematicDiagnostics.length,
      complete: complete,
      error: error,
    );
  }
}

final class RenPyGoldenPathMenuSelection {
  const RenPyGoldenPathMenuSelection({
    required this.caption,
    required this.choices,
    required this.selectedIndex,
  });

  final String? caption;
  final List<String> choices;
  final int selectedIndex;

  String get selectedChoice => choices[selectedIndex];
}

final class RenPyGoldenPathSummary {
  const RenPyGoldenPathSummary({
    required this.dialogueCount,
    required this.menuCount,
    required this.pauseCount,
    required this.imageChangeCount,
    required this.audioChangeCount,
    required this.transitionCount,
    required this.diagnosticCount,
    required this.problematicDiagnosticCount,
    required this.complete,
    required this.error,
  });

  final int dialogueCount;
  final int menuCount;
  final int pauseCount;
  final int imageChangeCount;
  final int audioChangeCount;
  final int transitionCount;
  final int diagnosticCount;
  final int problematicDiagnosticCount;
  final bool complete;
  final String? error;

  @override
  String toString() {
    return 'RenPyGoldenPathSummary('
        'dialogue: $dialogueCount, menus: $menuCount, pauses: $pauseCount, '
        'images: $imageChangeCount, audio: $audioChangeCount, '
        'transitions: $transitionCount, diagnostics: $diagnosticCount, '
        'problematicDiagnostics: $problematicDiagnosticCount, '
        'complete: $complete, error: $error)';
  }
}

int _chooseFirstMenuEntry(RenPyMenu menu, RenPyGoldenPathTrace trace) => 0;

const _problematicDiagnosticCodes = {
  RenPyDiagnosticCode.skippedPython,
  RenPyDiagnosticCode.unsupportedPlacement,
  RenPyDiagnosticCode.unsupportedTransition,
  RenPyDiagnosticCode.unresolvedImageAsset,
  RenPyDiagnosticCode.unresolvedAudioAsset,
  RenPyDiagnosticCode.unknownStatement,
};
