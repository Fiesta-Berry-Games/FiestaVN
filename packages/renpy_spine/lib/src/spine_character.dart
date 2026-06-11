import 'package:flutter/services.dart';

/// Declarative configuration tying a Ren'Py image tag to a Spine skeleton.
///
/// A character is selected by [tag]: any `show <tag> ...` statement whose
/// resolved asset path ends in `.spine` is rendered as a Spine sprite using
/// this character's [atlasAsset] and [skeletonAsset].
///
/// ## Image-name convention
///
/// Ren'Py image expressions name a Spine pose with an asset path ending in
/// `.spine`, parsed by [SpineImageName.tryParse]:
///
/// - `erikari-movement/idle-front.spine` → skin `erikari`, animation
///   `movement/idle-front` (a parent directory containing `-` is split at its
///   first dash into `<skin>-<group>`, and the animation becomes
///   `<group>/<file>`).
/// - `erikari-angry.spine` → skin `erikari`, animation `angry` (a bare file
///   name is split at its first dash into `<skin>-<animation>`).
/// - `wave.spine` → no skin, animation `wave`; the layer falls back to
///   [defaultSkin], then to [tag].
///
/// Leading directories such as a game root (`assets/games/1/game/`) are
/// ignored by the parser.
class SpineCharacter {
  const SpineCharacter({
    required this.tag,
    required this.atlasAsset,
    required this.skeletonAsset,
    this.defaultSkin,
    this.idleAnimation,
    this.scale = 1.0,
    this.mixSeconds = 0.2,
    this.bundle,
  });

  /// The Ren'Py image tag this character answers to (e.g. `erikari`, the
  /// first word of `show erikari wave`).
  final String tag;

  /// The `.atlas` asset for the skeleton's images.
  final String atlasAsset;

  /// The skeleton data asset: a `.skel` or `.json` Spine export.
  final String skeletonAsset;

  /// The skin used when the image name carries no skin prefix, or when the
  /// parsed skin does not exist in the skeleton. Defaults to [tag] when null.
  final String? defaultSkin;

  /// The animation used as a last resort when the requested animation cannot
  /// be found (e.g. `movement/idle-front`).
  final String? idleAnimation;

  /// A multiplier applied to the sprite's on-stage footprint.
  final double scale;

  /// The default animation mix (cross-fade) duration in seconds applied when
  /// switching animations.
  final double mixSeconds;

  /// The bundle the atlas/skeleton assets are loaded from; the root bundle
  /// when null.
  final AssetBundle? bundle;

  /// The skin to fall back to when an image name has no skin prefix.
  String get effectiveDefaultSkin => defaultSkin ?? tag;
}
