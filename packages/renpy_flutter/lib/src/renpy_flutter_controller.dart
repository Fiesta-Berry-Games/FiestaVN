import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:renpy_core/renpy_core.dart';

/// Public, minimal information describing what the player should currently see.
sealed class RenPyGameStatus {
  const RenPyGameStatus();
}

/// Idle: waiting for the app to load a script, nothing on screen yet.
final class RenPyIdle extends RenPyGameStatus {}

/// A line of dialogue, optionally attributed to a character.
final class RenPyDialogue extends RenPyGameStatus {
  RenPyDialogue(this.character, this.text, {this.characterId, this.color});

  /// The resolved display name shown to the player.
  final String? character;
  final String text;

  /// The RenPy character variable, such as `s` in `s "Hello"`.
  final String? characterId;

  /// The raw RenPy color expression for the character, usually `#rrggbb`.
  final String? color;
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
    this.sceneAt,
    this.showAt,
    this.sceneAsset,
    this.showAsset,
  });

  final String? scene;
  final String? show;
  final String? hide;
  final String? sceneAt;
  final String? showAt;
  final String? sceneAsset;
  final String? showAsset;
}

/// Emitted when a RenPy audio command is encountered.
final class RenPyAudioChange extends RenPyGameStatus {
  const RenPyAudioChange.play({required this.channel, required this.asset})
    : action = RenPyAudioAction.play,
      fadeout = null;

  const RenPyAudioChange.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadeout;

  @override
  String toString() {
    return 'RenPyAudioChange.$action(channel: $channel, asset: $asset, '
        'fadeout: $fadeout)';
  }
}

/// Emitted when a RenPy `with` transition command is encountered.
final class RenPyTransitionChange extends RenPyGameStatus {
  const RenPyTransitionChange(this.name);

  final String name;

  @override
  String toString() => 'RenPyTransitionChange($name)';
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
          ..onDialogueEvent = _onDialogueEvent
          ..onMenu = _onMenu
          ..onImageEvent = _onImageEvent
          ..onImageDefinition = _onImageDefinition
          ..onAudio = _onAudio
          ..onTransition = _onTransition;
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

  void _onDialogueEvent(RenPyDialogueEvent event) {
    debugPrint('Dialogue: ${event.displayName ?? "Narrator"}: ${event.text}');
    _ticker?.pause();
    value = RenPyDialogue(
      event.displayName,
      event.text,
      characterId: event.characterId,
      color: event.color,
    );
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

  void _onImageEvent(RenPyImageEvent event) {
    debugPrint(
      'Image command - ${event.action}: ${event.imageName} at ${event.at}',
    );
    switch (event.action) {
      case RenPyImageAction.scene:
        value = RenPyImageChange(
          scene: event.imageName,
          sceneAt: event.at,
          sceneAsset: _imageResolver.resolve(event.imageName),
        );
      case RenPyImageAction.show:
        value = RenPyImageChange(
          show: event.imageName,
          showAt: event.at,
          showAsset: _imageResolver.resolve(event.imageName),
        );
      case RenPyImageAction.hide:
        value = RenPyImageChange(hide: event.imageName);
    }
  }

  void _onImageDefinition(RenPyImageDefinitionEvent event) {
    debugPrint('Image definition - ${event.name}: ${event.expression}');
    _imageResolver = _imageResolver.withImageAlias(
      event.name,
      event.expression,
    );
  }

  void _onAudio(RenPyAudioEvent event) {
    debugPrint(
      'Audio command - ${event.action}: ${event.channel} '
      '${event.asset ?? ""}',
    );
    switch (event.action) {
      case RenPyAudioAction.play:
        final asset = event.asset;
        if (asset == null) return;
        value = RenPyAudioChange.play(channel: event.channel, asset: asset);
      case RenPyAudioAction.stop:
        value = RenPyAudioChange.stop(
          channel: event.channel,
          fadeout: event.fadeout,
        );
    }
  }

  void _onTransition(RenPyTransitionEvent event) {
    debugPrint('Transition command - ${event.name}');
    value = RenPyTransitionChange(event.name);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
