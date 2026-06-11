import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:renpy_core/renpy_core.dart'
    show RenPyImagePlacement, RenPyScreenSize, RenPyVisualElementSnapshot;
import 'package:renpy_flutter/renpy_flutter.dart'
    hide RenPyImagePlacement, RenPyScreenSize, RenPyVisualElementSnapshot;

import 'spine_character.dart';
import 'spine_image_name.dart';
import 'spine_sprite_widget.dart';

/// Builds an image layer for `RenPyPlayer.imageLayerBuilder` that renders the
/// default [RenPyImageLayer] underneath and overlays Spine sprites for image
/// changes whose resolved asset path ends in `.spine` and whose tag matches
/// one of [characters].
///
/// Non-spine images (scene backgrounds, regular sprites, text displayables)
/// keep rendering through the underlying layer, so scripts mixing both work
/// unchanged. Pass [fallback] to replace the default underlying layer; when
/// provided, suppressing `.spine` asset paths from it is the fallback's
/// responsibility.
RenPyLayerBuilder spineImageLayerBuilder({
  required List<SpineCharacter> characters,
  RenPyLayerBuilder? fallback,
}) {
  return (context, controller) => SpineImageLayer(
    controller: controller,
    characters: characters,
    fallback: fallback,
  );
}

/// The routing decision for a single Ren'Py `show`: which [SpineCharacter]
/// renders it and with what skin and animation.
class SpineShowRoute {
  const SpineShowRoute({
    required this.character,
    required this.tag,
    required this.skin,
    required this.animation,
  });

  /// The matched character configuration.
  final SpineCharacter character;

  /// The Ren'Py image tag (first word of the `show` statement).
  final String tag;

  /// The resolved Spine skin (parsed skin, else the character's default).
  final String skin;

  /// The resolved Spine animation name.
  final String animation;

  @override
  String toString() =>
      'SpineShowRoute(tag: $tag, skin: $skin, animation: $animation)';
}

/// Classifies a Ren'Py `show` event: returns the Spine route when the
/// resolved [assetPath] ends in `.spine` and the show's tag matches a
/// character in [charactersByTag], or null when the show should be delegated
/// to the regular image layer.
///
/// Pure and side-effect free so routing can be tested without initializing
/// the spine_flutter runtime.
SpineShowRoute? classifySpineShow({
  required String show,
  required String? assetPath,
  required Map<String, SpineCharacter> charactersByTag,
}) {
  final tag = imageTagFor(show);
  if (tag == null) return null;

  final character = charactersByTag[tag];
  if (character == null) return null;

  if (assetPath == null) return null;
  final parsed = SpineImageName.tryParse(assetPath);
  if (parsed == null) return null;

  return SpineShowRoute(
    character: character,
    tag: tag,
    skin: parsed.skin ?? character.effectiveDefaultSkin,
    animation:
        parsed.animation.isEmpty
            ? (character.idleAnimation ?? parsed.animation)
            : parsed.animation,
  );
}

/// The image tag of a Ren'Py image name: its first whitespace-separated word,
/// with any `#`-comment stripped. Null for blank input.
String? imageTagFor(String imageName) {
  final clean = imageName.split('#').first.trim();
  if (clean.isEmpty) return null;
  return clean.split(RegExp(r'\s+')).first;
}

/// An image layer that overlays Spine sprites on top of the regular
/// [RenPyImageLayer]. Usually constructed via [spineImageLayerBuilder].
class SpineImageLayer extends StatefulWidget {
  const SpineImageLayer({
    super.key,
    required this.controller,
    required this.characters,
    this.fallback,
  });

  /// The game controller whose image changes drive this layer.
  final RenPyFlutterController controller;

  /// The Spine characters available to `show` statements.
  final List<SpineCharacter> characters;

  /// Replaces the default underlying [RenPyImageLayer] when provided.
  final RenPyLayerBuilder? fallback;

  @override
  State<SpineImageLayer> createState() => _SpineImageLayerState();
}

class _SpineImageLayerState extends State<SpineImageLayer> {
  /// Active Spine sprites keyed by `<layer>::<tag>`, in show order.
  final _sprites = <String, _SpineSpriteEntry>{};

  late Map<String, SpineCharacter> _charactersByTag;

  @override
  void initState() {
    super.initState();
    _charactersByTag = _indexCharacters(widget.characters);
    widget.controller.addListener(_onStatusChanged);
  }

  @override
  void didUpdateWidget(SpineImageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.characters, widget.characters)) {
      _charactersByTag = _indexCharacters(widget.characters);
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onStatusChanged);
      widget.controller.addListener(_onStatusChanged);
    }
  }

  static Map<String, SpineCharacter> _indexCharacters(
    List<SpineCharacter> characters,
  ) {
    return {for (final character in characters) character.tag: character};
  }

  void _onStatusChanged() {
    final status = widget.controller.value;

    if (status is RenPyVisualRestore) {
      setState(() => _restoreFromSnapshot(status.visual.sprites));
      return;
    }

    if (status is! RenPyImageChange) return;

    setState(() {
      if (status.scene != null) {
        _clearLayer(status.sceneOnLayer);
      }

      if (status.hide != null) {
        final tag = imageTagFor(status.hide!);
        if (tag != null) {
          _sprites.remove(_spriteKey(tag, status.hideOnLayer));
        }
      }

      final show = status.show;
      if (show != null) {
        _applyShow(
          show: show,
          assetPath: status.showAsset ?? status.showImage?.assetPath,
          placement:
              status.showPlacement ?? RenPyImagePlacement.parse(status.showAt),
          layer: status.showOnLayer,
        );
      }
    });
  }

  void _applyShow({
    required String show,
    required String? assetPath,
    required RenPyImagePlacement? placement,
    required String? layer,
  }) {
    final route = classifySpineShow(
      show: show,
      assetPath: assetPath,
      charactersByTag: _charactersByTag,
    );

    final tag = imageTagFor(show);
    if (tag == null) return;
    final key = _spriteKey(tag, layer);

    if (route == null) {
      // A non-spine show reusing a spine tag replaces the Spine sprite (the
      // underlying layer renders it instead).
      _sprites.remove(key);
      return;
    }

    final previous = _sprites[key];
    _sprites[key] = _SpineSpriteEntry(
      character: route.character,
      skin: route.skin,
      animation: route.animation,
      x: _resolveX(placement, previous),
      y: _resolveY(placement, previous),
    );
  }

  void _restoreFromSnapshot(List<RenPyVisualElementSnapshot> sprites) {
    _sprites.clear();
    for (final sprite in sprites) {
      final show = sprite.tag ?? sprite.imageName;
      if (show == null) continue;
      _applyShow(
        show: show,
        assetPath: sprite.assetPath,
        placement: sprite.placement,
        layer: sprite.layer,
      );
    }
  }

  /// The horizontal stage fraction (0 = left edge, 1 = right edge) for a
  /// sprite. Explicit placements win; an existing sprite keeps its side;
  /// otherwise new characters alternate left/right like the prototype.
  double _resolveX(RenPyImagePlacement? placement, _SpineSpriteEntry? previous) {
    final explicit =
        placement?.xalign ??
        (placement?.xposIsPixel == false ? placement?.xpos : null);
    if (explicit != null) return explicit.clamp(0.0, 1.0).toDouble();
    if (previous != null) return previous.x;

    final leftTaken = _sprites.values.where((entry) => entry.x < 0.5).length;
    final rightTaken = _sprites.length - leftTaken;
    return leftTaken <= rightTaken ? 0.0 : 1.0;
  }

  /// The vertical stage fraction; sprites sit on the stage bottom by default.
  double _resolveY(RenPyImagePlacement? placement, _SpineSpriteEntry? previous) {
    final explicit =
        placement?.yalign ??
        (placement?.yposIsPixel == false ? placement?.ypos : null);
    if (explicit != null) return explicit.clamp(0.0, 1.0).toDouble();
    return previous?.y ?? 1.0;
  }

  void _clearLayer(String? layer) {
    final prefix = '${_normalizedLayer(layer)}::';
    _sprites.removeWhere((key, _) => key.startsWith(prefix));
  }

  String _spriteKey(String tag, String? layer) =>
      '${_normalizedLayer(layer)}::$tag';

  String _normalizedLayer(String? layer) {
    final value = layer?.trim();
    return value == null || value.isEmpty ? 'master' : value;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStatusChanged);
    super.dispose();
  }

  Widget _buildDefaultUnderlay(
    BuildContext context,
    RenPyFlutterController controller,
  ) {
    return RenPyImageLayer(
      controller: controller,
      screenSize: RenPyScreenSize.fallback,
      atlResolver: controller.resolveAtl,
      imageProvider: _spineAwareImageProvider,
    );
  }

  @override
  Widget build(BuildContext context) {
    final underlay = widget.fallback ?? _buildDefaultUnderlay;
    return Stack(
      fit: StackFit.expand,
      children: [
        underlay(context, widget.controller),
        for (final entry in _sprites.entries)
          Align(
            key: ValueKey('renpy-spine::${entry.key}'),
            alignment: Alignment(
              entry.value.x * 2 - 1,
              entry.value.y * 2 - 1,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: SizedBox(
                width: 200 * entry.value.character.scale,
                height: 300 * entry.value.character.scale,
                child: SpineSpriteWidget(
                  // Stable per-tag key: animation/skin changes update the
                  // live skeleton instead of reloading it.
                  key: ValueKey('renpy-spine-sprite::${entry.key}'),
                  atlasAsset: entry.value.character.atlasAsset,
                  skeletonAsset: entry.value.character.skeletonAsset,
                  skin: entry.value.skin,
                  defaultSkin: entry.value.character.effectiveDefaultSkin,
                  animation: entry.value.animation,
                  idleAnimation: entry.value.character.idleAnimation,
                  mixSeconds: entry.value.character.mixSeconds,
                  bundle: entry.value.character.bundle,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SpineSpriteEntry {
  const _SpineSpriteEntry({
    required this.character,
    required this.skin,
    required this.animation,
    required this.x,
    required this.y,
  });

  final SpineCharacter character;
  final String skin;
  final String animation;

  /// Horizontal stage fraction in 0..1.
  final double x;

  /// Vertical stage fraction in 0..1.
  final double y;
}

/// An [AssetImage]-backed provider that swallows `.spine` asset paths by
/// substituting a transparent pixel, so the underlying [RenPyImageLayer]
/// neither errors on nor draws placeholders for spine-routed shows.
ImageProvider<Object> _spineAwareImageProvider(String assetPath) {
  if (assetPath.toLowerCase().endsWith('.spine')) {
    return MemoryImage(_transparentPixelPng);
  }
  return AssetImage(assetPath);
}

/// A 1x1 fully transparent RGBA PNG.
final Uint8List _transparentPixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0b, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0x7a, 0x5e, 0xab, 0x3f, 0x00, 0x00, 0x00, 0x00, //
  0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
