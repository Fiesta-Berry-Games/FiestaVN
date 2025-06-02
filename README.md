# `fiestavn`

FiestaVN's standalone Dart/Flutter Melos monorepo implementing a RenPy Visual Novel engine in Dart for Flutter.

## Structure

```
fiestavn/                     # FiestaVN Melos monorepo with only Dart and Flutter apps.
├── melos.yaml                # Melos config specific to Dart/Flutter codebase.
├── packages/
│   ├── renpy_parser/         # RenPy script parser in Dart.
│   └── renpy_core/           # Core engine logic in Dart.
└── apps/
    └── renfly/               # Example Flutter application.
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

Check out the example project in `apps/renfly` to see how to use FiestaVN in a Flutter application.

## License

This project is licensed under the MIT license - see the LICENSE file for details.
