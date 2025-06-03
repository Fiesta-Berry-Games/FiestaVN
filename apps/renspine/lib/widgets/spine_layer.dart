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
  final _sprites   = <String, Widget>{}; // Image file → widget.
  final _skinSide  = <String, bool>{};   // Skin name  → atLeft?.

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onStatusChanged);
  }

  void _onStatusChanged() {
    final s = widget.controller.value;
    if (s is! RenPyImageChange) return;

    setState(() {

      String _file(String tag) {
        // If caller already passed a real .spine path just keep it.
        if (tag.endsWith('.spine')) return tag;
        var out = tag.trim().replaceAll(RegExp(r'\s+'), '_');
        return out.endsWith('.spine') ? out : '$out.spine';
      }

      if (s.hide  != null) _sprites.remove(_file(s.hide!));
      if (s.scene != null) _sprites.clear(); // Full scene change.
      if (s.show  != null) {
        final file = _file(s.show!);

        // Derive skin name (prefix up to first dash).
        final skin = file.split('-').first;
        final atLeft = _skinSide.putIfAbsent(
          skin, () => _skinSide.containsValue(false), // First skin → false? Then true.
        );

        _sprites[file] = SpineSprite(
          imageName: file,
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
  Widget build(BuildContext context) =>
      Stack(children: _sprites.values.toList(growable: false));
}
