import 'package:flutter/widgets.dart';
import 'package:spine_flutter/spine_flutter.dart' as spine;

/// A RenPy image name tied to a single Spine character such as
/// "erikari-angry.spine".
class SpineSprite extends StatefulWidget {
  const SpineSprite({
    super.key,
    required this.imageName,
    required this.atLeft,
  });

  final String imageName; // e.g. "erikari-angry.spine".
  final bool atLeft; // Simple L/R positioning.

  @override
  State<SpineSprite> createState() => _SpineSpriteState();
}

class _SpineSpriteState extends State<SpineSprite> {
  late final spine.SpineWidgetController _ctrl;
  static const _atlas = 'assets/chibi-stickers/export/chibi-stickers.atlas';
  static const _skel = 'assets/chibi-stickers/export/chibi-stickers-pro.skel';

  @override
  void initState() {
    super.initState();

    _ctrl = spine.SpineWidgetController(onInitialized: (_) {
      try {
        print('SpineSprite: Initializing ${widget.imageName} at ${widget.atLeft ? "left" : "right"}');

        // Parse "<skin>-<animation>.spine".
        final file = widget.imageName.replaceFirst('.spine', '');
        final lastDash = file.lastIndexOf('-');

        String skinName, animName;
        if (lastDash == -1) {
          skinName = 'spineboy';
          animName = 'movement/idle-front';
        } else {
          // Split on the last dash to handle paths like "erikari-movement/idle-front".
          final beforeDash = file.substring(0, lastDash);
          final afterDash = file.substring(lastDash + 1);

          // Check if this looks like a path (contains /).
          if (beforeDash.contains('/')) {
            // This means we have something like "erikari-movement/idle-front".
            // We need to find the skin name differently.
            final parts = file.split('-');
            skinName = parts[0]; // First part should be skin.
            animName = parts.sublist(1).join('-'); // Rest is animation.
          } else {
            skinName = beforeDash;
            animName = afterDash;
          }
        }

        print('SpineSprite: Parsed - skin: $skinName, animation: $animName');

        final skeleton = _ctrl.drawable.skeleton;
        final skeletonData = skeleton.getData();

        // Debug: Print available skins.
        final skins = skeletonData?.getSkins();
        print('Available skins: ${skins?.map((s) => s.getName()).toList()}');

        // Find the skin.
        final skinObj = skeletonData?.findSkin(skinName) ??
            skeletonData?.getDefaultSkin();

        if (skinObj != null) {
          print('Setting skin: ${skinObj.getName()}');
          skeleton.setSkin(skinObj);
          skeleton.setSlotsToSetupPose();
        } else {
          print('ERROR: Could not find skin: $skinName, using default');
          final defaultSkin = skeletonData?.getDefaultSkin();
          if (defaultSkin != null) {
            skeleton.setSkin(defaultSkin);
            skeleton.setSlotsToSetupPose();
          }
        }

        // Debug: Print available animations.
        final animations = _ctrl.animationState.getData().getSkeletonData().getAnimations();
        print('Available animations: ${animations.map((a) => a.getName()).toList()}');

        // Try to set the animation with various fallbacks.
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
            final trackEntry = _ctrl.animationState.setAnimationByName(0, tryAnim, true);
            trackEntry.setTrackTime(0);
            print('Successfully set animation: $tryAnim');
            animationSet = true;
            break;
          } catch (e) {
            print('Failed to set animation $tryAnim: $e');
          }
        }

        if (!animationSet) {
          print('Could not set any animation, trying first available animation');
          if (animations.isNotEmpty) {
            try {
              final firstAnim = animations.first.getName();
              final trackEntry = _ctrl.animationState.setAnimationByName(0, firstAnim, true);
              trackEntry.setTrackTime(0);
              print('Set first available animation: $firstAnim');
            } catch (e) {
              print('Even first animation failed: $e');
            }
          }
        }
      } catch (e) {
        print('SpineSprite initialization error: $e');
      }
    });
  }

  @override
  void dispose() {
    // Note: Don't dispose _ctrl here as it might be managed elsewhere.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('Building SpineSprite: ${widget.imageName} at ${widget.atLeft ? "left" : "right"}');

    return Positioned(
      left: widget.atLeft ? 50 : null,
      right: widget.atLeft ? null : 50,
      bottom: 0,
      child: Container(
        width: 200,
        height: 300,
        // // Add a colored border for debugging positioning.
        // decoration: BoxDecoration(
        //   border: Border.all(
        //       color: widget.atLeft ? const Color(0xFF00FF00) : const Color(0xFF0000FF),
        //       width: 2
        //   ),
        // ),
        child: spine.SpineWidget.fromAsset(
          _atlas,
          _skel,
          _ctrl,
          // Use broader bounds to ensure nothing is clipped
          boundsProvider: spine.SkinAndAnimationBounds(
              skins: const ['erikari', 'harri']
          ),
        ),
      ),
    );
  }
}