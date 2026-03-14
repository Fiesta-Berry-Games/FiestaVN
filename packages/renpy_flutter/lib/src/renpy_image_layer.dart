import 'package:flutter/material.dart';
import 'package:renpy_core/renpy_core.dart'
    show RenPyImageOperation, RenPyImageOperationType, RenPyResolvedImage;

import 'renpy_flutter_controller.dart';

typedef RenPyImageProviderFactory =
    ImageProvider<Object> Function(String assetPath);

/// Renders RenPy scene and show image changes as Flutter asset images.
class RenPyImageLayer extends StatefulWidget {
  const RenPyImageLayer({
    super.key,
    required this.controller,
    this.imageProvider,
  });

  final RenPyFlutterController controller;
  final RenPyImageProviderFactory? imageProvider;

  @override
  State<RenPyImageLayer> createState() => _RenPyImageLayerState();
}

class _RenPyImageLayerState extends State<RenPyImageLayer> {
  static const _transitionDuration = Duration(milliseconds: 300);

  final _sprites = <String, _RenPySpriteState>{};
  final _positions = <String, _RenPySpritePlacement>{};
  _RenPyRenderedImage? _backgroundImage;
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
        _backgroundImage =
            status.scene == 'black'
                ? null
                : _RenPyRenderedImage.fromStatus(
                  status.sceneImage,
                  status.sceneAsset,
                );
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

        final placement =
            _RenPySpritePlacement.fromExpression(status.showAt) ??
            _positions[name] ??
            _RenPySpritePlacement.center;
        _positions[name] = placement;

        final image = _RenPyRenderedImage.fromStatus(
          status.showImage,
          status.showAsset,
        );
        if (image == null) return;

        _sprites[name] = _RenPySpriteState(image: image, placement: placement);
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
        _RenPyVisualFrame(
          state: current,
          imageProvider: widget.imageProvider ?? _defaultImageProvider,
        ),
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
            child: _RenPyVisualFrame(
              state: previous,
              imageProvider: widget.imageProvider ?? _defaultImageProvider,
            ),
          ),
      ],
    );
  }

  _RenPyVisualState _currentVisualState() {
    return _RenPyVisualState(
      backgroundImage: _backgroundImage,
      sprites: Map.unmodifiable(_sprites),
    );
  }
}

ImageProvider<Object> _defaultImageProvider(String assetPath) {
  return AssetImage(assetPath);
}

class _RenPyVisualState {
  const _RenPyVisualState({
    required this.backgroundImage,
    required this.sprites,
  });

  final _RenPyRenderedImage? backgroundImage;
  final Map<String, _RenPySpriteState> sprites;
}

class _RenPyRenderedImage {
  const _RenPyRenderedImage({
    required this.assetPath,
    this.operations = const [],
  });

  factory _RenPyRenderedImage.fromResolved(RenPyResolvedImage image) {
    return _RenPyRenderedImage(
      assetPath: image.assetPath,
      operations: image.operations,
    );
  }

  static _RenPyRenderedImage? fromStatus(
    RenPyResolvedImage? image,
    String? assetPath,
  ) {
    if (image != null) return _RenPyRenderedImage.fromResolved(image);
    if (assetPath == null) return null;
    return _RenPyRenderedImage(assetPath: assetPath);
  }

  final String assetPath;
  final List<RenPyImageOperation> operations;
}

class _RenPySpriteState {
  const _RenPySpriteState({required this.image, required this.placement});

  final _RenPyRenderedImage image;
  final _RenPySpritePlacement placement;
}

enum _RenPySpritePlacement {
  left(Alignment.bottomLeft),
  center(Alignment.bottomCenter),
  right(Alignment.bottomRight);

  const _RenPySpritePlacement(this.alignment);

  final Alignment alignment;

  static _RenPySpritePlacement? fromExpression(String? expression) {
    final value = expression?.trim().toLowerCase();
    return switch (value) {
      'left' => _RenPySpritePlacement.left,
      'right' => _RenPySpritePlacement.right,
      'center' || 'truecenter' => _RenPySpritePlacement.center,
      _ => null,
    };
  }
}

class _RenPyVisualFrame extends StatelessWidget {
  const _RenPyVisualFrame({required this.state, required this.imageProvider});

  final _RenPyVisualState state;
  final RenPyImageProviderFactory imageProvider;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (state.backgroundImage == null && state.sprites.isEmpty)
          const ColoredBox(color: Colors.black),
        if (state.backgroundImage != null)
          _RenPyRenderedImageWidget(
            image: state.backgroundImage!,
            fit: BoxFit.cover,
            imageProvider: imageProvider,
            errorBuilder:
                (context, error, stackTrace) =>
                    Container(color: const Color(0xFF202020)),
          ),
        for (final entry in state.sprites.entries)
          _RenPyImageSprite(
            key: ValueKey(entry.key),
            image: entry.value.image,
            placement: entry.value.placement,
            imageProvider: imageProvider,
          ),
      ],
    );
  }
}

class _RenPyImageSprite extends StatelessWidget {
  const _RenPyImageSprite({
    super.key,
    required this.image,
    required this.placement,
    required this.imageProvider,
  });

  final _RenPyRenderedImage image;
  final _RenPySpritePlacement placement;
  final RenPyImageProviderFactory imageProvider;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: placement.alignment,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: (constraints.maxWidth * 0.45).clamp(160, 420),
                maxHeight: constraints.maxHeight * 0.9,
              ),
              child: _RenPyRenderedImageWidget(
                image: image,
                fit: BoxFit.contain,
                imageProvider: imageProvider,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
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
                          style: TextStyle(
                            color: Colors.grey.shade300,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          image.assetPath.split('/').last,
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RenPyRenderedImageWidget extends StatelessWidget {
  const _RenPyRenderedImageWidget({
    required this.image,
    required this.fit,
    required this.imageProvider,
    required this.errorBuilder,
  });

  final _RenPyRenderedImage image;
  final BoxFit fit;
  final RenPyImageProviderFactory imageProvider;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  Widget build(BuildContext context) {
    Widget child = Image(
      image: imageProvider(image.assetPath),
      fit: fit,
      errorBuilder: errorBuilder,
    );

    for (final operation in image.operations) {
      child = _applyOperation(operation, child);
    }

    return child;
  }

  Widget _applyOperation(RenPyImageOperation operation, Widget child) {
    return switch (operation.type) {
      RenPyImageOperationType.grayscale => ColorFiltered(
        colorFilter: const ColorFilter.matrix(_grayscaleMatrix),
        child: child,
      ),
      RenPyImageOperationType.sepia => ColorFiltered(
        colorFilter: const ColorFilter.matrix(_sepiaMatrix),
        child: child,
      ),
      RenPyImageOperationType.matrixColor => ColorFiltered(
        colorFilter: ColorFilter.matrix(_tintMatrix(operation)),
        child: child,
      ),
      RenPyImageOperationType.flipHorizontal => Transform.scale(
        scaleX: -1,
        child: child,
      ),
    };
  }
}

const _grayscaleMatrix = <double>[
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0.2126,
  0.7152,
  0.0722,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

const _sepiaMatrix = <double>[
  0.393,
  0.769,
  0.189,
  0,
  0,
  0.349,
  0.686,
  0.168,
  0,
  0,
  0.272,
  0.534,
  0.131,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

List<double> _tintMatrix(RenPyImageOperation operation) {
  return [
    operation.tintRed ?? 1,
    0,
    0,
    0,
    0,
    0,
    operation.tintGreen ?? 1,
    0,
    0,
    0,
    0,
    0,
    operation.tintBlue ?? 1,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}
