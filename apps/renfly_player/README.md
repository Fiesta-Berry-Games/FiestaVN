# RenFly

A Flutter player for Ren'Py games. RenFly is the player app of the FiestaVN
monorepo and drives the `renpy_parser`, `renpy_core`, and `renpy_flutter`
packages to parse and play Ren'Py scripts.

It ships a small launcher with bundled reference games and can also open an
external Ren'Py project folder from disk (desktop) or an uploaded directory
(web).

## Running

From this directory:

```bash
flutter pub get
flutter run
```

Pick a target device with `-d`, for example `flutter run -d linux`,
`flutter run -d chrome`, or a connected mobile device.

## Tests

```bash
flutter test
```

