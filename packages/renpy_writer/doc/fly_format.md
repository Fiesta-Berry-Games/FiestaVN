# The .fly Format Specification (version 1)

.fly is FiestaVN's text-editable interchange format for visual novel
stories. It is strictly-typed JSON that maps 1:1 onto the `renpy_parser`
AST, so a parsed `.rpy` script can be written out as `.fly`, edited by hand
or by tools, and read back without loss of meaning.

## Motivation

- **Text-editable.** A story is plain JSON: any editor, any diff tool, any
  scripting language can work with it. Keys are predictable snake_case and
  default-valued keys are omitted, so documents stay small and diffs stay
  focused on what actually changed.
- **Strictly-typed.** Every statement carries a `"type"` discriminator and a
  closed set of keys. Readers reject unknown types, unknown keys, missing
  required fields, and wrong JSON types *loudly*, with a JSON-pointer-ish
  path to the offending value. A typo never silently becomes a no-op.
- **JSON-native for Dart.** Encoding and decoding use `dart:convert` only;
  the document model is plain `Map<String, Object?>` / `List<Object?>`, so
  .fly flows naturally through Dart, Flutter assets, and web APIs.
- **Lossless for semantics.** Every semantic field of the `renpy_parser`
  AST is representable. Source positions (`filename` / `linenumber`) are
  *not* preserved: decoding synthesizes a filename (default `<fly>`) and
  sequential line numbers in document order.

File extension: **`.fly`**. Suggested MIME type:
**`application/x-fly+json`** (UTF-8).

## Envelope

Every document is a single JSON object with exactly these three keys:

```json
{
  "format": "fly",
  "version": 1,
  "script": [ ...statement objects... ]
}
```

| Key       | JSON type | Required | Constraint                              |
|-----------|-----------|----------|-----------------------------------------|
| `format`  | string    | yes      | must be exactly `"fly"`                 |
| `version` | integer   | yes      | must be a version this reader supports  |
| `script`  | array     | yes      | top-level statement objects, in order   |

Any other top-level key is an error.

## General rules

### Statement objects

Each element of `script` (and of every nested block) is a JSON object with
a required `"type"` key whose value is the statement's Ren'Py keyword in
snake_case. All other keys mirror the AST field names in snake_case.

### Omitted defaults

Writers omit any key whose value equals its default: `null`, `false`, an
empty array, or an empty object. Readers treat an absent key exactly as the
documented default. (`"is_expression": false` and a missing
`is_expression` are the same document.) Explicit JSON `null` is also
accepted as "absent". Integers and strings are written even when they look
boring (`"priority": 0`), except where a default is documented below.

### Nesting

Statements that contain a body carry it as a `block` array of statement
objects, recursively: `label`, `menu` (per choice), `if` (per branch),
`while`, `for`, and `init`. There is no depth limit. Screen bodies, ATL
bodies, and layeredimage bodies use their own typed node objects, described
with their statements below.

### Strictness

A conforming reader MUST reject, with an error naming the document path:

1. a document that is not a JSON object, or whose envelope deviates from
   the table above (wrong `format`, missing/non-integer/unsupported
   `version`, missing or non-array `script`, extra keys);
2. a statement that is not a JSON object;
3. a missing or non-string `"type"`, or a `"type"` not in the catalogue;
4. any key not in the statement's documented key set;
5. any field whose JSON type differs from the documented type;
6. any missing required field;
7. any enum string not in the documented value set.

Error paths look like `/script/3/items/0/text`: `/`-separated, array
indices as numbers, object keys verbatim.

## Statement catalogue

Notation: *req* = required; everything else is optional with the listed
default. `block` is always an array of statement objects, default `[]`.

### `label`

A `label name(params):` declaration.

| Key          | JSON type            | Required | Default |
|--------------|----------------------|----------|---------|
| `name`       | string               | req      |         |
| `parameters` | array of parameter   | no       | `[]`    |
| `block`      | array of statement   | no       | `[]`    |

A **parameter** object: `name` (string, req; a leading `*`/`**` marks
varargs) and `default_expression` (string, default null).

### `say`

Dialogue or narration.

| Key                    | JSON type        | Required | Default |
|------------------------|------------------|----------|---------|
| `character`            | string           | no       | null (narrator) |
| `text`                 | string           | no       | null    |
| `attributes`           | array of string  | no       | `[]`    |
| `temporary_attributes` | array of string  | no       | `[]` (the `@` form) |

### `menu`

| Key            | JSON type       | Required | Default |
|----------------|-----------------|----------|---------|
| `items`        | array of choice | no       | `[]`    |
| `caption`      | string          | no       | null    |
| `set_variable` | string          | no       | null (the `set` clause) |
| `name`         | string          | no       | null (named menu) |

A **choice** object: `text` (string, req), `condition` (string, default
`"True"`), `block`. An unconditioned choice stores the literal `"True"`.

### `jump`

| Key             | JSON type | Required | Default |
|-----------------|-----------|----------|---------|
| `target`        | string    | req      |         |
| `is_expression` | boolean   | no       | false (`jump expression ...`) |

### `call`

| Key             | JSON type | Required | Default |
|-----------------|-----------|----------|---------|
| `target`        | string    | req      |         |
| `is_expression` | boolean   | no       | false   |
| `is_screen`     | boolean   | no       | false (`call screen ...`) |
| `screen_name`   | string    | no       | null    |
| `screen_args`   | string    | no       | null (raw text inside the parens) |
| `call_args`     | string    | no       | null (raw text inside the parens) |

For `call screen`, `target` holds the literal `screen` token (a parser
back-compat quirk) while `screen_name`/`screen_args` carry the real call.

### `show`

| Key                   | JSON type | Required | Default |
|-----------------------|-----------|----------|---------|
| `image_name`          | string    | req      |         |
| `at_expression`       | string    | no       | null    |
| `behind_expression`   | string    | no       | null    |
| `on_layer_expression` | string    | no       | null    |
| `z_order_expression`  | string    | no       | null    |
| `with_expression`     | string    | no       | null    |
| `displayable_text`    | string    | no       | null    |

### `scene`

Same as `show` minus `behind_expression` and `displayable_text`, and
`image_name` is optional (a bare `scene` clears the stage).

### `hide`

| Key                   | JSON type | Required | Default |
|-----------------------|-----------|----------|---------|
| `image_name`          | string    | req      |         |
| `on_layer_expression` | string    | no       | null    |
| `with_expression`     | string    | no       | null    |

### `image`

| Key          | JSON type       | Required | Default |
|--------------|-----------------|----------|---------|
| `name`       | string          | req      |         |
| `expression` | string          | no       | `""` (assignment form) |
| `body`       | array of string | no       | `[]` (raw ATL lines, block form) |

Exactly one of `expression` / `body` is normally present.

### `layeredimage`

| Key      | JSON type      | Required | Default |
|----------|----------------|----------|---------|
| `name`   | string         | req      |         |
| `layers` | array of layer | no       | `[]` (bottom-to-top draw order) |

A **layer** object:

| Key           | JSON type        | Required | Default |
|---------------|------------------|----------|---------|
| `kind`        | string enum      | req      | one of `always`, `attribute`, `condition` |
| `displayable` | string           | req      |         |
| `group`       | string           | no       | null (attribute layers) |
| `attribute`   | string           | no       | null (attribute layers) |
| `is_default`  | boolean          | no       | false   |
| `condition`   | string           | no       | null (`if` layers) |
| `properties`  | object of string | no       | `{}` (`at`, `if_all`, ...) |

### `with`

| Key          | JSON type | Required |
|--------------|-----------|----------|
| `transition` | string    | req      |

### `transform`

| Key         | JSON type         | Required | Default |
|-------------|-------------------|----------|---------|
| `signature` | string            | req      |         |
| `body`      | array of string   | no       | `[]` (raw ATL lines, back-compat) |
| `atl`       | array of ATL node | no       | `[]` (structured ATL) |

An **ATL node** object:

| Key                   | JSON type         | Required | Default |
|-----------------------|-------------------|----------|---------|
| `node_kind`           | string enum       | req      | one of `property`, `interpolation`, `pause`, `repeat`, `block`, `parallel`, `choice`, `on`, `contains`, `raw` |
| `properties`          | object of string  | no       | `{}` (property/interpolation targets) |
| `warper`              | string            | no       | null (`linear`, `ease`, ...) |
| `duration`            | string            | no       | null (also the `choice` chance) |
| `repeat_count`        | string            | no       | null    |
| `event`               | string            | no       | null (`on` nodes) |
| `contains_expression` | string            | no       | null    |
| `children`            | array of ATL node | no       | `[]` (block/parallel/choice/on) |
| `raw`                 | string            | no       | null (`raw` nodes) |

### `play` / `queue`

| Key          | JSON type | Required |
|--------------|-----------|----------|
| `channel`    | string    | req (`music`, `sound`, ...) |
| `expression` | string    | req      |

### `voice`

| Key          | JSON type | Required |
|--------------|-----------|----------|
| `expression` | string    | req (`"file.ogg"` or `sustain`) |

### `stop`

| Key       | JSON type | Required | Default |
|-----------|-----------|----------|---------|
| `channel` | string    | req      |         |
| `fadeout` | string    | no       | null    |

### `pause`

| Key        | JSON type | Required | Default |
|------------|-----------|----------|---------|
| `duration` | string    | no       | null (bare `pause`) |

### `window`

| Key          | JSON type   | Required | Default |
|--------------|-------------|----------|---------|
| `action`     | string enum | req      | one of `show`, `hide`, `auto` |
| `transition` | string      | no       | null    |

### `python`

A `$ line` or `python:` block.

| Key       | JSON type | Required | Default |
|-----------|-----------|----------|---------|
| `code`    | string    | req      |         |
| `is_init` | boolean   | no       | false (`python early` etc.) |

### `init`

An `init [N] [python]:` block.

| Key         | JSON type          | Required | Default |
|-------------|--------------------|----------|---------|
| `priority`  | integer            | no       | 0       |
| `is_python` | boolean            | no       | false   |
| `block`     | array of statement | no       | `[]`    |

### `init_offset`

| Key      | JSON type | Required |
|----------|-----------|----------|
| `offset` | integer   | req      |

### `define` / `default`

| Key          | JSON type | Required |
|--------------|-----------|----------|
| `name`       | string    | req      |
| `expression` | string    | req      |

### `screen`

| Key         | JSON type            | Required | Default |
|-------------|----------------------|----------|---------|
| `signature` | string               | req      | raw `name(params)` text |
| `children`  | array of screen node | no       | `[]`    |

A **screen node** object:

| Key               | JSON type            | Required | Default |
|-------------------|----------------------|----------|---------|
| `kind`            | string               | req      | displayable/statement keyword (`vbox`, `text`, `if`, ...) |
| `node_kind`       | string enum          | req      | one of `displayable`, `if_chain`, `for_loop`, `python`, `python_block`, `on`, `use`, `transclude`, `has`, `keyword` |
| `positional_args` | array of string      | no       | `[]`    |
| `properties`      | object of string     | no       | `{}`    |
| `children`        | array of screen node | no       | `[]`    |
| `branches`        | array of branch      | no       | `[]` (`if_chain` only) |
| `for_target`      | string               | no       | null    |
| `for_iterable`    | string               | no       | null    |
| `python_code`     | string               | no       | null    |
| `event`           | string               | no       | null (`on` nodes) |
| `keyword`         | string               | no       | null (`keyword` nodes) |
| `value`           | string               | no       | null (`keyword` nodes) |

A **branch** object: `condition` (string, req; `else` is the literal
`"True"`) and `children` (array of screen node, default `[]`).

### `style`

| Key           | JSON type | Required | Default |
|---------------|-----------|----------|---------|
| `declaration` | string    | req      | raw `name [is parent]` text |
| `style`       | object    | no       | null    |

The structured **style** object: `name` (string, req), `parent` (string,
default null), `properties` (object of string, default `{}`).

### `nvl`

| Key      | JSON type   | Required |
|----------|-------------|----------|
| `action` | string enum | req — only `clear` |

### `if`

| Key        | JSON type       | Required |
|------------|-----------------|----------|
| `branches` | array of branch | req      |

Each **branch** object: `condition` (string, req) and `block`. Branches are
the `if`/`elif`/.../`else` chain in source order; an `else` branch is
stored with the literal condition `"True"` — exactly as the parser stores
it.

### `while`

| Key         | JSON type          | Required | Default |
|-------------|--------------------|----------|---------|
| `condition` | string             | req      |         |
| `block`     | array of statement | no       | `[]`    |

### `for`

| Key        | JSON type          | Required | Default |
|------------|--------------------|----------|---------|
| `variable` | string             | req (e.g. `q` or `i, value`) | |
| `iterable` | string             | req      |         |
| `block`    | array of statement | no       | `[]`    |

### `break` / `continue` / `pass`

No fields beyond `type`.

### `return`

| Key          | JSON type | Required | Default |
|--------------|-----------|----------|---------|
| `expression` | string    | no       | null    |

### `raw`

A statement the parser captured but could not classify
(`RenPyGenericStatement`). Round-trips verbatim.

| Key    | JSON type | Required |
|--------|-----------|----------|
| `text` | string    | req      |

## Worked example

The Ren'Py script:

```renpy
define e = Character("Eileen")

label start:
    scene bg meadow
    show eileen happy
    e "Shall we explore?"
    menu:
        "Yes!":
            jump explore
        "Not yet." if tired:
            e "We can rest first."
            return

label explore:
    e "Off we go!"
    return
```

is this .fly document:

```json
{
  "format": "fly",
  "version": 1,
  "script": [
    {
      "type": "define",
      "name": "e",
      "expression": "Character(\"Eileen\")"
    },
    {
      "type": "label",
      "name": "start",
      "block": [
        { "type": "scene", "image_name": "bg meadow" },
        { "type": "show", "image_name": "eileen happy" },
        { "type": "say", "character": "e", "text": "Shall we explore?" },
        {
          "type": "menu",
          "items": [
            {
              "text": "Yes!",
              "condition": "True",
              "block": [
                { "type": "jump", "target": "explore" }
              ]
            },
            {
              "text": "Not yet.",
              "condition": "tired",
              "block": [
                {
                  "type": "say",
                  "character": "e",
                  "text": "We can rest first."
                },
                { "type": "return" }
              ]
            }
          ]
        }
      ]
    },
    {
      "type": "label",
      "name": "explore",
      "block": [
        { "type": "say", "character": "e", "text": "Off we go!" },
        { "type": "return" }
      ]
    }
  ]
}
```

## Versioning policy

`version` is a single integer. Readers MUST reject any version they do not
support. Any breaking change — removing or renaming a key, changing a JSON
type, changing a default, narrowing an enum — bumps the version. Purely
additive changes (a new statement type, a new optional key) also bump the
version, because strict readers reject unknown input by design; a version-1
reader cannot safely skip what it does not understand. Writers always emit
the newest version they know.
