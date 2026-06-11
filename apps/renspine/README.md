# `renspine`

RenSpine = RenFly + Spine: a showcase app that runs a Ren'Py script through
`renpy_core`/`renpy_flutter` and renders its characters as
[Spine](https://esotericsoftware.com/) skeletal animations via the
[`renpy_spine`](../../packages/renpy_spine) package, while backgrounds and
regular images keep rendering through the default image layer.

## How characters are declared

Each Spine-backed character is declared once in `lib/main.dart` as a
`SpineCharacter` and the list is handed to the player:

```dart
const kSpineCharacters = [
  SpineCharacter(
    tag: 'erikari',
    atlasAsset: 'assets/chibi-stickers/export/chibi-stickers.atlas',
    skeletonAsset: 'assets/chibi-stickers/export/chibi-stickers-pro.skel',
    defaultSkin: 'erikari',
    idleAnimation: 'movement/idle-front',
  ),
  // ...
];

RenPyAssetPlayer(
  scriptAsset: assetPath,
  imageLayerBuilder: spineImageLayerBuilder(characters: kSpineCharacters),
);
```

Both demo characters (`erikari`, `harri`) are skins of the shared
`chibi-stickers` skeleton.

## The image-name convention

Ren'Py images whose asset paths end in `.spine` are routed to Spine when their
tag matches a declared character:

```renpy
init:
    image erikari idle  = Image("erikari-movement/idle-front.spine")
    image erikari angry = Image("erikari-emotes/angry.spine")

label start:
    scene bg whitehouse          # regular image: default layer
    show erikari idle at left    # Spine: skin "erikari", anim "movement/idle-front"
    show erikari angry at left   # same tag: animation swap without reloading
```

- `erikari-movement/idle-front.spine` → skin `erikari`, animation
  `movement/idle-front` (a dashed parent directory is `<skin>-<group>`).
- `erikari-angry.spine` → skin `erikari`, animation `angry`.
- `wave.spine` → no skin; the character's `defaultSkin` is used.

See [`packages/renpy_spine`](../../packages/renpy_spine) for the full rules
(`SpineImageName.tryParse`) and the layer API.

## Structure

- `lib/main.dart` - app entry point, the `SpineCharacter` declarations, and
  the game launcher/screen.
- `assets/games/1/` - the reference Ren'Py script.
- `assets/chibi-stickers/export/` - the Spine atlas, skeleton, and texture.

## Running

```bash
flutter pub get
flutter run
```

Pick "Reference Game 1" from the launcher to start the demo.
