import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_image_resolver.dart';

/// One contiguous run of script statements and the assets it references.
///
/// Segments are produced by [RenPyAssetPlan.fromScript]: statements before
/// the first top-level label form an optional preamble segment whose [label]
/// is null, and each top-level `label` statement starts a new segment named
/// after it. [assets] holds the segment's resolved asset paths (forward
/// slashes), deduplicated within the segment, in first-reference order.
final class RenPyAssetPlanSegment {
  RenPyAssetPlanSegment({
    this.label,
    required this.linenumber,
    required List<String> assets,
  }) : assets = List.unmodifiable(assets);

  /// The top-level label that starts this segment, or null for the preamble
  /// segment (statements before the first top-level label).
  final String? label;

  /// The source line the segment starts on: the label statement's line, or
  /// the first preamble statement's line for the preamble segment.
  final int linenumber;

  /// Resolved asset paths referenced by this segment, with forward slashes,
  /// deduplicated within the segment, in first-reference order.
  final List<String> assets;

  @override
  String toString() =>
      'RenPyAssetPlanSegment(${label ?? '<preamble>'}: '
      '${assets.length} assets)';
}

/// A static prefetch plan: which assets a script references, segmented by
/// top-level label, in source order.
///
/// The plan is built once from a parsed script and lets hosts stream a game
/// progressively — fetch [assetsFromSegment] for the label the player is
/// about to enter, report progress against [allAssets], and so on. It is a
/// static over-approximation of one playthrough: every branch (menu choices,
/// `if`/`while`/`for` bodies) contributes its assets to the enclosing
/// segment, and control flow (`jump`/`call`) is not followed.
final class RenPyAssetPlan {
  /// Creates a plan over [segments]. Most callers should use [fromScript].
  RenPyAssetPlan(List<RenPyAssetPlanSegment> segments)
    : segments = List.unmodifiable(segments);

  /// Builds the plan by walking [script]'s statements in source order,
  /// descending into nested blocks (label blocks, menu choice blocks,
  /// `if`/`while`/`for` branches, `init` blocks).
  ///
  /// Statements before the first top-level label form an optional preamble
  /// segment (label null, omitted when it references no assets); each
  /// top-level label statement starts a new segment.
  ///
  /// Per statement:
  ///
  /// * `scene`/`show` image names resolve through [resolver]; the resolved
  ///   asset path is recorded when non-null. Solid colors and bare text
  ///   displayables have no asset path and are skipped naturally.
  /// * `play`/`queue`/`voice` statements record their audio file when the
  ///   expression is a static quoted literal, joined under [gameRoot] the
  ///   same way `RenPyAudioAssetResolver` in `renpy_flutter` builds its
  ///   asset key (backslashes normalized to forward slashes, leading slashes
  ///   stripped, paths already under `assets/` kept as-is). Dynamic audio
  ///   expressions (variables, `[...]` playlists) cannot be resolved
  ///   statically and are skipped. `voice sustain` references no file.
  ///
  /// [resolver] must already be seeded with the script's `image name = ...`
  /// definitions — pass `RenPyImageResolver.fromScript(script, ...)`. Image
  /// definition statements are not re-registered here; they only matter
  /// through the resolver.
  ///
  /// When [availableAssets] is non-empty it acts as a manifest filter: only
  /// paths present in it are recorded, so speculative candidates for assets
  /// that do not ship with the game are dropped.
  factory RenPyAssetPlan.fromScript(
    RenPyScript script, {
    required RenPyImageResolver resolver,
    Set<String> availableAssets = const {},
    String? gameRoot,
  }) {
    final segments = <RenPyAssetPlanSegment>[];
    String? label;
    int? linenumber;
    var assets = <String>[];
    var seen = <String>{};

    void flush() {
      final line = linenumber;
      if (line == null) return;
      if (label == null && assets.isEmpty) return; // Optional preamble.
      segments.add(
        RenPyAssetPlanSegment(label: label, linenumber: line, assets: assets),
      );
    }

    void record(String? asset) {
      if (asset == null) return;
      if (availableAssets.isNotEmpty && !availableAssets.contains(asset)) {
        return;
      }
      if (seen.add(asset)) assets.add(asset);
    }

    void visit(RenPyStatement statement) {
      switch (statement) {
        case RenPySceneStatement(:final imageName):
          record(resolver.resolveImage(imageName)?.assetPath);
        case RenPyShowStatement(:final imageName):
          record(resolver.resolveImage(imageName)?.assetPath);
        case RenPyPlayStatement(:final expression) ||
            RenPyQueueStatement(:final expression):
          record(_audioAssetKey(expression, gameRoot));
        case RenPyVoiceStatement(isSustain: false, :final expression):
          record(_audioAssetKey(expression, gameRoot));
        case RenPyIfStatement(:final entries):
          for (final entry in entries) {
            entry.block.forEach(visit);
          }
        case RenPyMenuStatement(:final items):
          for (final choice in items) {
            choice.block.forEach(visit);
          }
        case RenPyBlockStatement(:final block):
          // Nested labels, while/for loops, init and translate blocks.
          block.forEach(visit);
        default:
          break;
      }
    }

    for (final statement in script.statements) {
      if (statement is RenPyLabelStatement) {
        flush();
        label = statement.name;
        linenumber = statement.linenumber;
        assets = <String>[];
        seen = <String>{};
        statement.block.forEach(visit);
      } else {
        linenumber ??= statement.linenumber; // Preamble starts lazily.
        visit(statement);
      }
    }
    flush();

    return RenPyAssetPlan(segments);
  }

  /// The plan's segments in source order: the optional preamble first, then
  /// one segment per top-level label.
  final List<RenPyAssetPlanSegment> segments;

  /// Every asset referenced anywhere in the plan.
  Set<String> get allAssets => {
    for (final segment in segments) ...segment.assets,
  };

  /// The assets of segment [index] and every later segment, flattened in
  /// plan order and deduplicated across segments — the prefetch list for
  /// "play from here to the end". A negative [index] is treated as 0; an
  /// [index] past the last segment yields an empty list.
  List<String> assetsFromSegment(int index) {
    final seen = <String>{};
    final result = <String>[];
    for (var i = index < 0 ? 0 : index; i < segments.length; i += 1) {
      for (final asset in segments[i].assets) {
        if (seen.add(asset)) result.add(asset);
      }
    }
    return result;
  }

  /// The index of the segment started by the top-level label [label], or -1
  /// when the plan has no such segment (unknown or nested labels).
  int segmentIndexForLabel(String label) {
    for (var i = 0; i < segments.length; i += 1) {
      if (segments[i].label == label) return i;
    }
    return -1;
  }
}

/// Extracts the static audio file from a `play`/`queue`/`voice` expression
/// and joins it under [gameRoot], mirroring how `RenPyAudioAssetResolver` in
/// `renpy_flutter` builds its asset key (reimplemented here because
/// renpy_core cannot depend on Flutter). Returns null when the expression is
/// not a quoted literal (e.g. a variable) and so cannot be resolved
/// statically.
String? _audioAssetKey(String expression, String? gameRoot) {
  final quoted = RegExp(r'''^["']([^"']+)["']''').firstMatch(expression.trim());
  if (quoted == null) return null;

  final normalized = quoted
      .group(1)!
      .replaceAll(r'\', '/')
      .replaceFirst(RegExp(r'^/+'), '');
  if (normalized.startsWith('assets/')) return normalized;
  final root = gameRoot;
  if (root == null || root.isEmpty) return normalized;
  return root.endsWith('/') ? '$root$normalized' : '$root/$normalized';
}
