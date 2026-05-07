# RenFly

A Flutter player for Ren'Py games. RenFly is the example app for the FiestaVN
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

## Linux desktop audio

Audio playback uses `audioplayers`, whose Linux backend needs the GStreamer
development packages installed before `flutter run -d linux` can configure the
native build:

```bash
sudo apt update
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

See the monorepo `README.md` ("Linux desktop audio") for details. Web builds
do not need these packages because the browser provides audio.
