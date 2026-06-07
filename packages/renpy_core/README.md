# renpy_core

A Dart library that executes parsed Ren'Py scripts: a Python-subset evaluator,
a script runner with callback-based I/O, and a screen-language interpreter.
Depends on [`renpy_parser`](https://pub.dev/packages/renpy_parser) for the AST.
This is an early-stage package (0.0.x); the API is broadly stable but may have
breaking changes before 1.0.

## Features

- `RenPyRunner` - step-by-step execution of a `RenPyScript`; drives dialogue,
  menus, images, and transitions through plain Dart callbacks, so it integrates
  with any UI framework
- `RenPyPythonEvaluator` - Python-subset evaluator covering variables, classes,
  inheritance, decorators, lambdas, list/dict/set comprehensions, augmented
  assignment, bare `raise`, and common builtins (`len`, `range`, `sorted`,
  `isinstance`, `hasattr`, `getattr`, `setattr`, `zip`, `enumerate`, etc.)
- Scoped variable storage via the `RenPyPythonScope` interface: `store`,
  `persistent.*`, `config.*`, and `gui.*` namespaces
- Screen-language runtime: evaluates `screen` displayable trees and fires
  `RenPyScreenAction` callbacks (`Jump`, `Call`, `SetVariable`, `ToggleVariable`,
  `Function`, `SetField`, `ToggleField`, and more)
- ATL (animation/transition language) skeleton, audio events, image resolver,
  layered-image resolver, transition resolver, styled-text parser
- `.rpa` archive reader (`RenPyRpaArchive`) for Ren'Py asset bundles
- Init-phase execution: `init python:` blocks and `define` statements run in
  priority/source order before gameplay begins, matching Ren'Py semantics
- Validated against the open-source game corpus shipped with Ren'Py

## Installation

```yaml
dependencies:
  renpy_core: ^0.0.2
```

## Usage

```dart
import 'dart:io';
import 'package:renpy_core/renpy_core.dart';

Future<void> main() async {
  // 1. Parse.
  final source = await File('script.rpy').readAsString();
  final parseResult = RenPyParser().parse(source, 'script.rpy');

  // 2. Create runner and wire callbacks.
  final runner = RenPyRunner(parseResult.script);

  runner.onDialogue = (character, text) {
    print('${character ?? "narrator"}: $text');
  };

  runner.onImage = (scene, show, hide) {
    if (scene != null) print('[scene] $scene');
    if (show  != null) print('[show]  $show');
    if (hide  != null) print('[hide]  $hide');
  };

  runner.onMenu = (choices, onChoice, caption) {
    for (var i = 0; i < choices.length; i++) {
      print('  ${i + 1}. ${choices[i]}');
    }
    onChoice(0); // always pick first choice
  };

  // 3. Jump to the entry point and run.
  if (parseResult.script.findLabel('start') != null) {
    runner.jumpToLabel('start');
  }
  runner.run();

  // 4. Drive the execution loop.
  while (runner.state != RenPyRunnerState.complete &&
         runner.state != RenPyRunnerState.error) {
    if (runner.state == RenPyRunnerState.waitingForInput) {
      runner.continueExecution();
    }
  }

  if (runner.state == RenPyRunnerState.error) {
    print('Error: ${runner.errorMessage}');
  }
}
```

Key `RenPyRunner` members:

| Member | Description |
|---|---|
| `RenPyRunner(script)` | Create a runner from a parsed `RenPyScript` |
| `run()` | Start (or restart) execution from the current position |
| `jumpToLabel(label)` | Set the execution pointer to a named label |
| `continueExecution()` | Advance past a `waitingForInput` pause |
| `state` | `RenPyRunnerState` enum: `ready`, `running`, `waitingForInput`, `complete`, `error` |
| `errorMessage` | Non-null when `state == error` |
| `onDialogue` | `void Function(String? character, String text)` |
| `onImage` | `void Function(String? scene, String? show, String? hide)` |
| `onMenu` | `void Function(List<String> choices, void Function(int) onChoice, String? caption)` |

## Repository

<https://git.cypherstack.com/FiestaBerry/fiestavn>

## License

MIT
