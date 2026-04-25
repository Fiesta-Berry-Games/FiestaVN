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

/// Emitted when a rollback or load replaces the full visual presentation.
final class RenPyVisualRestore extends RenPyGameStatus {
  const RenPyVisualRestore(this.visual);

  final RenPyVisualSnapshot visual;
}

/// Emitted when a RenPy audio command is encountered.
final class RenPyAudioChange extends RenPyGameStatus {
  const RenPyAudioChange.play({
    required this.channel,
    required this.asset,
    this.fadein,
    this.mixer,
    this.fadeout,
    this.volume,
    this.ifChanged,
    this.loop,
  }) : action = RenPyAudioAction.play;

  const RenPyAudioChange.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null,
      fadein = null,
      mixer = null,
      volume = null,
      ifChanged = null,
      loop = null;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadein;
  final String? fadeout;
  final String? mixer;
  final String? volume;
  final bool? ifChanged;
  final bool? loop;

  @override
  String toString() {
    return 'RenPyAudioChange.$action(channel: $channel, asset: $asset, '
        'fadein: $fadein, fadeout: $fadeout, volume: $volume, '
        'ifChanged: $ifChanged, mixer: $mixer, loop: $loop)';
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
  RenPyVisualElementSnapshot? _sceneSnapshot;
  final Map<String, RenPyVisualElementSnapshot> _spriteSnapshots = {};
  final Map<String, RenPyImagePlacement> _spritePlacements = {};
  final Map<String, RenPyAudioChannelSnapshot> _audioSnapshots = {};
  final List<RenPyTransientAudioSnapshot> _pendingTransientAudio = [];

  final List<RenPyRunnerSnapshot> _rollbackHistory = [];

  static const _masterLayer = 'master';
  static const _defaultSpritePlacement = RenPyImagePlacement.position(
    xpos: 0.5,
    xanchor: 0.5,
    ypos: 1,
    yanchor: 1,
  );
  List<RenPyDiagnostic> get diagnostics => List.unmodifiable(_diagnostics);
  static const _defaultVisualSnapshot = RenPyVisualSnapshot(
    scene: RenPyVisualElementSnapshot(imageName: 'black'),
    sprites: [],
  );

  static const _rollbackHistoryLimit = 100;

  Map<String, dynamic> get persistent => _runner?.persistent ?? const {};

  bool get hasSnapshotStore => snapshotStore != null;

  bool get canRollback => _rollbackHistory.isNotEmpty;

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
    _rollbackHistory.clear();
    value = RenPyIdle();
    _clearPresentationSnapshot();

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
      _recordRollbackBoundary(runner);
      _pendingTransientAudio.clear();
      runner.continueExecution();
      _ticker?.resume();
    }
  }

  Future<bool> saveGame() async {
    final store = snapshotStore;
    final runner = _runner;
    if (store == null || runner == null) return false;
    if (runner.state != RenPyRunnerState.waitingForInput) return false;

    await store.save(
      runner.snapshot().withPresentation(
        _presentationSnapshot(includeTransientAudio: false),
      ),
    );
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

  bool rollback() {
    if (_rollbackHistory.isEmpty) return false;
    final snapshot = _rollbackHistory.removeLast();
    _restoreSnapshot(snapshot);
    return true;
  }

  void restoreSnapshot(RenPyRunnerSnapshot snapshot) {
    _rollbackHistory.clear();
    _restoreSnapshot(snapshot);
  }

  void _restoreSnapshot(RenPyRunnerSnapshot snapshot) {
    final runner = _runner;
    if (runner == null) return;

    _pauseTimer?.cancel();
    _pauseTimer = null;
    _ticker?.pause();

    runner.restoreSnapshot(snapshot);
    _restorePresentation(snapshot.presentation);
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
      final runner = _runner;
      if (runner != null) {
        _recordRollbackBoundary(runner);
        _pendingTransientAudio.clear();
      }
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
    late final RenPyImageChange change;
    switch (event.action) {
      case RenPyImageAction.scene:
        final image = _imageResolver.resolveImage(event.imageName);
        _diagnoseResolvedImage(event.imageName, image);
        change = RenPyImageChange(
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
        change = RenPyImageChange(
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
        change = RenPyImageChange(
          hide: event.imageName,
          hideOnLayer: event.onLayer,
        );
    }
    _recordImageChange(change);
    value = change;
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
    late final RenPyAudioChange change;
    switch (event.action) {
      case RenPyAudioAction.play:
        final asset = event.asset;
        if (asset == null) return;
        _diagnoseAudioAsset(asset);
        change = RenPyAudioChange.play(
          channel: event.channel,
          asset: asset,
          fadein: event.fadein,
          fadeout: event.fadeout,
          volume: event.volume,
          ifChanged: event.ifChanged,
          mixer: event.mixer,
          loop: event.loop,
        );
      case RenPyAudioAction.stop:
        change = RenPyAudioChange.stop(
          channel: event.channel,
          fadeout: event.fadeout,
        );
    }
    _recordAudioChange(change);
    value = change;
  }

  void _onTransition(RenPyTransitionEvent event) {
    debugPrint('Transition command - ${event.name}');
    value = RenPyTransitionChange(event.name, intent: event.intent);
  }

  void _recordRollbackBoundary(RenPyRunner runner) {
    if (runner.state != RenPyRunnerState.waitingForInput) return;
    _rollbackHistory.add(
      runner.snapshot().withPresentation(_presentationSnapshot()),
    );
    if (_rollbackHistory.length > _rollbackHistoryLimit) {
      _rollbackHistory.removeAt(0);
    }
  }

  RenPyPresentationSnapshot _presentationSnapshot({
    bool includeTransientAudio = true,
  }) {
    return RenPyPresentationSnapshot(
      visual: RenPyVisualSnapshot(
        scene: _sceneSnapshot,
        sprites: _spriteSnapshots.values.toList(),
      ),
      audio: RenPyAudioSnapshot(
        channels: Map<String, RenPyAudioChannelSnapshot>.of(_audioSnapshots),
        transient:
            includeTransientAudio ? List.of(_pendingTransientAudio) : const [],
      ),
    );
  }

  void _clearPresentationSnapshot() {
    _sceneSnapshot = null;
    _spriteSnapshots.clear();
    _spritePlacements.clear();
    _audioSnapshots.clear();
    _pendingTransientAudio.clear();
  }

  void _restorePresentation(RenPyPresentationSnapshot? presentation) {
    final currentAudio = Map<String, RenPyAudioChannelSnapshot>.of(
      _audioSnapshots,
    );
    _clearPresentationSnapshot();

    for (final channel in currentAudio.keys) {
      final restoredChannel = presentation?.audio?.channels[channel];
      if (restoredChannel == null) {
        value = RenPyAudioChange.stop(channel: channel);
      }
    }

    final visual = presentation?.visual ?? _defaultVisualSnapshot;
    _restoreVisualSnapshot(visual);
    value = RenPyVisualRestore(visual);

    if (presentation == null) return;

    for (final entry
        in presentation.audio?.channels.entries ??
            const <MapEntry<String, RenPyAudioChannelSnapshot>>[]) {
      if (!_shouldRestoreAudioChannel(entry.key, entry.value)) continue;

      final change = RenPyAudioChange.play(
        channel: entry.key,
        asset: entry.value.asset,
        mixer: entry.value.mixer,
        loop: entry.value.loop,
      );
      _recordAudioChange(change);
      value = change;
    }

    final transientAudio =
        presentation.audio?.transient ?? const <RenPyTransientAudioSnapshot>[];
    for (final transient in transientAudio) {
      value = _audioChangeForTransient(transient);
    }
    _pendingTransientAudio
      ..clear()
      ..addAll(transientAudio);
  }

  void _restoreVisualSnapshot(RenPyVisualSnapshot visual) {
    _sceneSnapshot = visual.scene;
    _spriteSnapshots.clear();
    _spritePlacements.clear();

    for (final sprite in visual.sprites) {
      final tag = sprite.tag ?? _tagForSnapshot(sprite);
      if (tag == null) continue;

      final key = _spriteKey(tag, sprite.layer);
      final placement = sprite.placement ?? _defaultSpritePlacement;
      _spritePlacements[key] = placement;
      _spriteSnapshots[key] = RenPyVisualElementSnapshot(
        tag: tag,
        layer: sprite.layer,
        imageName: sprite.imageName,
        assetPath: sprite.assetPath,
        solidColor: sprite.solidColor,
        operations: sprite.operations,
        placement: placement,
        text: sprite.text,
      );
    }
  }

  RenPyImageChange _imageChangeForScene(RenPyVisualElementSnapshot snapshot) {
    return RenPyImageChange(
      scene: snapshot.imageName,
      scenePlacement: snapshot.placement,
      sceneAsset: snapshot.assetPath,
      sceneImage: _resolvedImageFor(snapshot),
    );
  }

  RenPyImageChange _imageChangeForSprite(RenPyVisualElementSnapshot snapshot) {
    return RenPyImageChange(
      show: snapshot.imageName,
      showOnLayer: snapshot.layer,
      showPlacement: snapshot.placement,
      showAsset: snapshot.assetPath,
      showImage: _resolvedImageFor(snapshot),
      showText: snapshot.text,
    );
  }

  RenPyResolvedImage? _resolvedImageFor(RenPyVisualElementSnapshot snapshot) {
    final solidColor = snapshot.solidColor;
    if (solidColor != null) {
      return RenPyResolvedImage.solid(
        solidColor,
        operations: snapshot.operations,
      );
    }

    final assetPath = snapshot.assetPath;
    if (assetPath != null) {
      return RenPyResolvedImage(
        assetPath: assetPath,
        operations: snapshot.operations,
      );
    }

    return null;
  }

  String? _tagForSnapshot(RenPyVisualElementSnapshot snapshot) {
    final imageName = snapshot.imageName;
    if (imageName == null) return null;
    return _imageTag(imageName);
  }

  void _recordImageChange(RenPyImageChange change) {
    final scene = change.scene;
    if (scene != null) {
      _clearSpriteLayer(change.sceneOnLayer);
      _sceneSnapshot = RenPyVisualElementSnapshot(
        layer: _snapshotLayer(change.sceneOnLayer),
        imageName: scene,
        assetPath: change.sceneAsset,
        solidColor: change.sceneImage?.solidColor,
        operations: change.sceneImage?.operations ?? const [],
        placement: change.scenePlacement,
      );
    }

    final hiddenImage = change.hide;
    if (hiddenImage != null) {
      final tag = _imageTag(hiddenImage);
      final key = _spriteKey(tag, change.hideOnLayer);
      _spriteSnapshots.remove(key);
      _spritePlacements.remove(key);
    }

    final shownImage = change.show;
    if (shownImage == null) return;

    final tag = _imageTag(shownImage);
    final key = _spriteKey(tag, change.showOnLayer);
    final placement =
        change.showPlacement ??
        RenPyImagePlacement.parse(change.showAt) ??
        _spritePlacements[key] ??
        _defaultSpritePlacement;
    _spritePlacements[key] = placement;
    _spriteSnapshots[key] = RenPyVisualElementSnapshot(
      tag: tag,
      layer: _snapshotLayer(change.showOnLayer),
      imageName: shownImage,
      assetPath: change.showAsset,
      solidColor: change.showImage?.solidColor,
      operations: change.showImage?.operations ?? const [],
      placement: placement,
      text: change.showText,
    );
  }

  void _clearSpriteLayer(String? layer) {
    final normalized = _normalizedLayer(layer);
    _spriteSnapshots.removeWhere(
      (_, sprite) => _normalizedLayer(sprite.layer) == normalized,
    );
    _spritePlacements.removeWhere((key, _) => key.startsWith('$normalized::'));
  }

  String _spriteKey(String tag, String? layer) {
    return '${_normalizedLayer(layer)}::$tag';
  }

  String? _snapshotLayer(String? layer) {
    final normalized = _normalizedLayer(layer);
    return normalized == _masterLayer ? null : normalized;
  }

  String _normalizedLayer(String? layer) {
    final value = layer?.trim();
    return value == null || value.isEmpty ? _masterLayer : value;
  }

  void _recordAudioChange(RenPyAudioChange change) {
    switch (change.action) {
      case RenPyAudioAction.play:
        final asset = change.asset;
        if (asset != null && _shouldRecordAudioChange(change)) {
          _audioSnapshots[change.channel] = RenPyAudioChannelSnapshot(
            asset: asset,
            mixer: change.mixer,
            loop: change.loop,
          );
        } else if (asset != null) {
          _pendingTransientAudio.add(_transientAudioForChange(change));
        }
      case RenPyAudioAction.stop:
        _audioSnapshots.remove(change.channel);
    }
  }

  bool _shouldRecordAudioChange(RenPyAudioChange change) {
    return _shouldRestoreAudioChannel(
      change.channel,
      RenPyAudioChannelSnapshot(
        asset: change.asset!,
        mixer: change.mixer,
        loop: change.loop,
      ),
    );
  }

  bool _shouldRestoreAudioChannel(
    String channel,
    RenPyAudioChannelSnapshot snapshot,
  ) {
    return channel == 'music' ||
        snapshot.mixer == 'music' ||
        snapshot.loop == true;
  }

  RenPyTransientAudioSnapshot _transientAudioForChange(
    RenPyAudioChange change,
  ) {
    return RenPyTransientAudioSnapshot(
      channel: change.channel,
      asset: change.asset!,
      fadein: change.fadein,
      fadeout: change.fadeout,
      mixer: change.mixer,
      volume: change.volume,
      ifChanged: change.ifChanged,
      loop: change.loop,
    );
  }

  RenPyAudioChange _audioChangeForTransient(
    RenPyTransientAudioSnapshot transient,
  ) {
    return RenPyAudioChange.play(
      channel: transient.channel,
      asset: transient.asset,
      fadein: transient.fadein,
      fadeout: transient.fadeout,
      mixer: transient.mixer,
      volume: transient.volume,
      ifChanged: transient.ifChanged,
      loop: transient.loop,
    );
  }

  String _imageTag(String imageName) {
    final baseName = imageName.split('#').first.trim();
    if (baseName.isEmpty) return imageName;
    return baseName.split(RegExp(r'\s+')).first;
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
