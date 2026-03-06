import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'renpy_chrome.dart';
import 'renpy_flutter_controller.dart';
import 'renpy_image_layer.dart';

/// A reusable visual novel surface for an already-managed controller.
class RenPyPlayer extends StatelessWidget {
  const RenPyPlayer({
    super.key,
    required this.controller,
    this.backgroundColor = const Color(0xFF212121),
    this.showRestartButton = true,
    this.onRestart,
  });

  final RenPyFlutterController controller;
  final Color backgroundColor;
  final bool showRestartButton;
  final VoidCallback? onRestart;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: backgroundColor),
        RenPyImageLayer(controller: controller),
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
  });

  final String scriptAsset;
  final AssetBundle? bundle;
  final String? gameRoot;
  final Set<String>? availableAssets;
  final Color backgroundColor;
  final bool showRestartButton;

  @override
  State<RenPyAssetPlayer> createState() => _RenPyAssetPlayerState();
}

class _RenPyAssetPlayerState extends State<RenPyAssetPlayer> {
  late final RenPyFlutterController _controller;
  String? _source;
  late Set<String> _availableAssets;

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
    _bootstrap();
  }

  @override
  void didUpdateWidget(RenPyAssetPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scriptAsset != oldWidget.scriptAsset ||
        widget.bundle != oldWidget.bundle ||
        widget.gameRoot != oldWidget.gameRoot ||
        widget.availableAssets != oldWidget.availableAssets) {
      _source = null;
      _availableAssets = widget.availableAssets ?? const {};
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    final source = await _bundle.loadString(widget.scriptAsset);
    if (!mounted) return;

    _source = source;
    _availableAssets = widget.availableAssets ?? await _loadAvailableAssets();

    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadController();
    });
  }

  Future<Set<String>> _loadAvailableAssets() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_bundle);
    return manifest
        .listAssets()
        .where((asset) => asset.startsWith(_gameRoot))
        .toSet();
  }

  void _loadController() {
    final source = _source;
    if (source == null) return;

    _controller.load(
      source,
      filename: widget.scriptAsset,
      gameRoot: _gameRoot,
      availableAssets: _availableAssets,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_source == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return RenPyPlayer(
      controller: _controller,
      backgroundColor: widget.backgroundColor,
      showRestartButton: widget.showRestartButton,
      onRestart: _loadController,
    );
  }
}
