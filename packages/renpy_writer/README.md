# renpy_writer

The write-side complement to [`renpy_parser`](https://pub.dev/packages/renpy_parser):
where `renpy_parser` turns Ren'Py `.rpy` script text into an AST, `renpy_writer`
turns that AST back into text — either as `.rpy` script or as a `.fly`
strictly-typed JSON document — and ships the migration and packaging tools
built on top of those two serializers.

This package is part of the [FiestaVN](https://git.cypherstack.com/FiestaBerry/fiestavn)
monorepo.

## RenPyEmitter

`RenPyEmitter` serializes a parsed `RenPyScript` AST back to valid `.rpy`
script text. It is designed as the inverse of `RenPyParser`: the emitted text
re-parses to an equivalent AST, and emission is a *fixpoint* — parsing the
emitted text and emitting it again yields the exact same text.

```dart
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/renpy_writer.dart';

void main() {
  final script = RenPyParser().parse('''
label start:
    e happy "Hello, world!"
    jump ending
''', 'script.rpy').script;

  const emitter = RenPyEmitter(); // or RenPyEmitter(indent: '  ')
  print(emitter.emitScript(script));   // the whole document
  print(emitter.emitStatement(script.statements.first)); // one statement
}
```

A few normalizations are applied (all stable under re-parsing), such as
`$ name = expression` re-emitting as `define name = expression` and empty
blocks gaining an explicit `pass`.

## FlyCodec

`FlyCodec` converts the same AST to and from **`.fly`** documents:
strictly-typed JSON that maps 1:1 onto the `renpy_parser` AST. Every statement
carries a `"type"` discriminator and a closed set of snake_case keys; readers
reject unknown types, unknown keys, missing fields, and wrong JSON types with
a `FlyFormatException` that points at the offending value.

```dart
import 'package:renpy_parser/renpy_parser.dart';
import 'package:renpy_writer/renpy_writer.dart';

void main() {
  final script = RenPyParser().parse('label start:\n    "Hi."\n', 's.rpy').script;

  const codec = FlyCodec();
  final text = codec.encodeToString(script);        // pretty-printed .fly JSON
  final decoded = codec.decodeFromString(text);     // back to a RenPyScript
  assert(decoded.statements.length == script.statements.length);
}
```

The full format is specified in [doc/fly_format.md](doc/fly_format.md).

## FlyMigrator

`FlyMigrator` (in `lib/src/fly_migrator.dart`) performs fidelity-checked
migration between `.rpy` and `.fly`: it converts a script in either direction,
verifies the result round-trips, and produces a machine-readable report of any
constructs that do not survive the conversion, so tooling (and humans) can see
exactly what was preserved and what was not before committing to a migration.

## FlyArchive

`FlyArchive` (in `lib/src/fly_archive.dart`) reads and writes **`.fly.zip`**
archives: a zipped RenFly game directory packaged for one-file distribution.
A `.fly.zip` contains the game's `.fly` story alongside its assets and can be
loaded directly by both the RenFly player and the editor.
