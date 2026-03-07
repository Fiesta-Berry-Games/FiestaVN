import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'renpy_audio_layer.dart';
import 'renpy_chrome.dart';
import 'renpy_flutter_controller.dart';
import 'renpy_image_layer.dart';

typedef RenPyLayerBuilder =
    Widget Function(BuildContext context, RenPyFlutterController controller);
typedef RenPyLoadingBuilder = Widget Function(BuildContext context);
typedef RenPyLoadErrorBuilder =
    Widget Function(BuildContext context, Object error, StackTrace stackTrace);

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
  });

  final RenPyFlutterController controller;
  final Color backgroundColor;
  final bool showRestartButton;
  final VoidCallback? onRestart;
  final RenPyLayerBuilder? imageLayerBuilder;
  final String gameRoot;
  final RenPyAudioPlayback? audioPlayback;

  @override
  Widget build(BuildContext context) {
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
        ),
        RenPyDialogueView(controller: controller),
        RenPyMenuSelector(controller: controller),
        if (showRestartButton && onRestart != null)
          PositionedDirectional(
            end: 16,
            bottom: 16,
            child: FloatingActionButton(
              tooltip: 'Restart',
              onPressed: onRestart,
              child: const Icon(Icons.refresh),
            ),
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
    this.showRestartButton = true,
    this.imageLayerBuilder,
    this.audioPlayback,
    this.loadingBuilder,
    this.loadErrorBuilder,
  });

  final String scriptAsset;
  final AssetBundle? bundle;
  final String? gameRoot;
  final Set<String>? availableAssets;
  final Color backgroundColor;
  final bool showRestartButton;
  final RenPyLayerBuilder? imageLayerBuilder;
  final RenPyAudioPlayback? audioPlayback;
  final RenPyLoadingBuilder? loadingBuilder;
  final RenPyLoadErrorBuilder? loadErrorBuilder;

  @override
  State<RenPyAssetPlayer> createState() => _RenPyAssetPlayerState();
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
    _controller = RenPyFlutterController();
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
    );
  }
}
