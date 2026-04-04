import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renpy_core/renpy_core.dart';

import 'renpy_audio_layer.dart';
import 'renpy_chrome.dart';
import 'renpy_flutter_controller.dart';
import 'renpy_image_layer.dart';
import 'renpy_preference_store.dart';

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
    this.audioPlayback,
    this.preferenceStore,
  });

  final RenPyFlutterController controller;
  final Color backgroundColor;
  final bool showRestartButton;
  final VoidCallback? onRestart;
  final RenPyLayerBuilder? imageLayerBuilder;
  final String gameRoot;
  final RenPyAudioPlayback? audioPlayback;
  final RenPyPreferenceStore? preferenceStore;

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

  @override
  Widget build(BuildContext context) {
    return _RenPyInputSurface(
      preferenceStore: preferenceStore,
      gameMenuBuilder: (closeGameMenu, preferences, setMusicMuted) {
        return _RenPyGameMenu(
          musicMuted: preferences.musicMuted,
          canSaveLoad: controller.hasSnapshotStore,
          canRestart: showRestartButton && onRestart != null,
          onResume: closeGameMenu,
          onMusicMutedChanged: setMusicMuted,
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
        );
      },
      onKeyEvent: (event) => _handleKeyEvent(context, event),
      onPointerSignal: (event) => _handlePointerSignal(context, event),
      childBuilder: (preferences) {
        return Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: backgroundColor),
            if (imageLayerBuilder != null)
              imageLayerBuilder!(context, controller)
            else
              RenPyImageLayer(controller: controller),
            RenPyAudioLayer(
              controller: controller,
              gameRoot: gameRoot,
              playback: audioPlayback,
              musicMuted: preferences.musicMuted,
            ),
            RenPyPauseView(controller: controller),
            RenPyDialogueView(controller: controller),
            RenPyMenuSelector(controller: controller),
            ValueListenableBuilder<RenPyGameStatus>(
              valueListenable: controller,
              builder: (context, status, child) {
                final hasRestart = showRestartButton && onRestart != null;
                final hasActions =
                    controller.canRollback ||
                    controller.hasSnapshotStore ||
                    hasRestart;
                if (!hasActions) return const SizedBox.shrink();

                return PositionedDirectional(
                  end: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (controller.canRollback) ...[
                        FloatingActionButton.small(
                          tooltip: 'Rollback',
                          heroTag: null,
                          onPressed: () => _rollbackGame(context),
                          child: const Icon(Icons.undo),
                        ),
                      ],
                      if (controller.hasSnapshotStore) ...[
                        if (controller.canRollback) const SizedBox(height: 8),
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
                        if (controller.canRollback ||
                            controller.hasSnapshotStore)
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
      },
    );
  }
}

class _RenPyInputSurface extends StatefulWidget {
  const _RenPyInputSurface({
    required this.childBuilder,
    required this.gameMenuBuilder,
    required this.onKeyEvent,
    required this.onPointerSignal,
    this.preferenceStore,
  });

  final Widget Function(RenPyPlayerPreferences preferences) childBuilder;
  final Widget Function(
    VoidCallback closeGameMenu,
    RenPyPlayerPreferences preferences,
    ValueChanged<bool> setMusicMuted,
  )
  gameMenuBuilder;
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

  void _setMusicMuted(bool muted) {
    if (_preferences.musicMuted == muted) return;
    setState(() {
      _preferences = _preferences.copyWith(musicMuted: muted);
    });
    widget.preferenceStore?.save(_preferences.toJson());
  }

  void _toggleMusicMuted() => _setMusicMuted(!_preferences.musicMuted);

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if ((event is KeyDownEvent || event is KeyRepeatEvent) &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _gameMenuOpen ? _closeGameMenu() : _openGameMenu();
      return KeyEventResult.handled;
    }
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
    if ((event.buttons & kSecondaryMouseButton) != 0) _openGameMenu();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_gameMenuOpen) return;
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
            widget.childBuilder(_preferences),
            if (_gameMenuOpen)
              widget.gameMenuBuilder(
                _closeGameMenu,
                _preferences,
                _setMusicMuted,
              ),
          ],
        ),
      ),
    );
  }
}

class _RenPyGameMenu extends StatefulWidget {
  const _RenPyGameMenu({
    required this.musicMuted,
    required this.canSaveLoad,
    required this.canRestart,
    required this.onResume,
    required this.onMusicMutedChanged,
    required this.onSave,
    required this.onLoad,
    required this.onRestart,
  });

  final bool musicMuted;
  final bool canSaveLoad;
  final bool canRestart;
  final VoidCallback onResume;
  final ValueChanged<bool> onMusicMutedChanged;
  final VoidCallback onSave;
  final VoidCallback onLoad;
  final VoidCallback onRestart;

  @override
  State<_RenPyGameMenu> createState() => _RenPyGameMenuState();
}

class _RenPyGameMenuState extends State<_RenPyGameMenu> {
  bool _showPreferences = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Material(
              color: colorScheme.surface,
              elevation: 8,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child:
                    _showPreferences
                        ? _buildPreferences(context)
                        : _buildRootMenu(context),
              ),
            ),
          ),
        ),
      ),
    );
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
          onPressed: () => setState(() => _showPreferences = true),
          icon: const Icon(Icons.tune),
          label: const Text('Preferences'),
        ),
        if (widget.canSaveLoad) ...[
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
    return Column(
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
          value: widget.musicMuted,
          onChanged: (value) {
            if (value == null) return;
            widget.onMusicMutedChanged(value);
          },
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() => _showPreferences = false),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Back'),
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
      _ownedAudioPlayback?.dispose();
      _configureOwnedAudio();
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

  ImageProvider<Object> _imageProvider(String assetPath) {
    final bytes = widget.project.readAsset(assetPath);
    if (bytes == null) return AssetImage(assetPath);
    return MemoryImage(bytes);
  }

  @override
  void dispose() {
    _ownedAudioPlayback?.dispose();
    _controller.dispose();
    super.dispose();
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
            );
          },
      gameRoot: widget.project.gameRoot,
      audioPlayback: widget.audioPlayback ?? _ownedAudioPlayback,
      preferenceStore: widget.preferenceStore,
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
      audioPlayback: widget.audioPlayback,
      preferenceStore: widget.preferenceStore,
    );
  }
}
