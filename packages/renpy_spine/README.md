# renpy_spine

Spine character displayables for the FiestaVN Ren'Py engine: show
[Spine](https://esotericsoftware.com/) skeletal-animated sprites straight from
Ren'Py scripts, while everything else (backgrounds, regular sprites, text
displayables) keeps rendering through the default `renpy_flutter` image layer.

## How it works

1. Declare each Spine-backed character once as a [`SpineCharacter`]: the
   Ren'Py image *tag* plus the `.atlas`/`.skel` (or `.json`) assets that hold
   its skeleton.
2. Define your Ren'Py images with asset paths ending in `.spine` following the
   naming convention below.
3. Pass `spineImageLayerBuilder(characters: [...])` to
   `RenPyPlayer.imageLayerBuilder` (or `RenPyAssetPlayer` /
   `RenPyProjectPlayer`).

```dart
import 'package:renpy_spine/renpy_spine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSpineFlutter(); // re-exported from spine_flutter
  runApp(const MyApp());
}

const characters = [
  SpineCharacter(
    tag: 'erikari',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'erikari',
    idleAnimation: 'movement/idle-front',
  ),
];

RenPyAssetPlayer(
  scriptAsset: 'assets/games/1/game/script.rpy',
  imageLayerBuilder: spineImageLayerBuilder(characters: characters),
);
```

```renpy
init:
    image erikari idle  = Image("erikari-movement/idle-front.spine")
    image erikari angry = Image("erikari-emotes/angry.spine")

label start:
    scene bg whitehouse
    show erikari idle at left
    show erikari angry at left   # same tag: animation swap, no reload
    hide erikari
```

A `show` is rendered as a Spine sprite when **both** hold:

- the resolved asset path ends in `.spine`, and
- the image tag (the first word of the `show` statement) matches a declared
  `SpineCharacter.tag`.

Everything else — `scene bg whitehouse`, regular image sprites, text
displayables — is delegated to the default `RenPyImageLayer` rendered
underneath the Spine overlay, so mixed scripts keep working.

## The `.spine` image-name convention

`SpineImageName.tryParse` maps an asset path ending in `.spine` to a
`(skin, animation)` pair. Only the last two path segments participate; any
leading directories (e.g. a game root like `assets/games/1/game/`) are
ignored.

| Asset path | Skin | Animation |
| --- | --- | --- |
| `erikari-movement/idle-front.spine` | `erikari` | `movement/idle-front` |
| `assets/games/1/game/harri-emotes/wave.spine` | `harri` | `emotes/wave` |
| `erikari-angry.spine` | `erikari` | `angry` |
| `wave.spine` | *(none)* | `wave` |

Rules, in order:

1. The path must end in `.spine` (case-insensitive); otherwise parsing fails.
2. If the parent directory segment contains a `-`, it is split at the **first**
   dash: the part before is the skin, and the part after is joined with the
   file name as `<group>/<file>` to form the animation
   (`erikari-movement/idle-front` → skin `erikari`, animation
   `movement/idle-front`).
3. Otherwise the bare file name is split at its **first** dash into
   `<skin>-<animation>` (`erikari-angry` → skin `erikari`, animation `angry`).
4. A file name without a dash is a bare animation with no skin
   (`wave` → animation `wave`); the layer then falls back to
   `SpineCharacter.defaultSkin`, then to the character tag.

When the parsed skin does not exist in the skeleton, the sprite falls back to
the skeleton's default skin; when the animation is missing, a few conventional
locations (`movement/<name>`, `emotes/<name>`, `<name>-front`, ...) and the
character's `idleAnimation` are tried.

## API

- `SpineCharacter` — declarative per-tag configuration (atlas/skeleton assets,
  default skin, idle animation, scale, animation mix duration).
- `SpineImageName` — the pure-Dart `.spine` path parser described above.
- `spineImageLayerBuilder({characters, fallback})` — builds a
  `RenPyLayerBuilder` for `RenPyPlayer.imageLayerBuilder`; `fallback` replaces
  the default underlying `RenPyImageLayer` when provided.
- `SpineImageLayer` — the layer widget itself, if you need to embed it
  directly.
- `SpineSpriteWidget` — a single skinned/animated Spine character widget that
  swaps skin/animation in place without reloading the skeleton.
- `classifySpineShow(...)` — the routing decision function (also used by the
  layer), handy for tests.

## Testing note

`SpineWidget` requires the spine_flutter native runtime (`initSpineFlutter()`),
which is unavailable in headless widget tests. Routing logic is therefore
exposed as pure functions (`SpineImageName.tryParse`, `classifySpineShow`) so
it can be tested without instantiating any Spine widgets.
