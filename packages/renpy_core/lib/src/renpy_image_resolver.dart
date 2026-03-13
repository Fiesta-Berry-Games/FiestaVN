import 'package:renpy_parser/renpy_parser.dart';

/// Resolves RenPy image names to conventional asset paths.
///
/// This class is platform-neutral: it works with strings only and lets host
/// apps decide how to load the resolved path.
class RenPyImageResolver {
  RenPyImageResolver({
    this.assetRoot,
    Iterable<String> availableAssets = const {},
    Map<String, String> imageAliases = const {},
  }) : availableAssets = Set.unmodifiable(availableAssets),
       imageAliases = Map.unmodifiable(imageAliases);

  factory RenPyImageResolver.fromScript(
    RenPyScript script, {
    String? assetRoot,
    Iterable<String> availableAssets = const {},
  }) {
    return RenPyImageResolver(
      assetRoot: assetRoot,
      availableAssets: availableAssets,
      imageAliases: aliasesFor(script),
    );
  }

  /// Builds image-name aliases from RenPy `image name = expression` statements.
  static Map<String, String> aliasesFor(RenPyScript script) {
    final aliases = <String, String>{};
    for (final image in script.findStatements<RenPyImageStatement>(
      (_) => true,
    )) {
      final expression = image.expression.trim();
      final imageCall = RegExp(
        r'''Image\s*\(\s*["']([^"']+)["']\s*\)''',
      ).firstMatch(expression);
      final quoted = RegExp(r'''^["']([^"']+)["']$''').firstMatch(expression);
      aliases[image.name] =
          imageCall?.group(1) ?? quoted?.group(1) ?? expression;
    }
    return aliases;
  }

  final String? assetRoot;
  final Set<String> availableAssets;
  final Map<String, String> imageAliases;

  /// Resolves a RenPy scene/show image name to an asset path.
  ///
  /// If [availableAssets] is non-empty, the first existing candidate wins. If
  /// no manifest is available, the first conventional candidate is returned so
  /// hosts can still attempt to render useful placeholders or external files.
  String? resolve(String? imageName) {
    final root = assetRoot;
    if (imageName == null || root == null) return null;
    if (imageName == 'black') return null;

    final clean = imageName.split('#').first.trim();
    final alias = imageAliases[clean];
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
      if (availableAssets.contains(candidate)) return candidate;
    }

    final manifestMatch = _resolveFromManifest(clean);
    if (manifestMatch != null) return manifestMatch;

    return candidates.isNotEmpty ? candidates.first : null;
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
