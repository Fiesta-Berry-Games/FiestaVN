import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:renfly_editor/renfly_editor.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'package:renpy_spine/renpy_spine.dart';

/// The Spine characters bundled with the editor: two skins of the shared
/// chibi-stickers skeleton (the same skeleton apps/renspine stages), copied
/// into this app's assets/.
const List<SpineCharacter> kSpineCharacters = [
  SpineCharacter(
    tag: 'erikari',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'erikari',
    idleAnimation: 'movement/idle-front',
  ),
  SpineCharacter(
    tag: 'harri',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'harri',
    idleAnimation: 'movement/idle-front',
  ),
];

/// One animation the bundled skeleton supports, as a short gallery label plus
/// the full Spine animation name.
class SpineAnimationOption {
  const SpineAnimationOption(this.label, this.animation);

  /// Short gallery label, e.g. `wave`.
  final String label;

  /// The full animation name in the skeleton, e.g. `emotes/wave`.
  final String animation;
}

/// The chibi-stickers animations the gallery offers. Every character shares
/// the one skeleton, so the catalog applies to each configured skin.
const List<SpineAnimationOption> kSpineAnimations = [
  SpineAnimationOption('idle', 'movement/idle-front'),
  SpineAnimationOption('wave', 'emotes/wave'),
  SpineAnimationOption('excited', 'emotes/excited'),
  SpineAnimationOption('laugh', 'emotes/laugh'),
  SpineAnimationOption('idea', 'emotes/idea'),
  SpineAnimationOption('hooray', 'emotes/hooray'),
  SpineAnimationOption('thinking', 'emotes/thinking'),
  SpineAnimationOption('sweat', 'emotes/sweat'),
  SpineAnimationOption('love', 'emotes/love'),
  SpineAnimationOption('scared', 'emotes/scared'),
];

/// The `show` statement a gallery tile inserts for [character] playing
/// [option]: `show <tag> <skin>-<animation>.spine` per the renpy_spine
/// naming convention (`erikari-emotes/wave.spine` -> skin `erikari`,
/// animation `emotes/wave`).
String spineShowStatement(
  SpineCharacter character,
  SpineAnimationOption option,
) {
  return 'show ${character.tag} '
      '${character.effectiveDefaultSkin}-${option.animation}.spine';
}

/// The virtual `.spine` asset paths the preview can resolve, fed to
/// `EditorScreen.extraPreviewAssets` so the player does not flag Spine shows
/// as unresolved. Covers both spellings the image resolver produces:
/// - `game/<skin>-<animation>.spine` from `image x = Image("...")`
///   definitions (the demo script's style), and
/// - `game/<tag> <skin>-<animation>.spine` from raw gallery insertions
///   (`show erikari erikari-emotes/wave.spine`).
Set<String> spinePreviewAssets({String gameRoot = 'game'}) {
  return {
    for (final character in kSpineCharacters)
      for (final option in kSpineAnimations) ...{
        '$gameRoot/${character.effectiveDefaultSkin}-'
            '${option.animation}.spine',
        '$gameRoot/${character.tag} ${character.effectiveDefaultSkin}-'
            '${option.animation}.spine',
      },
  };
}

/// The extra entries this app appends to the editor's "Examples ▾" menu.
final List<EditorExample> renSpineEditorExamples = [
  EditorExample(
    'spine-demo',
    'Fiesta rehearsal (Spine two-character demo)',
    () => rootBundle.loadString('assets/examples/spine_demo.rpy', cache: false),
  ),
];

/// The default preview image layer: renpy_spine's routing layer over a
/// session-asset-aware underlay, exactly like apps/renspine wires
/// `RenPyAssetPlayer.imageLayerBuilder`. `.spine` shows whose tag matches a
/// configured character become live Spine sprites; everything else renders
/// through the regular [RenPyImageLayer].
Widget spinePreviewImageLayer(
  BuildContext context,
  RenPyFlutterController controller,
  RenPyScreenSize screenSize,
  ImageProvider<Object> Function(String assetPath) imageProvider,
) {
  return spineImageLayerBuilder(
    characters: kSpineCharacters,
    fallback:
        (context, controller) => spineSuppressingImageLayer(
          context,
          controller,
          screenSize,
          imageProvider,
        ),
  )(context, controller);
}

/// The non-Spine underlay alone: the editor's regular image layer, with
/// `.spine` asset paths swallowed (substituted with a transparent pixel) so
/// it neither errors on nor draws placeholders for Spine-routed shows.
///
/// Used as [spinePreviewImageLayer]'s fallback, and injected directly by
/// widget tests: it never instantiates a Spine widget, so no spine_flutter
/// native runtime is needed.
Widget spineSuppressingImageLayer(
  BuildContext context,
  RenPyFlutterController controller,
  RenPyScreenSize screenSize,
  ImageProvider<Object> Function(String assetPath) imageProvider,
) {
  return RenPyImageLayer(
    controller: controller,
    screenSize: screenSize,
    atlResolver: controller.resolveAtl,
    imageProvider:
        (assetPath) =>
            assetPath.toLowerCase().endsWith('.spine')
                ? MemoryImage(_transparentPixelPng)
                : imageProvider(assetPath),
  );
}

/// A 1x1 fully transparent RGBA PNG (same stand-in renpy_spine's default
/// underlay uses for `.spine` paths).
final Uint8List _transparentPixelPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00, //
  0x0b, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x60, 0x00, 0x02, 0x00, //
  0x00, 0x05, 0x00, 0x01, 0x7a, 0x5e, 0xab, 0x3f, 0x00, 0x00, 0x00, 0x00, //
  0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);
