import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:renpy_core/renpy_core.dart';

/// Public, minimal information describing what the player should currently see.
sealed class RenPyGameStatus {}

/// Idle → waiting for the app to load a script, nothing on screen yet.
final class RenPyIdle extends RenPyGameStatus {}

/// A line of dialogue (optionally attributed to a character).
final class RenPyDialogue extends RenPyGameStatus {
  RenPyDialogue(this.character, this.text);
  final String? character;
  final String text;
}

/// A choice menu.  UI must call [onChoice] with the index the user picked.
final class RenPyMenu extends RenPyGameStatus {
  RenPyMenu(this.choices, this.onChoice);
  final List<String> choices;
  final void Function(int) onChoice;
}

/// Emitted when a `scene`, `show`, or `hide` image command is encountered.
final class RenPyImageChange extends RenPyGameStatus {
  RenPyImageChange({this.scene, this.show, this.hide});
  final String? scene;
  final String? show;
  final String? hide;
}

/// The game finished running normally.
final class RenPyComplete extends RenPyGameStatus {}

/// The runner encountered an unrecoverable error.
final class RenPyError extends RenPyGameStatus {
  RenPyError(this.message);
  final String message;
}

/// Drives [RenPyRunner] and turns callbacks into [ValueNotifier] updates.
class RenPyFlutterController extends ValueNotifier<RenPyGameStatus> {
  RenPyFlutterController({this.onComplete}) : super(RenPyIdle());

  final VoidCallback? onComplete;

  RenPyRunner?        _runner;
  StreamSubscription? _ticker; // Nullable so we can dispose/re-create.

  /// Loads a `.rpy` script (raw source string) and immediately jumps
  /// to the `start` label if it exists.  Calling [load] again cleanly
  /// restarts the controller with the new script.
  void load(String source, {String filename = '<memory>'}) {
    print('Loading RenPy script...');
    _ticker?.cancel();
    _runner = null;
    value   = RenPyIdle();

    final parser = RenPyParser();
    final result = parser.parse(source, filename);

    print('Parsed script with ${result.script.statements.length} statements');

    final runner = RenPyRunner(result.script)
      ..onDialogue = _onDialogue
      ..onMenu     = _onMenu
      ..onImage = _onImage;
    _runner = runner;

    if (result.script.findLabel('start') != null) {
      print('Found start label, jumping to it');
      runner.jumpToLabel('start');
    } else {
      print('No start label found');
    }

    _startTicker();
    print('Starting initial execution...');
    runner.run(); // Start first run-loop cycle.
  }

  /// Player pressed "next".
  void continueGame() {
    final r = _runner;
    if (r == null) return;
    if (r.state == RenPyRunnerState.waitingForInput) {
      print('Continuing game execution...');
      r.continueExecution();
      _ticker?.resume();
    }
  }

  void _startTicker() {
    // (re)create a 1 ms timer-based ticker that drives the runner forward.
    _ticker = Stream.periodic(const Duration(milliseconds: 1)).listen((_) {
      final r = _runner;
      if (r == null) return;

      switch (r.state) {
        case RenPyRunnerState.waitingForInput:
          _ticker?.pause(); // Wait for player / menu.
          break;
        case RenPyRunnerState.complete:
          print('Script execution complete');
          value = RenPyComplete();
          _ticker?.cancel();
          onComplete?.call();
          break;
        case RenPyRunnerState.error:
          print('Script execution error: ${r.errorMessage}');
          value = RenPyError(r.errorMessage ?? 'Unknown error');
          _ticker?.cancel();
          break;
        default:
          r.continueExecution(); // Keep crunching through script.
      }
    });
  }

  void _onDialogue(String? character, String text) {
    print('Dialogue: ${character ?? "Narrator"}: $text');
    _ticker?.pause(); // Freeze on dialogue.
    value = RenPyDialogue(character, text);
  }

  void _onMenu(List<String> choices, void Function(int index) onChoice) {
    print('Menu with choices: $choices');
    // Called for every menu, including nested ones.
    _ticker?.pause();
    value = RenPyMenu(choices, (i) {
      print('Menu choice selected: ${choices[i]}');
      onChoice(i); // Notify runner.
      _ticker?.resume(); // Resume execution afterwards.
    });
  }

  void _onImage(String? scene, String? show, String? hide) {
    print('Image command - scene: $scene, show: $show, hide: $hide');
    // _ticker?.pause(); // Can be used to allow a reaction before continuing.
    value = RenPyImageChange(scene: scene, show: show, hide: hide);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
