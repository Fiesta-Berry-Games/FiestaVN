import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renpy_core/renpy_core.dart';

import 'renpy_audio_layer.dart';
import 'renpy_chrome.dart';
import 'renpy_flutter_controller.dart';
import 'renpy_image_layer.dart';
import 'renpy_preference_store.dart';
import 'renpy_save_browser.dart';
import 'renpy_screen_layer.dart';

typedef RenPyLayerBuilder =
    Widget Function(BuildContext context, RenPyFlutterController controller);
typedef RenPyLoadingBuilder = Widget Function(BuildContext context);
typedef RenPyLoadErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);
typedef RenPyProjectFontRegistrar =
    Future<void> Function(String family, Uint8List bytes);

/// A reusable visual novel surface for an already-managed controller.
class RenPyPlayer extends StatelessWidget {
  const RenPyPlayer({
    super.key,
    required this.controller,
    this.backgroundColor = const Color(0xFF212121),
    this.showRestartButton = true,
    this.onRestart,
    this.imageLayerBuilder,
    this.gameRoot = '',
    this.dialogueImageProvider,
    this.dialogueImageResolver,
    this.screenSize,
    this.audioPlayback,
    this.preferenceStore,
    this.dialogueStyle,
    this.gui,
    this.layerOrder,
    this.screenImageProvider,
  });

  final RenPyFlutterController controller;
  final Color backgroundColor;
  final bool showRestartButton;
  final VoidCallback? onRestart;
  final RenPyLayerBuilder? imageLayerBuilder;
  final String gameRoot;
  final RenPyScreenSize? screenSize;
  final RenPyAudioPlayback? audioPlayback;
  final RenPyImageProviderFactory? dialogueImageProvider;
  final RenPyDialogueImageResolver? dialogueImageResolver;
  final RenPyPreferenceStore? preferenceStore;
  final TextStyle? dialogueStyle;
  final RenPyGuiConfiguration? gui;
  final List<String>? layerOrder;

  /// Resolves screen-layer image assets (`add`/`imagebutton`) to providers.
  final RenPyImageProviderFactory? screenImageProvider;

  Future<void> _saveGame(BuildContext context) async {
    final saved = await controller.saveGame();
    if (!context.mounted) return;
    _showSnackBar(context, saved ? 'Game saved.' : 'Nothing to save.');
  }

  Future<void> _loadGame(BuildContext context) async {
    final loaded = await controller.loadSavedGame();
    if (!context.mounted) return;
    _showSnackBar(context, loaded ? 'Game loaded.' : 'No saved game.');
  }

  bool _rollbackGame(
    BuildContext context, {
    bool showUnavailableMessage = true,
  }) {
    final rolledBack = controller.rollback();
    if (!context.mounted) return false;
    if (!rolledBack && showUnavailableMessage) {
      _showSnackBar(context, 'Nothing to roll back.');
    }
    return rolledBack;
  }

  KeyEventResult _handleKeyEvent(BuildContext context, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.pageUp) {
      return KeyEventResult.ignored;
    }
    return _rollbackGame(context, showUnavailableMessage: false)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _handlePointerSignal(BuildContext context, PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy >= 0) return;
    _rollbackGame(context, showUnavailableMessage: false);
  }

  void _showSnackBar(BuildContext context, String message) {
    if (Scaffold.maybeOf(context) == null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildStageBox(Widget child) {
    const stageKey = ValueKey('renpy-player-stage');
    final size = screenSize;
    if (size == null) {
      return SizedBox.expand(key: stageKey, child: child);
    }

    return Center(
      child: AspectRatio(
        key: stageKey,
        aspectRatio: size.aspectRatio,
        child: child,
      ),
    );
  }

  Widget _buildGameStage(
    BuildContext context,
    RenPyPlayerPreferences preferences,
    VoidCallback onOpenBacklog,
  ) {
    controller
      ..autoDelay = preferences.autoDelay
      ..skipEnabled = preferences.skip
      ..autoForwardEnabled = preferences.autoForward;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageLayerBuilder != null)
          imageLayerBuilder!(context, controller)
        else
          RenPyImageLayer(
            controller: controller,
            screenSize: screenSize,
            layerOrder: layerOrder,
            atlResolver: controller.resolveAtl,
          ),
        RenPyAudioLayer(
          controller: controller,
          gameRoot: gameRoot,
          playback: audioPlayback,
          preferences: preferences,
        ),
        RenPyPauseView(controller: controller),
        RenPyDialogueView(
          controller: controller,
          dialogueStyle: dialogueStyle,
          screenSize: screenSize,
          gui: gui,
          imageProvider: dialogueImageProvider,
          imageResolver: dialogueImageResolver,
          textCps: preferences.textCps,
        ),
        RenPyMenuSelector(controller: controller),
        RenPyScreenLayer(
          controller: controller,
          imageProvider: screenImageProvider,
        ),
        ValueListenableBuilder<RenPyGameStatus>(
          valueListenable: controller,
          builder: (context, status, child) {
            final hasRestart = showRestartButton && onRestart != null;

            return PositionedDirectional(
              end: 16,
              top: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    key: const ValueKey('renpy-open-backlog'),
                    tooltip: 'History',
                    heroTag: null,
                    onPressed: onOpenBacklog,
                    child: const Icon(Icons.history),
                  ),
                  if (controller.canRollback) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      tooltip: 'Rollback',
                      heroTag: null,
                      onPressed: () => _rollbackGame(context),
                      child: const Icon(Icons.undo),
                    ),
                  ],
                  if (controller.hasSnapshotStore) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      tooltip: 'Save',
                      heroTag: null,
                      onPressed: () => unawaited(_saveGame(context)),
                      child: const Icon(Icons.save),
                    ),
                    const SizedBox(height: 8),
                    FloatingActionButton.small(
                      tooltip: 'Load',
                      heroTag: null,
                      onPressed: () => unawaited(_loadGame(context)),
                      child: const Icon(Icons.folder_open),
                    ),
                  ],
                  if (hasRestart) ...[
                    const SizedBox(height: 8),
                    FloatingActionButton(
                      tooltip: 'Restart',
                      onPressed: onRestart,
                      child: const Icon(Icons.refresh),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _RenPyInputSurface(
      preferenceStore: preferenceStore,
      gameMenuBuilder: (
        closeGameMenu,
        preferences,
        setMixerMuted,
        setMixerVolume,
        pacing,
      ) {
        return _RenPyGameMenu(
          controller: controller,
          preferences: preferences,
          canSaveLoad: controller.hasSnapshotStore,
          canBrowseSlots: controller.hasSlotStore,
          canRestart: showRestartButton && onRestart != null,
          onResume: closeGameMenu,
          onMixerMutedChanged: setMixerMuted,
          onMixerVolumeChanged: setMixerVolume,
          pacing: pacing,
          onSave: () => unawaited(_saveGame(context)),
          onLoad: () {
            closeGameMenu();
            unawaited(_loadGame(context));
          },
          onRestart: () {
            final restart = onRestart;
            if (restart == null) return;
            closeGameMenu();
            restart();
          },
          onSlotLoaded: closeGameMenu,
        );
      },
      backlogBuilder: (closeBacklog) {
        return RenPyBacklogView(
          controller: controller,
          onClose: closeBacklog,
          dialogueStyle: dialogueStyle,
        );
      },
      onKeyEvent: (event) => _handleKeyEvent(context, event),
      onPointerSignal: (event) => _handlePointerSignal(context, event),
      childBuilder: (preferences, openBacklog) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: backgroundColor),
            _buildStageBox(_buildGameStage(context, preferences, openBacklog)),
          ],
        );
      },
    );
  }
}

typedef _RenPyMixerMutedSetter = void Function(String mixer, bool muted);
typedef _RenPyMixerVolumeSetter = void Function(String mixer, double volume);

/// Setters for the playback-pacing preferences shared by the menu and chrome.
class _RenPyPacingSetters {
  const _RenPyPacingSetters({
    required this.setTextCps,
    required this.setAutoDelay,
    required this.setAutoForward,
    required this.setSkip,
  });

  final ValueChanged<double> setTextCps;
  final ValueChanged<double> setAutoDelay;
  final ValueChanged<bool> setAutoForward;
  final ValueChanged<bool> setSkip;
}

class _RenPyInputSurface extends StatefulWidget {
  const _RenPyInputSurface({
    required this.childBuilder,
    required this.gameMenuBuilder,
    required this.backlogBuilder,
    required this.onKeyEvent,
    required this.onPointerSignal,
    this.preferenceStore,
  });

  final Widget Function(
    RenPyPlayerPreferences preferences,
    VoidCallback openBacklog,
  )
  childBuilder;
  final Widget Function(
    VoidCallback closeGameMenu,
    RenPyPlayerPreferences preferences,
    _RenPyMixerMutedSetter setMixerMuted,
    _RenPyMixerVolumeSetter setMixerVolume,
    _RenPyPacingSetters pacing,
  )
  gameMenuBuilder;
  final Widget Function(VoidCallback closeBacklog) backlogBuilder;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final ValueChanged<PointerSignalEvent> onPointerSignal;
  final RenPyPreferenceStore? preferenceStore;

  @override
  State<_RenPyInputSurface> createState() => _RenPyInputSurfaceState();
}

class _RenPyInputSurfaceState extends State<_RenPyInputSurface> {
  late final FocusNode _focusNode;
  late RenPyPlayerPreferences _preferences;
  bool _gameMenuOpen = false;
  bool _backlogOpen = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'RenPy player input');
    _preferences = _loadPreferences();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
  }

  @override
  void didUpdateWidget(_RenPyInputSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.preferenceStore, widget.preferenceStore)) {
      _preferences = _loadPreferences();
    }
  }

  RenPyPlayerPreferences _loadPreferences() {
    return RenPyPlayerPreferences.fromJson(
      widget.preferenceStore?.load() ?? const {},
    );
  }

  void _requestFocus() {
    if (!mounted || _focusNode.hasFocus) return;
    _focusNode.requestFocus();
  }

  void _openGameMenu() {
    if (_gameMenuOpen) return;
    setState(() => _gameMenuOpen = true);
    _requestFocus();
  }

  void _closeGameMenu() {
    if (!_gameMenuOpen) return;
    setState(() => _gameMenuOpen = false);
    _requestFocus();
  }

  void _openBacklog() {
    if (_backlogOpen) return;
    setState(() => _backlogOpen = true);
    _requestFocus();
  }

  void _closeBacklog() {
    if (!_backlogOpen) return;
    setState(() => _backlogOpen = false);
    _requestFocus();
  }

  void _setMixerMuted(String mixer, bool muted) {
    if (_preferences.isMixerMuted(mixer) == muted) return;
    setState(() {
      _preferences = _preferences.setMixerMuted(mixer, muted);
    });
    _savePreferences();
  }

  void _setMixerVolume(String mixer, double volume) {
    final updated = _preferences.setMixerVolume(mixer, volume);
    if (updated.mixerVolume(mixer) == _preferences.mixerVolume(mixer)) return;
    setState(() {
      _preferences = updated;
    });
    _savePreferences();
  }

  void _setTextCps(double cps) {
    final updated = _preferences.setTextCps(cps);
    if (updated.textCps == _preferences.textCps) return;
    setState(() => _preferences = updated);
    _savePreferences();
  }

  void _setAutoDelay(double delay) {
    final updated = _preferences.setAutoDelay(delay);
    if (updated.autoDelay == _preferences.autoDelay) return;
    setState(() => _preferences = updated);
    _savePreferences();
  }

  void _setAutoForward(bool enabled) {
    if (_preferences.autoForward == enabled) return;
    setState(() {
      _preferences = _preferences.setAutoForward(enabled);
      // Skip and auto are mutually exclusive, matching Ren'Py.
      if (enabled) _preferences = _preferences.setSkip(false);
    });
    _savePreferences();
  }

  void _setSkip(bool enabled) {
    if (_preferences.skip == enabled) return;
    setState(() {
      _preferences = _preferences.setSkip(enabled);
      if (enabled) _preferences = _preferences.setAutoForward(false);
    });
    _savePreferences();
  }

  _RenPyPacingSetters get _pacingSetters => _RenPyPacingSetters(
    setTextCps: _setTextCps,
    setAutoDelay: _setAutoDelay,
    setAutoForward: _setAutoForward,
    setSkip: _setSkip,
  );

  void _savePreferences() {
    widget.preferenceStore?.save(_preferences.toJson());
  }

  void _toggleMusicMuted() => _setMixerMuted(
    RenPyPlayerPreferences.musicMixer,
    !_preferences.musicMuted,
  );

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (_backlogOpen) {
        _closeBacklog();
      } else {
        _gameMenuOpen ? _closeGameMenu() : _openGameMenu();
      }
      return KeyEventResult.handled;
    }
    if (_backlogOpen) return KeyEventResult.handled;
    if (!_gameMenuOpen &&
        (event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.keyM) {
      _toggleMusicMuted();
      return KeyEventResult.handled;
    }
    return _gameMenuOpen ? KeyEventResult.handled : widget.onKeyEvent(event);
  }

  void _handlePointerDown(PointerDownEvent event) {
    _requestFocus();
    if (_backlogOpen) return;
    if ((event.buttons & kSecondaryMouseButton) != 0) _openGameMenu();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_gameMenuOpen || _backlogOpen) return;
    widget.onPointerSignal(event);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _handlePointerDown,
        onPointerSignal: _handlePointerSignal,
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.childBuilder(_preferences, _openBacklog),
            if (!_gameMenuOpen && !_backlogOpen)
              _RenPyPacingToggles(
                skip: _preferences.skip,
                autoForward: _preferences.autoForward,
                onSkipChanged: _setSkip,
                onAutoForwardChanged: _setAutoForward,
              ),
            if (_gameMenuOpen)
              widget.gameMenuBuilder(
                _closeGameMenu,
                _preferences,
                _setMixerMuted,
                _setMixerVolume,
                _pacingSetters,
              ),
            if (_backlogOpen) widget.backlogBuilder(_closeBacklog),
          ],
        ),
      ),
    );
  }
}

/// On-screen Skip and Auto toggles shown over the player chrome.
class _RenPyPacingToggles extends StatelessWidget {
  const _RenPyPacingToggles({
    required this.skip,
    required this.autoForward,
    required this.onSkipChanged,
    required this.onAutoForwardChanged,
  });

  final bool skip;
  final bool autoForward;
  final ValueChanged<bool> onSkipChanged;
  final ValueChanged<bool> onAutoForwardChanged;

  @override
  Widget build(BuildContext context) {
    return PositionedDirectional(
      start: 16,
      top: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            key: const ValueKey('renpy-toggle-skip'),
            tooltip: 'Skip',
            heroTag: null,
            backgroundColor:
                skip ? Theme.of(context).colorScheme.primary : null,
            onPressed: () => onSkipChanged(!skip),
            child: const Icon(Icons.fast_forward),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            key: const ValueKey('renpy-toggle-auto'),
            tooltip: 'Auto',
            heroTag: null,
            backgroundColor:
                autoForward ? Theme.of(context).colorScheme.primary : null,
            onPressed: () => onAutoForwardChanged(!autoForward),
            child: const Icon(Icons.play_circle_outline),
          ),
        ],
      ),
    );
  }
}

enum _RenPyGameMenuView { root, preferences, save, load }

class _RenPyGameMenu extends StatefulWidget {
  const _RenPyGameMenu({
    required this.controller,
    required this.preferences,
    required this.canSaveLoad,
    required this.canBrowseSlots,
    required this.canRestart,
    required this.onResume,
    required this.onMixerMutedChanged,
    required this.onMixerVolumeChanged,
    required this.pacing,
    required this.onSave,
    required this.onLoad,
    required this.onRestart,
    required this.onSlotLoaded,
  });

  final RenPyFlutterController controller;
  final RenPyPlayerPreferences preferences;
  final _RenPyPacingSetters pacing;
  final bool canSaveLoad;
  final bool canBrowseSlots;
  final bool canRestart;
  final VoidCallback onResume;
  final _RenPyMixerMutedSetter onMixerMutedChanged;
  final _RenPyMixerVolumeSetter onMixerVolumeChanged;
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback onRestart;
  final VoidCallback onSlotLoaded;

  @override
  State<_RenPyGameMenu> createState() => _RenPyGameMenuState();
}

class _RenPyGameMenuState extends State<_RenPyGameMenu> {
  _RenPyGameMenuView _view = _RenPyGameMenuView.root;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320, maxHeight: 480),
            child: Material(
              color: colorScheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildView(context),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildView(BuildContext context) {
    switch (_view) {
      case _RenPyGameMenuView.preferences:
        return _buildPreferences(context);
      case _RenPyGameMenuView.save:
        return RenPySaveBrowser(
          controller: widget.controller,
          mode: RenPySaveBrowserMode.save,
          onClose: () => setState(() => _view = _RenPyGameMenuView.root),
        );
      case _RenPyGameMenuView.load:
        return RenPySaveBrowser(
          controller: widget.controller,
          mode: RenPySaveBrowserMode.load,
          onClose: widget.onSlotLoaded,
        );
      case _RenPyGameMenuView.root:
        return _buildRootMenu(context);
    }
  }

  Widget _buildRootMenu(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Game Menu',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: widget.onResume,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Resume'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed:
              () => setState(() => _view = _RenPyGameMenuView.preferences),
          icon: const Icon(Icons.tune),
          label: const Text('Preferences'),
        ),
        if (widget.canBrowseSlots) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _view = _RenPyGameMenuView.save),
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _view = _RenPyGameMenuView.load),
            icon: const Icon(Icons.folder_open),
            label: const Text('Load'),
          ),
        ] else if (widget.canSaveLoad) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onSave,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onLoad,
            icon: const Icon(Icons.folder_open),
            label: const Text('Load'),
          ),
        ],
        if (widget.canRestart) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.onRestart,
            icon: const Icon(Icons.refresh),
            label: const Text('Restart'),
          ),
        ],
      ],
    );
  }

  Widget _buildPreferences(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Preferences',
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Music Muted'),
            value: widget.preferences.musicMuted,
            onChanged: (value) {
              if (value == null) return;
              widget.onMixerMutedChanged(
                RenPyPlayerPreferences.musicMixer,
                value,
              );
            },
          ),
          const SizedBox(height: 8),
          _buildMixerSlider(
            label: 'Music Volume',
            mixer: RenPyPlayerPreferences.musicMixer,
            key: const ValueKey('renpy-preference-music-volume'),
          ),
          const SizedBox(height: 8),
          _buildMixerSlider(
            label: 'Sound Volume',
            mixer: RenPyPlayerPreferences.sfxMixer,
            key: const ValueKey('renpy-preference-sound-volume'),
          ),
          const SizedBox(height: 8),
          _buildMixerSlider(
            label: 'Voice Volume',
            mixer: RenPyPlayerPreferences.voiceMixer,
            key: const ValueKey('renpy-preference-voice-volume'),
          ),
          const SizedBox(height: 8),
          _buildTextSpeedSlider(),
          const SizedBox(height: 8),
          _buildAutoDelaySlider(),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('renpy-preference-skip'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Skip'),
            value: widget.preferences.skip,
            onChanged: (value) {
              if (value == null) return;
              widget.pacing.setSkip(value);
            },
          ),
          CheckboxListTile(
            key: const ValueKey('renpy-preference-auto-forward'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto Forward'),
            value: widget.preferences.autoForward,
            onChanged: (value) {
              if (value == null) return;
              widget.pacing.setAutoForward(value);
            },
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _view = _RenPyGameMenuView.root),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextSpeedSlider() {
    final cps = widget.preferences.textCps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(cps <= 0 ? 'Text Speed (Instant)' : 'Text Speed'),
        Slider(
          key: const ValueKey('renpy-preference-text-speed'),
          value: cps,
          min: 0,
          max: RenPyPlayerPreferences.maxTextCps,
          onChanged: widget.pacing.setTextCps,
        ),
      ],
    );
  }

  Widget _buildAutoDelaySlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Auto-Forward Delay'),
        Slider(
          key: const ValueKey('renpy-preference-auto-delay'),
          value: widget.preferences.autoDelay,
          min: RenPyPlayerPreferences.minAutoDelay,
          max: RenPyPlayerPreferences.maxAutoDelay,
          onChanged: widget.pacing.setAutoDelay,
        ),
      ],
    );
  }

  Widget _buildMixerSlider({
    required String label,
    required String mixer,
    required Key key,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label),
        Slider(
          key: key,
          value: widget.preferences.mixerVolume(mixer),
          onChanged: (value) {
            widget.onMixerVolumeChanged(mixer, value);
          },
        ),
      ],
    );
  }
}

/// Loads a bundled RenPy script asset and displays it with [RenPyPlayer].
class RenPyAssetPlayer extends StatefulWidget {
  const RenPyAssetPlayer({
    super.key,
    required this.scriptAsset,
    this.bundle,
    this.gameRoot,
    this.availableAssets,
    this.backgroundColor = const Color(0xFF212121),
    this.persistentStore,
    this.snapshotStore,
    this.slotStore,
    this.showRestartButton = true,
    this.imageLayerBuilder,
    this.audioPlayback,
    this.loadingBuilder,
    this.loadErrorBuilder,
    this.onControllerCreated,
    this.preferenceStore,
  });

  final String scriptAsset;
  final AssetBundle? bundle;
  final String? gameRoot;
  final Set<String>? availableAssets;
  final Color backgroundColor;
  final bool showRestartButton;
  final RenPyLayerBuilder? imageLayerBuilder;
  final RenPyRunnerSnapshotStore? snapshotStore;
  final RenPyRunnerSnapshotSlotStore? slotStore;
  final RenPyAudioPlayback? audioPlayback;
  final RenPyLoadingBuilder? loadingBuilder;
  final RenPyPersistentStore? persistentStore;
  final RenPyLoadErrorBuilder? loadErrorBuilder;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;
  final RenPyPreferenceStore? preferenceStore;

  @override
  State<RenPyAssetPlayer> createState() => _RenPyAssetPlayerState();
}

/// Displays an externally loaded RenPy project folder.
class RenPyProjectPlayer extends StatefulWidget {
  const RenPyProjectPlayer({
    super.key,
    required this.project,
    this.availableAssets,
    this.backgroundColor = const Color(0xFF212121),
    this.showRestartButton = true,
    this.imageLayerBuilder,
    this.audioPlayback,
    this.fontRegistrar,
    this.onControllerCreated,
    this.persistentStore,
    this.snapshotStore,
    this.slotStore,
    this.preferenceStore,
  });

  final RenPyGameProject project;
  final Set<String>? availableAssets;
  final Color backgroundColor;
  final bool showRestartButton;
  final RenPyLayerBuilder? imageLayerBuilder;
  final RenPyAudioPlayback? audioPlayback;
  final RenPyProjectFontRegistrar? fontRegistrar;
  final ValueChanged<RenPyFlutterController>? onControllerCreated;
  final RenPyPersistentStore? persistentStore;
  final RenPyRunnerSnapshotStore? snapshotStore;
  final RenPyRunnerSnapshotSlotStore? slotStore;

  final RenPyPreferenceStore? preferenceStore;
  @override
  State<RenPyProjectPlayer> createState() => _RenPyProjectPlayerState();
}

class _RenPyProjectPlayerState extends State<RenPyProjectPlayer> {
  late final RenPyFlutterController _controller;
  RenPyBytesAudioPlayback? _ownedAudioPlayback;
  int _bootstrapGeneration = 0;

  @override
  void initState() {
    super.initState();
    _controller = RenPyFlutterController(
      persistentStore: widget.persistentStore,
      snapshotStore: widget.snapshotStore,
      slotStore: widget.slotStore,
    );
    widget.onControllerCreated?.call(_controller);
    _configureOwnedAudio();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrapProject();
    });
  }

  @override
  void didUpdateWidget(RenPyProjectPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.project, widget.project) ||
        !identical(oldWidget.audioPlayback, widget.audioPlayback) ||
        !identical(oldWidget.fontRegistrar, widget.fontRegistrar)) {
      // Stop and dispose the previous owned backend before the new one starts,
      // so the two cannot race over the same channels.
      final previousAudio = _ownedAudioPlayback;
      _configureOwnedAudio();
      previousAudio?.dispose();
      _bootstrapProject();
    }
  }

  void _configureOwnedAudio() {
    _ownedAudioPlayback =
        widget.audioPlayback == null
            ? RenPyBytesAudioPlayback(
              widget.project.assetBytes,
              readAsset: widget.project.readAsset,
            )
            : null;
  }

  Future<void> _bootstrapProject() async {
    final generation = ++_bootstrapGeneration;
    await _registerProjectFonts();
    if (!mounted || generation != _bootstrapGeneration) return;
    _loadController();
  }

  Future<void> _registerProjectFonts() async {
    final registrar = widget.fontRegistrar ?? _registerFlutterFont;
    for (final entry in widget.project.fontAssets.entries) {
      final bytes = widget.project.readAsset(entry.value);
      if (bytes == null) continue;
      try {
        await registrar(entry.key, bytes);
      } catch (error) {
        debugPrint('Could not register RenPy font ${entry.key}: $error');
      }
    }
  }

  void _loadController() {
    try {
      _controller.load(
        widget.project.scriptSource,
        filename: widget.project.scriptPath,
        gameRoot: widget.project.gameRoot,
        availableAssets:
            widget.availableAssets ?? widget.project.availableAssets,
      );
    } catch (error) {
      _controller.value = RenPyError(error.toString());
    }
  }

  Uint8List? _readProjectAsset(String assetPath) {
    return widget.project.readAsset(assetPath) ??
        (widget.project.gameRoot.isEmpty
            ? null
            : widget.project.readAsset(
              '${widget.project.gameRoot}/$assetPath',
            ));
  }

  ImageProvider<Object> _imageProvider(String assetPath) {
    final bytes = _readProjectAsset(assetPath);
    if (bytes == null) return AssetImage(assetPath);
    return MemoryImage(bytes);
  }

  @override
  void dispose() {
    _ownedAudioPlayback?.dispose();
    _controller.dispose();
    super.dispose();
  }

  RenPyDialogueResolvedImage _dialogueImageResolver(String assetPath) {
    final bytes = _readProjectAsset(assetPath);
    if (bytes == null) {
      return RenPyDialogueResolvedImage(provider: AssetImage(assetPath));
    }
    return RenPyDialogueResolvedImage(
      provider: MemoryImage(bytes),
      size: _pngSize(bytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RenPyPlayer(
      controller: _controller,
      backgroundColor: widget.backgroundColor,
      showRestartButton: widget.showRestartButton,
      onRestart: _loadController,
      imageLayerBuilder:
          widget.imageLayerBuilder ??
          (context, controller) {
            return RenPyImageLayer(
              controller: controller,
              imageProvider: _imageProvider,
              screenSize: widget.project.screenSize,
              layerOrder: widget.project.visualLayers,
            );
          },
      gameRoot: widget.project.gameRoot,
      screenSize: widget.project.screenSize,
      audioPlayback: widget.audioPlayback ?? _ownedAudioPlayback,
      preferenceStore: widget.preferenceStore,
      dialogueStyle: _dialogueStyle(widget.project.gui),
      gui: widget.project.gui,
      layerOrder: widget.project.visualLayers,
      dialogueImageResolver: _dialogueImageResolver,
      screenImageProvider: _imageProvider,
    );
  }
}

Future<void> _registerFlutterFont(String family, Uint8List bytes) async {
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
  await loader.load();
}

class _RenPyAssetPlayerState extends State<RenPyAssetPlayer> {
  late final RenPyFlutterController _controller;
  String? _source;
  late Set<String> _availableAssets;
  Object? _loadError;
  StackTrace? _loadStackTrace;
  int _bootstrapGeneration = 0;
  String? _bootstrappedScriptAsset;
  String? _bootstrappedGameRoot;
  AssetBundle? _bootstrappedBundle;
  Set<String>? _bootstrappedAvailableAssets;

  String get _gameRoot {
    final explicit = widget.gameRoot;
    if (explicit != null) return explicit;

    final scriptIndex = widget.scriptAsset.lastIndexOf('/script.rpy');
    if (scriptIndex != -1) {
      return widget.scriptAsset.substring(0, scriptIndex);
    }

    final slashIndex = widget.scriptAsset.lastIndexOf('/');
    if (slashIndex == -1) return '';
    return widget.scriptAsset.substring(0, slashIndex);
  }

  AssetBundle get _bundle => widget.bundle ?? DefaultAssetBundle.of(context);

  @override
  void initState() {
    super.initState();
    _controller = RenPyFlutterController(
      persistentStore: widget.persistentStore,
      snapshotStore: widget.snapshotStore,
      slotStore: widget.slotStore,
    );
    widget.onControllerCreated?.call(_controller);
    _availableAssets = widget.availableAssets ?? const {};
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bootstrapIfNeeded();
  }

  @override
  void didUpdateWidget(RenPyAssetPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bootstrapIfNeeded();
  }

  void _bootstrapIfNeeded() {
    final bundle = _bundle;
    if (_bootstrappedScriptAsset == widget.scriptAsset &&
        _bootstrappedGameRoot == widget.gameRoot &&
        identical(_bootstrappedBundle, bundle) &&
        identical(_bootstrappedAvailableAssets, widget.availableAssets)) {
      return;
    }

    _bootstrappedScriptAsset = widget.scriptAsset;
    _bootstrappedGameRoot = widget.gameRoot;
    _bootstrappedBundle = bundle;
    _bootstrappedAvailableAssets = widget.availableAssets;
    _bootstrap(bundle);
  }

  Future<void> _bootstrap(AssetBundle bundle) async {
    final generation = ++_bootstrapGeneration;
    setState(() {
      _source = null;
      _loadError = null;
      _loadStackTrace = null;
      _availableAssets = widget.availableAssets ?? const {};
    });
    try {
      final source = await bundle.loadString(widget.scriptAsset);
      final availableAssets =
          widget.availableAssets ?? await _loadAvailableAssets(bundle);
      if (!mounted || generation != _bootstrapGeneration) return;

      _source = source;
      _availableAssets = availableAssets;

      setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && generation == _bootstrapGeneration) _loadController();
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _bootstrapGeneration) return;

      setState(() {
        _loadError = error;
        _loadStackTrace = stackTrace;
      });
    }
  }

  Future<Set<String>> _loadAvailableAssets(AssetBundle bundle) async {
    final manifest = await AssetManifest.loadFromAssetBundle(bundle);
    return manifest
        .listAssets()
        .where((asset) => asset.startsWith(_gameRoot))
        .toSet();
  }

  void _loadController() {
    final source = _source;
    if (source == null) return;

    try {
      _controller.load(
        source,
        filename: widget.scriptAsset,
        gameRoot: _gameRoot,
        availableAssets: _availableAssets,
      );
    } catch (error) {
      _controller.value = RenPyError(error.toString());
    }
  }

  @override
  void dispose() {
    _bootstrapGeneration++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    final stackTrace = _loadStackTrace;
    if (error != null && stackTrace != null) {
      final builder = widget.loadErrorBuilder;
      if (builder != null) return builder(context, error, stackTrace);
      return Center(child: Text('Failed to load RenPy script: $error'));
    }

    if (_source == null) {
      final builder = widget.loadingBuilder;
      if (builder != null) return builder(context);
      return const Center(child: CircularProgressIndicator());
    }

    return RenPyPlayer(
      controller: _controller,
      backgroundColor: widget.backgroundColor,
      showRestartButton: widget.showRestartButton,
      onRestart: _loadController,
      imageLayerBuilder: widget.imageLayerBuilder,
      gameRoot: _gameRoot,
      screenSize: RenPyScreenSize.fromScriptSource(_source!),
      audioPlayback: widget.audioPlayback,
      preferenceStore: widget.preferenceStore,
    );
  }
}

TextStyle? _dialogueStyle(RenPyGuiConfiguration gui) {
  final color = _colorFromRenPyHex(gui.dialogueTextColor);
  final outlineColor = _colorFromRenPyHex(gui.dialogueTextOutlineColor);
  if (gui.dialogueTextFont == null &&
      gui.dialogueTextSize == null &&
      color == null &&
      outlineColor == null) {
    return null;
  }

  return TextStyle(
    fontFamily: gui.dialogueTextFont,
    fontSize: gui.dialogueTextSize,
    color: color,
    shadows: outlineColor == null ? null : _outlineShadows(outlineColor),
  );
}

Color? _colorFromRenPyHex(String? expression) {
  if (expression == null) return null;
  final value = expression.trim();
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (!RegExp(r'^[0-9a-fA-F]{3}$').hasMatch(hex) &&
      !RegExp(r'^[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(hex)) {
    return null;
  }
  final expanded =
      hex.length == 3 ? hex.split('').map((char) => '$char$char').join() : hex;
  final argb = expanded.length == 6 ? 'FF$expanded' : expanded;
  return Color(int.parse(argb, radix: 16));
}

List<Shadow> _outlineShadows(Color color) {
  return [
    for (final offset in const [
      Offset(-1, -1),
      Offset(0, -1),
      Offset(1, -1),
      Offset(-1, 0),
      Offset(1, 0),
      Offset(-1, 1),
      Offset(0, 1),
      Offset(1, 1),
    ])
      Shadow(offset: offset, color: color),
  ];
}

Size? _pngSize(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i += 1) {
    if (bytes[i] != signature[i]) return null;
  }
  if (String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') return null;

  final data = ByteData.sublistView(bytes);
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) return null;
  return Size(width.toDouble(), height.toDouble());
}
