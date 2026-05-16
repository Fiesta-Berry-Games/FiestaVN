import 'package:renpy_parser/renpy_parser.dart';

/// Registers RenPy `layeredimage` declarations and resolves a shown
/// layeredimage (with a set of active attributes) into the ordered list of
/// displayable expressions to stack from bottom to top.
///
/// Resolution rules mirror RenPy:
/// - `always` layers are always included.
/// - Each group contributes at most one attribute layer. A named attribute in
///   the requested set wins; otherwise the group's `default` attribute is used;
///   otherwise the group contributes nothing.
/// - `if <condition>` layers are included when [evaluateCondition] returns true
///   (best-effort; an absent evaluator treats conditions as false).
/// - Layers are emitted in their declared order.
class RenPyLayeredImageRegistry {
  RenPyLayeredImageRegistry({
    Map<String, RenPyLayeredImageStatement> definitions = const {},
  }) : _definitions = Map.unmodifiable(definitions);

  /// Builds a registry from every `layeredimage` declaration in [script],
  /// including those nested in `init` blocks.
  factory RenPyLayeredImageRegistry.fromScript(RenPyScript script) {
    final definitions = <String, RenPyLayeredImageStatement>{};
    void collect(List<RenPyStatement> statements) {
      for (final statement in statements) {
        if (statement is RenPyLayeredImageStatement) {
          definitions[statement.name] = statement;
        } else if (statement is RenPyInitStatement) {
          collect(statement.block);
        }
      }
    }

    collect(script.statements);
    return RenPyLayeredImageRegistry(definitions: definitions);
  }

  final Map<String, RenPyLayeredImageStatement> _definitions;

  /// Whether [name] (the first token of an image name) is a known layeredimage.
  bool isLayeredImage(String? name) {
    if (name == null) return false;
    return _definitions.containsKey(_baseName(name));
  }

  /// The declaration for [name], or null when it is not a layeredimage.
  RenPyLayeredImageStatement? definitionFor(String? name) {
    if (name == null) return null;
    return _definitions[_baseName(name)];
  }

  /// The default active-attribute map (group -> attribute) for [name], applying
  /// each group's `default` attribute. Used to seed a freshly shown sprite.
  Map<String, String> defaultAttributes(String name) {
    final definition = _definitions[_baseName(name)];
    if (definition == null) return {};
    final result = <String, String>{};
    for (final layer in definition.layers) {
      if (layer.kind == RenPyLayeredImageLayerKind.attribute &&
          layer.isDefault &&
          layer.group != null &&
          layer.attribute != null) {
        result[layer.group!] = layer.attribute!;
      }
    }
    return result;
  }

  /// Merges the attributes named in [imageName] (everything after the
  /// layeredimage tag) into [current], replacing the active attribute of each
  /// named attribute's group. Unmentioned groups keep their current selection.
  /// This is what makes an incremental `show eileen frown` swap only the face
  /// group while leaving the outfit untouched.
  Map<String, String> mergeAttributes(
    String imageName,
    Map<String, String> current,
  ) {
    final definition = _definitions[_baseName(imageName)];
    if (definition == null) return {...current};

    final groupForAttribute = <String, String>{};
    for (final layer in definition.layers) {
      if (layer.kind == RenPyLayeredImageLayerKind.attribute &&
          layer.group != null &&
          layer.attribute != null) {
        groupForAttribute[layer.attribute!] = layer.group!;
      }
    }

    final merged = {...current};
    for (final attribute in _attributeTokens(imageName)) {
      final group = groupForAttribute[attribute];
      if (group != null) merged[group] = attribute;
    }
    return merged;
  }

  /// Resolves a layeredimage to the ordered list of displayable expressions to
  /// stack, given the [activeAttributes] (group -> attribute). Returns an empty
  /// list when [name] is not a layeredimage.
  List<String> resolveLayers(
    String name,
    Map<String, String> activeAttributes, {
    bool Function(String condition)? evaluateCondition,
  }) {
    final definition = _definitions[_baseName(name)];
    if (definition == null) return const [];

    final layers = <String>[];
    for (final layer in definition.layers) {
      switch (layer.kind) {
        case RenPyLayeredImageLayerKind.always:
          layers.add(layer.displayable);
        case RenPyLayeredImageLayerKind.attribute:
          final group = layer.group;
          if (group == null) continue;
          if (activeAttributes[group] == layer.attribute) {
            layers.add(layer.displayable);
          }
        case RenPyLayeredImageLayerKind.condition:
          final condition = layer.condition;
          if (condition != null &&
              evaluateCondition != null &&
              evaluateCondition(condition)) {
            layers.add(layer.displayable);
          }
      }
    }
    return layers;
  }

  static String _baseName(String imageName) {
    final clean = imageName.split('#').first.trim();
    if (clean.isEmpty) return clean;
    return clean.split(RegExp(r'\s+')).first;
  }

  static List<String> _attributeTokens(String imageName) {
    final clean = imageName.split('#').first.trim();
    if (clean.isEmpty) return const [];
    final tokens = clean.split(RegExp(r'\s+'));
    return tokens.length <= 1 ? const [] : tokens.sublist(1);
  }
}
