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
  static const _skel  = 'assets/chibi-stickers/export/chibi-stickers-pro.skel';

  @override
  void initState() {
    super.initState();

    // Parse "<skin>-<animation>.spine".
    final file = widget.imageName.replaceAll('.spine', '');
    final dash  = file.indexOf('-');
    final skin  = dash == -1 ? 'spineboy' : file.substring(0, dash);
    final anim  = dash == -1 ? 'movement/idle-front' : file.substring(dash + 1);

    _ctrl = spine.SpineWidgetController(onInitialized: (_) {
      // Parse "<skin>-<animation>.spine"
      final file = widget.imageName.replaceFirst('.spine', '');
      final dash = file.indexOf('-');
      final skinName = dash == -1 ? 'spineboy'  : file.substring(0, dash);
      final animName = dash == -1 ? 'movement/idle-front' : file.substring(dash + 1);

      final skeleton = _ctrl.drawable.skeleton;
      final skinObj  = skeleton.getData()?.findSkin(skinName)
          ?? skeleton.getData()?.getDefaultSkin();
      skeleton.setSkin(skinObj!);
      skeleton.setSlotsToSetupPose();

      _ctrl.animationState
          .setAnimationByName(0, animName, true)
          .setTrackTime(0);
    });

  }

  @override
  void dispose() {
    // _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: widget.atLeft ? Alignment.bottomLeft : Alignment.bottomRight,
        child: spine.SpineWidget.fromAsset(
          _atlas,
          _skel,
          _ctrl,
          // Use the animation itself for bounds so nothing is clipped.
          boundsProvider: spine.SkinAndAnimationBounds(skins: const ['spineboy']),
        ),
      );
}
