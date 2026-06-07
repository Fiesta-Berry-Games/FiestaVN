# renpy_parser

A Dart library for parsing [Ren'Py](https://www.renpy.org/) `.rpy` script files
into a typed AST (abstract syntax tree). This is an early-stage package (0.0.x);
the API is broadly stable but may have breaking changes before 1.0.

## Features

- Lexes and parses `.rpy` source into a `RenPyScript` holding a list of typed
  `RenPyStatement` subtypes
- Covers labels (including parameterized labels), say/dialogue, menus,
  `if`/`elif`/`else`, `jump`/`call`/`return`, `define`/`default`, `image`,
  `show`/`scene`/`hide`, `play`/`stop`/`queue`, `init`/`init python`,
  `python:` blocks, ATL transforms, NVL mode, translate blocks, and more
- Full screen-language parser: `screen` statements, displayables, actions
- Layered-image (`layeredimage`) block support
- Non-fatal parse warnings - the parser collects unknown constructs and
  continues rather than aborting on the first error
- No Flutter dependency; works in pure Dart CLI, server, and Flutter contexts

## Installation

```yaml
dependencies:
  renpy_parser: ^0.0.1
```

## Usage

```dart
import 'dart:io';
import 'package:renpy_parser/renpy_parser.dart';

void main() async {
  final source = await File('script.rpy').readAsString();

  final result = RenPyParser().parse(source, 'script.rpy');

  // Non-fatal warnings - unknown constructs the parser skipped over.
  for (final w in result.warnings) {
    print('warning: $w');
  }

  final script = result.script;
  print('Labels    : ${script.labels.keys.join(', ')}');
  print('Characters: ${script.characters.keys.join(', ')}');

  // Walk the top-level statement list.
  for (final stmt in script.statements) {
    if (stmt is RenPySayStatement) {
      print('${stmt.character ?? "narrator"}: ${stmt.text}');
    }
  }

  // Recursive type-safe search helper.
  final images = script.findStatements<RenPyImageStatement>((_) => true);
  for (final img in images) {
    print('image ${img.name} = ${img.expression}');
  }
}
```

`RenPyParseResult` exposes:

- `script` - root `RenPyScript` (a list of `RenPyStatement` subtypes plus
  helpers `labels`, `characters`, `findStatements`, `findLabel`)
- `warnings` - non-fatal parse diagnostics; the parser never silently drops
  content

## Statement types

`RenPyLabelStatement`, `RenPySayStatement`, `RenPyMenuStatement`,
`RenPyIfStatement`, `RenPyJumpStatement`, `RenPyCallStatement`,
`RenPyReturnStatement`, `RenPyDefineStatement`, `RenPyDefaultStatement`,
`RenPyImageStatement`, `RenPyShowStatement`, `RenPySceneStatement`,
`RenPyHideStatement`, `RenPyPythonStatement`, `RenPyInitPythonStatement`,
`RenPyScreenStatement`, `RenPyTransformStatement`, `RenPyStyleStatement`,
`RenPyTranslateStatement`, and more - see
`lib/src/models/renpy_statement.dart`.

## Repository

<https://git.cypherstack.com/FiestaBerry/fiestavn>

## License

MIT
