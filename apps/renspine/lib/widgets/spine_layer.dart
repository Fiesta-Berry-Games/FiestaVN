import 'package:flutter/widgets.dart';
import '../controller.dart';
import 'spine_sprite.dart';

class SpineLayer extends StatefulWidget {
  const SpineLayer({super.key, required this.controller});
  final RenPyFlutterController controller;

  @override
  State<SpineLayer> createState() => _SpineLayerState();
}

class _SpineLayerState extends State<SpineLayer> {
  final _sprites = <String, Widget>{}; // Character -> widget.
  final _positions = <String, bool>{}; // Character -> atLeft?

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    final s = widget.controller.value;
    if (s is! RenPyImageChange) return;

    setState(() {
      // -- scene -------------------------------------------------------------
      if (s.scene != null) {
        _sprites.clear();
        _positions.clear();
      }

      // -- hide --------------------------------------------------------------
      if (s.hide != null) {
        final name = s.hide!.trim().split(RegExp(r'\s+')).first;
        _sprites.remove(name);
        _positions.remove(name);
      }

      // -- show --------------------------------------------------------------
      if (s.show != null) {
        final clean = s.show!.split('#')[0].trim();
        final parts = clean.split(RegExp(r'\s+'));
        if (parts.length < 2) return; // Malformed.

        final name = parts[0]; // Character name.
        final anim = parts[1]; // idle / wave / angry ...

        // Optional "at left/right".
        bool? explicitLeft;
        final atIdx = parts.indexOf('at');
        if (atIdx != -1 && atIdx + 1 < parts.length) {
          explicitLeft = parts[atIdx + 1] == 'left';
        }

        // Decide side (alternate L/R for new characters).
        late bool atLeft;
        if (explicitLeft != null) {
          atLeft = explicitLeft;
        } else if (_positions.containsKey(name)) {
          atLeft = _positions[name]!; // Stick to previous side.
        } else {
          // First unseen character -> left, next -> right, then alternate.
          final leftTaken = _positions.values.where((v) => v).length;
          final rightTaken = _positions.length - leftTaken;
          atLeft = leftTaken <= rightTaken;
        }
        _positions[name] = atLeft;

        // Build Spine file path (assume skin name == character name).
        final skin = name;
        final file =
            (anim == 'idle')
                ? '$skin-movement/idle-front.spine'
                : '$skin-emotes/$anim.spine';

        // Check if we already have a sprite for this character.
        if (_sprites.containsKey(name)) {
          // Character already exists, just update the existing widget.
          // We need to create a new widget but with a stable key.
          _sprites[name] = SpineSprite(
            key: ValueKey(name), // Use character name as key, not animation.
            imageName: file,
            atLeft: atLeft,
          );
        } else {
          // New character, create sprite.
          _sprites[name] = SpineSprite(
            key: ValueKey(name), // Use character name as key, not animation.
            imageName: file,
            atLeft: atLeft,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Stack(fit: StackFit.expand, children: _sprites.values.toList());
}
