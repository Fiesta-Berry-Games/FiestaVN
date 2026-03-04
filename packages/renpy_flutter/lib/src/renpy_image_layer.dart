import 'package:flutter/material.dart';

import 'renpy_flutter_controller.dart';

/// Renders RenPy scene and show image changes as Flutter asset images.
class RenPyImageLayer extends StatefulWidget {
  const RenPyImageLayer({super.key, required this.controller});

  final RenPyFlutterController controller;

  @override
  State<RenPyImageLayer> createState() => _RenPyImageLayerState();
}

class _RenPyImageLayerState extends State<RenPyImageLayer> {
  final _sprites = <String, Widget>{};
  final _positions = <String, bool>{};
  String? _backgroundAsset;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    final status = widget.controller.value;
    if (status is! RenPyImageChange) return;

    setState(() {
      if (status.scene != null) {
        _sprites.clear();
        _positions.clear();
        _backgroundAsset = status.scene == 'black' ? null : status.sceneAsset;
      }

      if (status.hide != null) {
        final name = status.hide!.trim().split(RegExp(r'\s+')).first;
        _sprites.remove(name);
        _positions.remove(name);
      }

      if (status.show != null) {
        final clean = status.show!.split('#').first.trim();
        final parts = clean.split(RegExp(r'\s+'));
        if (parts.isEmpty) return;

        final name = parts.first;

        bool? explicitLeft;
        final atIndex = parts.indexOf('at');
        if (atIndex != -1 && atIndex + 1 < parts.length) {
          explicitLeft = parts[atIndex + 1] == 'left';
        }

        final atLeft =
            explicitLeft ??
            _positions[name] ??
            (_positions.values.where((isLeft) => isLeft).length <=
                _positions.values.where((isLeft) => !isLeft).length);
        _positions[name] = atLeft;

        final imagePath = status.showAsset;
        if (imagePath == null) return;

        _sprites[name] = _RenPyImageSprite(
          key: ValueKey(name),
          imagePath: imagePath,
          atLeft: atLeft,
        );
      }
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onStatusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
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
}

class _RenPyImageSprite extends StatelessWidget {
  const _RenPyImageSprite({
    super.key,
    required this.imagePath,
    required this.atLeft,
  });

  final String imagePath;
  final bool atLeft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: atLeft ? 50 : null,
      right: atLeft ? null : 50,
      bottom: 0,
      child: Image.asset(
        imagePath,
        width: 200,
        height: 300,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.image_not_supported,
                  size: 48,
                  color: Colors.grey.shade300,
                ),
                const SizedBox(height: 8),
                Text(
                  'Image not found',
                  style: TextStyle(color: Colors.grey.shade300, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  imagePath.split('/').last,
                  style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
