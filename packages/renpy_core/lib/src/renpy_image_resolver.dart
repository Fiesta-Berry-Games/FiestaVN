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
    Map<String, String> imageAliases = const {},
    Map<String, List<RenPyImageOperation>> imageOperations = const {},
  }) : availableAssets = Set.unmodifiable(availableAssets),
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
      imageAliases: aliasesFor(script),
      imageOperations: operationsFor(script),
    );
  }

  /// Builds image-name aliases from RenPy `image name = expression` statements.
  static Map<String, String> aliasesFor(RenPyScript script) {
    final aliases = <String, String>{};
    void addImage(RenPyImageStatement image) {
      aliases[image.name] = parseExpression(image.expression).assetPath;
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
  final Map<String, String> imageAliases;
  final Map<String, List<RenPyImageOperation>> imageOperations;

  RenPyImageResolver withImageAlias(String name, String expression) {
    final parsed = parseExpression(expression);
    return RenPyImageResolver(
      assetRoot: assetRoot,
      availableAssets: availableAssets,
      imageAliases: {...imageAliases, name: parsed.assetPath},
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
    final root = assetRoot;
    if (imageName == null || root == null) return null;

    final clean = imageName.split('#').first.trim();
    if (_solidSceneNames.contains(clean)) return null;
    final alias = imageAliases[clean];
    final operations = imageOperations[clean] ?? const <RenPyImageOperation>[];
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

    final hasExtension = RegExp(
      r'\.(png|jpg|jpeg|webp|gif)$',
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

const _solidSceneNames = {'black', 'white'};

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
