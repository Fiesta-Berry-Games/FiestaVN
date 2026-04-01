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
  RenPyDialogue(
    this.character,
    this.text, {
    String? displayText,
    this.characterId,
    this.color,
  }) : displayText = displayText ?? text;

  /// The resolved display name shown to the player.
  final String? character;
  final String text;

  /// Text intended for rendering after removing control tags.
  final String displayText;

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

/// A RenPy pause that waits for player input or a future timed resume.
final class RenPyPause extends RenPyGameStatus {
  const RenPyPause({this.duration});

  /// Optional pause duration in seconds.
  final double? duration;
}

/// Emitted when a `scene`, `show`, or `hide` image command is encountered.
final class RenPyImageChange extends RenPyGameStatus {
  RenPyImageChange({
    this.scene,
    this.show,
    this.hide,
    this.sceneAt,
    this.showAt,
    this.sceneOnLayer,
    this.showOnLayer,
    this.hideOnLayer,
    this.showBehind,
    this.scenePlacement,
    this.showPlacement,
    this.sceneAsset,
    this.showAsset,
    this.sceneImage,
    this.showImage,
    this.showText,
  });

  final String? scene;
  final String? show;
  final String? hide;
  final String? sceneAt;
  final String? showAt;
  final String? sceneOnLayer;
  final String? showOnLayer;
  final String? hideOnLayer;
  final String? showBehind;
  final RenPyImagePlacement? scenePlacement;
  final RenPyImagePlacement? showPlacement;
  final String? sceneAsset;
  final String? showAsset;
  final RenPyResolvedImage? sceneImage;
  final RenPyResolvedImage? showImage;
  final String? showText;
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
  const RenPyTransitionChange(this.name, {this.intent});

  final String name;
  final RenPyTransitionIntent? intent;

  @override
  String toString() => 'RenPyTransitionChange($name, intent: $intent)';
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
  RenPyFlutterController({
    this.onComplete,
    this.onDiagnostic,
    this.persistentStore,
    this.snapshotStore,
  }) : super(RenPyIdle());

  final VoidCallback? onComplete;
  final RenPyDiagnosticCallback? onDiagnostic;
  final RenPyPersistentStore? persistentStore;
  final RenPyRunnerSnapshotStore? snapshotStore;

  RenPyRunner? _runner;
  StreamSubscription? _ticker;
  Timer? _pauseTimer;
  RenPyImageResolver _imageResolver = RenPyImageResolver();
  final List<RenPyDiagnostic> _diagnostics = [];
  String? _gameRoot;
  Set<String> _availableAssets = const {};

  List<RenPyDiagnostic> get diagnostics => List.unmodifiable(_diagnostics);

  Map<String, dynamic> get persistent => _runner?.persistent ?? const {};

  bool get hasSnapshotStore => snapshotStore != null;

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
    _pauseTimer?.cancel();
    _runner = null;
    _diagnostics.clear();
    _gameRoot = gameRoot;
    _availableAssets = availableAssets;
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

    final runner = RenPyRunner(result.script, persistentStore: persistentStore)
      ..configureCallbacks(this);
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
      _pauseTimer?.cancel();
      _pauseTimer = null;
      runner.continueExecution();
      _ticker?.resume();
    }
  }

  Future<bool> saveGame() async {
    final store = snapshotStore;
    final runner = _runner;
    if (store == null || runner == null) return false;
    if (runner.state != RenPyRunnerState.waitingForInput) return false;

    await store.save(runner.snapshot());
    return true;
  }

  Future<bool> loadSavedGame() async {
    final store = snapshotStore;
    final runner = _runner;
    if (store == null || runner == null) return false;

    final snapshot = await store.load();
    if (snapshot == null) return false;

    restoreSnapshot(snapshot);
    return true;
  }

  void restoreSnapshot(RenPyRunnerSnapshot snapshot) {
    final runner = _runner;
    if (runner == null) return;

    _pauseTimer?.cancel();
    _pauseTimer = null;
    _ticker?.pause();

    runner.restoreSnapshot(snapshot);
    _presentRestoredRunner(snapshot, runner);
  }

  void _presentRestoredRunner(
    RenPyRunnerSnapshot snapshot,
    RenPyRunner runner,
  ) {
    switch (runner.state) {
      case RenPyRunnerState.waitingForInput:
        if (runner.isWaitingAtMenu) {
          runner.continueExecution();
          return;
        }

        final dialogue = snapshot.lastDialogue?.toDialogueEvent();
        if (dialogue != null) {
          _onDialogueEvent(dialogue);
          _ticker?.pause();
          return;
        }

        value = const RenPyPause();
      case RenPyRunnerState.complete:
        value = RenPyComplete();
      case RenPyRunnerState.error:
        value = RenPyError(runner.errorMessage ?? 'Unknown error');
      case RenPyRunnerState.ready || RenPyRunnerState.running:
        _ticker?.resume();
        runner.run();
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
    _pauseTimer?.cancel();
    _pauseTimer = null;
    value = RenPyDialogue(
      event.displayName,
      event.text,
      displayText: event.displayText,
      characterId: event.characterId,
      color: event.color,
    );

    final duration = event.autoContinueDuration;
    if (duration == null) return;
    _pauseTimer = Timer(Duration(milliseconds: (duration * 1000).round()), () {
      continueGame();
    });
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

  void _onPause(RenPyPauseEvent event) {
    debugPrint('Pause: ${event.duration ?? "input"}');
    _ticker?.pause();
    value = RenPyPause(duration: event.duration);

    final duration = event.duration;
    if (duration == null) return;
    _pauseTimer?.cancel();
    _pauseTimer = Timer(Duration(milliseconds: (duration * 1000).round()), () {
      continueGame();
    });
  }

  void _onImageEvent(RenPyImageEvent event) {
    debugPrint(
      'Image command - ${event.action}: ${event.imageName} at ${event.at}',
    );
    switch (event.action) {
      case RenPyImageAction.scene:
        final image = _imageResolver.resolveImage(event.imageName);
        _diagnoseResolvedImage(event.imageName, image);
        value = RenPyImageChange(
          scene: event.imageName,
          sceneAt: event.at,
          sceneOnLayer: event.onLayer,
          scenePlacement: event.placement,
          sceneAsset: image?.assetPath,
          sceneImage: image,
        );
      case RenPyImageAction.show:
        final image =
            event.displayableText == null
                ? _imageResolver.resolveImage(event.imageName)
                : null;
        if (event.displayableText == null) {
          _diagnoseResolvedImage(event.imageName, image);
        }
        value = RenPyImageChange(
          show: event.imageName,
          showAt: event.at,
          showOnLayer: event.onLayer,
          showBehind: event.behind,
          showPlacement: event.placement,
          showAsset: image?.assetPath,
          showImage: image,
          showText: event.displayableText,
        );
      case RenPyImageAction.hide:
        value = RenPyImageChange(
          hide: event.imageName,
          hideOnLayer: event.onLayer,
        );
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
        _diagnoseAudioAsset(asset);
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
    value = RenPyTransitionChange(event.name, intent: event.intent);
  }

  void _diagnoseResolvedImage(String? imageName, RenPyResolvedImage? image) {
    final asset = image?.assetPath;
    if (imageName == null || asset == null || _availableAssets.isEmpty) return;
    if (_availableAssetExists(asset)) return;
    _emitDiagnostic(
      RenPyDiagnostic(
        code: RenPyDiagnosticCode.unresolvedImageAsset,
        message: 'Resolved image asset was not found in available assets.',
        detail: '$imageName -> $asset',
      ),
    );
  }

  void _diagnoseAudioAsset(String asset) {
    if (_availableAssets.isEmpty) return;
    final assetPath = _audioAssetSourcePath(asset);
    if (_availableAssetExists(assetPath)) return;
    _emitDiagnostic(
      RenPyDiagnostic(
        code: RenPyDiagnosticCode.unresolvedAudioAsset,
        message: 'Resolved audio asset was not found in available assets.',
        detail: '$asset -> $assetPath',
      ),
    );
  }

  String _audioAssetSourcePath(String asset) {
    final normalizedAsset = asset
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'^/+'), '');
    if (normalizedAsset.startsWith('assets/')) return normalizedAsset;

    final root = _gameRoot ?? '';
    if (root.isEmpty) return normalizedAsset;
    if (root.endsWith('/')) return '$root$normalizedAsset';
    return '$root/$normalizedAsset';
  }

  bool _availableAssetExists(String assetPath) {
    if (_availableAssets.contains(assetPath)) return true;
    final lower = assetPath.toLowerCase();
    return _availableAssets.any((asset) => asset.toLowerCase() == lower);
  }

  void _emitDiagnostic(RenPyDiagnostic diagnostic) {
    _diagnostics.add(diagnostic);
    onDiagnostic?.call(diagnostic);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pauseTimer?.cancel();
    super.dispose();
  }
}

extension on RenPyRunner {
  void configureCallbacks(RenPyFlutterController controller) {
    onDialogueEvent = controller._onDialogueEvent;
    onMenu = controller._onMenu;
    onImageEvent = controller._onImageEvent;
    onImageDefinition = controller._onImageDefinition;
    onAudio = controller._onAudio;
    onTransition = controller._onTransition;
    onPause = controller._onPause;
    onDiagnostic = controller._emitDiagnostic;
  }
}
