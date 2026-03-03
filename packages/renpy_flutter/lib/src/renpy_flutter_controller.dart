import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:renpy_core/renpy_core.dart';

/// Public, minimal information describing what the player should currently see.
sealed class RenPyGameStatus {}

/// Idle: waiting for the app to load a script, nothing on screen yet.
final class RenPyIdle extends RenPyGameStatus {}

/// A line of dialogue, optionally attributed to a character.
final class RenPyDialogue extends RenPyGameStatus {
  RenPyDialogue(this.character, this.text);

  final String? character;
  final String text;
}

/// A choice menu. UI must call [onChoice] with the index the user picked.
final class RenPyMenu extends RenPyGameStatus {
  RenPyMenu(this.choices, this.onChoice, {this.caption});

  final List<String> choices;
  final void Function(int) onChoice;
  final String? caption;
}

/// Emitted when a `scene`, `show`, or `hide` image command is encountered.
final class RenPyImageChange extends RenPyGameStatus {
  RenPyImageChange({
    this.scene,
    this.show,
    this.hide,
    this.sceneAsset,
    this.showAsset,
  });

  final String? scene;
  final String? show;
  final String? hide;
  final String? sceneAsset;
  final String? showAsset;
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

  RenPyRunner? _runner;
  StreamSubscription? _ticker;
  RenPyImageResolver _imageResolver = RenPyImageResolver();

  /// Loads a `.rpy` script and immediately jumps to `start` when present.
  ///
  /// Calling [load] again cleanly restarts the controller with the new script.
  void load(
    String source, {
    String filename = '<memory>',
    String? gameRoot,
    Set<String> availableAssets = const {},
  }) {
    debugPrint('Loading RenPy script...');
    _ticker?.cancel();
    _runner = null;
    value = RenPyIdle();

    final parser = RenPyParser();
    final result = parser.parse(source, filename);
    _imageResolver = RenPyImageResolver.fromScript(
      result.script,
      assetRoot: gameRoot,
      availableAssets: availableAssets,
    );

    debugPrint(
      'Parsed script with ${result.script.statements.length} statements',
    );

    final runner =
        RenPyRunner(result.script)
          ..onDialogue = _onDialogue
          ..onMenu = _onMenu
          ..onImage = _onImage;
    _runner = runner;

    if (result.script.findLabel('start') != null) {
      debugPrint('Found start label, jumping to it');
      runner.jumpToLabel('start');
    } else {
      debugPrint('No start label found');
    }

    _startTicker();
    debugPrint('Starting initial execution...');
    runner.run();
  }

  /// Player pressed "next".
  void continueGame() {
    final runner = _runner;
    if (runner == null) return;
    if (runner.state == RenPyRunnerState.waitingForInput) {
      debugPrint('Continuing game execution...');
      runner.continueExecution();
      _ticker?.resume();
    }
  }

  void _startTicker() {
    _ticker = Stream.periodic(const Duration(milliseconds: 1)).listen((_) {
      final runner = _runner;
      if (runner == null) return;

      switch (runner.state) {
        case RenPyRunnerState.waitingForInput:
          _ticker?.pause();
          break;
        case RenPyRunnerState.complete:
          debugPrint('Script execution complete');
          value = RenPyComplete();
          _ticker?.cancel();
          onComplete?.call();
          break;
        case RenPyRunnerState.error:
          debugPrint('Script execution error: ${runner.errorMessage}');
          value = RenPyError(runner.errorMessage ?? 'Unknown error');
          _ticker?.cancel();
          break;
        default:
          runner.continueExecution();
      }
    });
  }

  void _onDialogue(String? character, String text) {
    debugPrint('Dialogue: ${character ?? "Narrator"}: $text');
    _ticker?.pause();
    value = RenPyDialogue(character, text);
  }

  void _onMenu(
    List<String> choices,
    void Function(int index) onChoice,
    String? caption,
  ) {
    debugPrint('Menu with choices: $choices');
    _ticker?.pause();
    value = RenPyMenu(choices, (i) {
      debugPrint('Menu choice selected: ${choices[i]}');
      onChoice(i);
      _ticker?.resume();
    }, caption: caption);
  }

  void _onImage(String? scene, String? show, String? hide) {
    debugPrint('Image command - scene: $scene, show: $show, hide: $hide');
    value = RenPyImageChange(
      scene: scene,
      show: show,
      hide: hide,
      sceneAsset: _imageResolver.resolve(scene),
      showAsset: _imageResolver.resolve(show),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
