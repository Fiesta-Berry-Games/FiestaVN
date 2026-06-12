# renpy_flutter

Flutter widgets and UI adapters for running Ren'Py-compatible visual novels.
Built on top of [`renpy_core`](https://pub.dev/packages/renpy_core) and
[`renpy_parser`](https://pub.dev/packages/renpy_parser).

> **Early release (0.0.x):** the package is functional for typical ADV-style
> scripts. Some advanced transitions and ATL animations render best-effort and
> will improve in future releases.

---

## What it does

`renpy_flutter` turns the script runner output from `renpy_core` into visible,
interactive Flutter UI:

- **Dialogue window** - typewriter reveal, character name, inline `{tag}` text
  styling, variable interpolation, and a scrollable backlog overlay.
- **Choice menus** - rendered as an overlay button row; auto-forward and skip
  modes stop at menus so the player can choose.
- **Image layer** (`RenPyImageLayer`) - scene and sprite compositing with
  z-order, layeredimage composites, and ATL transform animation.
- **Audio layer** (`RenPyAudioLayer`) - multi-channel play/stop/queue with
  fade-in/fade-out and per-mixer volume/mute via `sound_dart`.
- **Screen-language displayables** (`RenPyScreenLayer`) - renders `show screen`
  / `call screen` output including `text`, `imagebutton`, `textbutton`, and
  common layout containers.
- **Transitions** - dissolve, fade, and move families are supported; complex
  composites are best-effort.
- **Save / load / rollback** - snapshot-based with optional slot browser UI.
- **Game menu** - preferences (text speed, auto delay, mixer volumes), save/load
  browser, and restart.

---

## Installation

```yaml
dependencies:
  renpy_flutter: ^0.0.1
```

---

## Minimal usage

The easiest path is `RenPyAssetPlayer`, which loads a bundled `.rpy` asset,
manages the controller lifecycle, and renders the full player surface:

```dart
import 'package:flutter/material.dart';
import 'package:renpy_flutter/renpy_flutter.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: RenPyAssetPlayer(
          scriptAsset: 'assets/game/script.rpy',
        ),
      ),
    );
  }
}
```

Declare the asset in your app's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/game/script.rpy
```

---

## Manual controller wiring

For more control, construct a `RenPyFlutterController` yourself and wire it to
`RenPyPlayer`:

```dart
final controller = RenPyFlutterController(
  onComplete: () => debugPrint('Script finished'),
);

// Load a script string at any time:
controller.load(scriptSource, filename: 'myscript.rpy');

// Display it:
RenPyPlayer(
  controller: controller,
  showRestartButton: false,
)
```

`RenPyFlutterController` is a `ValueNotifier<RenPyGameStatus>`. You can listen
to it directly to build a fully custom UI: the emitted subtypes are
`RenPyDialogue`, `RenPyMenu`, `RenPyPause`, `RenPyImageChange`,
`RenPyAudioChange`, `RenPyTransitionChange`, `RenPyVisualRestore`,
`RenPyComplete`, and `RenPyError`.

---

## Key public API

| Symbol | Description |
|---|---|
| `RenPyFlutterController` | Drives the runner; `ValueNotifier<RenPyGameStatus>` |
| `RenPyPlayer` | Full-surface widget (requires an existing controller) |
| `RenPyAssetPlayer` | Self-contained widget loading a Flutter asset |
| `RenPyProjectPlayer` | Self-contained widget for a `RenPyGameProject` |
| `RenPyImageLayer` | Scene/sprite compositor |
| `RenPyAudioLayer` | Multi-channel audio playback |
| `RenPyScreenLayer` | Screen-language displayable renderer |
| `RenPyDialogueView` | Standalone dialogue chrome |
| `RenPyMenuSelector` | Standalone choice-menu overlay |
| `RenPyBacklogView` | Scrollable dialogue history overlay |
| `RenPyAudioPlayback` | Interface for custom audio backends |
| `RenPyBytesAudioPlayback` | In-memory audio backend (for project files) |
| `RenPyNoOpAudioPlayback` | Silent backend for tests |
| `RenPySharedPreferencesStore` | `shared_preferences`-backed persistence |

---

## Example

See the [`example/`](example/) directory for a minimal runnable Flutter app.

---

## Repository

<https://git.cypherstack.com/FiestaBerry/fiestavn>

MIT License - Copyright 2025-2026 Fiesta Berry Games
