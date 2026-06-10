# Migration Fidelity

`FlyMigrator` converts classic Ren'Py `.rpy` scripts to `.fly` documents (and
back) and tells you **exactly** which constructs were not faithfully
migrated. Nothing is lost silently: every finding is a `FlyMigrationIssue`
in the returned `FlyMigrationReport`.

## The fidelity model

A migration is **faithful** when the converted document re-parses to an
equivalent script — nothing was dropped, changed, or misread. Three things
can break (or qualify) faithfulness:

1. **Unstructured constructs.** The parser turns anything it does not
   understand into a raw-text passthrough (`RenPyGenericStatement` /
   `"type": "raw"`). The text survives byte-for-byte, but its *meaning* is
   not structured: tools cannot inspect or transform it, and the runtime
   cannot execute it.
2. **Parse warnings.** The parser skipped or only partially understood a
   construct (e.g. an invalid menu choice). The affected content may be
   missing from the output entirely.
3. **Round-trip divergence.** The emitter/codec produced output that
   re-parses to a *different* document than the input. This is the only
   channel where content changes rather than merely staying opaque; any
   occurrence is a bug-grade loss and is always reported.

Some recognized statements intentionally keep raw-text bodies (transform/
image ATL bodies the ATL parser could not structure, bare style
declarations). These are preserved verbatim and round-trip faithfully, so
they are reported at `info` severity only.

`report.isFaithful` is true when the report contains **no `warning` and no
`lossy` issues** — `info` findings do not break faithfulness.

## Issue kinds

| `kind`                    | Severity  | Meaning |
|---------------------------|-----------|---------|
| `unstructured-statement`  | `lossy`   | A construct the parser does not understand. It survives only as raw text (`snippet` holds it); it is not structured and will not execute. |
| `parse-warning`           | `warning` | The parser reported a problem; the construct may have been skipped or partially read. The message is the parser's warning text. |
| `roundtrip-divergence`    | `lossy`   | Re-parsing the converted output produced a different document. The message names the diverging location as a JSON-pointer path into the `.fly` encoding (at most 10 paths are listed, plus a summary if there are more). |
| `raw-passthrough-body`    | `info`    | A recognized statement whose body is kept verbatim instead of structured (raw transform/image ATL bodies, raw ATL lines, bare style declarations). Faithful, just opaque. |

Each issue carries `severity`, `kind`, a human-readable `message`, and —
when known — `filename`, `linenumber`, and the offending `snippet`.

## API

```dart
const migrator = FlyMigrator();

// .rpy -> .fly
final result = migrator.rpyToFly(rpySource, filename: 'script.rpy');
result.output;          // the .fly JSON text
result.report.issues;   // what was not fully structured

// .fly -> .rpy (throws FlyFormatException on an invalid document)
final back = migrator.flyToRpy(flySource);

// THE faithfulness check: parse -> encode -> decode -> emit -> reparse
// -> re-encode, then deep-diff the two encodes.
final report = migrator.verifyRoundTrip(rpySource);
if (report.isFaithful) {
  // safe to save the .fly and discard the .rpy
}
```

`flyJsonDiff(a, b)` — the deep diff used to detect divergences — is also
exported; it returns JSON-pointer paths with short value descriptions.

## How apps should surface reports

- **Always run `verifyRoundTrip` before letting the user discard a `.rpy`
  source** (e.g. on project import or before save). Block or warn loudly
  when `isFaithful` is false.
- **Show `lossy` issues prominently** (a blocking dialog or a persistent
  banner) with the `filename:linenumber` location and the `snippet`, so the
  user can see precisely which code is affected and decide whether to keep
  the original file.
- **Show `warning` issues as a reviewable list** — the construct may have
  been dropped; the user should check the named lines.
- **`info` issues need no interruption.** A collapsed "N constructs kept as
  raw text" note (or a gutter marker on the line) is enough; the content is
  safe, it is just not editable as structure.
- Use `kind` for programmatic handling (filtering, grouping, suppressing
  known-accepted findings) and `message` for display; `report.toString()`
  gives a one-line summary suitable for logs and status bars.
- `roundtrip-divergence` should be treated as a bug in the toolchain, not a
  user error: report it with the diverging paths so it can be filed
  upstream.
