import 'package:flutter/widgets.dart';
import 'package:spine_flutter/spine_flutter.dart' as spine;

/// A single Spine character: one skeleton instance showing one skin and one
/// looping animation.
///
/// The skeleton is loaded once via [spine.SpineWidget.fromAsset]; subsequent
/// [skin]/[animation] changes (delivered through `didUpdateWidget`, i.e. by
/// rebuilding this widget with the same key and new values) are applied to
/// the live skeleton without reloading any assets, cross-fading animations
/// over [mixSeconds].
///
/// Requires `initSpineFlutter()` to have completed before being built.
class SpineSpriteWidget extends StatefulWidget {
  const SpineSpriteWidget({
    super.key,
    required this.atlasAsset,
    required this.skeletonAsset,
    required this.animation,
    this.skin,
    this.defaultSkin,
    this.idleAnimation,
    this.mixSeconds = 0.2,
    this.bundle,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.bottomCenter,
  });

  /// The `.atlas` asset for the skeleton's images.
  final String atlasAsset;

  /// The skeleton data asset: a `.skel` or `.json` Spine export.
  final String skeletonAsset;

  /// The skin to apply, or null to use [defaultSkin] (or the skeleton's
  /// default skin).
  final String? skin;

  /// The skin tried when [skin] is null or missing from the skeleton.
  final String? defaultSkin;

  /// The looping animation to play. When the exact name is missing, a few
  /// conventional locations are tried (`movement/<name>`, `emotes/<name>`,
  /// `<name>-front`, `movement/<name>-front`), then [idleAnimation], then the
  /// skeleton's first animation.
  final String animation;

  /// The animation played as a last resort when [animation] cannot be found.
  final String? idleAnimation;

  /// The default animation mix (cross-fade) duration in seconds.
  final double mixSeconds;

  /// The bundle the assets are loaded from; the root bundle when null.
  final AssetBundle? bundle;

  /// How the skeleton is fitted inside this widget.
  final BoxFit fit;

  /// How the skeleton is aligned inside this widget.
  final Alignment alignment;

  @override
  State<SpineSpriteWidget> createState() => _SpineSpriteWidgetState();
}

class _SpineSpriteWidgetState extends State<SpineSpriteWidget> {
  late final spine.SpineWidgetController _controller;
  bool _initialized = false;
  String? _appliedSkin;

  @override
  void initState() {
    super.initState();
    _controller = spine.SpineWidgetController(
      onInitialized: (_) {
        _initialized = true;
        _apply();
      },
    );
  }

  @override
  void didUpdateWidget(SpineSpriteWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_initialized) return;
    if (widget.skin != oldWidget.skin ||
        widget.animation != oldWidget.animation) {
      _apply();
    }
  }

  /// Applies the widget's skin and animation to the live skeleton.
  void _apply() {
    try {
      _applySkin();
      _applyAnimation();
    } catch (error) {
      debugPrint('SpineSpriteWidget: could not apply pose: $error');
    }
  }

  void _applySkin() {
    final wanted = widget.skin ?? widget.defaultSkin;
    if (_appliedSkin == wanted && _appliedSkin != null) return;

    final skin = _findSkin(_controller.skeletonData, wanted);
    if (skin == null) return;

    _controller.skeleton
      ..setSkin(skin)
      ..setSlotsToSetupPose();
    _appliedSkin = wanted ?? skin.getName();
  }

  spine.Skin? _findSkin(spine.SkeletonData data, String? wanted) {
    for (final name in [wanted, widget.defaultSkin]) {
      if (name == null) continue;
      final skin = data.findSkin(name);
      if (skin != null) return skin;
    }
    return data.getDefaultSkin();
  }

  void _applyAnimation() {
    // Cross-fade between animations on the same track.
    _controller.animationStateData.setDefaultMix(widget.mixSeconds);

    final data = _controller.skeletonData;
    spine.Animation? animation;
    for (final candidate in _animationCandidates()) {
      animation = data.findAnimation(candidate);
      if (animation != null) break;
    }

    // Nothing matched: fall back to the skeleton's first animation so the
    // sprite never freezes in setup pose.
    if (animation == null) {
      final animations = data.getAnimations();
      if (animations.isEmpty) {
        debugPrint(
          'SpineSpriteWidget: no animation named "${widget.animation}" and '
          'the skeleton has no animations.',
        );
        return;
      }
      animation = animations[0];
    }

    _controller.animationState.setAnimation(0, animation, true).setTrackTime(0);
  }

  /// The animation names tried, in order, for [SpineSpriteWidget.animation].
  List<String> _animationCandidates() {
    final name = widget.animation;
    final idle = widget.idleAnimation;
    return [
      name,
      'movement/$name',
      'emotes/$name',
      '$name-front',
      'movement/$name-front',
      if (idle != null && idle != name) idle,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return spine.SpineWidget.fromAsset(
      widget.atlasAsset,
      widget.skeletonAsset,
      _controller,
      bundle: widget.bundle,
      fit: widget.fit,
      alignment: widget.alignment,
      // Size bounds to the skins this sprite may actually show so partial
      // skins do not inherit the whole skeleton's bounding box.
      boundsProvider: spine.SkinAndAnimationBounds(
        skins: [
          if (widget.skin != null) widget.skin!,
          if (widget.defaultSkin != null) widget.defaultSkin!,
        ],
      ),
    );
  }
}
