# renpy_flutter example

A minimal example of the [`renpy_flutter`](../) package.

It plays a tiny bundled Ren'Py script out of the box, and lets you **open a real
Ren'Py game folder** (a directory containing a `game/` subfolder with loose
`.rpy` files or an `.rpa` archive) to run actual "from the wild" games through
the engine.

```sh
cd packages/renpy_flutter/example
flutter run            # desktop
flutter run -d chrome  # web
```

This example is intentionally small and unopinionated - it shows the package's
two entry-point widgets, `RenPyAssetPlayer` (bundled asset script) and
`RenPyProjectPlayer` (a loaded `RenPyGameProject`). For a fuller, styled,
end-user-facing player built on the same package, see the **RenFly** app in
[`apps/renfly`](../../../apps/renfly).

> Other platform folders (`android/`, `ios/`, `macos/`, etc.) aren't checked in;
> run `flutter create .` here to generate them if you need them.
