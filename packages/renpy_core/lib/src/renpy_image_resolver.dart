import 'package:renpy_parser/renpy_parser.dart';

import 'renpy_resolved_image.dart';

/// Resolves RenPy image names to conventional asset paths.
///
/// This class is platform-neutral: it works with strings only and lets host
/// apps decide how to load the resolved path.
class RenPyImageResolver {
  RenPyImageResolver({
    this.assetRoot,
    Iterable<String> availableAssets = const {},
    Map<String, RenPyResolvedImage> imageDefinitions = const {},
    Map<String, String> imageAliases = const {},
    Map<String, List<RenPyImageOperation>> imageOperations = const {},
  }) : availableAssets = Set.unmodifiable(availableAssets),
       imageDefinitions = Map.unmodifiable({
         ...imageDefinitions,
         for (final entry in imageAliases.entries)
           entry.key: RenPyResolvedImage(
             assetPath: entry.value,
             operations: imageOperations[entry.key] ?? const [],
           ),
       }),
       imageAliases = Map.unmodifiable(imageAliases),
       imageOperations = Map<String, List<RenPyImageOperation>>.unmodifiable({
         for (final entry in imageOperations.entries)
           entry.key: List<RenPyImageOperation>.unmodifiable(entry.value),
       });

  factory RenPyImageResolver.fromScript(
    RenPyScript script, {
    String? assetRoot,
    Iterable<String> availableAssets = const {},
  }) {
    return RenPyImageResolver(
      assetRoot: assetRoot,
      availableAssets: availableAssets,
      imageDefinitions: definitionsFor(script),
      imageAliases: aliasesFor(script),
      imageOperations: operationsFor(script),
    );
  }

  static Map<String, RenPyResolvedImage> definitionsFor(RenPyScript script) {
    final definitions = <String, RenPyResolvedImage>{};
    void addImage(RenPyImageStatement image) {
      definitions[image.name] = parseExpression(image.expression);
    }

    for (final statement in script.statements) {
      if (statement is RenPyImageStatement) {
        addImage(statement);
      } else if (statement is RenPyInitStatement) {
        for (final image in statement.block.whereType<RenPyImageStatement>()) {
          addImage(image);
        }
      }
    }
    return definitions;
  }

  /// Builds image-name aliases from RenPy `image name = expression` statements.
  static Map<String, String> aliasesFor(RenPyScript script) {
    final aliases = <String, String>{};
    void addImage(RenPyImageStatement image) {
      final assetPath = parseExpression(image.expression).assetPath;
      if (assetPath != null) aliases[image.name] = assetPath;
    }

    for (final statement in script.statements) {
      if (statement is RenPyImageStatement) {
        addImage(statement);
      } else if (statement is RenPyInitStatement) {
        for (final image in statement.block.whereType<RenPyImageStatement>()) {
          addImage(image);
        }
      }
    }
    return aliases;
  }

  static Map<String, List<RenPyImageOperation>> operationsFor(
    RenPyScript script,
  ) {
    final operations = <String, List<RenPyImageOperation>>{};
    void addImage(RenPyImageStatement image) {
      operations[image.name] = parseExpression(image.expression).operations;
    }

    for (final statement in script.statements) {
      if (statement is RenPyImageStatement) {
        addImage(statement);
      } else if (statement is RenPyInitStatement) {
        for (final image in statement.block.whereType<RenPyImageStatement>()) {
          addImage(image);
        }
      }
    }
    return operations;
  }

  static RenPyResolvedImage parseExpression(String expression) {
    final trimmed = expression.trim();
    final solidColor = _solidColorForExpression(trimmed);
    if (solidColor != null) return RenPyResolvedImage.solid(solidColor);

    final displayableWrapper = RegExp(
      r'''^(?:Image|im\.[A-Za-z_]\w*)\s*\(\s*["']([^"']+)["']''',
    ).firstMatch(trimmed);
    final quoted = RegExp(r'''^["']([^"']+)["']$''').firstMatch(trimmed);
    return RenPyResolvedImage(
      assetPath: displayableWrapper?.group(1) ?? quoted?.group(1) ?? trimmed,
      operations: _operationsForExpression(trimmed),
    );
  }

  final String? assetRoot;
  final Set<String> availableAssets;
  final Map<String, RenPyResolvedImage> imageDefinitions;
  final Map<String, String> imageAliases;
  final Map<String, List<RenPyImageOperation>> imageOperations;

  RenPyImageResolver withImageAlias(String name, String expression) {
    final parsed = parseExpression(expression);
    final aliases = {...imageAliases};
    final assetPath = parsed.assetPath;
    if (assetPath == null) {
      aliases.remove(name);
    } else {
      aliases[name] = assetPath;
    }

    return RenPyImageResolver(
      assetRoot: assetRoot,
      availableAssets: availableAssets,
      imageDefinitions: {...imageDefinitions, name: parsed},
      imageAliases: aliases,
      imageOperations: {...imageOperations, name: parsed.operations},
    );
  }

  /// Resolves a RenPy scene/show image name to an asset path.
  ///
  /// If [availableAssets] is non-empty, the first existing candidate wins. If
  /// no manifest is available, the first conventional candidate is returned so
  /// hosts can still attempt to render useful placeholders or external files.
  String? resolve(String? imageName) {
    return resolveImage(imageName)?.assetPath;
  }

  RenPyResolvedImage? resolveImage(String? imageName) {
    if (imageName == null) return null;

    final clean = imageName.split('#').first.trim();
    final definition = imageDefinitions[clean];
    if (definition?.solidColor != null) return definition;
    final builtInColor = _builtInSolidSceneColors[clean];
    if (builtInColor != null) return RenPyResolvedImage.solid(builtInColor);

    final root = assetRoot;
    if (root == null) return null;

    final alias = definition?.assetPath ?? imageAliases[clean];
    final operations =
        definition?.operations ??
        imageOperations[clean] ??
        const <RenPyImageOperation>[];
    final candidates = <String>[];

    void addCandidate(String relativePath) {
      final normalized = relativePath.replaceAll(RegExp(r'^/+'), '');
      if (normalized.startsWith('assets/')) {
        candidates.add(normalized);
      } else {
        candidates.add('$root/$normalized');
        candidates.add('$root/images/$normalized');
      }
    }

    if (alias != null) {
      addCandidate(alias);
    }

    // `.spine` counts as an extension so names like
    // `erikari erikari-emotes/wave.spine` resolve to a `.spine` asset path
    // (routed to a Spine layer by hosts) instead of growing `.png` candidates.
    final hasExtension = RegExp(
      r'\.(png|jpg|jpeg|webp|gif|spine)$',
      caseSensitive: false,
    ).hasMatch(clean);
    if (hasExtension) {
      addCandidate(clean);
    } else {
      for (final extension in const ['png', 'jpg', 'jpeg', 'webp', 'gif']) {
        addCandidate('$clean.$extension');
        addCandidate('${clean.replaceAll(' ', '_')}.$extension');
      }
    }

    for (final candidate in candidates) {
      if (availableAssets.contains(candidate)) {
        return RenPyResolvedImage(assetPath: candidate, operations: operations);
      }
    }

    final manifestMatch = _resolveFromManifest(clean);
    if (manifestMatch != null) {
      return RenPyResolvedImage(
        assetPath: manifestMatch,
        operations: operations,
      );
    }

    return candidates.isNotEmpty
        ? RenPyResolvedImage(
          assetPath: candidates.first,
          operations: operations,
        )
        : null;
  }

  String? _resolveFromManifest(String imageName) {
    final root = assetRoot;
    if (root == null || availableAssets.isEmpty) return null;

    final wantedNames =
        {
          imageName,
          imageName.replaceAll(' ', '_'),
        }.map((name) => name.toLowerCase()).toSet();

    final matches =
        availableAssets.where((asset) {
            if (!asset.startsWith('$root/')) return false;
            final filename = asset.split('/').last;
            final basename = filename.replaceFirst(
              RegExp(r'\.[^.]+$', caseSensitive: false),
              '',
            );
            return wantedNames.contains(basename.toLowerCase());
          }).toList()
          ..sort();

    return matches.isEmpty ? null : matches.first;
  }
}

const _builtInSolidSceneColors = {
  'black': RenPyColorValue(0, 0, 0, 255),
  'white': RenPyColorValue(255, 255, 255, 255),
  'red': RenPyColorValue(255, 0, 0, 255),
};

RenPyColorValue? _solidColorForExpression(String expression) {
  final quoted = RegExp(
    r'''^Solid\s*\(\s*["'](#[0-9a-fA-F]{3,8})["']''',
  ).firstMatch(expression);
  if (quoted != null) return _solidColorFromHex(quoted.group(1)!);

  final tuple = RegExp(r'^Solid\s*\(\s*\(([^)]+)\)').firstMatch(expression);
  if (tuple == null) return null;

  final values =
      tuple
          .group(1)!
          .split(',')
          .map((value) => int.tryParse(value.trim()))
          .whereType<int>()
          .toList();
  if (values.length < 3) return null;
  return RenPyColorValue(
    _clampColorChannel(values[0]),
    _clampColorChannel(values[1]),
    _clampColorChannel(values[2]),
    values.length >= 4 ? _clampColorChannel(values[3]) : 255,
  );
}

int _clampColorChannel(int value) => value.clamp(0, 255).toInt();

RenPyColorValue? _solidColorFromHex(String expression) {
  final hex = expression.startsWith('#') ? expression.substring(1) : expression;
  final expanded = switch (hex.length) {
    3 || 4 => hex.split('').map((char) => '$char$char').join(),
    6 || 8 => hex,
    _ => null,
  };
  if (expanded == null) return null;

  final red = int.parse(expanded.substring(0, 2), radix: 16);
  final green = int.parse(expanded.substring(2, 4), radix: 16);
  final blue = int.parse(expanded.substring(4, 6), radix: 16);
  final alpha =
      expanded.length == 8
          ? int.parse(expanded.substring(6, 8), radix: 16)
          : 255;
  return RenPyColorValue(red, green, blue, alpha);
}

List<RenPyImageOperation> _operationsForExpression(String expression) {
  if (expression.startsWith('im.Grayscale(')) {
    return const [RenPyImageOperation.grayscale()];
  }
  if (expression.startsWith('im.Sepia(')) {
    return const [RenPyImageOperation.sepia()];
  }
  if (expression.startsWith('im.Flip(') &&
      expression.contains('horizontal=True')) {
    return const [RenPyImageOperation.flipHorizontal()];
  }
  if (expression.startsWith('im.MatrixColor(')) {
    final tint = RegExp(r'im\.matrix\.tint\(([^)]+)\)').firstMatch(expression);
    if (tint == null) return const [];

    final values =
        tint
            .group(1)!
            .split(',')
            .map((value) => double.tryParse(value.trim()))
            .whereType<double>()
            .toList();
    if (values.length < 3) return const [];

    return [
      RenPyImageOperation.matrixColor(
        tintRed: values[0],
        tintGreen: values[1],
        tintBlue: values[2],
      ),
    ];
  }
  return const [];
}
