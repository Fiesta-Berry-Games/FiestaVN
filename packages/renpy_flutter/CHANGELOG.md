## 0.0.1 - 2026-06-08

Initial release.

- `RenPyFlutterController` - `ValueNotifier`-based controller that drives
  `RenPyRunner` and exposes `RenPyGameStatus` variants (`RenPyDialogue`,
  `RenPyMenu`, `RenPyPause`, `RenPyImageChange`, `RenPyAudioChange`,
  `RenPyTransitionChange`, `RenPyVisualRestore`, `RenPyComplete`, `RenPyError`).
- `RenPyPlayer` - full-surface Flutter widget rendering dialogue, choice menus,
  image layer, audio layer, backlog overlay, game menu, and pacing controls (skip
  / auto-forward).
- `RenPyAssetPlayer` - convenience widget that loads a bundled `.rpy` asset and
  manages the controller lifecycle.
- `RenPyProjectPlayer` - widget for externally loaded `RenPyGameProject` folders,
  including font registration and in-memory audio via `RenPyBytesAudioPlayback`.
- `RenPyImageLayer` - sprite/scene compositor with ATL transform support.
- `RenPyAudioLayer` + `RenPyAudioPlayback` - multi-channel audio with fade in/out,
  queue, and mixer volume/mute; production backend via `audioplayers`.
- `RenPyScreenLayer` - renders Ren'Py screen-language displayables.
- `RenPyDialogueView`, `RenPyMenuSelector`, `RenPyBacklogView`,
  `RenPyPauseView` - individual chrome widgets.
- `RenPySharedPreferencesStore` - `shared_preferences`-backed preference and
  snapshot persistence.
- Rollback, save/load snapshot, and save-slot browser support.
