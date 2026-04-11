import 'package:flutter/material.dart';
import 'package:renpy_core/renpy_core.dart'
    show
        RenPyImageOperation,
        RenPyImageOperationType,
        RenPyImagePlacement,
        RenPyResolvedImage,
        RenPyScreenSize,
        RenPyTransitionIntent,
        RenPyTransitionType;

import 'renpy_flutter_controller.dart';
import 'renpy_text.dart';

typedef RenPyImageProviderFactory =
    ImageProvider<Object> Function(String assetPath);

/// Renders RenPy scene and show image changes as Flutter asset images.
class RenPyImageLayer extends StatefulWidget {
  const RenPyImageLayer({
    super.key,
    required this.controller,
    this.imageProvider,
    this.screenSize,
  });

  final RenPyFlutterController controller;
  final RenPyImageProviderFactory? imageProvider;
  final RenPyScreenSize? screenSize;

  @override
  State<RenPyImageLayer> createState() => _RenPyImageLayerState();
}

class _RenPyImageLayerState extends State<RenPyImageLayer> {
  static const _transitionDuration = Duration(milliseconds: 300);

  final _sprites = <String, _RenPySpriteState>{};
  final _positions = <String, RenPyImagePlacement>{};
  Color _backgroundColor = Colors.black;
  _RenPyRenderedImage? _backgroundImage;
  _RenPyVisualState? _previousVisualState;
  RenPyTransitionIntent? _activeTransitionIntent;
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
      if (status.intent?.type == RenPyTransitionType.none) return;

      setState(() {
        _activeTransitionIntent = status.intent;
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
        final solidColor =
            _colorForResolvedSolid(status.sceneImage) ??
            _solidColorForScene(status.scene!);
        _backgroundColor = solidColor ?? Colors.black;
        _backgroundImage =
            solidColor == null
                ? _RenPyRenderedImage.fromStatus(
                  status.sceneImage,
                  status.sceneAsset,
                )
                : null;
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
            status.showPlacement ??
            RenPyImagePlacement.parse(status.showAt) ??
            _positions[name] ??
            _defaultSpritePlacement;
        _positions[name] = placement;

        final text = status.showText;
        if (text != null) {
          _putSprite(
            name,
            _RenPySpriteState.text(text: text, placement: placement),
            behind: status.showBehind,
          );
        } else {
          final image = _RenPyRenderedImage.fromStatus(
            status.showImage,
            status.showAsset,
          );
          if (image == null) return;

          _putSprite(
            name,
            _RenPySpriteState.image(image: image, placement: placement),
            behind: status.showBehind,
          );
        }
      }
    });
  }

  void _putSprite(String name, _RenPySpriteState sprite, {String? behind}) {
    _sprites.remove(name);

    final behindValue = behind?.trim();
    final target =
        behindValue == null || behindValue.isEmpty
            ? null
            : behindValue.split(RegExp(r'\s+')).first;
    if (target == null || target.isEmpty || !_sprites.containsKey(target)) {
      _sprites[name] = sprite;
      return;
    }

    final ordered = <String, _RenPySpriteState>{};
    for (final entry in _sprites.entries) {
      if (entry.key == target) {
        ordered[name] = sprite;
      }
      ordered[entry.key] = entry.value;
    }

    _sprites
      ..clear()
      ..addAll(ordered);
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
    final transitionIntent = _activeTransitionIntent;
    final currentFrame = _RenPyVisualFrame(
      state: current,
      imageProvider: widget.imageProvider ?? _defaultImageProvider,
      screenSize: widget.screenSize,
    );
    final isPunch =
        _transitionActive &&
        transitionIntent?.type == RenPyTransitionType.punch;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (isPunch)
          TweenAnimationBuilder<double>(
            key: ValueKey(_transitionGeneration),
            tween: Tween(begin: 1, end: 0),
            duration: _durationFor(transitionIntent),
            onEnd: _clearTransition,
            builder: (context, remaining, child) {
              return _RenPyTransitionOverlay(
                remaining: remaining,
                intent: transitionIntent,
                child: child!,
              );
            },
            child: currentFrame,
          )
        else
          currentFrame,
        if (previous != null && !isPunch)
          TweenAnimationBuilder<double>(
            key: ValueKey(_transitionGeneration),
            tween: Tween(begin: 1, end: 0),
            duration: _durationFor(transitionIntent),
            onEnd: _clearTransition,
            builder: (context, opacity, child) {
              return _RenPyTransitionOverlay(
                remaining: opacity,
                intent: transitionIntent,
                child: child!,
              );
            },
            child: _RenPyVisualFrame(
              state: previous,
              imageProvider: widget.imageProvider ?? _defaultImageProvider,
              screenSize: widget.screenSize,
            ),
          ),
      ],
    );
  }

  void _clearTransition() {
    if (!mounted) return;
    setState(() {
      _transitionActive = false;
      _previousVisualState = null;
      _activeTransitionIntent = null;
    });
  }

  _RenPyVisualState _currentVisualState() {
    return _RenPyVisualState(
      backgroundColor: _backgroundColor,
      backgroundImage: _backgroundImage,
      sprites: Map.unmodifiable(_sprites),
    );
  }

  Duration _durationFor(RenPyTransitionIntent? intent) {
    final seconds = intent?.totalDuration ?? 0;
    if (seconds <= 0) return _transitionDuration;
    return Duration(milliseconds: (seconds * 1000).round());
  }
}

ImageProvider<Object> _defaultImageProvider(String assetPath) {
  return AssetImage(assetPath);
}

class _RenPyVisualState {
  const _RenPyVisualState({
    required this.backgroundColor,
    required this.backgroundImage,
    required this.sprites,
  });

  final Color backgroundColor;
  final _RenPyRenderedImage? backgroundImage;
  final Map<String, _RenPySpriteState> sprites;
}

Color? _solidColorForScene(String scene) {
  switch (scene.trim().toLowerCase()) {
    case 'black':
      return Colors.black;
    case 'white':
      return Colors.white;
    case 'red':
      return const Color(0xFFFF0000);
  }
  return null;
}

Color? _colorForResolvedSolid(RenPyResolvedImage? image) {
  final color = image?.solidColor;
  if (color == null) return null;
  return Color.fromARGB(color.alpha, color.red, color.green, color.blue);
}

class _RenPyRenderedImage {
  const _RenPyRenderedImage({
    required this.assetPath,
    this.operations = const [],
  });

  static _RenPyRenderedImage? fromResolved(RenPyResolvedImage image) {
    final assetPath = image.assetPath;
    if (assetPath == null) return null;

    return _RenPyRenderedImage(
      assetPath: assetPath,
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
  const _RenPySpriteState.image({required this.image, required this.placement})
    : text = null;

  const _RenPySpriteState.text({required this.text, required this.placement})
    : image = null;

  final _RenPyRenderedImage? image;
  final String? text;
  final RenPyImagePlacement placement;
}

const _defaultSpritePlacement = RenPyImagePlacement.position(
  xpos: 0.5,
  xanchor: 0.5,
  ypos: 1,
  yanchor: 1,
);

class _RenPyVisualFrame extends StatelessWidget {
  const _RenPyVisualFrame({
    required this.state,
    required this.imageProvider,
    required this.screenSize,
  });

  final _RenPyVisualState state;
  final RenPyImageProviderFactory imageProvider;
  final RenPyScreenSize? screenSize;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(
          key: const ValueKey('renpy-stage-color'),
          color: state.backgroundColor,
        ),
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
          _RenPyDisplayableSprite(
            key: ValueKey(entry.key),
            sprite: entry.value,
            imageProvider: imageProvider,
            screenSize: screenSize,
          ),
      ],
    );
  }
}

class _RenPyDisplayableSprite extends StatelessWidget {
  const _RenPyDisplayableSprite({
    super.key,
    required this.sprite,
    required this.imageProvider,
    required this.screenSize,
  });

  final _RenPySpriteState sprite;
  final RenPyImageProviderFactory imageProvider;
  final RenPyScreenSize? screenSize;
  @override
  Widget build(BuildContext context) {
    final resolved = _ResolvedSpritePlacement.from(
      sprite.placement,
      screenSize: screenSize,
    );
    return Positioned.fill(
      child: Align(
        alignment: resolved.alignment,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return FractionalTranslation(
              translation: resolved.anchorTranslation,
              child: Transform.translate(
                offset: resolved.anchorOffset,
                child:
                    sprite.text == null
                        ? _RenPySpriteImage(
                          image: sprite.image!,
                          imageProvider: imageProvider,
                        )
                        : ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * 0.9,
                            maxHeight: constraints.maxHeight * 0.9,
                          ),
                          child: _RenPyTextDisplayable(text: sprite.text!),
                        ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RenPySpriteImage extends StatelessWidget {
  const _RenPySpriteImage({required this.image, required this.imageProvider});

  final _RenPyRenderedImage image;
  final RenPyImageProviderFactory imageProvider;

  @override
  Widget build(BuildContext context) {
    return _RenPyRenderedImageWidget(
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
                style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                image.assetPath.split('/').last,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RenPyTextDisplayable extends StatelessWidget {
  const _RenPyTextDisplayable({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final baseStyle =
        Theme.of(context).textTheme.displayMedium?.copyWith(
          color: Colors.white,
          shadows: const [
            Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
          ],
        ) ??
        const TextStyle(
          color: Colors.white,
          fontSize: 48,
          shadows: [
            Shadow(offset: Offset(1, 1), blurRadius: 2, color: Colors.black),
          ],
        );

    return RenPyText(text, style: baseStyle, textAlign: TextAlign.center);
  }
}

class _ResolvedSpritePlacement {
  const _ResolvedSpritePlacement({
    required this.alignment,
    required this.anchorTranslation,
    required this.anchorOffset,
  });

  factory _ResolvedSpritePlacement.from(
    RenPyImagePlacement placement, {
    RenPyScreenSize? screenSize,
  }) {
    final stageWidth = screenSize?.width.toDouble();
    final stageHeight = screenSize?.height.toDouble();
    final xpos =
        placement.xalign ??
        _positionFraction(
          placement.xpos,
          placement.xposIsPixel,
          stageWidth,
          0.5,
        );
    final ypos =
        placement.yalign ??
        _positionFraction(
          placement.ypos,
          placement.yposIsPixel,
          stageHeight,
          1.0,
        );
    final xanchor = placement.xalign ?? placement.xanchor ?? 0.5;
    final yanchor = placement.yalign ?? placement.yanchor ?? 1.0;
    final xanchorIsPixel = placement.xalign == null && placement.xanchorIsPixel;
    final yanchorIsPixel = placement.yalign == null && placement.yanchorIsPixel;

    return _ResolvedSpritePlacement(
      alignment: Alignment((xpos * 2) - 1, (ypos * 2) - 1),
      anchorTranslation: Offset(
        xanchorIsPixel ? 0.5 : 0.5 - xanchor,
        yanchorIsPixel ? 0.5 : 0.5 - yanchor,
      ),
      anchorOffset: Offset(
        xanchorIsPixel ? -xanchor : 0,
        yanchorIsPixel ? -yanchor : 0,
      ),
    );
  }

  final Alignment alignment;
  final Offset anchorTranslation;
  final Offset anchorOffset;
}

double _positionFraction(
  double? value,
  bool isPixel,
  double? axisSize,
  double fallback,
) {
  if (value == null) return fallback;
  if (!isPixel || axisSize == null || axisSize <= 0) return value;
  return value / axisSize;
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

class _RenPyTransitionOverlay extends StatelessWidget {
  const _RenPyTransitionOverlay({
    required this.remaining,
    required this.intent,
    required this.child,
  });

  final double remaining;
  final RenPyTransitionIntent? intent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final intent = this.intent;
    if (intent?.type == RenPyTransitionType.punch) {
      return _RenPyPunchOverlay(
        remaining: remaining,
        intent: intent!,
        child: child,
      );
    }

    if (intent?.type == RenPyTransitionType.fade) {
      return _RenPyFadeOverlay(
        remaining: remaining,
        intent: intent!,
        child: child,
      );
    }

    final direction = _wipeDirectionFor(intent);
    if (direction != null) {
      return ClipPath(
        clipper: _RenPyWipeClipper(
          progress: 1 - remaining,
          direction: direction,
        ),
        child: child,
      );
    }

    return Opacity(opacity: remaining, child: child);
  }
}

class _RenPyPunchOverlay extends StatelessWidget {
  const _RenPyPunchOverlay({
    required this.remaining,
    required this.intent,
    required this.child,
  });

  final double remaining;
  final RenPyTransitionIntent intent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final progress = (1 - remaining).clamp(0.0, 1.0);
    final wave = _triangleWave(progress * 6);
    final amplitude = 12.0 * remaining;
    final offset =
        intent.mode == 'horizontal'
            ? Offset(wave * amplitude, 0)
            : Offset(0, wave * amplitude);

    return Transform.translate(offset: offset, child: child);
  }
}

class _RenPyFadeOverlay extends StatelessWidget {
  const _RenPyFadeOverlay({
    required this.remaining,
    required this.intent,
    required this.child,
  });

  final double remaining;
  final RenPyTransitionIntent intent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final progress = (1 - remaining).clamp(0.0, 1.0);
    final outFraction = _fraction(intent.outTime, intent.totalDuration);
    final holdFraction = _fraction(intent.holdTime, intent.totalDuration);
    final inStart = outFraction + holdFraction;

    final colorOpacity =
        progress < outFraction
            ? _ratio(progress, outFraction)
            : progress < inStart
            ? 1.0
            : (1 - _ratio(progress - inStart, 1 - inStart)).clamp(0.0, 1.0);
    final previousOpacity =
        progress < outFraction ? 1.0 : (1 - colorOpacity).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (previousOpacity > 0)
          Opacity(opacity: previousOpacity, child: child),
        if (colorOpacity > 0)
          ColoredBox(
            color: _colorForFade(intent).withValues(alpha: colorOpacity),
          ),
      ],
    );
  }
}

enum _RenPyWipeDirection { right, left, up, down }

_RenPyWipeDirection? _wipeDirectionFor(RenPyTransitionIntent? intent) {
  if (intent == null) return null;
  if (intent.type == RenPyTransitionType.cropMove) {
    return switch (intent.mode) {
      'wiperight' || 'slideright' || 'pushright' => _RenPyWipeDirection.right,
      'wipeleft' || 'slideleft' || 'pushleft' => _RenPyWipeDirection.left,
      'wipeup' || 'slideup' || 'pushup' => _RenPyWipeDirection.up,
      'wipedown' || 'slidedown' || 'pushdown' => _RenPyWipeDirection.down,
      _ => null,
    };
  }

  if (intent.type == RenPyTransitionType.imageDissolve) {
    return switch (intent.maskAsset?.split('/').last.toLowerCase()) {
      'right.png' => _RenPyWipeDirection.right,
      'left.png' => _RenPyWipeDirection.left,
      'up.png' || 'upright.png' => _RenPyWipeDirection.up,
      'down.png' => _RenPyWipeDirection.down,
      _ => null,
    };
  }

  return null;
}

class _RenPyWipeClipper extends CustomClipper<Path> {
  const _RenPyWipeClipper({required this.progress, required this.direction});

  final double progress;
  final _RenPyWipeDirection direction;

  @override
  Path getClip(Size size) {
    final value = progress.clamp(0.0, 1.0);
    final rect = switch (direction) {
      _RenPyWipeDirection.right => Rect.fromLTRB(
        size.width * value,
        0,
        size.width,
        size.height,
      ),
      _RenPyWipeDirection.left => Rect.fromLTRB(
        0,
        0,
        size.width * (1 - value),
        size.height,
      ),
      _RenPyWipeDirection.up => Rect.fromLTRB(
        0,
        0,
        size.width,
        size.height * (1 - value),
      ),
      _RenPyWipeDirection.down => Rect.fromLTRB(
        0,
        size.height * value,
        size.width,
        size.height,
      ),
    };

    return Path()..addRect(rect);
  }

  @override
  bool shouldReclip(covariant _RenPyWipeClipper oldClipper) {
    return progress != oldClipper.progress || direction != oldClipper.direction;
  }
}

double _fraction(double? value, double total) {
  if (value == null || total <= 0) return 0;
  return (value / total).clamp(0.0, 1.0);
}

double _ratio(double value, double total) {
  if (total <= 0) return 1;
  return (value / total).clamp(0.0, 1.0);
}

double _triangleWave(double value) {
  final phase = value % 1;
  return phase < 0.5 ? -1 + (phase * 4) : 3 - (phase * 4);
}

Color _colorForFade(RenPyTransitionIntent intent) {
  final raw = intent.color;
  if (raw == null || raw.isEmpty) return Colors.black;
  final hex = raw.replaceFirst('#', '');
  final expanded =
      hex.length == 3 ? hex.split('').map((char) => '$char$char').join() : hex;
  if (expanded.length != 6) return Colors.black;
  final value = int.tryParse(expanded, radix: 16);
  if (value == null) return Colors.black;
  return Color(0xFF000000 | value);
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
