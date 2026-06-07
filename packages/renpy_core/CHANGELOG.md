## 0.0.2 - 2026-06-08

Runtime for executing Ren'Py scripts parsed by `renpy_parser`.

- `RenPyRunner`: callback-based step execution of `RenPyScript`; drives
  dialogue, menus, images, and transitions through plain Dart callbacks
- `RenPyPythonEvaluator`: Python-subset evaluator covering classes,
  inheritance, decorators, lambdas, comprehensions, augmented assignment,
  `raise`, and common builtins
- `RenPyPythonScope` interface with `store`, `persistent.*`, `config.*`, and
  `gui.*` namespace support
- Screen-language runtime: evaluates `screen` trees and fires
  `RenPyScreenAction` callbacks
- ATL skeleton, audio events, image/layered-image/transition resolvers,
  styled-text parser, `.rpa` archive reader
- Init-phase: `init python:` blocks and `define` statements run in
  priority/source order before gameplay, matching Ren'Py semantics
- Validated against the open-source game corpus shipped with Ren'Py
- Re-exports `renpy_parser` so callers need only `package:renpy_core/renpy_core.dart`

## 0.0.1

- Initial version.
- **FEAT**: renpy_parser tests and examples.
