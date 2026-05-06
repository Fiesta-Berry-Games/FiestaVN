import 'package:flutter/widgets.dart';
import 'package:spine_flutter/spine_flutter.dart' as spine;

/// A RenPy image name tied to a single Spine character such as
/// "erikari-angry.spine".
class SpineSprite extends StatefulWidget {
  const SpineSprite({super.key, required this.imageName, required this.atLeft});

  final String imageName; // e.g. "erikari-angry.spine".
  final bool atLeft; // Simple L/R positioning.

  @override
  State<SpineSprite> createState() => _SpineSpriteState();
}

class _SpineSpriteState extends State<SpineSprite> {
  late final spine.SpineWidgetController _ctrl;
  static const _atlas = 'assets/chibi-stickers/export/chibi-stickers.atlas';
  static const _skel = 'assets/chibi-stickers/export/chibi-stickers-pro.skel';

  String? _currentSkinName;

  @override
  void initState() {
    super.initState();

    _ctrl = spine.SpineWidgetController(
      onInitialized: (_) {
        _setImageAndAnimation(widget.imageName);
      },
    );
  }

  @override
  void didUpdateWidget(SpineSprite oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Only update animation if the imageName changed.
    if (widget.imageName != oldWidget.imageName) {
      _setImageAndAnimation(widget.imageName);
    }
  }

  // Default skin used when an image name carries no skin prefix.
  static const _fallbackSkin = 'spineboy';

  /// Parses `"<skin>-<animation>.spine"` into (skin, animation).
  static ({String skin, String anim}) _parse(String imageName) {
    final file = imageName.replaceFirst('.spine', '');
    final lastDash = file.lastIndexOf('-');

    if (lastDash == -1) {
      return (skin: _fallbackSkin, anim: 'movement/idle-front');
    }

    // Split on the last dash to handle paths like "erikari-movement/idle-front".
    final beforeDash = file.substring(0, lastDash);
    final afterDash = file.substring(lastDash + 1);

    // Check if this looks like a path (contains /).
    if (beforeDash.contains('/')) {
      // This means we have something like "erikari-movement/idle-front".
      // We need to find the skin name differently.
      final parts = file.split('-');
      return (skin: parts[0], anim: parts.sublist(1).join('-'));
    }
    return (skin: beforeDash, anim: afterDash);
  }

  void _setImageAndAnimation(String imageName) {
    try {
      debugPrint(
        'SpineSprite: Setting $imageName at ${widget.atLeft ? "left" : "right"}',
      );

      final parsed = _parse(imageName);
      final skinName = parsed.skin;
      final animName = parsed.anim;

      debugPrint('SpineSprite: Parsed - skin: $skinName, animation: $animName');

      final skeleton = _ctrl.drawable.skeleton;
      final skeletonData = skeleton.getData();

      // Only change skin if it's different from current.
      if (_currentSkinName != skinName) {
        // Find the skin.
        final skinObj =
            skeletonData?.findSkin(skinName) ?? skeletonData?.getDefaultSkin();

        if (skinObj != null) {
          debugPrint('Setting skin: ${skinObj.getName()}');
          skeleton.setSkin(skinObj);
          skeleton.setSlotsToSetupPose();
          _currentSkinName = skinName;
        } else {
          debugPrint('ERROR: Could not find skin: $skinName, using default');
          final defaultSkin = skeletonData?.getDefaultSkin();
          if (defaultSkin != null) {
            skeleton.setSkin(defaultSkin);
            skeleton.setSlotsToSetupPose();
            _currentSkinName = defaultSkin.getName();
          }
        }
      }

      // Always try to set the animation (this is what changes frequently).
      bool animationSet = false;
      final animationsToTry = [
        animName,
        'movement/$animName',
        'emotes/$animName',
        '$animName-front',
        'movement/$animName-front',
        'movement/idle-front',
        'idle',
      ];

      for (final tryAnim in animationsToTry) {
        try {
          // Use blend time for smooth transition between animations.
          _ctrl.animationState.getData().setDefaultMix(0.1);
          final trackEntry = _ctrl.animationState.setAnimationByName(
            0,
            tryAnim,
            true,
          );
          trackEntry.setTrackTime(0);
          debugPrint('Successfully set animation: $tryAnim');
          animationSet = true;
          break;
        } catch (e) {
          // Silently try next animation
        }
      }

      if (!animationSet) {
        debugPrint(
          'Could not set any animation, trying first available animation',
        );
        final animations =
            _ctrl.animationState.getData().getSkeletonData().getAnimations();
        if (animations.isNotEmpty) {
          try {
            final firstAnim = animations.first.getName();
            _ctrl.animationState.getData().setDefaultMix(0.1);
            final trackEntry = _ctrl.animationState.setAnimationByName(
              0,
              firstAnim,
              true,
            );
            trackEntry.setTrackTime(0);
            debugPrint('Set first available animation: $firstAnim');
          } catch (e) {
            debugPrint('Even first animation failed: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('SpineSprite animation change error: $e');
    }
  }

  @override
  void dispose() {
    // Note: Don't dispose _ctrl here as it might be managed elsewhere.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'Building SpineSprite: ${widget.imageName} at ${widget.atLeft ? "left" : "right"}',
    );

    return Positioned(
      left: widget.atLeft ? 50 : null,
      right: widget.atLeft ? null : 50,
      bottom: 0,
      child: SizedBox(
        width: 200,
        height: 300,
        child: spine.SpineWidget.fromAsset(
          _atlas,
          _skel,
          _ctrl,
          // Size bounds to whatever skin this sprite actually shows, falling
          // back to the default skin so the fallback sprite is sized correctly.
          boundsProvider: spine.SkinAndAnimationBounds(
            skins: [_parse(widget.imageName).skin, _fallbackSkin],
          ),
        ),
      ),
    );
  }
}
