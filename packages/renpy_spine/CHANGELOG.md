## 0.0.1

- Initial release.
- `SpineCharacter` declarative configuration for Spine-backed Ren'Py image
  tags.
- `SpineImageName` parser for the `<skin>-<group>/<animation>.spine` /
  `<skin>-<animation>.spine` / `<animation>.spine` naming convention.
- `spineImageLayerBuilder` / `SpineImageLayer`: an image layer for
  `RenPyPlayer.imageLayerBuilder` that overlays Spine sprites for `.spine`
  shows and delegates everything else to the default `RenPyImageLayer`.
- `SpineSpriteWidget`: a single Spine character widget that applies skin and
  animation changes in place without reloading the skeleton.
