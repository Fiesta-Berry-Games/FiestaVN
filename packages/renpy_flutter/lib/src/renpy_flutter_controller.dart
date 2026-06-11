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
    this.sceneZOrder,
    this.showBehind,
    this.showZOrder,
    this.scenePlacement,
    this.showPlacement,
    this.sceneAsset,
    this.showAsset,
    this.sceneImage,
    this.showImage,
    this.showText,
    this.showLayers = const [],
  });

  final String? scene;
  final String? show;
  final String? hide;
  final String? sceneAt;
  final String? showAt;
  final String? sceneOnLayer;
  final String? showOnLayer;
  final String? hideOnLayer;
  final int? sceneZOrder;
  final String? showBehind;
  final int? showZOrder;
  final RenPyImagePlacement? scenePlacement;
  final RenPyImagePlacement? showPlacement;
  final String? sceneAsset;
  final String? showAsset;
  final RenPyResolvedImage? sceneImage;
  final RenPyResolvedImage? showImage;
  final String? showText;

  /// The resolved, ordered (bottom-to-top) layer images of a `show` that named
  /// a layeredimage. Empty for an ordinary single-image show.
  final List<RenPyResolvedImage> showLayers;
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
    this.queued = false,
  }) : action = RenPyAudioAction.play;

  const RenPyAudioChange.stop({required this.channel, this.fadeout})
    : action = RenPyAudioAction.stop,
      asset = null,
      fadein = null,
      mixer = null,
      volume = null,
      ifChanged = null,
      loop = null,
      queued = false;

  final RenPyAudioAction action;
  final String channel;
  final String? asset;
  final String? fadein;
  final String? fadeout;
  final String? mixer;
  final String? volume;
  final bool? ifChanged;
  final bool? loop;

  /// Whether this play should append to the channel's playlist (queue) instead
  /// of replacing the current track.
  final bool queued;

  @override
  String toString() {
    return 'RenPyAudioChange.${queued ? 'queue' : action.name}'
        '(channel: $channel, asset: $asset, '
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

/// A single dialogue line recorded in the player's backlog/history.
final class RenPyBacklogEntry {
  const RenPyBacklogEntry({required this.text, this.character, this.color});

  /// The resolved display name shown to the player, or null for narration.
  final String? character;

  /// The raw dialogue text, including any inline RenPy tags.
  final String text;

  /// The raw RenPy color expression for the character, usually `#rrggbb`.
  final String? color;

  @override
  bool operator ==(Object other) =>
      other is RenPyBacklogEntry &&
      other.character == character &&
      other.text == text &&
      other.color == color;

  @override
  int get hashCode => Object.hash(character, text, color);

  @override
  String toString() {
    final name = character;
    return name == null || name.isEmpty
        ? 'RenPyBacklogEntry($text)'
        : 'RenPyBacklogEntry($name: $text)';
  }
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
    this.slotStore,
    this.backlogLimit = defaultBacklogLimit,
  }) : super(RenPyIdle());

  /// Default maximum number of dialogue lines kept in the backlog.
  static const defaultBacklogLimit = 200;

  /// Maximum number of dialogue lines retained in [dialogueHistory]. The
  /// oldest entries are dropped once this is exceeded to bound memory.
  final int backlogLimit;

  final VoidCallback? onComplete;
  final RenPyDiagnosticCallback? onDiagnostic;
  final RenPyPersistentStore? persistentStore;
  final RenPyRunnerSnapshotStore? snapshotStore;
  final RenPyRunnerSnapshotSlotStore? slotStore;

  RenPyRunner? _runner;
  _RunnerTicker? _ticker;
  Timer? _pauseTimer;
  Timer? _autoTimer;

  bool _skipEnabled = false;
  bool _autoForwardEnabled = false;

  /// Whether the current dialogue line has fully revealed (reported by the
  /// view via [notifyTextRevealed]); reset on each new line.
  bool _textRevealed = false;
  bool _suppressBacklog = false;
  double _autoDelay = 1.0;

  /// Per-line auto-forward base delay before applying the user's multiplier.
  static const _autoForwardBaseDelay = Duration(milliseconds: 1400);

  /// Fixed delay between skipped lines so audio and visuals can keep up.
  static const _skipLineDelay = Duration(milliseconds: 40);
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

  final List<RenPyBacklogEntry> _dialogueHistory = [];
  final ValueNotifier<List<RenPyBacklogEntry>> _dialogueHistoryNotifier =
      ValueNotifier<List<RenPyBacklogEntry>>(const []);

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

  /// The screens currently shown on the screen layer, in show order, or empty
  /// when no script is loaded.
  List<RenPyShownScreen> get shownScreens =>
      _runner?.shownScreens ?? const <RenPyShownScreen>[];

  /// The pending `call screen`, when one is blocking, or null.
  RenPyShownScreen? get pendingCallScreen => _runner?.pendingCallScreen;

  /// Resolves the shown screen named [name] against current engine state.
  /// Returns null when no script is loaded or the screen is not registered.
  RenPyResolvedScreen? resolveScreen(
    String name, {
    List<Object?> positional = const [],
    Map<String, Object?> keywords = const {},
  }) =>
      _runner?.resolveScreen(name, positional: positional, keywords: keywords);

  /// Substitutes RenPy `[expression]` references in [text] against current
  /// engine state, binding the named screen's parameters when supplied.
  String interpolateScreenText(
    String text, {
    String? screenName,
    List<Object?> positional = const [],
    Map<String, Object?> keywords = const {},
  }) =>
      _runner?.interpolateScreenText(
        text,
        screenName: screenName,
        positional: positional,
        keywords: keywords,
      ) ??
      text;

  /// Executes a parsed screen [action] against the runner, routing it through
  /// the engine and firing [onScreenLayerChanged] so the layer re-resolves.
  void executeScreenAction(RenPyScreenAction action) {
    _runner?.executeScreenAction(action);
  }

  /// Compiles the ATL animation for a `show X at <name>` transform, or returns
  /// null when the name is not a registered animatable transform. Used by the
  /// image layer to drive sprite animation.
  RenPyAtlProgram? resolveAtl(String transformName) {
    final runner = _runner;
    if (runner == null) return null;
    final atl = runner.atlForTransform(transformName);
    if (atl == null) return null;
    return RenPyAtlProgram.compile(atl, scope: runner.pythonScope);
  }

  /// Registers a listener for screen-layer changes (`show screen` / `Show` /
  /// `Hide` / a mutating action). Replaces any prior listener.
  set onScreenLayerChanged(
    void Function(List<RenPyShownScreen> shown)? listener,
  ) {
    _onScreenLayerChanged = listener;
    _runner?.onScreenLayerChanged = listener;
  }

  void Function(List<RenPyShownScreen> shown)? get onScreenLayerChanged =>
      _onScreenLayerChanged;

  void Function(List<RenPyShownScreen> shown)? _onScreenLayerChanged;

  bool get hasSnapshotStore => snapshotStore != null;

  bool get hasSlotStore => slotStore != null;

  bool get canRollback => _rollbackHistory.isNotEmpty;

  /// The dialogue lines shown so far, oldest first, capped at [backlogLimit].
  List<RenPyBacklogEntry> get dialogueHistory =>
      List.unmodifiable(_dialogueHistory);

  /// Notifies when [dialogueHistory] changes so a viewer can rebuild.
  ValueListenable<List<RenPyBacklogEntry>> get dialogueHistoryListenable =>
      _dialogueHistoryNotifier;

  /// Loads a `.rpy` script and immediately jumps to `start` when present.
  ///
  /// When [startLabel] is given and exists, execution begins there instead of
  /// at `start` — used by editors to preview a specific part of a script.
  ///
  /// Calling [load] again cleanly restarts the controller with the new script.
  void load(
    String source, {
    String filename = '<memory>',
    String? gameRoot,
    Set<String> availableAssets = const {},
    String? startLabel,
  }) {
    debugPrint('Loading RenPy script...');
    _ticker?.cancel();
    _pauseTimer?.cancel();
    _autoTimer?.cancel();
    _autoTimer = null;
    _textRevealed = false;
    _runner = null;
    _diagnostics.clear();
    _gameRoot = gameRoot;
    _availableAssets = availableAssets;
    _rollbackHistory.clear();
    _clearBacklog();
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

    final runner =
        RenPyRunner(result.script, persistentStore: persistentStore)
          ..configureCallbacks(this)
          ..onScreenLayerChanged = _onScreenLayerChanged;
    _runner = runner;

    final entryLabel =
        startLabel != null && result.script.findLabel(startLabel) != null
            ? startLabel
            : 'start';
    if (result.script.findLabel(entryLabel) != null) {
      debugPrint('Jumping to label $entryLabel');
      runner.jumpToLabel(entryLabel);
    } else {
      debugPrint('No start label found');
    }

    _startTicker();
    debugPrint('Starting initial execution...');
    runner.run();
  }

  /// The source line (1-based) of the most recently executed statement, or
  /// null before any script runs.
  int? get currentLine => _runner?.currentLine;

  /// Advances dialogue and input pauses until execution reaches [line]
  /// (1-based in the loaded file), a menu or other non-advanceable state, or
  /// [maxSteps] advances — whichever comes first. Used by editors to bring a
  /// freshly loaded preview to the beat at the cursor. A [line] past the end
  /// of the script settles on the script's last beat instead of its
  /// completion state.
  void fastForwardToLine(int line, {int maxSteps = 1000}) {
    for (var step = 0; step < maxSteps; step++) {
      final runner = _runner;
      if (runner == null) return;
      if (runner.state != RenPyRunnerState.waitingForInput) return;
      final current = runner.currentLine;
      if (current == null || current >= line) return;
      if (value is! RenPyDialogue && value is! RenPyPause) return;
      continueGame();
      if (_runner?.state == RenPyRunnerState.complete) {
        rollback();
        return;
      }
    }
  }

  /// Player pressed "next".
  void continueGame() {
    final runner = _runner;
    if (runner == null) return;
    if (runner.state == RenPyRunnerState.waitingForInput) {
      debugPrint('Continuing game execution...');
      _pauseTimer?.cancel();
      _pauseTimer = null;
      _autoTimer?.cancel();
      _autoTimer = null;
      _recordRollbackBoundary(runner);
      _pendingTransientAudio.clear();
      runner.continueExecution();
      _ticker?.resume();
    }
  }

  /// Whether skip mode is currently fast-forwarding dialogue.
  bool get skipEnabled => _skipEnabled;

  /// Whether auto-forward advances dialogue after each line is revealed.
  bool get autoForwardEnabled => _autoForwardEnabled;

  /// Enables or disables skip mode, scheduling the next advance immediately.
  set skipEnabled(bool value) {
    if (_skipEnabled == value) return;
    _skipEnabled = value;
    if (value) {
      _autoForwardEnabled = false;
      _maybeScheduleSkip();
    } else {
      _autoTimer?.cancel();
      _autoTimer = null;
    }
  }

  /// Enables or disables auto-forward. Auto only advances after a line has
  /// finished revealing; the view signals that through [notifyTextRevealed].
  /// Enabling while the current line is already revealed schedules the
  /// advance immediately, so the toggle takes effect on the parked line.
  set autoForwardEnabled(bool value) {
    if (_autoForwardEnabled == value) return;
    _autoForwardEnabled = value;
    if (value) {
      _skipEnabled = false;
      if (_textRevealed) _maybeScheduleAuto();
    } else {
      _autoTimer?.cancel();
      _autoTimer = null;
    }
  }

  /// Updates the auto-forward delay multiplier applied to the base per-line
  /// delay. Values are taken as-is; clamping is handled by the preference.
  set autoDelay(double value) => _autoDelay = value;

  /// Called by the dialogue view once the current line is fully revealed so
  /// auto-forward can begin its delay. The revealed state is remembered so
  /// enabling auto afterwards still advances the parked line.
  void notifyTextRevealed() {
    _textRevealed = true;
    if (!_autoForwardEnabled) return;
    _maybeScheduleAuto();
  }

  void _maybeScheduleSkip() {
    if (!_skipEnabled || !_canAutoAdvance) return;
    _autoTimer?.cancel();
    _autoTimer = Timer(_skipLineDelay, continueGame);
  }

  void _maybeScheduleAuto() {
    if (!_autoForwardEnabled || !_canAutoAdvance) return;
    _autoTimer?.cancel();
    final base = _autoForwardBaseDelay.inMilliseconds * _autoDelay;
    _autoTimer = Timer(Duration(milliseconds: base.round()), continueGame);
  }

  /// Whether skip/auto may advance the current line. Only dialogue and
  /// input pauses qualify; menus stop both modes, and an active {w}/{nw}
  /// auto-continue timer already owns the advance.
  bool get _canAutoAdvance {
    final runner = _runner;
    if (runner == null) return false;
    if (runner.state != RenPyRunnerState.waitingForInput) return false;
    if (_pauseTimer != null) return false;
    return value is RenPyDialogue || value is RenPyPause;
  }

  Future<bool> saveGame() async {
    final store = snapshotStore;
    final snapshot = _captureSnapshot();
    if (store == null || snapshot == null) return false;

    await store.save(snapshot);
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

  /// Writes the current state into the named [slot], capturing metadata so a
  /// browser can describe the save without decoding the full snapshot.
  Future<bool> saveToSlot(String slot) async {
    final store = slotStore;
    final snapshot = _captureSnapshot();
    if (store == null || snapshot == null) return false;

    await store.save(
      slot,
      RenPyRunnerSlotEntry(
        metadata: RenPyRunnerSlotMetadata(
          slot: slot,
          savedAt: DateTime.now(),
          label: snapshot.currentLabel,
          preview: _slotPreview(snapshot),
        ),
        snapshot: snapshot,
      ),
    );
    return true;
  }

  /// Restores the snapshot stored in the named [slot], if any.
  Future<bool> loadFromSlot(String slot) async {
    final store = slotStore;
    final runner = _runner;
    if (store == null || runner == null) return false;

    final entry = await store.load(slot);
    if (entry == null) return false;

    restoreSnapshot(entry.snapshot);
    return true;
  }

  /// Removes the snapshot stored in the named [slot].
  Future<bool> deleteSlot(String slot) async {
    final store = slotStore;
    if (store == null) return false;

    await store.delete(slot);
    return true;
  }

  /// Lists the metadata for every populated save slot.
  Future<List<RenPyRunnerSlotMetadata>> listSaveSlots() async {
    final store = slotStore;
    if (store == null) return const [];

    return store.list();
  }

  RenPyRunnerSnapshot? _captureSnapshot() {
    final runner = _runner;
    if (runner == null) return null;
    if (runner.state != RenPyRunnerState.waitingForInput) return null;

    return runner.snapshot().withPresentation(
      _presentationSnapshot(includeTransientAudio: false),
    );
  }

  String? _slotPreview(RenPyRunnerSnapshot snapshot) {
    final dialogue = snapshot.lastDialogue;
    if (dialogue == null) return null;
    final name = dialogue.displayName;
    final text = dialogue.text;
    return name == null || name.isEmpty ? text : '$name: $text';
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
    _autoTimer?.cancel();
    _autoTimer = null;
    _ticker?.pause();

    // Restoring re-presents the current line through the normal dialogue
    // path. Reset the backlog to a clean state and seed it with the restored
    // line so the viewer never shows lines ahead of the current position.
    _clearBacklog();
    _suppressBacklog = true;
    try {
      runner.restoreSnapshot(snapshot);
      _restorePresentation(snapshot.presentation);
      _presentRestoredRunner(snapshot, runner);
    } finally {
      _suppressBacklog = false;
    }

    final restored = snapshot.lastDialogue;
    if (restored != null) {
      _recordBacklog(
        RenPyBacklogEntry(
          character: restored.displayName,
          text: restored.text,
          color: restored.color,
        ),
      );
    }
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
    _ticker = _RunnerTicker(_tick)..resume();
  }

  void _tick() {
    final runner = _runner;
    if (runner == null) return;

    switch (runner.state) {
      case RenPyRunnerState.waitingForInput:
        _ticker?.pause();
        // Now that the runner is parked, skip can fast-forward this line.
        _maybeScheduleSkip();
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
  }

  void _onDialogueEvent(RenPyDialogueEvent event) {
    debugPrint('Dialogue: ${event.displayName ?? "Narrator"}: ${event.text}');
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _autoTimer?.cancel();
    _autoTimer = null;
    _textRevealed = false;
    _recordBacklog(
      RenPyBacklogEntry(
        character: event.displayName,
        text: event.text,
        color: event.color,
      ),
    );
    value = RenPyDialogue(
      event.displayName,
      event.text,
      displayText: event.displayText,
      characterId: event.characterId,
      color: event.color,
    );

    // Skip is scheduled from _tick once the runner parks at this line, and
    // auto-forward waits for the view to report the line fully revealed.
    final duration = event.autoContinueDuration;
    if (duration == null) return;
    _pauseTimer = Timer(
      Duration(milliseconds: (duration * 1000).round()),
      continueGame,
    );
  }

  void _onMenu(
    List<String> choices,
    void Function(int index) onChoice,
    String? caption,
  ) {
    debugPrint('Menu with choices: $choices');
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _autoTimer?.cancel();
    _autoTimer = null;
    // Skip and auto-forward both stop at menus so the player can choose.
    _skipEnabled = false;
    _autoForwardEnabled = false;
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
    _autoTimer?.cancel();
    _autoTimer = null;
    _ticker?.pause();
    value = RenPyPause(duration: event.duration);

    final duration = event.duration;
    if (duration != null) {
      _pauseTimer?.cancel();
      _pauseTimer = Timer(
        Duration(milliseconds: (duration * 1000).round()),
        continueGame,
      );
      return;
    }

    // A pause that waits for input also accepts skip/auto advancement. Defer
    // so the runner has settled into its wait state before we schedule.
    scheduleMicrotask(() {
      _maybeScheduleSkip();
      _maybeScheduleAuto();
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
          sceneZOrder: event.zOrder,
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
        final showLayers = _resolveLayeredImageLayers(event.layers);
        change = RenPyImageChange(
          show: event.imageName,
          showAt: event.at,
          showOnLayer: event.onLayer,
          showBehind: event.behind,
          showZOrder: event.zOrder,
          showPlacement: event.placement,
          showAsset: image?.assetPath,
          showImage: image,
          showText: event.displayableText,
          showLayers: showLayers,
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

  /// Resolves each layeredimage layer name to an asset, dropping any that fail
  /// to resolve so a partially-missing composite still renders the rest.
  List<RenPyResolvedImage> _resolveLayeredImageLayers(List<String> names) {
    if (names.isEmpty) return const [];
    final resolved = <RenPyResolvedImage>[];
    for (final name in names) {
      final image = _imageResolver.resolveImage(name);
      _diagnoseResolvedImage(name, image);
      if (image != null) resolved.add(image);
    }
    return resolved;
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
          queued: event.queued,
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

  /// Appends [entry] to the backlog unless it merely re-presents the current
  /// line (snapshot/rollback restore) or duplicates the last recorded line.
  /// Enforces [backlogLimit] by dropping the oldest entries.
  void _recordBacklog(RenPyBacklogEntry entry) {
    if (_suppressBacklog) return;
    if (_dialogueHistory.isNotEmpty && _dialogueHistory.last == entry) return;

    _dialogueHistory.add(entry);
    while (_dialogueHistory.length > backlogLimit && backlogLimit >= 0) {
      _dialogueHistory.removeAt(0);
    }
    _publishBacklog();
  }

  void _clearBacklog() {
    if (_dialogueHistory.isEmpty) return;
    _dialogueHistory.clear();
    _publishBacklog();
  }

  void _publishBacklog() {
    _dialogueHistoryNotifier.value = List.unmodifiable(_dialogueHistory);
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
    final scene = visual.scene;
    _sceneSnapshot =
        scene == null || !_isMasterLayer(scene.layer) ? null : scene;
    _spriteSnapshots.clear();
    _spritePlacements.clear();

    if (scene != null && !_isMasterLayer(scene.layer)) {
      _restoreSpriteSnapshot(scene);
    }

    for (final sprite in visual.sprites) {
      _restoreSpriteSnapshot(sprite);
    }
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
      if (_isMasterLayer(change.sceneOnLayer)) {
        _sceneSnapshot = RenPyVisualElementSnapshot(
          imageName: scene,
          assetPath: change.sceneAsset,
          solidColor: change.sceneImage?.solidColor,
          operations: change.sceneImage?.operations ?? const [],
          placement: change.scenePlacement,
          zOrder: change.sceneZOrder,
        );
      } else {
        final tag = _imageTag(scene);
        final key = _spriteKey(tag, change.sceneOnLayer);
        final placement =
            change.scenePlacement ??
            RenPyImagePlacement.parse(change.sceneAt) ??
            _defaultSpritePlacement;
        _spritePlacements[key] = placement;
        _spriteSnapshots[key] = RenPyVisualElementSnapshot(
          tag: tag,
          layer: _snapshotLayer(change.sceneOnLayer),
          imageName: scene,
          assetPath: change.sceneAsset,
          solidColor: change.sceneImage?.solidColor,
          operations: change.sceneImage?.operations ?? const [],
          placement: placement,
          zOrder: change.sceneZOrder,
        );
      }
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
    final snapshot = RenPyVisualElementSnapshot(
      tag: tag,
      layer: _snapshotLayer(change.showOnLayer),
      imageName: shownImage,
      assetPath: change.showAsset,
      solidColor: change.showImage?.solidColor,
      operations: change.showImage?.operations ?? const [],
      placement: placement,
      zOrder: change.showZOrder,
      text: change.showText,
    );
    _putSpriteSnapshot(key, snapshot, behind: change.showBehind);
  }

  void _clearSpriteLayer(String? layer) {
    final normalized = _normalizedLayer(layer);
    _spriteSnapshots.removeWhere(
      (_, sprite) => _normalizedLayer(sprite.layer) == normalized,
    );
    _spritePlacements.removeWhere((key, _) => key.startsWith('$normalized::'));
  }

  void _restoreSpriteSnapshot(RenPyVisualElementSnapshot sprite) {
    final tag = sprite.tag ?? _tagForSnapshot(sprite);
    if (tag == null) return;

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
      zOrder: sprite.zOrder,
      text: sprite.text,
    );
  }

  void _putSpriteSnapshot(
    String key,
    RenPyVisualElementSnapshot snapshot, {
    String? behind,
  }) {
    _spriteSnapshots.remove(key);

    final behindValue = behind?.trim();
    final target =
        behindValue == null || behindValue.isEmpty
            ? null
            : behindValue.split(RegExp(r'\s+')).first;
    if (target == null || target.isEmpty) {
      _spriteSnapshots[key] = snapshot;
      return;
    }

    final targetKey = _spriteKey(target, snapshot.layer);
    if (!_spriteSnapshots.containsKey(targetKey)) {
      _spriteSnapshots[key] = snapshot;
      return;
    }

    final ordered = <String, RenPyVisualElementSnapshot>{};
    for (final entry in _spriteSnapshots.entries) {
      if (entry.key == targetKey) {
        ordered[key] = snapshot;
      }
      ordered[entry.key] = entry.value;
    }

    _spriteSnapshots
      ..clear()
      ..addAll(ordered);
  }

  String _spriteKey(String tag, String? layer) {
    return '${_normalizedLayer(layer)}::$tag';
  }

  String? _snapshotLayer(String? layer) {
    final normalized = _normalizedLayer(layer);
    return normalized == _masterLayer ? null : normalized;
  }

  bool _isMasterLayer(String? layer) {
    return _normalizedLayer(layer) == _masterLayer;
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
    _autoTimer?.cancel();
    _dialogueHistoryNotifier.dispose();
    super.dispose();
  }
}

/// Drains the runner one step per microtask while resumed.
///
/// Mirrors the [pause]/[resume]/[cancel] surface the controller relied on when
/// the ticker was a periodic stream subscription, but only schedules work while
/// running so it never busy-spins. The [onTick] callback is expected to pause
/// the ticker once the runner reaches a wait point and to cancel it on
/// completion or error.
class _RunnerTicker {
  _RunnerTicker(this.onTick);

  final void Function() onTick;

  bool _paused = true;
  bool _cancelled = false;
  bool _scheduled = false;

  void resume() {
    if (_cancelled || !_paused) return;
    _paused = false;
    _schedule();
  }

  void pause() {
    _paused = true;
  }

  void cancel() {
    _cancelled = true;
    _paused = true;
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    scheduleMicrotask(_drain);
  }

  void _drain() {
    _scheduled = false;
    if (_cancelled || _paused) return;
    onTick();
    if (_cancelled || _paused) return;
    _schedule();
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
