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
