# `fiestavn`

FiestaVN's standalone Dart/Flutter Melos monorepo implementing a RenPy Visual Novel engine in Dart for Flutter.

## Structure

```
fiestavn/                     # FiestaVN Melos monorepo with only Dart and Flutter apps.
+-- melos.yaml                # Melos config specific to Dart/Flutter codebase.
+-- packages/
|   +-- renpy_parser/         # RenPy script parser in Dart.
|   +-- renpy_core/           # Core engine logic in Dart.
|   +-- renpy_writer/         # .rpy emitter, .fly codec, migration fidelity, .fly.zip.
+-- apps/
|   +-- fiestavn.com/         # Static landing page for the FiestaVN project; serves the editor at /edit/.
|   +-- renfly.org/           # Static product site for RenFly; serves the player at /play/.
|   +-- renfly_editor/        # RenFly Editor Flutter application (write, preview, package).
|   +-- renfly_player/        # RenFly player Flutter application.
    +-- renspine/             # Example Flutter application with Spine asset integration.
```

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Dart SDK](https://dart.dev/get-dart)
- [Melos](https://melos.invertase.dev/getting-started)

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
