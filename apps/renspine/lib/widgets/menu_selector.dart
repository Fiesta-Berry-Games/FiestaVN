import 'package:flutter/material.dart';
import '../controller.dart';

/// Overlay that shows Ren'Py in-game menus.
///
/// When the player taps a choice we forward the index back to the controller.
class MenuSelector extends StatelessWidget {
  const MenuSelector({super.key, required this.controller});
  final RenPyFlutterController controller;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RenPyGameStatus>(
      valueListenable: controller,
      builder: (context, status, _) {
        if (status is! RenPyMenu) return const SizedBox.shrink();

        return Material(
          color: Colors.black54,
          child: Center(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < status.choices.length; ++i)
                  ElevatedButton(
                    key: ValueKey('menu_choice_$i'),
                    onPressed: () => status.onChoice(i),
                    child: Text(status.choices[i]),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
