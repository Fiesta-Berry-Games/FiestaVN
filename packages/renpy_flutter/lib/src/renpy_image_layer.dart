import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:renpy_core/renpy_core.dart'
    show
        RenPyAtlProgram,
        RenPyAtlState,
        RenPyImageOperation,
        RenPyImageOperationType,
        RenPyImagePlacement,
        RenPyResolvedImage,
        RenPyScreenSize,
        RenPyVisualElementSnapshot,
        RenPyVisualSnapshot,
        RenPyTransitionIntent,
        RenPyTransitionType;

import 'renpy_flutter_controller.dart';
import 'renpy_text.dart';

typedef RenPyImageProviderFactory =
    ImageProvider<Object> Function(String assetPath);

/// Resolves the transform named in a `show X at <name>` clause to a compiled
/// ATL animation program, or null when the name is not an animatable transform.
/// The host wires this from the runner's transform registry (`atlForTransform`
/// + `pythonScope`); when unset, sprites render with their static placement.
typedef RenPyAtlResolver = RenPyAtlProgram? Function(String transformName);

/// Renders RenPy scene and show image changes as Flutter asset images.
class RenPyImageLayer extends StatefulWidget {
  const RenPyImageLayer({
    super.key,
    required this.controller,
    this.imageProvider,
    this.screenSize,
    this.layerOrder,
    this.atlResolver,
  });

  final RenPyFlutterController controller;
  final RenPyImageProviderFactory? imageProvider;
  final RenPyScreenSize? screenSize;
  final List<String>? layerOrder;

  /// Resolves a `show X at <name>` transform to its ATL animation. When null,
  /// sprites keep their static placement (today's behavior).
  final RenPyAtlResolver? atlResolver;

  @override
  State<RenPyImageLayer> createState() => _RenPyImageLayerState();
}

const _masterLayer = 'master';
const _defaultLayerOrder = [
  'belowmid',
  _masterLayer,
  'abovemid',
  'transient',
  'screens',
  'overlay',
];

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

    if (status is RenPyVisualRestore) {
      setState(() {
        _previousVisualState = null;
        _transitionActive = false;
        _activeTransitionIntent = null;
        _transitionGeneration++;
        _applyVisualSnapshot(status.visual);
      });
      return;
    }

    if (status is! RenPyImageChange) return;

    setState(() {
      _previousVisualState = _currentVisualState();
      _transitionActive = false;

      if (status.scene != null) {
        _clearSpriteLayer(status.sceneOnLayer);

        if (_isMasterLayer(status.sceneOnLayer)) {
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
        } else {
          _putSceneSprite(status);
        }
      }

      if (status.hide != null) {
        final name = status.hide!.trim().split(RegExp(r'\s+')).first;
        final key = _spriteKey(name, status.hideOnLayer);
        _sprites.remove(key);
        _positions.remove(key);
      }

      if (status.show != null) {
        final clean = status.show!.split('#').first.trim();
        final parts = clean.split(RegExp(r'\s+'));
        if (parts.isEmpty) return;

        final name = parts.first;
        final key = _spriteKey(name, status.showOnLayer);

        final placement =
            status.showPlacement ??
            RenPyImagePlacement.parse(status.showAt) ??
            _positions[key] ??
            _defaultSpritePlacement;
        _positions[key] = placement;

        final atl = _resolveAtl(status.showAt);

        final text = status.showText;
        final layers = _renderedLayers(status.showLayers);
        if (text != null) {
          _putSprite(
            name,
            _RenPySpriteState.text(
              text: text,
              placement: placement,
              zOrder: status.showZOrder ?? 0,
              atl: atl,
            ),
            behind: status.showBehind,
            layer: status.showOnLayer,
          );
        } else if (layers.isNotEmpty) {
          _putSprite(
            name,
            _RenPySpriteState.layered(
              layers: layers,
              placement: placement,
              zOrder: status.showZOrder ?? 0,
              atl: atl,
            ),
            behind: status.showBehind,
            layer: status.showOnLayer,
          );
        } else {
          final image = _RenPyRenderedImage.fromStatus(
            status.showImage,
            status.showAsset,
          );
          if (image == null) return;

          _putSprite(
            name,
            _RenPySpriteState.image(
              image: image,
              placement: placement,
              zOrder: status.showZOrder ?? 0,
              atl: atl,
            ),
            behind: status.showBehind,
            layer: status.showOnLayer,
          );
        }
      }
    });
  }

  /// Maps the resolved layeredimage layer images to renderable images, dropping
  /// any that carry no asset path so the rest of the composite still draws.
  List<_RenPyRenderedImage> _renderedLayers(List<RenPyResolvedImage> layers) {
    final rendered = <_RenPyRenderedImage>[];
    for (final layer in layers) {
      final image = _RenPyRenderedImage.fromResolved(layer);
      if (image != null) rendered.add(image);
    }
    return rendered;
  }

  /// Resolves the `at` clause to a compiled ATL program, trying the whole
  /// expression then each comma-separated transform name. Returns null when no
  /// resolver is wired or no name names an animatable transform.
  RenPyAtlProgram? _resolveAtl(String? at) {
    final resolver = widget.atlResolver;
    final clean = at?.trim();
    if (resolver == null || clean == null || clean.isEmpty) return null;

    final whole = resolver(clean);
    if (whole != null) return whole;

    for (final part in clean.split(',')) {
      final name = part.trim();
      if (name.isEmpty) continue;
      final program = resolver(name);
      if (program != null) return program;
    }
    return null;
  }

  void _applyVisualSnapshot(RenPyVisualSnapshot visual) {
    _sprites.clear();
    _positions.clear();

    final scene = visual.scene;
    final backgroundScene =
        scene == null || !_isMasterLayer(scene.layer) ? null : scene;
    final sceneName = backgroundScene?.imageName;
    final solidColor =
        _colorForSnapshotSolid(backgroundScene) ??
        (sceneName == null ? Colors.black : _solidColorForScene(sceneName));
    _backgroundColor = solidColor ?? Colors.black;
    _backgroundImage =
        solidColor == null && backgroundScene != null
            ? _RenPyRenderedImage.fromSnapshot(backgroundScene)
            : null;

    if (scene != null && !_isMasterLayer(scene.layer)) {
      _putSnapshotSprite(scene);
    }

    for (final sprite in visual.sprites) {
      _putSnapshotSprite(sprite);
    }
  }

  void _putSnapshotSprite(RenPyVisualElementSnapshot sprite) {
    final name = _tagForSnapshot(sprite);
    if (name == null) return;
    final key = _spriteKey(name, sprite.layer);

    final placement = sprite.placement ?? _defaultSpritePlacement;
    _positions[key] = placement;

    final text = sprite.text;
    if (text != null) {
      _sprites[key] = _RenPySpriteState.text(
        text: text,
        placement: placement,
        zOrder: sprite.zOrder ?? 0,
      );
      return;
    }

    final solidColor = _colorForSnapshotSolid(sprite);
    if (solidColor != null) {
      _sprites[key] = _RenPySpriteState.solid(
        solidColor: solidColor,
        placement: placement,
        zOrder: sprite.zOrder ?? 0,
      );
      return;
    }

    final image = _RenPyRenderedImage.fromSnapshot(sprite);
    if (image == null) return;
    _sprites[key] = _RenPySpriteState.image(
      image: image,
      placement: placement,
      zOrder: sprite.zOrder ?? 0,
    );
  }

  String? _tagForSnapshot(RenPyVisualElementSnapshot snapshot) {
    final tag = snapshot.tag;
    if (tag != null && tag.isNotEmpty) return tag;
    final imageName = snapshot.imageName;
    if (imageName == null) return null;
    return _imageTag(imageName);
  }

  String _imageTag(String imageName) {
    final baseName = imageName.split('#').first.trim();
    if (baseName.isEmpty) return imageName;
    return baseName.split(RegExp(r'\s+')).first;
  }

  void _putSprite(
    String name,
    _RenPySpriteState sprite, {
    String? behind,
    String? layer,
  }) {
    final key = _spriteKey(name, layer);
    _sprites.remove(key);

    final behindValue = behind?.trim();
    final target =
        behindValue == null || behindValue.isEmpty
            ? null
            : behindValue.split(RegExp(r'\s+')).first;
    if (target == null || target.isEmpty) {
      _sprites[key] = sprite;
      return;
    }

    final targetKey = _spriteKey(target, layer);
    if (!_sprites.containsKey(targetKey)) {
      _sprites[key] = sprite;
      return;
    }

    final ordered = <String, _RenPySpriteState>{};
    for (final entry in _sprites.entries) {
      if (entry.key == targetKey) {
        ordered[key] = sprite;
      }
      ordered[entry.key] = entry.value;
    }

    _sprites
      ..clear()
      ..addAll(ordered);
  }

  void _putSceneSprite(RenPyImageChange status) {
    final scene = status.scene;
    if (scene == null) return;

    final name = _imageTag(scene);
    final placement =
        status.scenePlacement ??
        RenPyImagePlacement.parse(status.sceneAt) ??
        _defaultSpritePlacement;

    final solidColor =
        _colorForResolvedSolid(status.sceneImage) ?? _solidColorForScene(scene);
    if (solidColor != null) {
      _putSprite(
        name,
        _RenPySpriteState.solid(
          solidColor: solidColor,
          placement: placement,
          zOrder: status.sceneZOrder ?? 0,
        ),
        layer: status.sceneOnLayer,
      );
      return;
    }

    final image = _RenPyRenderedImage.fromStatus(
      status.sceneImage,
      status.sceneAsset,
    );
    if (image == null) return;

    _putSprite(
      name,
      _RenPySpriteState.image(
        image: image,
        placement: placement,
        zOrder: status.sceneZOrder ?? 0,
      ),
      layer: status.sceneOnLayer,
    );
  }

  void _clearSpriteLayer(String? layer) {
    final normalized = _normalizedLayer(layer);
    _sprites.removeWhere((key, _) => key.startsWith('$normalized::'));
    _positions.removeWhere((key, _) => key.startsWith('$normalized::'));
  }

  String _spriteKey(String tag, String? layer) {
    return '${_normalizedLayer(layer)}::$tag';
  }

  String _widgetKey(String spriteKey) {
    final separator = spriteKey.indexOf('::');
    if (separator < 0) return spriteKey;
    final layer = spriteKey.substring(0, separator);
    final tag = spriteKey.substring(separator + 2);
    return layer == _masterLayer ? tag : spriteKey;
  }

  String _normalizedLayer(String? layer) {
    final value = layer?.trim();
    return value == null || value.isEmpty ? _masterLayer : value;
  }

  bool _isMasterLayer(String? layer) {
    return _normalizedLayer(layer) == _masterLayer;
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
      layerOrder: widget.layerOrder,
    );
    final previousFrame =
        previous == null
            ? null
            : _RenPyVisualFrame(
              state: previous,
              imageProvider: widget.imageProvider ?? _defaultImageProvider,
              screenSize: widget.screenSize,
              layerOrder: widget.layerOrder,
            );
    final isPunch =
        _transitionActive &&
        transitionIntent?.type == RenPyTransitionType.punch;
    final isFade =
        _transitionActive &&
        previous != null &&
        transitionIntent?.type == RenPyTransitionType.fade;

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
        else if (isFade)
          TweenAnimationBuilder<double>(
            key: ValueKey(_transitionGeneration),
            tween: Tween(begin: 1, end: 0),
            duration: _durationFor(transitionIntent),
            onEnd: _clearTransition,
            builder: (context, remaining, child) {
              return _RenPyFadeTransition(
                remaining: remaining,
                intent: transitionIntent!,
                previous: previousFrame!,
                current: currentFrame,
              );
            },
          )
        else
          currentFrame,
        if (previous != null && !isPunch && !isFade)
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
            child: previousFrame!,
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
      widgetKey: _widgetKey,
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
    required this.widgetKey,
  });

  final Color backgroundColor;
  final _RenPyRenderedImage? backgroundImage;
  final Map<String, _RenPySpriteState> sprites;
  final String Function(String spriteKey) widgetKey;
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

Color? _colorForSnapshotSolid(RenPyVisualElementSnapshot? snapshot) {
  final color = snapshot?.solidColor;
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

  static _RenPyRenderedImage? fromSnapshot(
    RenPyVisualElementSnapshot snapshot,
  ) {
    final assetPath = snapshot.assetPath;
    if (assetPath == null) return null;

    return _RenPyRenderedImage(
      assetPath: assetPath,
      operations: snapshot.operations,
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
  const _RenPySpriteState.image({
    required this.image,
    required this.placement,
    this.zOrder = 0,
    this.atl,
  }) : solidColor = null,
       text = null,
       layers = const [];

  const _RenPySpriteState.text({
    required this.text,
    required this.placement,
    this.zOrder = 0,
    this.atl,
  }) : image = null,
       solidColor = null,
       layers = const [];

  const _RenPySpriteState.solid({
    required this.solidColor,
    required this.placement,
    this.zOrder = 0,
  }) : image = null,
       text = null,
       atl = null,
       layers = const [];

  /// A layeredimage composite: [layers] drawn bottom-to-top in one sprite.
  const _RenPySpriteState.layered({
    required this.layers,
    required this.placement,
    this.zOrder = 0,
    this.atl,
  }) : image = null,
       solidColor = null,
       text = null;

  final _RenPyRenderedImage? image;
  final Color? solidColor;
  final String? text;

  /// The ordered (bottom-to-top) layer images of a layeredimage composite, or
  /// empty for a single-image / solid / text sprite.
  final List<_RenPyRenderedImage> layers;
  final RenPyImagePlacement placement;
  final int zOrder;

  /// The compiled ATL animation driving this sprite, or null for a static
  /// placement.
  final RenPyAtlProgram? atl;
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
    required this.layerOrder,
  });

  final _RenPyVisualState state;
  final RenPyImageProviderFactory imageProvider;
  final RenPyScreenSize? screenSize;
  final List<String>? layerOrder;

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
        for (final entry in _orderedSprites(state.sprites, layerOrder))
          _RenPyDisplayableSprite(
            key: ValueKey(state.widgetKey(entry.key)),
            sprite: entry.value,
            imageProvider: imageProvider,
            screenSize: screenSize,
          ),
      ],
    );
  }
}

class _RenPyDisplayableSprite extends StatefulWidget {
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
  State<_RenPyDisplayableSprite> createState() =>
      _RenPyDisplayableSpriteState();
}

class _RenPyDisplayableSpriteState extends State<_RenPyDisplayableSprite>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _elapsed = 0;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(covariant _RenPyDisplayableSprite oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.sprite.atl, oldWidget.sprite.atl)) {
      _elapsed = 0;
      _startTicker();
    }
  }

  void _startTicker() {
    final atl = widget.sprite.atl;
    _ticker?.dispose();
    _ticker = null;
    if (atl == null) return;

    _ticker = createTicker((elapsed) {
      final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      setState(() => _elapsed = seconds);
      if (atl.isComplete(seconds)) _ticker?.stop();
    })..start();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sprite = widget.sprite;
    final solidColor = sprite.solidColor;
    if (solidColor != null) {
      return Positioned.fill(child: ColoredBox(color: solidColor));
    }

    final atlState = sprite.atl?.transformAt(_elapsed);
    final placement = _mergePlacement(sprite.placement, atlState);

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stageSize = constraints.biggest;
          final screenScale = _screenScale(widget.screenSize, stageSize);
          final resolved = _ResolvedSpritePlacement.from(
            placement,
            stageSize: stageSize,
            screenScale: screenScale,
          );
          Widget content =
              sprite.layers.isNotEmpty
                  ? _RenPyLayeredSpriteImage(
                    layers: sprite.layers,
                    imageProvider: widget.imageProvider,
                  )
                  : sprite.text == null
                  ? _RenPySpriteImage(
                    image: sprite.image!,
                    imageProvider: widget.imageProvider,
                  )
                  : ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.9,
                      maxHeight: constraints.maxHeight * 0.9,
                    ),
                    child: _RenPyTextDisplayable(text: sprite.text!),
                  );

          content = _applyAtlEffects(atlState, content);

          final offset = _atlOffsetPixels(atlState, screenScale);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: resolved.position.dx + offset.dx,
                top: resolved.position.dy + offset.dy,
                child: _positionDisplayable(
                  placement: placement,
                  resolved: resolved,
                  screenScale: screenScale,
                  child: content,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Folds the ATL [state] into the base [placement] for the position/zoom/alpha
/// fields the static renderer already understands; rotate/offset/crop are
/// applied separately as widget transforms.
RenPyImagePlacement _mergePlacement(
  RenPyImagePlacement placement,
  RenPyAtlState? state,
) {
  if (state == null) return placement;
  return RenPyImagePlacement.position(
    xpos: state.xpos ?? placement.xpos,
    ypos: state.ypos ?? placement.ypos,
    xanchor: state.xanchor ?? placement.xanchor,
    yanchor: state.yanchor ?? placement.yanchor,
    xalign: state.xalign ?? placement.xalign,
    yalign: state.yalign ?? placement.yalign,
    xposIsPixel: state.xpos != null ? state.xposIsPixel : placement.xposIsPixel,
    yposIsPixel: state.ypos != null ? state.yposIsPixel : placement.yposIsPixel,
    xanchorIsPixel: placement.xanchorIsPixel,
    yanchorIsPixel: placement.yanchorIsPixel,
    zoom: state.zoom ?? placement.zoom,
    xzoom: state.xzoom ?? placement.xzoom,
    yzoom: state.yzoom ?? placement.yzoom,
    alpha: state.alpha ?? placement.alpha,
  );
}

/// The pixel translation contributed by the ATL `xoffset`/`yoffset`.
Offset _atlOffsetPixels(RenPyAtlState? state, double screenScale) {
  if (state == null) return Offset.zero;
  return Offset(
    (state.xoffset ?? 0) * screenScale,
    (state.yoffset ?? 0) * screenScale,
  );
}

/// Applies the ATL rotation and crop that the static placement cannot express.
Widget _applyAtlEffects(RenPyAtlState? state, Widget child) {
  if (state == null) return child;

  var result = child;

  if (state.hasCrop) {
    result = ClipRect(
      clipper: _RenPyAtlCropClipper(
        left: state.cropLeft!,
        top: state.cropTop!,
        width: state.cropWidth!,
        height: state.cropHeight!,
      ),
      child: result,
    );
  }

  final rotate = state.rotate;
  if (rotate != null && rotate != 0) {
    result = Transform.rotate(angle: rotate * math.pi / 180, child: result);
  }

  return result;
}

/// Clips a sprite to an ATL `crop (l, t, w, h)` rectangle. Values <= 1 are
/// treated as fractions of the sprite size; larger values are pixels.
class _RenPyAtlCropClipper extends CustomClipper<Rect> {
  const _RenPyAtlCropClipper({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  double _resolve(double value, double extent) =>
      value <= 1 && value >= -1 ? value * extent : value;

  @override
  Rect getClip(Size size) {
    return Rect.fromLTWH(
      _resolve(left, size.width),
      _resolve(top, size.height),
      _resolve(width, size.width),
      _resolve(height, size.height),
    );
  }

  @override
  bool shouldReclip(covariant _RenPyAtlCropClipper oldClipper) {
    return left != oldClipper.left ||
        top != oldClipper.top ||
        width != oldClipper.width ||
        height != oldClipper.height;
  }
}

List<MapEntry<String, _RenPySpriteState>> _orderedSprites(
  Map<String, _RenPySpriteState> sprites,
  List<String>? layerOrder,
) {
  final indexed = <({int index, MapEntry<String, _RenPySpriteState> entry})>[];
  var index = 0;
  for (final entry in sprites.entries) {
    indexed.add((index: index++, entry: entry));
  }

  indexed.sort((left, right) {
    final layerComparison = _layerRank(
      _layerForSpriteKey(left.entry.key),
      layerOrder,
    ).compareTo(_layerRank(_layerForSpriteKey(right.entry.key), layerOrder));
    if (layerComparison != 0) return layerComparison;
    final zOrderComparison = left.entry.value.zOrder.compareTo(
      right.entry.value.zOrder,
    );
    if (zOrderComparison != 0) return zOrderComparison;
    return left.index.compareTo(right.index);
  });

  return [for (final item in indexed) item.entry];
}

String _layerForSpriteKey(String spriteKey) {
  final separator = spriteKey.indexOf('::');
  if (separator < 0) return _masterLayer;
  return spriteKey.substring(0, separator);
}

int _layerRank(String layer, List<String>? layerOrder) {
  final order = _effectiveLayerOrder(layerOrder);
  final explicitRank = order.indexOf(layer);
  if (explicitRank >= 0) return explicitRank * 10;

  if (layerOrder == null || layerOrder.isEmpty) {
    final masterRank = order.indexOf(_masterLayer) * 10;
    if (layer.startsWith('below')) return masterRank - 5;
  }

  return order.length * 10 + 5;
}

List<String> _effectiveLayerOrder(List<String>? layerOrder) {
  final raw =
      layerOrder == null || layerOrder.isEmpty
          ? _defaultLayerOrder
          : layerOrder;
  final seen = <String>{};
  return [
    for (final layer in raw)
      if (layer.trim().isNotEmpty && seen.add(layer.trim())) layer.trim(),
  ];
}

Widget _positionDisplayable({
  required RenPyImagePlacement placement,
  required _ResolvedSpritePlacement resolved,
  required double screenScale,
  required Widget child,
}) {
  final anchored = FractionalTranslation(
    translation: resolved.anchorTranslation,
    child: Transform.translate(offset: resolved.anchorOffset, child: child),
  );

  final scaled = _scaleDisplayable(placement, screenScale, anchored);
  final alpha = placement.alpha;
  if (alpha == null) return scaled;

  final target = placement.alphaTarget;
  final duration = placement.alphaDuration;
  if (target == null || duration == null || duration <= 0) {
    return Opacity(opacity: alpha.clamp(0, 1).toDouble(), child: scaled);
  }

  return TweenAnimationBuilder<double>(
    tween: Tween(begin: alpha, end: target),
    duration: Duration(milliseconds: (duration * 1000).round()),
    builder:
        (context, opacity, child) =>
            Opacity(opacity: opacity.clamp(0, 1).toDouble(), child: child),
    child: scaled,
  );
}

Widget _scaleDisplayable(
  RenPyImagePlacement placement,
  double screenScale,
  Widget child,
) {
  final zoom = placement.zoom ?? 1;
  final xScale = screenScale * zoom * (placement.xzoom ?? 1);
  final yScale = screenScale * zoom * (placement.yzoom ?? 1);
  if (xScale == 1 && yScale == 1) return child;

  return Transform.scale(
    scaleX: xScale,
    scaleY: yScale,
    alignment: Alignment.topLeft,
    child: child,
  );
}

double _screenScale(RenPyScreenSize? screenSize, Size stageSize) {
  if (screenSize == null || stageSize.width <= 0 || stageSize.height <= 0) {
    return 1;
  }

  return math.min(
    stageSize.width / screenSize.width,
    stageSize.height / screenSize.height,
  );
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

/// Renders a layeredimage composite: each layer image stacked bottom-to-top.
/// The first layer establishes the composite's intrinsic size; the remaining
/// layers fill that box so they register pixel-for-pixel like real RenPy.
class _RenPyLayeredSpriteImage extends StatelessWidget {
  const _RenPyLayeredSpriteImage({
    required this.layers,
    required this.imageProvider,
  });

  final List<_RenPyRenderedImage> layers;
  final RenPyImageProviderFactory imageProvider;

  @override
  Widget build(BuildContext context) {
    if (layers.length == 1) {
      return _RenPySpriteImage(
        image: layers.first,
        imageProvider: imageProvider,
      );
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _RenPySpriteImage(image: layers.first, imageProvider: imageProvider),
        for (final layer in layers.skip(1))
          Positioned.fill(
            child: _RenPySpriteImage(
              image: layer,
              imageProvider: imageProvider,
            ),
          ),
      ],
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
    required this.position,
    required this.anchorTranslation,
    required this.anchorOffset,
  });

  factory _ResolvedSpritePlacement.from(
    RenPyImagePlacement placement, {
    required Size stageSize,
    required double screenScale,
  }) {
    final xpos = placement.xalign ?? placement.xpos;
    final ypos = placement.yalign ?? placement.ypos;
    final xanchor = placement.xalign ?? placement.xanchor ?? 0.5;
    final yanchor = placement.yalign ?? placement.yanchor ?? 1.0;
    final xanchorIsPixel = placement.xalign == null && placement.xanchorIsPixel;
    final yanchorIsPixel = placement.yalign == null && placement.yanchorIsPixel;

    return _ResolvedSpritePlacement(
      position: Offset(
        _positionPixels(
          xpos,
          placement.xposIsPixel,
          stageSize.width,
          screenScale,
          0.5,
        ),
        _positionPixels(
          ypos,
          placement.yposIsPixel,
          stageSize.height,
          screenScale,
          1.0,
        ),
      ),
      anchorTranslation: Offset(
        xanchorIsPixel ? 0 : -xanchor,
        yanchorIsPixel ? 0 : -yanchor,
      ),
      anchorOffset: Offset(
        xanchorIsPixel ? -xanchor : 0,
        yanchorIsPixel ? -yanchor : 0,
      ),
    );
  }

  final Offset position;
  final Offset anchorTranslation;
  final Offset anchorOffset;
}

double _positionPixels(
  double? value,
  bool isPixel,
  double stageAxisSize,
  double screenScale,
  double fallback,
) {
  if (value == null) return fallback * stageAxisSize;
  if (isPixel) return value * screenScale;
  return value * stageAxisSize;
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

class _RenPyFadeTransition extends StatelessWidget {
  const _RenPyFadeTransition({
    required this.remaining,
    required this.intent,
    required this.previous,
    required this.current,
  });

  final double remaining;
  final RenPyTransitionIntent intent;
  final Widget previous;
  final Widget current;

  @override
  Widget build(BuildContext context) {
    final progress = (1 - remaining).clamp(0.0, 1.0);
    final outFraction = _fraction(intent.outTime, intent.totalDuration);
    final holdFraction = _fraction(intent.holdTime, intent.totalDuration);
    final inStart = outFraction + holdFraction;
    final color = _colorForFade(intent);

    if (progress < outFraction) {
      final colorOpacity = _ratio(progress, outFraction);
      return Stack(
        fit: StackFit.expand,
        children: [
          previous,
          if (colorOpacity > 0)
            ColoredBox(color: color.withValues(alpha: colorOpacity)),
        ],
      );
    }

    if (progress < inStart) {
      return ColoredBox(color: color);
    }

    final inFraction = (1 - inStart).clamp(0.0, 1.0);
    final colorOpacity = (1 - _ratio(progress - inStart, inFraction)).clamp(
      0.0,
      1.0,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        current,
        if (colorOpacity > 0)
          ColoredBox(color: color.withValues(alpha: colorOpacity)),
      ],
    );
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
