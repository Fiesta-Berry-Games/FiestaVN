/// A parsed `.spine` image name: the `(skin, animation)` pair encoded in a
/// Ren'Py image expression or resolved asset path.
///
/// ## Naming rules
///
/// [tryParse] accepts any path whose final extension is `.spine`
/// (case-insensitive) and applies these rules, in order:
///
/// 1. Only the last two path segments participate: leading directories (game
///    roots like `assets/games/1/game/`) are ignored.
/// 2. If the parent directory segment contains a `-`, it is split at its
///    **first** dash into `<skin>-<group>`, and the animation is
///    `<group>/<file>`:
///    `erikari-movement/idle-front.spine` → (`erikari`, `movement/idle-front`).
/// 3. Otherwise the bare file name is split at its **first** dash into
///    `<skin>-<animation>`: `erikari-angry.spine` → (`erikari`, `angry`),
///    `erikari-idle-front.spine` → (`erikari`, `idle-front`).
/// 4. A file name without a dash (or with only a leading/trailing dash) is a
///    bare animation with no skin: `wave.spine` → (null, `wave`). Consumers
///    should fall back to a default skin in that case.
class SpineImageName {
  const SpineImageName({this.skin, required this.animation});

  /// The Spine skin encoded in the name, or null for a bare animation name.
  final String? skin;

  /// The Spine animation name, possibly folder-qualified
  /// (e.g. `movement/idle-front`).
  final String animation;

  /// Parses [assetPath] according to the naming rules above, returning null
  /// when the path does not end in `.spine` or has no usable file name.
  static SpineImageName? tryParse(String assetPath) {
    final trimmed = assetPath.trim();
    if (!trimmed.toLowerCase().endsWith(_extension)) return null;

    final withoutExtension = trimmed.substring(
      0,
      trimmed.length - _extension.length,
    );
    final segments =
        withoutExtension
            .split('/')
            .where((segment) => segment.isNotEmpty)
            .toList();
    if (segments.isEmpty) return null;

    final file = segments.last;
    final parent = segments.length >= 2 ? segments[segments.length - 2] : null;

    // Rule 2: a dashed parent directory carries the skin and animation group.
    if (parent != null && parent.contains('-')) {
      final dash = parent.indexOf('-');
      final skin = parent.substring(0, dash);
      final group = parent.substring(dash + 1);
      return SpineImageName(
        skin: skin.isEmpty ? null : skin,
        animation: group.isEmpty ? file : '$group/$file',
      );
    }

    // Rule 3: a dashed bare file name is <skin>-<animation>.
    final dash = file.indexOf('-');
    if (dash > 0 && dash < file.length - 1) {
      return SpineImageName(
        skin: file.substring(0, dash),
        animation: file.substring(dash + 1),
      );
    }

    // Rule 4: a bare animation name with no skin.
    return SpineImageName(animation: file);
  }

  static const _extension = '.spine';

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SpineImageName &&
            skin == other.skin &&
            animation == other.animation;
  }

  @override
  int get hashCode => Object.hash(skin, animation);

  @override
  String toString() => 'SpineImageName(skin: $skin, animation: $animation)';
}
