## 0.0.3 - 2026-06-11

- New `RenPyCameraStatement`: `camera [layer] [at expr-list] [with expr]`
  parses into structured layer/at/with fields, with an optional trailing `:`
  ATL block captured as raw `body` lines (mirroring `image name:`).
  Previously `camera` lines fell through to `RenPyGenericStatement`.
- New `RenPyTranslateStatement`: `translate <language> <label>:` blocks parse
  their body as ordinary statements; `translate <lang> python:` reconstructs
  its body as a single `RenPyPythonStatement`; `translate <lang> strings:`
  keeps its body verbatim in a `strings` raw-line list. Previously every
  translate block collapsed to `RenPyPassStatement` and its body was
  discarded.

## 0.0.2

- Resolve type-related analyzer warnings (no API changes).

## 0.0.1 - 2026-06-08

First public release. Parses Ren'Py `.rpy` script files into a typed Dart AST.

- Lexer and parser covering the common Ren'Py statement set: labels
  (including parameterized labels), say/dialogue, menus, `if`/`elif`/`else`,
  `jump`/`call`/`return`, `define`/`default`, `image`, `show`/`scene`/`hide`,
  `play`/`stop`/`queue`, `init`/`init python`, `python:` blocks, ATL
  transforms, NVL mode, and translate blocks
- Full screen-language parser: `screen` statements, displayables, and actions
- Layered-image (`layeredimage`) block support
- Non-fatal parse warnings; parser collects unknown constructs and continues
- `RenPyScript` helpers: `labels`, `characters`, `findStatements`, `findLabel`
- Pure Dart; no Flutter dependency
