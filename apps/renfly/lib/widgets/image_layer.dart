import 'package:flutter/widgets.dart';
import 'package:renpy_flutter/renpy_flutter.dart';
import 'image_sprite.dart';

class ImageLayer extends StatefulWidget {
  const ImageLayer({super.key, required this.controller});
  final RenPyFlutterController controller;

  @override
  State<ImageLayer> createState() => _ImageLayerState();
}

class _ImageLayerState extends State<ImageLayer> {
  final _sprites = <String, Widget>{}; // Character -> widget.
  final _positions = <String, bool>{}; // Character -> atLeft?
  String? _backgroundAsset;

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
        _backgroundAsset = s.scene == 'black' ? null : s.sceneAsset;
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
        if (parts.isEmpty) return; // Malformed.

        final name = parts[0]; // Character name.

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

        final imagePath = s.showAsset;
        if (imagePath == null) return;

        // Check if we already have a sprite for this character.
        if (_sprites.containsKey(name)) {
          // Character already exists, just update the existing widget.
          // We need to create a new widget but with a stable key.
          _sprites[name] = ImageSprite(
            key: ValueKey(name), // Use character name as key, not animation.
            imagePath: imagePath,
            atLeft: atLeft,
          );
        } else {
          // New character, create sprite.
          _sprites[name] = ImageSprite(
            key: ValueKey(name), // Use character name as key, not animation.
            imagePath: imagePath,
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
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (_backgroundAsset != null)
        Image.asset(
          _backgroundAsset!,
          fit: BoxFit.cover,
          errorBuilder:
              (context, error, stackTrace) =>
                  Container(color: const Color(0xFF202020)),
        ),
      ..._sprites.values,
    ],
  );
}
