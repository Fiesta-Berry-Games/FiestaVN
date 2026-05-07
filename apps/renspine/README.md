# `renspine`

A Spine 2D skeletal-animation demo for the FiestaVN stack. It runs a Ren'Py
script through `renpy_core`/`renpy_flutter` and renders the characters as
[Spine](https://esotericsoftware.com/) skeletons instead of flat images.

Ren'Py `show` statements such as `show erikari idle` are mapped to a Spine skin
(the character name) and an animation, so each character is drawn from the
shared `chibi-stickers` skeleton.

## Structure

- `lib/main.dart` - app entry point and the game launcher/screen.
- `lib/widgets/spine_layer.dart` - listens to the Ren'Py controller and turns
  `scene`/`show`/`hide` events into Spine sprites.
- `lib/widgets/spine_sprite.dart` - a single Spine character, wiring an image
  name to a skin and animation.
- `assets/games/1/` - the reference Ren'Py script.
- `assets/chibi-stickers/export/` - the Spine atlas, skeleton, and texture.

## Running

```bash
flutter pub get
flutter run
```

Pick "Reference Game 1" from the launcher to start the demo.
