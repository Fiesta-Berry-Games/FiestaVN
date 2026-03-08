import 'package:flutter/material.dart';

import 'renpy_flutter_controller.dart';

/// Renders RenPy scene and show image changes as Flutter asset images.
class RenPyImageLayer extends StatefulWidget {
  const RenPyImageLayer({super.key, required this.controller});

  final RenPyFlutterController controller;

  @override
  State<RenPyImageLayer> createState() => _RenPyImageLayerState();
}

class _RenPyImageLayerState extends State<RenPyImageLayer> {
  static const _transitionDuration = Duration(milliseconds: 300);

  final _sprites = <String, _RenPySpriteState>{};
  final _positions = <String, bool>{};
  String? _backgroundAsset;
  _RenPyVisualState? _previousVisualState;
  bool _transitionActive = false;
  int _transitionGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    final status = widget.controller.value;

    if (status is RenPyTransitionChange) {
      if (_previousVisualState == null) return;

      setState(() {
        _transitionActive = true;
        _transitionGeneration++;
      });
      return;
    }

    if (status is! RenPyImageChange) return;

    setState(() {
      _previousVisualState = _currentVisualState();
      _transitionActive = false;

      if (status.scene != null) {
        _sprites.clear();
        _positions.clear();
        _backgroundAsset = status.scene == 'black' ? null : status.sceneAsset;
      }

      if (status.hide != null) {
        final name = status.hide!.trim().split(RegExp(r'\s+')).first;
        _sprites.remove(name);
        _positions.remove(name);
      }

      if (status.show != null) {
        final clean = status.show!.split('#').first.trim();
        final parts = clean.split(RegExp(r'\s+'));
        if (parts.isEmpty) return;

        final name = parts.first;

        bool? explicitLeft;
        final atIndex = parts.indexOf('at');
        if (atIndex != -1 && atIndex + 1 < parts.length) {
          explicitLeft = parts[atIndex + 1] == 'left';
        }

        final atLeft =
            explicitLeft ??
            _positions[name] ??
            (_positions.values.where((isLeft) => isLeft).length <=
                _positions.values.where((isLeft) => !isLeft).length);
        _positions[name] = atLeft;

        final imagePath = status.showAsset;
        if (imagePath == null) return;

        _sprites[name] = _RenPySpriteState(
          imagePath: imagePath,
          atLeft: atLeft,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final previous = _transitionActive ? _previousVisualState : null;
    final current = _currentVisualState();

    return Stack(
      fit: StackFit.expand,
      children: [
        _RenPyVisualFrame(state: current),
        if (previous != null)
          TweenAnimationBuilder<double>(
            key: ValueKey(_transitionGeneration),
            tween: Tween(begin: 1, end: 0),
            duration: _transitionDuration,
            onEnd: () {
              if (!mounted) return;
              setState(() {
                _transitionActive = false;
                _previousVisualState = null;
              });
            },
            builder: (context, opacity, child) {
              return Opacity(opacity: opacity, child: child);
            },
            child: _RenPyVisualFrame(state: previous),
          ),
      ],
    );
  }

  _RenPyVisualState _currentVisualState() {
    return _RenPyVisualState(
      backgroundAsset: _backgroundAsset,
      sprites: Map.unmodifiable(_sprites),
    );
  }
}

class _RenPyVisualState {
  const _RenPyVisualState({
    required this.backgroundAsset,
    required this.sprites,
  });

  final String? backgroundAsset;
  final Map<String, _RenPySpriteState> sprites;
}

class _RenPySpriteState {
  const _RenPySpriteState({required this.imagePath, required this.atLeft});

  final String imagePath;
  final bool atLeft;
}

class _RenPyVisualFrame extends StatelessWidget {
  const _RenPyVisualFrame({required this.state});

  final _RenPyVisualState state;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (state.backgroundAsset == null && state.sprites.isEmpty)
          const ColoredBox(color: Colors.black),
        if (state.backgroundAsset != null)
          Image.asset(
            state.backgroundAsset!,
            fit: BoxFit.cover,
            errorBuilder:
                (context, error, stackTrace) =>
                    Container(color: const Color(0xFF202020)),
          ),
        for (final entry in state.sprites.entries)
          _RenPyImageSprite(
            key: ValueKey(entry.key),
            imagePath: entry.value.imagePath,
            atLeft: entry.value.atLeft,
          ),
      ],
    );
  }
}

class _RenPyImageSprite extends StatelessWidget {
  const _RenPyImageSprite({
    super.key,
    required this.imagePath,
    required this.atLeft,
  });

  final String imagePath;
  final bool atLeft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: atLeft ? 50 : null,
      right: atLeft ? null : 50,
      bottom: 0,
      child: Image.asset(
        imagePath,
        width: 200,
        height: 300,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_not_supported,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 8),
                Text(
                  'Image not found',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  imagePath.split('/').last,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
