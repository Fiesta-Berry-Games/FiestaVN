# The .fly.zip Archive Format (version 1)

A `.fly.zip` is a standard ZIP archive of a full RenFly game directory,
intended for one-file distribution of a story plus its assets. The same
file is loadable by both the RenFly player and the editor.

File extension: **`.fly.zip`**. MIME type: **`application/zip`**.
Text entries (the script) are UTF-8.

## Layout

The archive mirrors a classic Ren'Py project:

```
game/script.fly        (or game/script.rpy — exactly one script)
game/images/...        assets, any depth
game/audio/...         etc.
```

- The script lives in the `game/` tree and is any entry matching
  `game/**.fly` or `game/**.rpy`.
- Assets keep their project-relative paths under `game/`, at any depth.
- Entries outside `game/` (e.g. `README.md`) are preserved verbatim but
  ignored for loading.
- Paths use forward slashes; backslashes are normalized on read.

## The single-script rule

Exactly one script must be loadable:

1. Collect every `game/**.fly` and `game/**.rpy` entry.
2. **`.fly` wins.** If any `.fly` script is present, all `.rpy` scripts are
   ignored for loading (but kept as plain file entries), and each one is
   recorded as a note, e.g.
   `ignored game/script.rpy because game/script.fly is present`.
3. If multiple candidates of the winning kind exist, `game/script.<ext>`
   is preferred; the others are noted as ignored. If none of them is
   `game/script.<ext>`, the archive is rejected as ambiguous.
4. If no candidate exists at all, the archive is rejected.

A stored `.fly` script is the strictly-typed JSON document described in
`doc/fly_format.md`; a stored `.rpy` script is plain Ren'Py text.

## Security constraints (zip-slip)

Readers and writers MUST reject any entry whose path:

- is absolute (`/etc/passwd`, `C:\evil`), or
- contains a `..` segment (`../evil`, `game/../../evil`).

This prevents a hostile archive from escaping its extraction directory.
Duplicate entry paths are also rejected on write.

## Loading (player and editor)

```dart
final archive = FlyArchive.decode(zipBytes); // validates everything above
final rpyText = archive.scriptAsRpy();       // .fly is converted via
                                             // FlyCodec + RenPyEmitter;
                                             // .rpy is returned verbatim
```

The resulting `.rpy` text and `archive.files` (asset paths and bytes) feed
the existing `RenPyGameProject.fromFiles` flow unchanged: the player runs
the project, the editor opens it for editing. `archive.notes` carries
human-readable remarks (ignored scripts) worth surfacing in tooling.

## Writing

- `FlyArchive.encode(files)` builds the ZIP from explicit entries and
  enforces path safety and the single-script rule.
- `FlyArchive.fromScript(scriptSource: rpyText, storeAsFly: true,
  assets: [...])` is the convenience path: it parses the `.rpy` text and
  stores it as `game/script.fly` (set `storeAsFly: false` to store the
  text verbatim as `game/script.rpy`). Asset paths are relative to `game/`
  (e.g. `images/bg.png`); paths already starting with `game/` are kept.
