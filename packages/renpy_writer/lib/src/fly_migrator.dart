import 'dart:convert';

import 'package:renpy_parser/renpy_parser.dart';

import 'fly_codec.dart';
import 'renpy_emitter.dart';

/// How badly an issue affects migration fidelity.
enum FlyMigrationSeverity {
  /// The construct is preserved byte-for-byte but is not structured (raw
  /// passthrough). Round-trips remain faithful; tooling just cannot look
  /// inside it.
  info,

  /// The parser reported a problem while reading the source. The affected
  /// construct may have been skipped or only partially understood.
  warning,

  /// Content is (or may be) lost or changed by the migration. The output
  /// must be reviewed before the original source is discarded.
  lossy,
}

/// A single fidelity finding produced while migrating between `.rpy` and
/// `.fly` (see `doc/migration.md`).
class FlyMigrationIssue {
  const FlyMigrationIssue({
    required this.severity,
    required this.kind,
    required this.message,
    this.filename,
    this.linenumber,
    this.snippet,
  });

  /// How badly this issue affects fidelity.
  final FlyMigrationSeverity severity;

  /// Machine-readable issue key. One of:
  ///
  /// * `unstructured-statement` - a construct the parser does not understand;
  ///   it survives only as raw text ([FlyMigrationSeverity.lossy]).
  /// * `parse-warning` - the parser reported a warning; the construct may
  ///   have been skipped ([FlyMigrationSeverity.warning]).
  /// * `roundtrip-divergence` - re-parsing the converted output produced a
  ///   different document ([FlyMigrationSeverity.lossy]).
  /// * `raw-passthrough-body` - a recognized statement whose body is kept
  ///   verbatim rather than structured ([FlyMigrationSeverity.info]).
  final String kind;

  /// Human-readable explanation of the issue.
  final String message;

  /// Source file the issue points into, when known.
  final String? filename;

  /// 1-based line number in [filename], when known.
  final int? linenumber;

  /// The offending source text, when available.
  final String? snippet;

  @override
  String toString() {
    final location =
        filename == null
            ? ''
            : ' at $filename${linenumber == null ? '' : ':$linenumber'}';
    return '[${severity.name}] $kind$location: $message';
  }
}

/// The fidelity findings for one migration or round-trip verification.
class FlyMigrationReport {
  const FlyMigrationReport(this.issues);

  /// All findings, in document order (divergences last).
  final List<FlyMigrationIssue> issues;

  /// True when nothing was lost: no [FlyMigrationSeverity.warning] and no
  /// [FlyMigrationSeverity.lossy] issues. [FlyMigrationSeverity.info]
  /// findings (raw-passthrough bodies) do not break faithfulness.
  bool get isFaithful =>
      issues.every((issue) => issue.severity == FlyMigrationSeverity.info);

  /// The number of issues with the given [severity].
  int countOf(FlyMigrationSeverity severity) =>
      issues.where((issue) => issue.severity == severity).length;

  /// The number of [FlyMigrationSeverity.info] issues.
  int get infoCount => countOf(FlyMigrationSeverity.info);

  /// The number of [FlyMigrationSeverity.warning] issues.
  int get warningCount => countOf(FlyMigrationSeverity.warning);

  /// The number of [FlyMigrationSeverity.lossy] issues.
  int get lossyCount => countOf(FlyMigrationSeverity.lossy);

  @override
  String toString() {
    if (issues.isEmpty) return 'faithful migration, no issues';
    final parts = <String>[
      if (lossyCount > 0) '$lossyCount lossy',
      if (warningCount > 0) '$warningCount warning(s)',
      if (infoCount > 0) '$infoCount info',
    ];
    final verdict = isFaithful ? 'faithful' : 'NOT faithful';
    return '$verdict: ${parts.join(', ')}';
  }
}

/// The output of a migration plus its fidelity [report].
class FlyMigrationResult {
  const FlyMigrationResult(this.output, this.report);

  /// The converted document text (`.fly` JSON or `.rpy` script).
  final String output;

  /// What was and was not faithfully migrated.
  final FlyMigrationReport report;
}

/// Converts between classic Ren'Py `.rpy` scripts and `.fly` documents while
/// reporting exactly which constructs are not faithfully migrated.
///
/// Migration is never silently lossy: every construct that survives only as
/// raw text, every parser warning, and every round-trip divergence is
/// surfaced as a [FlyMigrationIssue]. Call [verifyRoundTrip] before
/// discarding an original `.rpy` source; a [FlyMigrationReport.isFaithful]
/// result guarantees the `.fly` document re-emits to an equivalent script.
class FlyMigrator {
  const FlyMigrator({
    this.codec = const FlyCodec(),
    this.emitter = const RenPyEmitter(),
  });

  /// The codec used to read and write `.fly` documents.
  final FlyCodec codec;

  /// The emitter used to write `.rpy` script text.
  final RenPyEmitter emitter;

  /// The maximum number of `roundtrip-divergence` issues reported per
  /// migration; further divergences are summarized in one extra issue.
  static const int maxReportedDivergences = 10;

  /// Converts Ren'Py [rpySource] to a `.fly` document.
  ///
  /// The report carries a `parse-warning` for every parser warning, an
  /// `unstructured-statement` for every construct the parser kept only as
  /// raw text, and a `raw-passthrough-body` for every statement whose body
  /// is preserved verbatim rather than structured.
  FlyMigrationResult rpyToFly(
    String rpySource, {
    String filename = 'script.rpy',
    bool pretty = true,
  }) {
    final parsed = RenPyParser().parse(rpySource, filename);
    final issues = <FlyMigrationIssue>[
      ..._warningIssues(parsed.warnings),
      ..._scriptIssues(parsed.script),
    ];
    final output = codec.encodeToString(parsed.script, pretty: pretty);
    return FlyMigrationResult(output, FlyMigrationReport(issues));
  }

  /// Converts a `.fly` document to Ren'Py script text.
  ///
  /// Throws [FlyFormatException] when [flySource] is not a valid `.fly`
  /// document - structural invalidity is a hard error, not an issue.
  ///
  /// After emitting, the result is verified: the emitted script is re-parsed
  /// and re-encoded, and any difference from the input document is reported
  /// as a `roundtrip-divergence` issue. `raw` statements in the input are
  /// reported as `unstructured-statement`.
  FlyMigrationResult flyToRpy(
    String flySource, {
    String filename = 'story.fly',
  }) {
    final script = codec.decodeFromString(flySource, filename: filename);
    final issues = <FlyMigrationIssue>[..._scriptIssues(script)];
    final output = emitter.emitScript(script);

    // Verify the emitted script means the same thing as the input document:
    // reparse it and compare canonical re-encodes of both sides.
    final reparsed = RenPyParser().parse(output, filename);
    issues.addAll(
      _divergenceIssues(
        codec.encodeScript(script),
        codec.encodeScript(reparsed.script),
        filename,
      ),
    );
    return FlyMigrationResult(output, FlyMigrationReport(issues));
  }

  /// Verifies that [rpySource] survives a full round trip:
  /// parse -> encode `.fly` -> decode -> emit `.rpy` -> reparse -> re-encode,
  /// then deep-diffs the first encode against the second.
  ///
  /// This is THE faithfulness check applications should run before (and
  /// after) saving a migrated project. A faithful report means the `.fly`
  /// document carries everything needed to reproduce an equivalent script.
  FlyMigrationReport verifyRoundTrip(
    String rpySource, {
    String filename = 'script.rpy',
  }) {
    final parsed = RenPyParser().parse(rpySource, filename);
    final issues = <FlyMigrationIssue>[
      ..._warningIssues(parsed.warnings),
      ..._scriptIssues(parsed.script),
    ];

    final firstEncode = codec.encodeScript(parsed.script);
    final flyText = codec.encodeToString(parsed.script);
    final decoded = codec.decodeFromString(flyText, filename: filename);
    final emitted = emitter.emitScript(decoded);
    final reparsed = RenPyParser().parse(emitted, filename);
    final secondEncode = codec.encodeScript(reparsed.script);

    issues.addAll(_divergenceIssues(firstEncode, secondEncode, filename));
    return FlyMigrationReport(issues);
  }

  // ---------------------------------------------------------------------
  // Issue collection
  // ---------------------------------------------------------------------

  /// `filename.rpy:12` location extractor for parser warning strings, which
  /// look like `Warning: ... at file.rpy:12: text` or
  /// `Warning: Could not parse line 12 in file.rpy: error`.
  static final RegExp _warningLocationPattern = RegExp(
    r'(?:at\s+(\S+?):(\d+)|line\s+(\d+)\s+in\s+(\S+?):)',
  );

  List<FlyMigrationIssue> _warningIssues(List<String> warnings) {
    return [
      for (final warning in warnings)
        () {
          final match = _warningLocationPattern.firstMatch(warning);
          final filename = match?.group(1) ?? match?.group(4);
          final line = match?.group(2) ?? match?.group(3);
          return FlyMigrationIssue(
            severity: FlyMigrationSeverity.warning,
            kind: 'parse-warning',
            message: warning,
            filename: filename,
            linenumber: line == null ? null : int.tryParse(line),
          );
        }(),
    ];
  }

  List<FlyMigrationIssue> _scriptIssues(RenPyScript script) {
    final issues = <FlyMigrationIssue>[];
    _collectStatementIssues(script.statements, issues);
    return issues;
  }

  void _collectStatementIssues(
    List<RenPyStatement> statements,
    List<FlyMigrationIssue> issues,
  ) {
    for (final statement in statements) {
      if (statement is RenPyGenericStatement) {
        issues.add(
          FlyMigrationIssue(
            severity: FlyMigrationSeverity.lossy,
            kind: 'unstructured-statement',
            message:
                'construct is not understood by the parser and survives only '
                'as raw text: ${statement.text}',
            filename: statement.filename,
            linenumber: statement.linenumber,
            snippet: statement.text,
          ),
        );
      } else if (statement is RenPyTransformStatement) {
        if (statement.atl.isEmpty && statement.body.isNotEmpty) {
          issues.add(
            _rawBody(
              statement,
              'transform "${statement.signature}" has a raw (unstructured) '
              'ATL body',
              statement.body.join('\n'),
            ),
          );
        } else {
          _collectRawAtlIssues(statement, statement.atl, issues);
        }
      } else if (statement is RenPyImageStatement &&
          statement.body.isNotEmpty) {
        issues.add(
          _rawBody(
            statement,
            'image "${statement.name}" has a raw (unstructured) ATL body',
            statement.body.join('\n'),
          ),
        );
      } else if (statement is RenPyCameraStatement &&
          statement.body.isNotEmpty) {
        issues.add(
          _rawBody(
            statement,
            'camera statement has a raw (unstructured) ATL body',
            statement.body.join('\n'),
          ),
        );
      } else if (statement is RenPyTranslateStatement &&
          statement.strings.isNotEmpty) {
        issues.add(
          _rawBody(
            statement,
            'translate ${statement.language} strings block is kept as raw '
            'lines only',
            statement.strings.join('\n'),
          ),
        );
      } else if (statement is RenPyStyleStatement && statement.style == null) {
        issues.add(
          _rawBody(
            statement,
            'style declaration "${statement.declaration}" is kept as raw '
            'text only',
            statement.declaration,
          ),
        );
      }

      // Recurse into every nested block. RenPyIfStatement aliases its
      // (deprecated) block field to the first branch, so it must be handled
      // before the generic RenPyBlockStatement case.
      if (statement is RenPyIfStatement) {
        for (final entry in statement.entries) {
          _collectStatementIssues(entry.block, issues);
        }
      } else if (statement is RenPyMenuStatement) {
        for (final choice in statement.items) {
          _collectStatementIssues(choice.block, issues);
        }
      } else if (statement is RenPyBlockStatement) {
        _collectStatementIssues(statement.block, issues);
      }
    }
  }

  void _collectRawAtlIssues(
    RenPyTransformStatement statement,
    List<RenPyAtlNode> nodes,
    List<FlyMigrationIssue> issues,
  ) {
    for (final node in nodes) {
      if (node.nodeKind == RenPyAtlNodeKind.raw) {
        issues.add(
          _rawBody(
            statement,
            'transform "${statement.signature}" contains an unstructured '
            'ATL line: ${node.raw ?? ''}',
            node.raw,
          ),
        );
      }
      _collectRawAtlIssues(statement, node.children, issues);
    }
  }

  FlyMigrationIssue _rawBody(
    RenPyStatement statement,
    String message,
    String? snippet,
  ) {
    return FlyMigrationIssue(
      severity: FlyMigrationSeverity.info,
      kind: 'raw-passthrough-body',
      message: '$message (preserved verbatim, faithful but not structured)',
      filename: statement.filename,
      linenumber: statement.linenumber,
      snippet: snippet,
    );
  }

  List<FlyMigrationIssue> _divergenceIssues(
    Map<String, Object?> expected,
    Map<String, Object?> actual,
    String filename,
  ) {
    final divergences = flyJsonDiff(
      expected,
      actual,
      maxPaths: maxReportedDivergences + 1,
    );
    final truncated = divergences.length > maxReportedDivergences;
    return [
      for (final divergence in divergences.take(maxReportedDivergences))
        FlyMigrationIssue(
          severity: FlyMigrationSeverity.lossy,
          kind: 'roundtrip-divergence',
          message: 'round trip changed the document at $divergence',
          filename: filename,
        ),
      if (truncated)
        FlyMigrationIssue(
          severity: FlyMigrationSeverity.lossy,
          kind: 'roundtrip-divergence',
          message:
              'round trip diverges in more than '
              '$maxReportedDivergences places (further divergences omitted)',
          filename: filename,
        ),
    ];
  }
}

/// Converts [rpySource] to a `.fly` document and merges in the round-trip
/// verification, so the caller sees every fidelity issue before discarding
/// the original `.rpy` source.
///
/// This is the migration gate: a [FlyMigrationReport.isFaithful] result
/// means the produced `.fly` output reproduces an equivalent script, so the
/// migration may proceed silently. Otherwise the report lists exactly which
/// code is not faithfully migrated.
///
/// Throws [RenPyParseError] (from `renpy_parser`) when [rpySource] does not
/// parse at all.
FlyMigrationResult runRpyToFlyGate(
  String rpySource, {
  String filename = 'script.rpy',
}) {
  const migrator = FlyMigrator();
  final result = migrator.rpyToFly(rpySource, filename: filename);
  // rpyToFly already reports parse warnings and unstructured statements;
  // verifyRoundTrip repeats those, so only its divergence findings are new.
  final verification = migrator.verifyRoundTrip(rpySource, filename: filename);
  final divergences = [
    for (final issue in verification.issues)
      if (issue.kind == 'roundtrip-divergence') issue,
  ];
  if (divergences.isEmpty) return result;
  return FlyMigrationResult(
    result.output,
    FlyMigrationReport([...result.report.issues, ...divergences]),
  );
}

/// Deep-diffs two JSON values (maps, lists, scalars) and returns one entry
/// per divergence, formatted as a JSON-pointer path followed by a short
/// description, e.g. `/script/3/items/0/text: "Yes" != "No"`.
///
/// At most [maxPaths] entries are returned; recursion stops once the cap is
/// reached. Used by [FlyMigrator] to pinpoint round-trip divergences.
List<String> flyJsonDiff(Object? a, Object? b, {int maxPaths = 10}) {
  final paths = <String>[];
  _diffValue(a, b, '', paths, maxPaths);
  return paths;
}

void _diffValue(
  Object? a,
  Object? b,
  String path,
  List<String> paths,
  int maxPaths,
) {
  if (paths.length >= maxPaths) return;
  if (a is Map<String, Object?> && b is Map<String, Object?>) {
    for (final key in {...a.keys, ...b.keys}) {
      if (paths.length >= maxPaths) return;
      final childPath = '$path/${_escapePointerSegment(key)}';
      if (!b.containsKey(key)) {
        paths.add('$childPath: ${_describe(a[key])} != (absent)');
      } else if (!a.containsKey(key)) {
        paths.add('$childPath: (absent) != ${_describe(b[key])}');
      } else {
        _diffValue(a[key], b[key], childPath, paths, maxPaths);
      }
    }
    return;
  }
  if (a is List<Object?> && b is List<Object?>) {
    final shared = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < shared; i++) {
      if (paths.length >= maxPaths) return;
      _diffValue(a[i], b[i], '$path/$i', paths, maxPaths);
    }
    if (a.length != b.length && paths.length < maxPaths) {
      paths.add('$path: list length ${a.length} != ${b.length}');
    }
    return;
  }
  if (a != b) {
    paths.add('$path: ${_describe(a)} != ${_describe(b)}');
  }
}

/// JSON-pointer key escaping per RFC 6901: `~` -> `~0`, `/` -> `~1`.
String _escapePointerSegment(String key) =>
    key.replaceAll('~', '~0').replaceAll('/', '~1');

/// A short, single-line JSON rendering of [value] for diff messages.
String _describe(Object? value) {
  final text = jsonEncode(value);
  return text.length <= 60 ? text : '${text.substring(0, 57)}...';
}
