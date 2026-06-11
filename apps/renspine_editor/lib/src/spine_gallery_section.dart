import 'package:flutter/material.dart';
import 'package:renpy_spine/renpy_spine.dart';

import 'spine_editor_config.dart';

/// The "Spine characters" section this app appends to the editor's
/// Characters gallery (via `EditorScreen.extraGallerySection`).
///
/// For each configured [SpineCharacter] it lists the character's skin and the
/// skeleton's animations as tappable poses: the pose tile inserts
/// `show <tag> <skin>-<animation>.spine` at the editor cursor, and the L / C
/// / R shortcuts underneath append ` at left|center|right`. When at least two
/// characters are configured, a pair helper inserts two positioned shows
/// ready for back-and-forth dialogue.
class SpineGallerySection extends StatefulWidget {
  const SpineGallerySection({
    super.key,
    required this.characters,
    required this.animations,
    required this.onInsert,
  });

  /// The configured Spine characters, in display order.
  final List<SpineCharacter> characters;

  /// The animations the shared skeleton supports.
  final List<SpineAnimationOption> animations;

  /// Closes the gallery and inserts the statements at the editor cursor.
  final void Function(List<String> statements) onInsert;

  @override
  State<SpineGallerySection> createState() => _SpineGallerySectionState();
}

/// One pair-helper choice: a character playing an animation.
class _SpinePose {
  const _SpinePose(this.character, this.option);

  final SpineCharacter character;
  final SpineAnimationOption option;

  /// Stable id used in dropdown keys and as the dropdown value.
  String get id => '${character.tag} ${option.label}';

  String get statement => spineShowStatement(character, option);
}

class _SpineGallerySectionState extends State<SpineGallerySection> {
  // Pose ids (not pose objects): poses are rebuilt every build, and dropdown
  // values must compare equal across rebuilds.
  String? _pairLeft;
  String? _pairRight;

  List<_SpinePose> get _poses => [
    for (final character in widget.characters)
      for (final option in widget.animations) _SpinePose(character, option),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('spine-gallery-section'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Spine characters', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Skeletal-animated sprites. Tap a pose to insert '
          '"show <tag> <skin>-<animation>.spine" at the cursor; L / C / R '
          'place it at left, center, or right.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: 12),
        for (final character in widget.characters) ...[
          Text(
            '${character.tag} — skin "${character.effectiveDefaultSkin}"',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final option in widget.animations)
                _poseTile(context, character, option),
            ],
          ),
          const SizedBox(height: 16),
        ],
        if (widget.characters.length >= 2) _pairHelper(context),
      ],
    );
  }

  /// One pose tile: the badge inserts a plain show, and the L / C / R
  /// shortcuts underneath insert `... at left|center|right` (mirroring the
  /// editor's own character tiles).
  Widget _poseTile(
    BuildContext context,
    SpineCharacter character,
    SpineAnimationOption option,
  ) {
    final theme = Theme.of(context);
    final statement = spineShowStatement(character, option);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Insert "$statement"',
          child: InkWell(
            key: ValueKey(
              'spine-gallery-show-${character.tag}-${option.label}',
            ),
            onTap: () => widget.onInsert([statement]),
            borderRadius: BorderRadius.circular(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF202020),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(
                    Icons.directions_run,
                    size: 24,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 80,
                  child: Text(
                    option.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final position in const ['left', 'center', 'right'])
              Tooltip(
                message: 'Insert "$statement at $position"',
                child: InkWell(
                  key: ValueKey(
                    'spine-gallery-show-${character.tag}-${option.label}'
                    '-$position',
                  ),
                  borderRadius: BorderRadius.circular(4),
                  onTap: () => widget.onInsert(['$statement at $position']),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      position.substring(0, 1).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// Two-character helper: pick a left and a right pose, insert both shows
  /// positioned for back-and-forth dialogue.
  Widget _pairHelper(BuildContext context) {
    final theme = Theme.of(context);
    final poses = _poses;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Two Spine characters', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Insert a pair of Spine shows at left and right.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.white54),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _pairDropdown(
                keyPrefix: 'spine-gallery-pair-left',
                hint: 'Left character',
                value: _pairLeft,
                poses: poses,
                onChanged: (id) => setState(() => _pairLeft = id),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _pairDropdown(
                keyPrefix: 'spine-gallery-pair-right',
                hint: 'Right character',
                value: _pairRight,
                poses: poses,
                onChanged: (id) => setState(() => _pairRight = id),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              key: const ValueKey('spine-gallery-pair-insert'),
              onPressed:
                  _pairLeft == null || _pairRight == null
                      ? null
                      : () => widget.onInsert([
                        '${_poseById(poses, _pairLeft!).statement} at left',
                        '${_poseById(poses, _pairRight!).statement} at right',
                      ]),
              child: const Text('Insert pair'),
            ),
          ],
        ),
      ],
    );
  }

  static _SpinePose _poseById(List<_SpinePose> poses, String id) =>
      poses.firstWhere((pose) => pose.id == id);

  Widget _pairDropdown({
    required String keyPrefix,
    required String hint,
    required String? value,
    required List<_SpinePose> poses,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButton<String>(
      key: ValueKey(keyPrefix),
      isExpanded: true,
      hint: Text(hint),
      value: value,
      items: [
        for (final pose in poses)
          DropdownMenuItem(
            key: ValueKey('$keyPrefix-${pose.id}'),
            value: pose.id,
            child: Text(pose.id),
          ),
      ],
      onChanged: onChanged,
    );
  }
}
