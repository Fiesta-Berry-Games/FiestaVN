# RenFly Editor

A web-first Ren'Py visual novel editor with live preview, built on the
FiestaVN packages (`renpy_parser`, `renpy_core`, `renpy_flutter`,
`renpy_writer`).

## Features

- **Script editor** - a monospace, dependency-free text editor with a
  line/character count status bar and parse-as-you-type diagnostics
  (~400 ms debounce). Parse errors (with line numbers) and warnings show in
  an issues strip under the editor without disturbing the running preview.
- **Live preview** - press **Run** to (re)load the current script into an
  embedded `RenPyPlayer`. Runtime diagnostics (missing assets, etc.) are
  collected into the issues strip. The preview uses in-memory preference and
  save stores, so editor runs never pollute persisted game saves.
- **Layout** - a draggable splitter between editor and preview on wide
  viewports; below 700 px the panes stack behind an Editor | Preview tab
  switcher.
- **File operations**
  - **New** - confirm-if-dirty, then load the starter template.
  - **Open…** - pick a `.rpy`, `.fly`, or `.txt` file. `.fly` documents are
    decoded with `FlyCodec` and re-emitted as `.rpy` text (the editor's
    source of truth).
  - **Save .fly** - parse the script and download it as `story.fly`. Parse
    failures surface as a SnackBar instead of saving.
  - **Export .rpy** - download the editor text as `script.rpy`.

The starter template is a small self-contained story that previews with zero
assets (only the built-in `black` / `white` / `red` solid-color images).

## Running

```sh
flutter run -d chrome
```

## Building for the web

```sh
flutter build web --base-href /edit/
```

## Tests

```sh
flutter test
```
