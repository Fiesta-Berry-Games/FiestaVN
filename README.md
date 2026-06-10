# `fiestavn`

FiestaVN's standalone Dart/Flutter Melos monorepo implementing a RenPy Visual Novel engine in Dart for Flutter.

## Structure

```
fiestavn/                     # FiestaVN Melos monorepo with only Dart and Flutter apps.
+-- melos.yaml                # Melos config specific to Dart/Flutter codebase.
+-- packages/
|   +-- renpy_parser/         # RenPy script parser in Dart.
|   +-- renpy_core/           # Core engine logic in Dart.
+-- apps/
|   +-- fiestavn.com/         # Static landing page for the FiestaVN project.
|   +-- renfly.org/           # Static product site for RenFly; serves the player at /play/.
|   +-- renfly_player/        # RenFly player Flutter application.
    +-- renspine/             # Example Flutter application with Spine asset integration.
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Dart SDK](https://dart.dev/get-dart)
- [Melos](https://melos.invertase.dev/getting-started)

#### Linux desktop audio

The RenFly example app uses `audioplayers` for Ren'Py music and sound
playback. On Linux desktop, the `audioplayers_linux` backend requires
GStreamer development packages to be installed before `flutter run -d linux`
can generate native build files:

```bash
sudo apt update
sudo apt install libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
```

Without these packages, CMake may fail while configuring
`audioplayers_linux` with an error such as `gstreamer-1.0` not found. Web
builds do not need these Linux packages because browser audio is provided by
the browser runtime instead of native Linux libraries.

### Setup

1. Initialize the monorepo:
   ```bash
   melos bootstrap
   ```

2. Run tests:
   ```bash
   melos run test
   ```

## Usage

Check out the RenFly player in `apps/renfly_player` to see how to use FiestaVN in a Flutter application.

## License

This project is licensed under the MIT license - see the LICENSE file for details.
