// Guards the showcase script against drift, in both directions:
//
// - the script must parse cleanly (no warnings, no generic fallback
//   statements), and
// - every `show <tag> <attribute>` that routes to a Spine character must map
//   (via the renpy_spine `.spine` naming convention) to a skin and animation
//   that actually exist in the bundled chibi-stickers skeleton export.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:renpy_core/renpy_core.dart';
import 'package:renpy_spine/renpy_spine.dart' show SpineImageName;
import 'package:renspine/main.dart' show kSpineCharacters;

const _scriptPath = 'assets/games/1/game/script.rpy';
const _skeletonJsonPath = 'assets/chibi-stickers/export/chibi-stickers.json';

void main() {
  final source = File(_scriptPath).readAsStringSync();
  final result = RenPyParser().parse(source, _scriptPath);
  final statements = _flatten(result.script.statements).toList();

  final skeleton =
      jsonDecode(File(_skeletonJsonPath).readAsStringSync())
          as Map<String, dynamic>;
  final skins = _skinNames(skeleton);
  final animations =
      (skeleton['animations'] as Map<String, dynamic>).keys.toSet();

  test('script parses with zero warnings', () {
    expect(result.warnings, isEmpty);
  });

  test('script contains no generic (unrecognized) statements', () {
    expect(
      statements.whereType<RenPyGenericStatement>().map((s) => s.text),
      isEmpty,
    );
  });

  test('script defines a start label and all jump targets resolve', () {
    final labels = result.script.labels.keys.toSet();
    expect(labels, contains('start'));
    for (final jump in statements.whereType<RenPyJumpStatement>()) {
      expect(
        labels,
        contains(jump.target),
        reason: 'jump target "${jump.target}" (line ${jump.linenumber}) '
            'has no matching label',
      );
    }
  });

  test('every .spine image definition names an existing skin and animation',
      () {
    final spineAliases = _spineImageAliases(result.script);
    expect(spineAliases, isNotEmpty);

    for (final entry in spineAliases.entries) {
      final parsed = SpineImageName.tryParse(entry.value);
      expect(
        parsed,
        isNotNull,
        reason: 'image "${entry.key}" -> "${entry.value}" does not follow '
            'the renpy_spine naming convention',
      );
      expect(
        skins,
        contains(parsed!.skin),
        reason: 'image "${entry.key}" names skin "${parsed.skin}", which is '
            'not exported by the skeleton (available: $skins)',
      );
      expect(
        animations,
        contains(parsed.animation),
        reason: 'image "${entry.key}" names animation "${parsed.animation}", '
            'which is not exported by the skeleton',
      );
    }
  });

  test('every show of a Spine tag resolves to an existing animation', () {
    final spineTags = {for (final c in kSpineCharacters) c.tag: c};
    final spineAliases = _spineImageAliases(result.script);

    final spineShows = statements
        .whereType<RenPyShowStatement>()
        .map((show) => show.imageName.split('#').first.trim())
        .where(
          (name) => spineTags.containsKey(name.split(RegExp(r'\s+')).first),
        )
        .toList();
    expect(spineShows, isNotEmpty);

    for (final imageName in spineShows) {
      final tag = imageName.split(RegExp(r'\s+')).first;
      final alias = spineAliases[imageName];
      expect(
        alias,
        isNotNull,
        reason: '"show $imageName" has no matching `image $imageName = '
            'Image("...spine")` definition',
      );

      final parsed = SpineImageName.tryParse(alias!)!;
      final skin = parsed.skin ?? spineTags[tag]!.effectiveDefaultSkin;
      expect(
        skins,
        contains(skin),
        reason: '"show $imageName" resolves to skin "$skin", which is not '
            'exported by the skeleton',
      );
      expect(
        animations,
        contains(parsed.animation),
        reason: '"show $imageName" resolves to animation '
            '"${parsed.animation}", which is not exported by the skeleton',
      );
    }
  });

  test('skin identity stays stable per tag', () {
    // Every attribute of a tag must select that tag's own skin, so a tag
    // never flips identity mid-story.
    final spineTags = {for (final c in kSpineCharacters) c.tag: c};
    for (final entry in _spineImageAliases(result.script).entries) {
      final tag = entry.key.split(RegExp(r'\s+')).first;
      final character = spineTags[tag];
      if (character == null) continue;
      final parsed = SpineImageName.tryParse(entry.value)!;
      expect(
        parsed.skin ?? character.effectiveDefaultSkin,
        character.effectiveDefaultSkin,
        reason: 'image "${entry.key}" selects skin "${parsed.skin}" but the '
            'tag "$tag" is configured for skin '
            '"${character.effectiveDefaultSkin}"',
      );
    }
  });
}

/// All statements in the script, including those nested in init blocks,
/// labels, menus, and if branches.
Iterable<RenPyStatement> _flatten(List<RenPyStatement> statements) sync* {
  for (final statement in statements) {
    yield statement;
    if (statement is RenPyIfStatement) {
      for (final entry in statement.entries) {
        yield* _flatten(entry.block);
      }
    } else if (statement is RenPyBlockStatement) {
      yield* _flatten(statement.block);
    }
    if (statement is RenPyMenuStatement) {
      for (final item in statement.items) {
        yield* _flatten(item.block);
      }
    }
  }
}

/// Image name -> asset path for every image definition ending in `.spine`.
Map<String, String> _spineImageAliases(RenPyScript script) {
  final aliases = RenPyImageResolver.aliasesFor(script);
  return {
    for (final entry in aliases.entries)
      if (entry.value.toLowerCase().endsWith('.spine'))
        entry.key: entry.value,
  };
}

/// Skin names from a Spine JSON export (a list of `{"name": ...}` objects in
/// the 4.x format, or plain strings in older exports).
Set<String> _skinNames(Map<String, dynamic> skeleton) {
  final skins = skeleton['skins'];
  if (skins is List) {
    return {
      for (final skin in skins)
        if (skin is Map<String, dynamic>)
          skin['name'] as String
        else
          skin as String,
    };
  }
  if (skins is Map<String, dynamic>) return skins.keys.toSet();
  return const {};
}
